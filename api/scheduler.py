"""
Standalone scheduler process — runs in its own Docker container.
Keeps jobs out of the API workers so they never fire multiple times
when running multiple uvicorn workers or gunicorn.
"""
import asyncio
import logging

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger

from api.db import init_db
from api.jobs.scrape_dgddi import scrape_dgddi

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)


async def main():
    await init_db()
    await scrape_dgddi()  # run once on startup

    scheduler = AsyncIOScheduler()
    scheduler.add_job(scrape_dgddi, CronTrigger(hour=0, minute=0))
    scheduler.start()

    log.info("Scheduler running.")
    try:
        while True:
            await asyncio.sleep(3600)
    except (KeyboardInterrupt, SystemExit):
        scheduler.shutdown()


if __name__ == "__main__":
    asyncio.run(main())
