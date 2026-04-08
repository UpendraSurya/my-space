"""
Job board scrapers using Playwright + BeautifulSoup.
Implements one class per job site, all sharing a common interface.
"""
import asyncio
import logging
import random
import re
from abc import ABC, abstractmethod
from datetime import datetime
from typing import Optional
from urllib.parse import urlencode, urlparse, urlunparse

from bs4 import BeautifulSoup

logger = logging.getLogger(__name__)

USER_AGENTS = [
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_5) AppleWebKit/605.1.15 "
    "(KHTML, like Gecko) Version/16.5 Safari/605.1.15",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36",
]


def normalize_url(url: str) -> str:
    """Strip tracking params, normalize URL for deduplication."""
    parsed = urlparse(url)
    # Keep only path for LinkedIn, as query strings contain tracking
    if "linkedin.com" in parsed.netloc:
        return urlunparse(parsed._replace(query="", fragment=""))
    return urlunparse(parsed._replace(fragment=""))


class JobScraper(ABC):
    """Base class for all job board scrapers."""

    @abstractmethod
    async def scrape(self, query: str, location: str = "remote",
                     max_results: int = 20) -> list[dict]:
        """Return list of job dicts with keys: title, company, location,
        salary, url, description, requirements, posted_date, source"""
        pass

    async def _random_delay(self, min_s: float = 2.0, max_s: float = 6.0):
        await asyncio.sleep(random.uniform(min_s, max_s))


class IndeedScraper(JobScraper):
    """Scrapes Indeed job listings."""

    async def scrape(self, query: str, location: str = "remote",
                     max_results: int = 20) -> list[dict]:
        try:
            from playwright.async_api import async_playwright
        except ImportError:
            logger.error("playwright not installed. Run: pip install playwright && playwright install")
            return []

        jobs = []
        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=True)
            context = await browser.new_context(
                user_agent=random.choice(USER_AGENTS),
                viewport={"width": 1280, "height": 800},
            )
            page = await context.new_page()

            try:
                params = urlencode({"q": query, "l": location, "sort": "date"})
                url = f"https://www.indeed.com/jobs?{params}"
                await page.goto(url, wait_until="domcontentloaded", timeout=30000)
                await self._random_delay(2, 4)

                content = await page.content()
                soup = BeautifulSoup(content, "html.parser")

                job_cards = soup.find_all("div", {"class": re.compile(r"job_seen_beacon|resultContent")})
                logger.info(f"Indeed: found {len(job_cards)} cards for '{query}'")

                for card in job_cards[:max_results]:
                    try:
                        title_el = card.find("h2", {"class": re.compile(r"jobTitle")})
                        company_el = card.find(attrs={"data-testid": "company-name"})
                        location_el = card.find(attrs={"data-testid": "text-location"})
                        salary_el = card.find(attrs={"data-testid": "attribute_snippet_testid"})

                        title = title_el.get_text(strip=True) if title_el else "Unknown"
                        company = company_el.get_text(strip=True) if company_el else "Unknown"
                        loc = location_el.get_text(strip=True) if location_el else location
                        salary = salary_el.get_text(strip=True) if salary_el else ""

                        link_el = card.find("a", href=True)
                        job_url = ""
                        if link_el:
                            href = link_el["href"]
                            if href.startswith("/"):
                                job_url = f"https://www.indeed.com{href}"
                            else:
                                job_url = href
                        job_url = normalize_url(job_url)

                        if title != "Unknown" and job_url:
                            jobs.append({
                                "title": title,
                                "company": company,
                                "location": loc,
                                "salary": salary,
                                "url": job_url,
                                "description": "",
                                "requirements": "",
                                "posted_date": datetime.utcnow().strftime("%Y-%m-%d"),
                                "source": "indeed",
                            })
                    except Exception as e:
                        logger.debug(f"Indeed card parse error: {e}")

            except Exception as e:
                logger.error(f"Indeed scrape failed for '{query}': {e}")
            finally:
                await browser.close()

        return jobs


class RemotiveScraper(JobScraper):
    """Scrapes Remotive API (free, no auth required, no ToS issues)."""

    REMOTIVE_URL = "https://remotive.com/api/remote-jobs"

    async def scrape(self, query: str, location: str = "remote",
                     max_results: int = 20) -> list[dict]:
        import httpx
        jobs = []
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                resp = await client.get(
                    self.REMOTIVE_URL,
                    params={"search": query, "limit": max_results},
                    headers={"User-Agent": random.choice(USER_AGENTS)},
                )
                resp.raise_for_status()
                data = resp.json()
                for job in data.get("jobs", []):
                    jobs.append({
                        "title": job.get("title", ""),
                        "company": job.get("company_name", ""),
                        "location": job.get("candidate_required_location", "Remote"),
                        "salary": job.get("salary", ""),
                        "url": normalize_url(job.get("url", "")),
                        "description": BeautifulSoup(
                            job.get("description", ""), "html.parser"
                        ).get_text(separator="\n", strip=True)[:3000],
                        "requirements": "",
                        "posted_date": job.get("publication_date", "")[:10],
                        "source": "remotive",
                    })
        except Exception as e:
            logger.error(f"Remotive scrape failed for '{query}': {e}")
        return jobs


