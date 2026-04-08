"""
ATS Optimizer Agent — scores and iteratively improves CVs for ATS compatibility.
"""
import logging
import os

from config import settings
from database.init_db import SessionLocal
from database.models import Job, JobStatus, Application, ATSScore
from utils.ats_scorer import score_cv, ATSScoreResult
from utils.latex_handler import read_template, find_placeholders, fill_placeholders, write_tex, compile_latex
from utils.llm_client import get_llm_client

logger = logging.getLogger(__name__)

IMPROVE_SYSTEM = (
    "You are an ATS optimization expert. Help improve CV content to better match "
    "job requirements and pass Applicant Tracking Systems. Respond with JSON only."
)


class ATSOptimizerAgent:
    def __init__(self):
        self.llm = get_llm_client()

    async def _improve_section(self, section_name: str, current_content: str,
                                missing_keywords: list[str], job_description: str) -> str:
        """Ask LLM to improve a CV section to include missing keywords."""
        keywords_str = ", ".join(missing_keywords[:10])
        prompt = (
            f"Improve this CV section to better match the job requirements.\n"
            f"Section: {section_name}\n"
            f"Current content:\n{current_content}\n\n"
            f"Missing keywords to naturally incorporate: {keywords_str}\n"
            f"Job context (first 500 chars): {job_description[:500]}\n\n"
            f"Rules: Keep content truthful and professional. Don't keyword-stuff. "
            f"Return JSON: {{\"improved_content\": \"<improved text>\"}}"
        )
        result = await self.llm.generate_json(prompt, IMPROVE_SYSTEM)
        return result.get("improved_content", current_content)

    async def optimize_application(self, application: Application,
                                    job: Job) -> ATSScoreResult:
        """
        Run ATS optimization loop on an application.
        Returns final ATSScoreResult.
        """
        if not application.tex_path or not os.path.exists(application.tex_path):
            logger.error(f"No .tex file for application {application.id}")
            return ATSScoreResult()

        tex_content = read_template(application.tex_path)
        job_description = job.raw_description or job.requirements or job.title

        best_score = None
        best_tex = tex_content

        for iteration in range(settings.max_ats_iterations):
            score = await score_cv(
                job_description=job_description,
                cv_tex_content=tex_content,
                cv_text_plain="",
            )
            logger.info(
                f"ATS iteration {iteration+1}: score={score.total_score:.1f}/100 "
                f"(job: {job.title})"
            )

            # Save score to DB
            db = SessionLocal()
            try:
                ats_score = ATSScore(
                    application_id=application.id,
                    keyword_score=score.keyword_score,
                    formatting_score=score.formatting_score,
                    relevance_score=score.relevance_score,
                    completeness_score=score.completeness_score,
                    total_score=score.total_score,
                    iteration=iteration,
                    breakdown_json=score.breakdown,
                )
                db.add(ats_score)
                db.commit()
            finally:
                db.close()

            if best_score is None or score.total_score > best_score.total_score:
                best_score = score
                best_tex = tex_content

            # If score is good enough, stop
            if score.total_score >= settings.ats_target_score:
                logger.info(f"Target ATS score {settings.ats_target_score} reached!")
                break

            # If on last iteration, stop
            if iteration == settings.max_ats_iterations - 1:
                break

            # Try to improve — focus on keyword gaps
            if score.missing_keywords:
                placeholders = find_placeholders(tex_content)
                # Improve skills or summary section if present
                for target_ph in ["SKILLS_LIST", "PROFESSIONAL_SUMMARY", "EXPERIENCE_SECTION"]:
                    if target_ph in placeholders:
                        # Extract current content for this placeholder
                        # (approximated by finding content between markers if present)
                        improved = await self._improve_section(
                            target_ph,
                            f"[Data professional skills for {job.title}]",
                            score.missing_keywords,
                            job_description,
                        )
                        tex_content = tex_content.replace(
                            f"[{target_ph}]", improved
                        )
                        break

                # Write improved version
                write_tex(tex_content, application.tex_path)
                logger.info(f"Wrote improved .tex for iteration {iteration+2}")

        # Re-compile with best version
        if best_tex != tex_content:
            write_tex(best_tex, application.tex_path)

        success, result = compile_latex(application.tex_path, settings.cvs_dir)
        if success:
            db = SessionLocal()
            try:
                app = db.query(Application).filter(Application.id == application.id).first()
                if app:
                    app.cv_path = result
                    app.ats_score = best_score.total_score
                    db.commit()
            finally:
                db.close()

        return best_score or ATSScoreResult()

    async def optimize_tailored_jobs(self) -> int:
        """Run ATS optimization on all CV_TAILORED jobs."""
        db = SessionLocal()
        processed = 0
        try:
            jobs_with_apps = (
                db.query(Job, Application)
                .join(Application, Job.id == Application.job_id)
                .filter(Job.status == JobStatus.CV_TAILORED)
                .all()
            )
            logger.info(f"Optimizing {len(jobs_with_apps)} CVs...")

            for job, app in jobs_with_apps:
                try:
                    score = await self.optimize_application(app, job)
                    job.status = JobStatus.ATS_OPTIMIZED
                    if score.total_score >= 60:
                        job.status = JobStatus.READY
                    db.commit()
                    processed += 1
                    logger.info(
                        f"Optimized: {job.title} @ {job.company} -> "
                        f"ATS: {score.total_score:.1f}"
                    )
                except Exception as e:
                    db.rollback()
                    logger.error(f"ATS optimization failed for job {job.id}: {e}")
        finally:
            db.close()

        return processed
