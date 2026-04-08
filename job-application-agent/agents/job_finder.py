"""
Job Finder Agent — searches multiple job boards and persists results to DB.
"""
import asyncio
import logging
from datetime import datetime

from database.init_db import SessionLocal
from database.models import Job, JobStatus
from utils.scraper import ScraperRegistry

logger = logging.getLogger(__name__)


class JobFinderAgent:
    def __init__(self, sites: list[str] = None):
        self.registry = ScraperRegistry()
        self.sites = sites or ["remotive", "indeed", "linkedin"]

    async def _scrape_site(self, site_name: str, query: str, location: str,
                            max_results: int) -> list[dict]:
        scraper = self.registry.get(site_name)
        if not scraper:
            logger.warning(f"Unknown scraper: {site_name}")
            return []
        logger.info(f"Searching {site_name} for '{query}'...")
        try:
            jobs = await scraper.scrape(query, location, max_results)
            logger.info(f"{site_name}: {len(jobs)} jobs found for '{query}'")
            return jobs
        except Exception as e:
            logger.error(f"{site_name} scrape failed: {e}")
            return []

    def _deduplicate(self, jobs: list[dict]) -> list[dict]:
        seen_urls: set[str] = set()
        unique = []
        for job in jobs:
            url = job.get("url", "").strip()
            if url and url not in seen_urls:
                seen_urls.add(url)
                unique.append(job)
        return unique

    def _save_jobs(self, raw_jobs: list[dict]) -> tuple[int, int]:
        """Save jobs to DB. Returns (new_count, duplicate_count)."""
        db = SessionLocal()
        new_count = 0
        dup_count = 0
        try:
            for j in raw_jobs:
                url = j.get("url", "").strip()
                if not url:
                    continue
                existing = db.query(Job).filter(Job.url == url).first()
                if existing:
                    dup_count += 1
                    continue
                job = Job(
                    title=j.get("title", "Unknown")[:256],
                    company=j.get("company", "Unknown")[:256],
                    location=(j.get("location") or "")[:256],
                    salary=(j.get("salary") or "")[:128],
                    url=url[:1024],
                    source=j.get("source", "")[:64],
                    raw_description=j.get("description", ""),
                    requirements=j.get("requirements", ""),
                    posted_date=j.get("posted_date", ""),
                    found_date=datetime.utcnow(),
                    status=JobStatus.NEW,
                )
                db.add(job)
                new_count += 1
            db.commit()
        except Exception as e:
            db.rollback()
            logger.error(f"DB save failed: {e}")
        finally:
            db.close()
        return new_count, dup_count

    async def search(self, queries: list[str], location: str = "remote",
                     max_per_site: int = 20) -> int:
        """
        Search all configured sites for all queries concurrently.
        Returns total new jobs saved to DB.
        """
        tasks = [
            self._scrape_site(site, query, location, max_per_site)
            for site in self.sites
            for query in queries
        ]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        all_jobs = []
        for r in results:
            if isinstance(r, list):
                all_jobs.extend(r)
            elif isinstance(r, Exception):
                logger.error(f"Scrape task exception: {r}")

        unique_jobs = self._deduplicate(all_jobs)
        logger.info(f"Total unique jobs found: {len(unique_jobs)}")

        new_count, dup_count = self._save_jobs(unique_jobs)
        logger.info(f"Saved {new_count} new jobs, skipped {dup_count} duplicates.")
        return new_count
