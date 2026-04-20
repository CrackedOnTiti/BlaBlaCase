"""
Daily cron job — scrapes DGDDI customs allowances for goods brought from Andorra
and upserts them into the allowance_items table.

Target page: https://www.douane.gouv.fr/passer-la-douane-en-andorre-taxes-et-franchises

If the scrape fails we log the error and leave existing DB data untouched —
the app keeps serving the last successful values.
"""
import logging
import re
from datetime import datetime, timezone

import httpx
from sqlalchemy.dialects.postgresql import insert as pg_insert

from api.db import SessionLocal
from api.models import AllowanceItem

log = logging.getLogger(__name__)

DGDDI_URL = "https://www.douane.gouv.fr/passer-la-douane-en-andorre-taxes-et-franchises"
_ACCORDION   = '<div class="accordion accordeonGris">'
_CONTENT_DIV = '<div class="clearfix text-formatted field field--name-field-contenu-principal field--type-text-with-summary field--label-hidden field__item">'

FALLBACK_ALLOWANCES: list[dict] = [
    {"item_type": "spirits",         "label": "Spiritueux (> 22° vol.)",            "unit": "L",      "per_adult": 1.5,    "per_minor": None, "per_child": None},
    {"item_type": "beverages_low",   "label": "Boissons alcoolisées (≤ 22° vol.)",  "unit": "L",      "per_adult": 3.0,    "per_minor": None, "per_child": None},
    {"item_type": "still_wine",      "label": "Vin tranquille",                      "unit": "L",      "per_adult": 5.0,    "per_minor": None, "per_child": None},
    {"item_type": "cigarettes",      "label": "Cigarettes",                          "unit": "unités", "per_adult": 300.0,  "per_minor": None, "per_child": None},
    {"item_type": "cigarillos",      "label": "Cigarillos (max. 3g/pièce)",         "unit": "unités", "per_adult": 150.0,  "per_minor": None, "per_child": None},
    {"item_type": "cigars",          "label": "Cigares",                             "unit": "unités", "per_adult": 75.0,   "per_minor": None, "per_child": None},
    {"item_type": "tobacco",         "label": "Tabac à rouler",                      "unit": "g",      "per_adult": 400.0,  "per_minor": None, "per_child": None},
    {"item_type": "perfume",         "label": "Parfum",                              "unit": "mL",     "per_adult": 75.0,   "per_minor": None, "per_child": None},
    {"item_type": "eau_de_toilette", "label": "Eau de toilette",                     "unit": "mL",     "per_adult": 375.0,  "per_minor": None, "per_child": None},
    {"item_type": "coffee",          "label": "Café",                                "unit": "g",      "per_adult": 1000.0, "per_minor": None, "per_child": None},
    {"item_type": "coffee_extract",  "label": "Extraits et essences de café",        "unit": "g",      "per_adult": 400.0,  "per_minor": None, "per_child": None},
    {"item_type": "tea",             "label": "Thé",                                 "unit": "g",      "per_adult": 200.0,  "per_minor": None, "per_child": None},
    {"item_type": "tea_extract",     "label": "Extraits et essences de thé",         "unit": "g",      "per_adult": 80.0,   "per_minor": None, "per_child": None},
    {"item_type": "food_value",      "label": "Denrées alimentaires (valeur max.)",  "unit": "€",      "per_adult": 300.0,  "per_minor": None, "per_child": 150.0},
]

# (section_keyword, label_keyword_or_None, item_type, db_field)
# Order matters: specific rules before catch-alls
_RULES: list[tuple[str, str | None, str, str]] = [
    ("TABAC",   "cigarette",   "cigarettes",      "per_adult"),
    ("TABAC",   "cigarillo",   "cigarillos",      "per_adult"),
    ("TABAC",   "cigare",      "cigars",          "per_adult"),
    ("TABAC",   "tabac",       "tobacco",         "per_adult"),
    ("ALCOOL",  "ou moins",    "beverages_low",   "per_adult"),
    ("ALCOOL",  "tranquille",  "still_wine",      "per_adult"),
    ("ALCOOL",  "22",          "spirits",         "per_adult"),
    ("CAF",     "extrait",     "coffee_extract",  "per_adult"),
    ("CAF",     "essence",     "coffee_extract",  "per_adult"),
    ("CAF",     None,          "coffee",          "per_adult"),
    ("TH",      "extrait",     "tea_extract",     "per_adult"),
    ("TH",      "essence",     "tea_extract",     "per_adult"),
    ("TH",      None,          "tea",             "per_adult"),
    ("PARFUM",  None,          "perfume",         "per_adult"),
    ("EAUX",    None,          "eau_de_toilette", "per_adult"),
    ("DENR",    "15 ans et",   "food_value",      "per_adult"),
    ("DENR",    "moins de 15", "food_value",      "per_child"),
]


def _strip_tags(text: str) -> str:
    text = re.sub(r'<sup[^>]*>.*?</sup>', '', text, flags=re.DOTALL)
    text = re.sub(r'<[^>]+>', '', text)
    return text.replace('&nbsp;', ' ').strip()


