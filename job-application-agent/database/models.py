from datetime import datetime
from sqlalchemy import (
    Column, Integer, String, Float, Text, DateTime,
    ForeignKey, JSON, Enum as SAEnum
)
from sqlalchemy.orm import DeclarativeBase, relationship
import enum


class Base(DeclarativeBase):
    pass


class JobStatus(str, enum.Enum):
    NEW = "new"
    ANALYZED = "analyzed"
    CV_TAILORED = "cv_tailored"
    ATS_OPTIMIZED = "ats_optimized"
    READY = "ready"
    APPLIED = "applied"
    REJECTED = "rejected"
    INTERVIEWING = "interviewing"
    OFFER = "offer"
    SKIPPED = "skipped"


class Job(Base):
    __tablename__ = "jobs"

    id = Column(Integer, primary_key=True, autoincrement=True)
    title = Column(String(256), nullable=False)
    company = Column(String(256), nullable=False)
    location = Column(String(256))
    salary = Column(String(128))
    url = Column(String(1024), unique=True, nullable=False)
    source = Column(String(64))  # linkedin, indeed, naukri, etc.
    raw_description = Column(Text)
    requirements = Column(Text)
    posted_date = Column(String(64))
    found_date = Column(DateTime, default=datetime.utcnow)
    status = Column(SAEnum(JobStatus), default=JobStatus.NEW)
    match_score = Column(Float, default=0.0)
    analysis_json = Column(JSON)

    applications = relationship("Application", back_populates="job")


class Application(Base):
    __tablename__ = "applications"

    id = Column(Integer, primary_key=True, autoincrement=True)
    job_id = Column(Integer, ForeignKey("jobs.id"), nullable=False)
    cv_path = Column(String(1024))
    tex_path = Column(String(1024))
    ats_score = Column(Float, default=0.0)
    created_date = Column(DateTime, default=datetime.utcnow)
    applied_date = Column(DateTime)
    status = Column(String(64), default="draft")
    notes = Column(Text)
    modifications_json = Column(JSON)

    job = relationship("Job", back_populates="applications")
    ats_scores = relationship("ATSScore", back_populates="application")


class ATSScore(Base):
    __tablename__ = "ats_scores"

    id = Column(Integer, primary_key=True, autoincrement=True)
    application_id = Column(Integer, ForeignKey("applications.id"), nullable=False)
    keyword_score = Column(Float, default=0.0)
    formatting_score = Column(Float, default=0.0)
    relevance_score = Column(Float, default=0.0)
    completeness_score = Column(Float, default=0.0)
    total_score = Column(Float, default=0.0)
    iteration = Column(Integer, default=0)
    breakdown_json = Column(JSON)
    created_at = Column(DateTime, default=datetime.utcnow)

    application = relationship("Application", back_populates="ats_scores")


class UserProfile(Base):
    __tablename__ = "user_profiles"

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(256))
    email = Column(String(256))
    phone = Column(String(64))
    linkedin = Column(String(256))
    github = Column(String(256))
    base_cv_path = Column(String(1024))
    skills_json = Column(JSON)
    experience_json = Column(JSON)
    created_at = Column(DateTime, default=datetime.utcnow)
