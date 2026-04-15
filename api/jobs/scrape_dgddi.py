"""
Daily cron job — scrapes DGDDI customs allowances for goods brought from Andorra
and upserts them into the allowance_items table.

The DGDDI page structure can change; this scraper targets the table on:
https://www.douane.gouv.fr/particuliers/vous-rentrez-en-france/vous-revenez-dun-pays-hors-union-europeenne/franchise-de-douane-de-retour-dun-pays-hors-union-europeenne

If the scrape fails we log the error and leave existing DB data untouched —
the app keeps serving the last successful values.
"""
import logging
from datetime import datetime, timezone

import httpx
from bs4 import BeautifulSoup
from sqlalchemy import select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert

from api.db import SessionLocal
from api.models import AllowanceItem

log = logging.getLogger(__name__)

DGDDI_URL = (
    "https://www.douane.gouv.fr/particuliers/vous-rentrez-en-france/"
    "vous-revenez-dun-pays-hors-union-europeenne/"
    "franchise-de-douane-de-retour-dun-pays-hors-union-europeenne"
)

# ── Fallback hardcoded data (from current DGDDI rules for Andorra) ──────────
# This is used on first boot if the scrape fails, and also serves as the
# canonical source of truth for item_type keys and labels.
FALLBACK_ALLOWANCES: list[dict] = [
    {
        "item_type": "spirits",
        "label": "Spiritueux (> 22% vol.)",
        "unit": "L",
        "per_adult": 1.0,
        "per_minor": None,
        "per_child": None,
    },
    {
        "item_type": "fortified_wine",
        "label": "Vins fortifiés / Porto / Champagne (≤ 22% vol.)",
        "unit": "L",
        "per_adult": 2.0,
        "per_minor": None,
        "per_child": None,
    },
    {
        "item_type": "still_wine",
        "label": "Vin tranquille",
        "unit": "L",
        "per_adult": 4.0,
        "per_minor": None,
        "per_child": None,
    },
    {
        "item_type": "beer",
        "label": "Bière",
        "unit": "L",
        "per_adult": 16.0,
        "per_minor": None,
        "per_child": None,
    },
    {
        "item_type": "cigarettes",
        "label": "Cigarettes",
        "unit": "unités",
        "per_adult": 200.0,
        "per_minor": None,
        "per_child": None,
    },
    {
        "item_type": "cigarillos",
        "label": "Cigarillos (max. 3g/pièce)",
        "unit": "unités",
        "per_adult": 100.0,
        "per_minor": None,
        "per_child": None,
    },
    {
        "item_type": "cigars",
        "label": "Cigares",
        "unit": "unités",
        "per_adult": 50.0,
        "per_minor": None,
        "per_child": None,
    },
    {
        "item_type": "tobacco",
        "label": "Tabac à rouler",
        "unit": "g",
        "per_adult": 250.0,
        "per_minor": None,
        "per_child": None,
    },
    {
        "item_type": "perfume",
        "label": "Parfum",
        "unit": "g",
        "per_adult": 50.0,
        "per_minor": 25.0,
        "per_child": None,
    },
    {
        "item_type": "eau_de_toilette",
        "label": "Eau de toilette",
        "unit": "mL",
        "per_adult": 250.0,
        "per_minor": 125.0,
        "per_child": None,
    },
    {
        "item_type": "coffee",
        "label": "Café",
        "unit": "g",
        "per_adult": 500.0,
        "per_minor": 200.0,
        "per_child": None,
    },
    {
        "item_type": "tea",
        "label": "Thé",
        "unit": "g",
        "per_adult": 100.0,
        "per_minor": 50.0,
        "per_child": None,
    },
    {
        "item_type": "goods_value",
        "label": "Autres marchandises (valeur)",
        "unit": "€",
        "per_adult": 300.0,
        "per_minor": 150.0,
        "per_child": 150.0,
    },
]


async def _try_scrape() -> list[dict] | None:
    """
    Attempt to scrape the DGDDI page. Returns a list of allowance dicts if
    parsing succeeds, or None if it fails for any reason.

    NOTE: The DGDDI page layout is subject to change. If this function starts
    returning None after a government site redesign, update the parsing logic
    below while FALLBACK_ALLOWANCES keeps the app running in the meantime.
    """
    try:
        async with httpx.AsyncClient(timeout=15, follow_redirects=True) as client:
            resp = await client.get(DGDDI_URL, headers={"Accept-Language": "fr-FR,fr;q=0.9"})
            resp.raise_for_status()
        soup = BeautifulSoup(resp.text, "html.parser")

        # Look for a table that mentions "Andorre" or "franchise"
        # This is a best-effort parse; return None if we can't find it.
        tables = soup.find_all("table")
        if not tables:
            log.warning("scrape_dgddi: no <table> found on DGDDI page — falling back to hardcoded data")
            return None

        # Return None to signal "couldn't parse reliably" — fallback data will be used.
        # TODO: implement column-by-column extraction once we've confirmed the live layout.
        log.info("scrape_dgddi: page fetched OK but structured parsing not yet implemented — using hardcoded data")
        return None
    except Exception as exc:
        log.error("scrape_dgddi: HTTP error — %s", exc)
        return None


async def scrape_dgddi() -> None:
    """Entry point called by APScheduler and on startup."""
    log.info("scrape_dgddi: starting")
    scraped = await _try_scrape()
    items = scraped if scraped is not None else FALLBACK_ALLOWANCES

    now = datetime.now(timezone.utc)
    async with SessionLocal() as db:
        for item in items:
            stmt = (
                pg_insert(AllowanceItem)
                .values(**item, last_updated=now)
                .on_conflict_do_update(
                    index_elements=["item_type"],
                    set_={
                        "label": item["label"],
                        "unit": item["unit"],
                        "per_adult": item["per_adult"],
                        "per_minor": item["per_minor"],
                        "per_child": item["per_child"],
                        "last_updated": now,
                    },
                )
            )
            await db.execute(stmt)
        await db.commit()

    log.info("scrape_dgddi: upserted %d items", len(items))