def _normalize(value_str: str, unit_str: str) -> tuple[float, str]:
    value = float(value_str.replace(',', '.'))
    u = unit_str.lower().rstrip('s').strip('.')
    if u in ('litre', 'l'):        return value, 'L'
    if u == 'cl':                  return round(value * 10, 1), 'mL'
    if u in ('ml', 'millilitre'):  return value, 'mL'
    if u == 'kg':                  return round(value * 1000, 1), 'g'
    if u == 'g':                   return value, 'g'
    if u in ('unité', 'unite'):    return value, 'unités'
    if u in ('euro', '€'):         return value, '€'
    return value, unit_str


def _parse_table(content: str) -> list[tuple[str, str, str]]:
    results = []
    for row in re.findall(r'<tr>(.*?)</tr>', content, re.DOTALL):
        cells = re.findall(r'<td>(.*?)</td>', row, re.DOTALL)
        if len(cells) >= 2:
            label = _strip_tags(cells[0])
            parts = _strip_tags(cells[1]).split()
            if len(parts) >= 2:
                results.append((label, parts[0], ' '.join(parts[1:])))
    return results


def _parse_nbsp(content: str, title: str) -> list[tuple[str, str, str]]:
    results = []
    pos = 0
    while True:
        nbsp = content.find('&nbsp;', pos)
        if nbsp == -1:
            break
        before = content[:nbsp]
        after  = content[nbsp + len('&nbsp;'):]
        colon  = before.rfind(':')
        if colon == -1:
            pos = nbsp + 1
            continue
        value    = _strip_tags(before[colon + 1:]).strip()
        next_tag = after.find('<')
        unit     = after[:next_tag].strip() if next_tag != -1 else after.strip()
        if value and unit:
            results.append((title.capitalize(), value, unit))
        pos = nbsp + 1
    return results


def _parse_sections(html: str) -> list[tuple[str, list[tuple[str, str, str]]]]:
    idx = html.find(_ACCORDION)
    if idx == -1:
        return []
    html = html[idx:]

    sections = []
    for m in re.finditer(r'<span[^>]*>([^<]+)</span>', html):
        text = m.group(1).strip()
        if text != text.upper() or not any(c.isalpha() for c in text):
            continue
        content_start = html.find(_CONTENT_DIV, m.end())
        if content_start == -1:
            continue
        content_end = html.find('</div>', content_start + len(_CONTENT_DIV))
        content = html[content_start + len(_CONTENT_DIV):content_end].strip()
        items = _parse_table(content) if '<td>' in content else _parse_nbsp(content, text)
        sections.append((text, items))
    return sections


def _map_to_items(sections: list[tuple[str, list[tuple[str, str, str]]]]) -> dict[str, dict]:
    fallback_by_type = {f["item_type"]: f for f in FALLBACK_ALLOWANCES}
    result: dict[str, dict] = {}

    for title, rows in sections:
        title_up = title.upper()
        for label, value_str, unit_str in rows:
            label_low = label.lower()
            for sec_kw, lbl_kw, item_type, field in _RULES:
                if sec_kw not in title_up:
                    continue
                if lbl_kw is not None and lbl_kw not in label_low:
                    continue
                try:
                    value, unit = _normalize(value_str, unit_str)
                except ValueError:
                    log.debug("scrape_dgddi: could not parse '%s %s'", value_str, unit_str)
                    break
                if item_type not in result:
                    base = fallback_by_type.get(item_type, {})
                    result[item_type] = {
                        "item_type": item_type,
                        "label":     base.get("label", label),
                        "unit":      unit,
                        "per_adult": base.get("per_adult"),
                        "per_minor": base.get("per_minor"),
                        "per_child": base.get("per_child"),
                    }
                result[item_type][field] = value
                result[item_type]["unit"] = unit
                log.debug("scrape_dgddi: %s.%s = %.3f %s", item_type, field, value, unit)
                break

    return result


async def _try_scrape() -> list[dict] | None:
    try:
        async with httpx.AsyncClient(timeout=20, follow_redirects=True) as client:
            resp = await client.get(
                DGDDI_URL,
                headers={"Accept-Language": "fr-FR,fr;q=0.9", "User-Agent": "Mozilla/5.0"},
            )
            resp.raise_for_status()
    except Exception as exc:
        log.error("scrape_dgddi: HTTP error — %s", exc)
        return None

    sections = _parse_sections(resp.text)
    if not sections:
        log.warning("scrape_dgddi: accordion marker not found — layout may have changed")
        return None

    scraped = _map_to_items(sections)
    if not scraped:
        log.warning("scrape_dgddi: no items matched — layout may have changed")
        return None

    merged = []
    for item in FALLBACK_ALLOWANCES:
        if item["item_type"] in scraped:
            merged.append(scraped[item["item_type"]])
        else:
            log.info("scrape_dgddi: '%s' not on page, using hardcoded value", item["item_type"])
            merged.append(item)

    log.info("scrape_dgddi: parsed %d/%d items from live page", len(scraped), len(FALLBACK_ALLOWANCES))
    return merged


async def scrape_dgddi() -> None:
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
                        "label":        item["label"],
                        "unit":         item["unit"],
                        "per_adult":    item["per_adult"],
                        "per_minor":    item["per_minor"],
                        "per_child":    item["per_child"],
                        "last_updated": now,
                    },
                )
            )
            await db.execute(stmt)
        await db.commit()

    log.info("scrape_dgddi: upserted %d items", len(items))
