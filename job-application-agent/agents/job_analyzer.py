"""
Job Analyzer Agent — uses LLM to extract structured info from job descriptions.
"""
import logging
import re

from database.init_db import SessionLocal
from database.models import Job, JobStatus
from utils.llm_client import get_llm_client

logger = logging.getLogger(__name__)

ANALYSIS_SYSTEM = (
    "You are an expert job description analyzer. "
    "Extract structured information and always respond with valid JSON only."
)

ANALYSIS_PROMPT = """Analyze this job description and extract key information.

JOB TITLE: {title}
COMPANY: {company}
DESCRIPTION:
{description}

Return this exact JSON structure:
{{
  "required_skills": ["skill1", "skill2"],
  "preferred_skills": ["skill1", "skill2"],
  "tech_stack": ["tech1", "tech2"],
  "key_responsibilities": ["resp1", "resp2"],
  "seniority_level": "entry|junior|mid|senior|lead",
  "experience_years_required": 0,
  "education_required": "bachelor|master|phd|any",
  "is_remote": true,
  "match_score": 0.7,
  "summary": "2-3 sentence plain English summary",
  "red_flags": ["flag1"]
}}

For match_score (0.0-1.0), assess fit for a data professional with Python, SQL, ML skills."""


class JobAnalyzerAgent:
    def __init__(self):
        self.llm = get_llm_client()

    async def analyze_job(self, job: Job) -> dict:
        """Analyze a single job, return analysis dict."""
        description = job.raw_description or job.requirements or ""
        if not description:
            description = f"{job.title} at {job.company}"

        prompt = ANALYSIS_PROMPT.format(
            title=job.title,
            company=job.company,
            description=description[:2500],
        )

        analysis = await self.llm.generate_json(prompt, ANALYSIS_SYSTEM)
        if not analysis:
            # Fallback minimal analysis
            analysis = {
                "required_skills": [],
                "preferred_skills": [],
                "tech_stack": [],
                "key_responsibilities": [],
                "seniority_level": "entry",
                "experience_years_required": 0,
                "is_remote": True,
                "match_score": 0.5,
                "summary": f"{job.title} role at {job.company}",
                "red_flags": [],
            }

        return analysis

    async def analyze_new_jobs(self, limit: int = 50) -> int:
        """Analyze all NEW jobs in DB. Returns count processed."""
        db = SessionLocal()
        processed = 0
        try:
            jobs = (
                db.query(Job)
                .filter(Job.status == JobStatus.NEW)
                .limit(limit)
                .all()
            )
            logger.info(f"Analyzing {len(jobs)} new jobs...")

            for job in jobs:
                try:
                    analysis = await self.analyze_job(job)
                    job.analysis_json = analysis
                    job.match_score = float(analysis.get("match_score", 0.5))
                    job.status = JobStatus.ANALYZED
                    db.commit()
                    processed += 1
                    logger.info(
                        f"Analyzed: {job.title} @ {job.company} "
                        f"(match: {job.match_score:.0%})"
                    )
                except Exception as e:
                    db.rollback()
                    logger.error(f"Failed to analyze job {job.id}: {e}")

        finally:
            db.close()

        logger.info(f"Analysis complete: {processed} jobs processed.")
        return processed