class AdzunaScraper(JobScraper):
    """Scrapes Adzuna API — free tier, 250 calls/day."""

    BASE_URL = "https://api.adzuna.com/v1/api/jobs/us/search/1"

    def __init__(self, app_id: str = "", app_key: str = ""):
        self.app_id = app_id or "test"
        self.app_key = app_key or "test"

    async def scrape(self, query: str, location: str = "remote",
                     max_results: int = 20) -> list[dict]:
        import httpx
        jobs = []
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                resp = await client.get(
                    self.BASE_URL,
                    params={
                        "app_id": self.app_id,
                        "app_key": self.app_key,
                        "what": query,
                        "where": location,
                        "results_per_page": min(max_results, 50),
                        "content-type": "application/json",
                    },
                )
                resp.raise_for_status()
                data = resp.json()
                for job in data.get("results", []):
                    jobs.append({
                        "title": job.get("title", ""),
                        "company": job.get("company", {}).get("display_name", ""),
                        "location": job.get("location", {}).get("display_name", ""),
                        "salary": (
                            f"${job.get('salary_min', '')}-${job.get('salary_max', '')}"
                            if job.get("salary_min") else ""
                        ),
                        "url": normalize_url(job.get("redirect_url", "")),
                        "description": job.get("description", "")[:3000],
                        "requirements": "",
                        "posted_date": job.get("created", "")[:10],
                        "source": "adzuna",
                    })
        except Exception as e:
            logger.error(f"Adzuna scrape failed for '{query}': {e}")
        return jobs


class LinkedInPublicScraper(JobScraper):
    """Scrapes LinkedIn public job listings (no login required)."""

    async def scrape(self, query: str, location: str = "remote",
                     max_results: int = 20) -> list[dict]:
        try:
            from playwright.async_api import async_playwright
        except ImportError:
            logger.error("playwright not installed.")
            return []

        jobs = []
        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=True)
            context = await browser.new_context(
                user_agent=random.choice(USER_AGENTS),
                viewport={"width": 1280, "height": 900},
            )
            page = await context.new_page()
            try:
                params = urlencode({
                    "keywords": query,
                    "location": location,
                    "f_E": "1,2",  # Entry level, Associate
                    "sortBy": "DD",
                })
                url = f"https://www.linkedin.com/jobs/search/?{params}"
                await page.goto(url, wait_until="domcontentloaded", timeout=30000)
                await self._random_delay(3, 5)

                # Scroll to load more results
                for _ in range(3):
                    await page.evaluate("window.scrollBy(0, 600)")
                    await asyncio.sleep(1)

                content = await page.content()
                soup = BeautifulSoup(content, "html.parser")

                cards = soup.find_all("div", {"class": re.compile(r"base-card|job-search-card")})
                logger.info(f"LinkedIn: found {len(cards)} cards for '{query}'")

                for card in cards[:max_results]:
                    try:
                        title_el = card.find("h3", {"class": re.compile(r"base-search-card__title")})
                        company_el = card.find("h4", {"class": re.compile(r"base-search-card__subtitle")})
                        location_el = card.find("span", {"class": re.compile(r"job-search-card__location")})
                        link_el = card.find("a", {"class": re.compile(r"base-card__full-link")})

                        title = title_el.get_text(strip=True) if title_el else "Unknown"
                        company = company_el.get_text(strip=True) if company_el else "Unknown"
                        loc = location_el.get_text(strip=True) if location_el else location
                        job_url = normalize_url(link_el["href"]) if link_el else ""

                        if title != "Unknown" and job_url:
                            jobs.append({
                                "title": title,
                                "company": company,
                                "location": loc,
                                "salary": "",
                                "url": job_url,
                                "description": "",
                                "requirements": "",
                                "posted_date": datetime.utcnow().strftime("%Y-%m-%d"),
                                "source": "linkedin",
                            })
                    except Exception as e:
                        logger.debug(f"LinkedIn card parse error: {e}")

            except Exception as e:
                logger.error(f"LinkedIn scrape failed for '{query}': {e}")
            finally:
                await browser.close()

        return jobs


class ScraperRegistry:
    """Central registry of all scrapers."""

    def __init__(self):
        self.scrapers = {
            "remotive": RemotiveScraper(),
            "indeed": IndeedScraper(),
            "linkedin": LinkedInPublicScraper(),
        }

    def get(self, name: str) -> Optional[JobScraper]:
        return self.scrapers.get(name)

    def all_scrapers(self) -> list[tuple[str, JobScraper]]:
        return list(self.scrapers.items())
