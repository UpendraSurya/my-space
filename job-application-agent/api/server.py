"""
FastAPI backend — exposes the job application pipeline as a REST API
for the native Swift macOS app to consume.
"""
import asyncio
import logging
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional

import uvicorn
from fastapi import FastAPI, HTTPException, BackgroundTasks, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

sys.path.insert(0, str(Path(__file__).parent.parent))

from config import settings
from database.init_db import init_database, SessionLocal
from database.models import Job, JobStatus, Application, ATSScore, UserProfile

logger = logging.getLogger(__name__)

# ─── Study Hub index (built at startup) ───────────────────────────────────── #
_study_index = None

def _get_study_index():
    global _study_index
    if _study_index is None:
        from study_hub.notes_index import NotesIndex
        _study_index = NotesIndex()
        try:
            _study_index.build()
        except Exception as e:
            logger.warning(f"Study index build failed: {e}")
    return _study_index

app = FastAPI(
    title="Job Application Agent API",
    description="Backend API for the personal macOS super-app",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ─── Pipeline state ───────────────────────────────────────────────────────── #
pipeline_log: list[dict] = []
pipeline_running: bool = False


def log_event(stage: str, message: str, data: dict = None):
    entry = {
        "timestamp": datetime.utcnow().isoformat(),
        "stage": stage,
        "message": message,
        "data": data or {},
    }
    pipeline_log.append(entry)
    if len(pipeline_log) > 500:
        pipeline_log.pop(0)


# ─── Schemas ──────────────────────────────────────────────────────────────── #
class JobOut(BaseModel):
    id: int
    title: str
    company: str
    location: Optional[str]
    salary: Optional[str]
    url: str
    source: Optional[str]
    status: str
    match_score: float
    found_date: Optional[str]
    has_application: bool
    ats_score: Optional[float]

    class Config:
        from_attributes = True


class JobDetailOut(BaseModel):
    id: int
    title: str
    company: str
    location: Optional[str]
    salary: Optional[str]
    url: str
    source: Optional[str]
    status: str
    match_score: float
    raw_description: Optional[str]
    analysis: Optional[dict]
    found_date: Optional[str]


class ApplicationOut(BaseModel):
    id: int
    job_id: int
    cv_path: Optional[str]
    tex_path: Optional[str]
    ats_score: Optional[float]
    status: Optional[str]
    created_date: Optional[str]


class ATSScoreOut(BaseModel):
    total_score: float
    keyword_score: float
    formatting_score: float
    relevance_score: float
    completeness_score: float
    breakdown: Optional[dict]


class StatsOut(BaseModel):
    total_jobs: int
    new_jobs: int
    analyzed_jobs: int
    ready_jobs: int
    applied_jobs: int
    avg_ats_score: float
    cvs_generated: int


class PipelineStatusOut(BaseModel):
    running: bool
    log: list[dict]


class UserProfileOut(BaseModel):
    id: int
    name: Optional[str]
    email: Optional[str]
    phone: Optional[str]
    linkedin: Optional[str]
    github: Optional[str]
    skills: Optional[list]


class UserProfileIn(BaseModel):
    name: Optional[str] = None
    email: Optional[str] = None
    phone: Optional[str] = None
    linkedin: Optional[str] = None
    github: Optional[str] = None
    skills: Optional[list] = None


class StatusUpdate(BaseModel):
    status: str


# ─── Helpers ──────────────────────────────────────────────────────────────── #
def _job_to_out(job: Job, db) -> JobOut:
    app = (
        db.query(Application)
        .filter(Application.job_id == job.id)
        .order_by(Application.created_date.desc())
        .first()
    )
    return JobOut(
        id=job.id,
        title=job.title,
        company=job.company,
        location=job.location,
        salary=job.salary,
        url=job.url,
        source=job.source,
        status=job.status.value if job.status else "new",
        match_score=job.match_score or 0.0,
        found_date=job.found_date.isoformat() if job.found_date else None,
        has_application=app is not None,
        ats_score=app.ats_score if app else None,
    )


# ─── Routes: Stats ────────────────────────────────────────────────────────── #
@app.get("/stats", response_model=StatsOut)
def get_stats():
    db = SessionLocal()
    try:
        from sqlalchemy import func
        total = db.query(Job).count()
        new = db.query(Job).filter(Job.status == JobStatus.NEW).count()
        analyzed = db.query(Job).filter(Job.status == JobStatus.ANALYZED).count()
        ready = db.query(Job).filter(Job.status == JobStatus.READY).count()
        applied = db.query(Job).filter(Job.status == JobStatus.APPLIED).count()
        avg_ats = db.query(func.avg(Application.ats_score)).scalar() or 0.0
        cvs = db.query(Application).count()
        return StatsOut(
            total_jobs=total,
            new_jobs=new,
            analyzed_jobs=analyzed,
            ready_jobs=ready,
            applied_jobs=applied,
            avg_ats_score=round(float(avg_ats), 1),
            cvs_generated=cvs,
        )
    finally:
        db.close()


# ─── Routes: Jobs ─────────────────────────────────────────────────────────── #
@app.get("/jobs", response_model=list[JobOut])
def list_jobs(
    status: Optional[str] = None,
    source: Optional[str] = None,
    min_score: Optional[float] = None,
    limit: int = 200,
    offset: int = 0,
):
    db = SessionLocal()
    try:
        q = db.query(Job)
        if status and status != "all":
            try:
                q = q.filter(Job.status == JobStatus(status))
            except ValueError:
                pass
        if source:
            q = q.filter(Job.source == source)
        if min_score is not None:
            q = q.filter(Job.match_score >= min_score)
        jobs = q.order_by(Job.found_date.desc()).offset(offset).limit(limit).all()
        return [_job_to_out(j, db) for j in jobs]
    finally:
        db.close()


@app.get("/jobs/{job_id}", response_model=JobDetailOut)
def get_job(job_id: int):
    db = SessionLocal()
    try:
        job = db.query(Job).filter(Job.id == job_id).first()
        if not job:
            raise HTTPException(status_code=404, detail="Job not found")
        return JobDetailOut(
            id=job.id,
            title=job.title,
            company=job.company,
            location=job.location,
            salary=job.salary,
            url=job.url,
            source=job.source,
            status=job.status.value if job.status else "new",
            match_score=job.match_score or 0.0,
            raw_description=job.raw_description,
            analysis=job.analysis_json,
            found_date=job.found_date.isoformat() if job.found_date else None,
        )
    finally:
        db.close()


@app.patch("/jobs/{job_id}/status")
def update_job_status(job_id: int, body: StatusUpdate):
    db = SessionLocal()
    try:
        job = db.query(Job).filter(Job.id == job_id).first()
        if not job:
            raise HTTPException(status_code=404, detail="Job not found")
        try:
            job.status = JobStatus(body.status)
        except ValueError:
            raise HTTPException(status_code=400, detail=f"Invalid status: {body.status}")
        if body.status == "applied":
            app = (
                db.query(Application)
                .filter(Application.job_id == job_id)
                .first()
            )
            if app:
                app.applied_date = datetime.utcnow()
                app.status = "applied"
        db.commit()
        return {"ok": True, "status": body.status}
    finally:
        db.close()


@app.get("/jobs/{job_id}/application", response_model=Optional[ApplicationOut])
def get_application(job_id: int):
    db = SessionLocal()
    try:
        app = (
            db.query(Application)
            .filter(Application.job_id == job_id)
            .order_by(Application.created_date.desc())
            .first()
        )
        if not app:
            return None
        return ApplicationOut(
            id=app.id,
            job_id=app.job_id,
            cv_path=app.cv_path,
            tex_path=app.tex_path,
            ats_score=app.ats_score,
            status=app.status,
            created_date=app.created_date.isoformat() if app.created_date else None,
        )
    finally:
        db.close()


@app.get("/jobs/{job_id}/ats", response_model=Optional[ATSScoreOut])
def get_ats_score(job_id: int):
    db = SessionLocal()
    try:
        app = (
            db.query(Application)
            .filter(Application.job_id == job_id)
            .first()
        )
        if not app:
            return None
        score = (
            db.query(ATSScore)
            .filter(ATSScore.application_id == app.id)
            .order_by(ATSScore.total_score.desc())
            .first()
        )
        if not score:
            return None
        return ATSScoreOut(
            total_score=score.total_score,
            keyword_score=score.keyword_score,
            formatting_score=score.formatting_score,
            relevance_score=score.relevance_score,
            completeness_score=score.completeness_score,
            breakdown=score.breakdown_json,
        )
    finally:
        db.close()


# ─── Routes: Pipeline ─────────────────────────────────────────────────────── #
@app.get("/pipeline/status", response_model=PipelineStatusOut)
def pipeline_status():
    return PipelineStatusOut(running=pipeline_running, log=pipeline_log[-50:])


@app.post("/pipeline/run")
async def run_pipeline(background_tasks: BackgroundTasks):
    global pipeline_running
    if pipeline_running:
        return {"ok": False, "message": "Pipeline already running"}
    background_tasks.add_task(_run_pipeline_bg)
    return {"ok": True, "message": "Pipeline started"}


async def _run_pipeline_bg():
    global pipeline_running
    pipeline_running = True
    log_event("orchestrator", "Pipeline started")
    try:
        from agents.orchestrator import Orchestrator
        orc = Orchestrator()

        async def relay(event):
            log_event(event.stage, event.message, event.data)

        # Patch event queue to relay to our log
        async def _emit(stage, message, data=None):
            log_event(stage, message, data or {})

        orc._emit = _emit
        summary = await orc.run_cycle()
        log_event("orchestrator", "Pipeline complete", summary)
    except Exception as e:
        log_event("orchestrator", f"Pipeline error: {e}")
        logger.exception("Pipeline background task failed")
    finally:
        pipeline_running = False


# ─── Routes: Profile ──────────────────────────────────────────────────────── #
@app.get("/profile", response_model=UserProfileOut)
def get_profile():
    db = SessionLocal()
    try:
        p = db.query(UserProfile).first()
        if not p:
            raise HTTPException(status_code=404, detail="No profile found")
        return UserProfileOut(
            id=p.id,
            name=p.name,
            email=p.email,
            phone=p.phone,
            linkedin=p.linkedin,
            github=p.github,
            skills=p.skills_json,
        )
    finally:
        db.close()


@app.patch("/profile")
def update_profile(body: UserProfileIn):
    db = SessionLocal()
    try:
        p = db.query(UserProfile).first()
        if not p:
            raise HTTPException(status_code=404, detail="No profile found")
        if body.name is not None:
            p.name = body.name
        if body.email is not None:
            p.email = body.email
        if body.phone is not None:
            p.phone = body.phone
        if body.linkedin is not None:
            p.linkedin = body.linkedin
        if body.github is not None:
            p.github = body.github
        if body.skills is not None:
            p.skills_json = body.skills
        db.commit()
        return {"ok": True}
    finally:
        db.close()


# ─── Routes: Study Hub ────────────────────────────────────────────────────── #

class StudySearchIn(BaseModel):
    query: str
    k: int = 8


class StudyChatIn(BaseModel):
    query: str
    history: list[dict] = []


@app.get("/study/notes")
def study_list_notes():
    """List all notes from ~/dev-notes/."""
    idx = _get_study_index()
    return idx.list_notes()


@app.post("/study/reindex")
def study_reindex():
    """Re-scan and re-embed all notes. Call after adding new notes."""
    idx = _get_study_index()
    count = idx.build()
    return {"ok": True, "notes_indexed": count}


@app.get("/study/notes/{note_id:path}")
def study_get_note(note_id: str):
    """Get full content of a note by its relative path id."""
    idx = _get_study_index()
    note = idx.get_note_content(note_id)
    if not note:
        raise HTTPException(status_code=404, detail="Note not found")
    return note


@app.post("/study/search")
def study_search(body: StudySearchIn):
    """Semantic search across all notes."""
    idx = _get_study_index()
    results = idx.search(body.query, k=body.k)
    return {"results": results, "query": body.query}


@app.post("/study/chat")
async def study_chat(body: StudyChatIn):
    """RAG chat — finds relevant notes and answers using LLM."""
    idx = _get_study_index()
    from study_hub.chat_agent import chat
    result = await chat(body.query, body.history, idx)
    return result


@app.post("/study/upload")
async def study_upload(
    file: UploadFile = File(...),
    title: str = Form(""),
    topic: str = Form("general"),
):
    """Upload a file (PDF/DOCX/TXT/MD), extract text, save as dev note."""
    import tempfile, shutil
    from pathlib import Path
    from study_hub.file_extractor import extract_text, save_as_dev_note

    suffix = Path(file.filename).suffix if file.filename else ".txt"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        shutil.copyfileobj(file.file, tmp)
        tmp_path = Path(tmp.name)

    try:
        raw_text = extract_text(tmp_path)
        note_title = title.strip() or Path(file.filename or "upload").stem
        saved_path = save_as_dev_note(note_title, raw_text, topic=topic)

        # Rebuild index to include the new note
        idx = _get_study_index()
        idx.build()

        return {
            "ok": True,
            "saved_path": str(saved_path),
            "note_id": str(saved_path.relative_to(Path.home() / "dev-notes")),
            "title": note_title,
            "chars_extracted": len(raw_text),
        }
    finally:
        tmp_path.unlink(missing_ok=True)


# ─── Health ───────────────────────────────────────────────────────────────── #
@app.get("/health")
def health():
    return {"status": "ok", "time": datetime.utcnow().isoformat()}


# ─── Entry point ──────────────────────────────────────────────────────────── #
def start():
    init_database()
    # Pre-build study index in background so first search is fast
    import threading
    threading.Thread(target=_get_study_index, daemon=True).start()
    uvicorn.run(app, host="127.0.0.1", port=8000, log_level="info")


if __name__ == "__main__":
    start()
