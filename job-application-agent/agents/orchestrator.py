"""
Orchestrator — coordinates all agents in the pipeline.
Emits progress events via asyncio.Queue for UI consumption.
"""
import asyncio
import logging
from datetime import datetime
from typing import Callable, Optional

from config import settings
from agents.job_finder import JobFinderAgent
from agents.job_analyzer import JobAnalyzerAgent
from agents.cv_tailor import CVTailorAgent
from agents.ats_optimizer import ATSOptimizerAgent

logger = logging.getLogger(__name__)


class PipelineEvent:
    def __init__(self, stage: str, message: str, data: dict = None):
        self.stage = stage
        self.message = message
        self.data = data or {}
        self.timestamp = datetime.utcnow().isoformat()

    def __repr__(self):
        return f"[{self.stage}] {self.message}"


class Orchestrator:
    def __init__(self, event_queue: Optional[asyncio.Queue] = None):
        self.event_queue = event_queue or asyncio.Queue()
        self.job_finder = JobFinderAgent(
            sites=["remotive", "indeed", "linkedin"]
        )
        self.job_analyzer = JobAnalyzerAgent()
        self.cv_tailor = CVTailorAgent()
        self.ats_optimizer = ATSOptimizerAgent()
        self._running = False

    async def _emit(self, stage: str, message: str, data: dict = None):
        event = PipelineEvent(stage, message, data)
        logger.info(str(event))
        await self.event_queue.put(event)

    async def run_cycle(self) -> dict:
        """
        Run one full pipeline cycle:
        1. Find new jobs
        2. Analyze new jobs
        3. Tailor CVs for good matches
        4. Optimize ATS scores

        Returns summary dict.
        """
        summary = {
            "start_time": datetime.utcnow().isoformat(),
            "jobs_found": 0,
            "jobs_analyzed": 0,
            "cvs_tailored": 0,
            "cvs_optimized": 0,
            "errors": [],
        }

        # Step 1: Find jobs
        await self._emit("job_finder", "Starting job search...")
        try:
            new_jobs = await self.job_finder.search(
                queries=settings.target_roles,
                location="remote",
                max_per_site=settings.max_results_per_site,
            )
            summary["jobs_found"] = new_jobs
            await self._emit("job_finder", f"Found {new_jobs} new jobs.")
        except Exception as e:
            msg = f"Job finder failed: {e}"
            logger.error(msg)
            summary["errors"].append(msg)

        # Step 2: Analyze jobs
        await self._emit("job_analyzer", "Analyzing new jobs...")
        try:
            analyzed = await self.job_analyzer.analyze_new_jobs(limit=50)
            summary["jobs_analyzed"] = analyzed
            await self._emit("job_analyzer", f"Analyzed {analyzed} jobs.")
        except Exception as e:
            msg = f"Job analyzer failed: {e}"
            logger.error(msg)
            summary["errors"].append(msg)

        # Step 3: Tailor CVs
        await self._emit("cv_tailor", "Tailoring CVs...")
        try:
            tailored = await self.cv_tailor.tailor_analyzed_jobs(
                min_match_score=settings.min_match_score,
                limit=10,
            )
            summary["cvs_tailored"] = tailored
            await self._emit("cv_tailor", f"Tailored {tailored} CVs.")
        except Exception as e:
            msg = f"CV tailor failed: {e}"
            logger.error(msg)
            summary["errors"].append(msg)

        # Step 4: Optimize ATS
        await self._emit("ats_optimizer", "Optimizing ATS scores...")
        try:
            optimized = await self.ats_optimizer.optimize_tailored_jobs()
            summary["cvs_optimized"] = optimized
            await self._emit("ats_optimizer", f"Optimized {optimized} CVs.")
        except Exception as e:
            msg = f"ATS optimizer failed: {e}"
            logger.error(msg)
            summary["errors"].append(msg)

        summary["end_time"] = datetime.utcnow().isoformat()
        await self._emit("orchestrator", "Cycle complete.", summary)
        return summary

    async def run_autonomous(self, cycles: int = -1, callback: Callable = None):
        """
        Run pipeline autonomously, looping every search_interval_hours.
        cycles=-1 means run forever.
        """
        self._running = True
        cycle_count = 0

        while self._running:
            if cycles != -1 and cycle_count >= cycles:
                break

            cycle_count += 1
            logger.info(f"\n{'='*60}\nStarting Pipeline Cycle {cycle_count}\n{'='*60}")

            summary = await self.run_cycle()

            if callback:
                callback(summary)

            logger.info(f"Cycle {cycle_count} summary: {summary}")

            if cycles != -1 and cycle_count >= cycles:
                break

            # Wait for next cycle
            wait_seconds = settings.search_interval_hours * 3600
            logger.info(f"Waiting {settings.search_interval_hours}h until next cycle...")
            await self._emit(
                "orchestrator",
                f"Sleeping {settings.search_interval_hours}h until next cycle.",
            )
            await asyncio.sleep(wait_seconds)

        self._running = False
        logger.info("Orchestrator stopped.")

    def stop(self):
        self._running = False
