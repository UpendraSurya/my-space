"""
CV Tailor Agent — fills LaTeX template placeholders with job-specific content.
Uses LLM to rewrite [BRACKETED] sections to match job requirements.
"""
import logging
import os
import re
from datetime import datetime
from pathlib import Path

from config import settings
from database.init_db import SessionLocal
from database.models import Job, JobStatus, Application, UserProfile
from utils.latex_handler import (
    find_placeholders, fill_placeholders, read_template,
    write_tex, compile_latex, latex_escape
)
from utils.llm_client import get_llm_client

logger = logging.getLogger(__name__)

TAILOR_SYSTEM = (
    "You are an expert CV writer specializing in data engineering and data science roles. "
    "Write concise, achievement-focused content. Use action verbs. Be truthful and professional. "
    "Always respond with valid JSON only."
)


class CVTailorAgent:
    def __init__(self):
        self.llm = get_llm_client()
        self.template_path = os.path.join(settings.cv_templates_dir, "base_template.tex")

    def _build_prompt(self, placeholder: str, job: Job, profile: UserProfile,
                      analysis: dict) -> str:
        required_skills = ", ".join(analysis.get("required_skills", [])[:10])
        tech_stack = ", ".join(analysis.get("tech_stack", [])[:8])
        responsibilities = "; ".join(analysis.get("key_responsibilities", [])[:4])
        user_skills = ", ".join(profile.skills_json or [])
        summary_context = analysis.get("summary", "")

        prompts = {
            "PROFESSIONAL_SUMMARY": (
                f"Write a 3-sentence professional summary for a CV applying to: "
                f"'{job.title}' at '{job.company}'.\n"
                f"Job requires: {required_skills}\n"
                f"Candidate skills: {user_skills}\n"
                f"Job context: {summary_context}\n"
                f"Return JSON: {{\"content\": \"<summary text>\"}}"
            ),
            "SKILLS_LIST": (
                f"Create a skills section for a '{job.title}' application.\n"
                f"Required skills: {required_skills}\n"
                f"Tech stack: {tech_stack}\n"
                f"Candidate's skills: {user_skills}\n"
                f"Return a LaTeX itemize list. "
                f"Return JSON: {{\"content\": \"<latex itemize content>\"}}"
            ),
            "EXPERIENCE_SECTION": (
                f"Write 2-3 experience bullet points emphasizing skills for '{job.title}'.\n"
                f"Key responsibilities they want: {responsibilities}\n"
                f"Required skills: {required_skills}\n"
                f"Write achievement-focused bullets with metrics where possible.\n"
                f"Return JSON: {{\"content\": \"<latex itemize bullet points>\"}}"
            ),
            "PROJECT_DESCRIPTIONS": (
                f"Write 2 project descriptions relevant to '{job.title}' at '{job.company}'.\n"
                f"Tech stack they use: {tech_stack}\n"
                f"Each project: name, 2-3 bullet points, technologies used.\n"
                f"Return JSON: {{\"content\": \"<project descriptions in latex>\"}}"
            ),
        }

        default_prompt = (
            f"Fill in the '{placeholder}' section for a '{job.title}' CV application.\n"
            f"Job at: {job.company}. Required skills: {required_skills}\n"
            f"Return JSON: {{\"content\": \"<appropriate content>\"}}"
        )

        return prompts.get(placeholder, default_prompt)

    async def _fill_placeholder(self, placeholder: str, job: Job,
                                 profile: UserProfile, analysis: dict) -> str:
        prompt = self._build_prompt(placeholder, job, profile, analysis)
        result = await self.llm.generate_json(prompt, TAILOR_SYSTEM)
        content = result.get("content", "")
        if not content:
            logger.warning(f"Empty content for placeholder {placeholder}, using default.")
            return f"[Content for {placeholder}]"
        return content

    async def tailor_cv(self, job: Job) -> tuple[str, str, dict]:
        """
        Tailor CV for a job. Returns (tex_path, pdf_path, modifications).
        pdf_path may be empty if pdflatex not available.
        """
        if not os.path.exists(self.template_path):
            logger.warning(f"Template not found at {self.template_path}, using minimal fallback.")
            self._create_minimal_template()

        db = SessionLocal()
        try:
            profile = db.query(UserProfile).first()
            if not profile:
                raise RuntimeError("No user profile found in DB.")

            template_content = read_template(self.template_path)
            placeholders = find_placeholders(template_content)
            analysis = job.analysis_json or {}

            logger.info(f"Tailoring CV for {job.title} @ {job.company}. "
                        f"Placeholders: {placeholders}")

            # Fill profile-static placeholders from user profile
            static_values = {
                "CANDIDATE_NAME": latex_escape(profile.name or "Your Name"),
                "EMAIL": latex_escape(profile.email or "email@example.com"),
                "PHONE": latex_escape(profile.phone or "+1-555-0000"),
                "LINKEDIN": latex_escape(profile.linkedin or ""),
                "GITHUB": latex_escape(profile.github or ""),
            }

            # Fill dynamic placeholders using LLM
            dynamic_values = {}
            for ph in placeholders:
                if ph in static_values:
                    continue
                dynamic_values[ph] = await self._fill_placeholder(
                    ph, job, profile, analysis
                )

            all_values = {**static_values, **dynamic_values}
            filled_content = fill_placeholders(template_content, all_values)

            # Save files
            safe_company = re.sub(r'[^a-zA-Z0-9_]', '_', job.company[:30])
            safe_title = re.sub(r'[^a-zA-Z0-9_]', '_', job.title[:30])
            date_str = datetime.utcnow().strftime("%Y%m%d")
            filename = f"cv_{safe_company}_{safe_title}_{date_str}"

            tex_path = os.path.join(settings.cvs_dir, f"{filename}.tex")
            write_tex(filled_content, tex_path)
            logger.info(f"Saved .tex: {tex_path}")

            # Attempt PDF compilation
            success, result = compile_latex(tex_path, settings.cvs_dir)
            if success:
                pdf_path = result
                logger.info(f"Compiled PDF: {pdf_path}")
            else:
                pdf_path = ""
                logger.warning(f"PDF compilation failed: {result}")

            return tex_path, pdf_path, all_values

        finally:
            db.close()

    def _create_minimal_template(self):
        """Create a minimal LaTeX template if none exists."""
        os.makedirs(settings.cv_templates_dir, exist_ok=True)
        # Write the base template (defined in cv_templates/base_template.tex)
        from cv_templates import TEMPLATE_CONTENT
        with open(self.template_path, "w") as f:
            f.write(TEMPLATE_CONTENT)

    async def tailor_analyzed_jobs(self, min_match_score: float = 0.5,
                                    limit: int = 20) -> int:
        """Tailor CVs for all ANALYZED jobs above match threshold."""
        db = SessionLocal()
        processed = 0
        try:
            jobs = (
                db.query(Job)
                .filter(
                    Job.status == JobStatus.ANALYZED,
                    Job.match_score >= min_match_score,
                )
                .order_by(Job.match_score.desc())
                .limit(limit)
                .all()
            )
            logger.info(f"Tailoring CVs for {len(jobs)} jobs...")

            for job in jobs:
                try:
                    tex_path, pdf_path, mods = await self.tailor_cv(job)

                    app = Application(
                        job_id=job.id,
                        cv_path=pdf_path,
                        tex_path=tex_path,
                        status="draft",
                        modifications_json=list(mods.keys()),
                    )
                    db.add(app)
                    job.status = JobStatus.CV_TAILORED
                    db.commit()
                    processed += 1
                    logger.info(f"CV tailored for {job.title} @ {job.company}")
                except Exception as e:
                    db.rollback()
                    logger.error(f"CV tailoring failed for job {job.id}: {e}")

        finally:
            db.close()

        return processed
