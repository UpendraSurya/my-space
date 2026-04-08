from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from database.models import Base, UserProfile
from config import settings


engine = create_engine(f"sqlite:///{settings.db_path}", echo=False)
SessionLocal = sessionmaker(bind=engine)


def init_database():
    Base.metadata.create_all(engine)
    db = SessionLocal()
    try:
        if not db.query(UserProfile).first():
            profile = UserProfile(
                name="Job Seeker",
                email="your.email@example.com",
                phone="+1-555-0000",
                linkedin="https://linkedin.com/in/yourprofile",
                github="https://github.com/yourusername",
                base_cv_path="cv_templates/base_template.tex",
                skills_json=["Python", "SQL", "Data Analysis", "Machine Learning", "ETL"],
                experience_json=[],
            )
            db.add(profile)
            db.commit()
            print("[DB] Default user profile created.")
    finally:
        db.close()
    print(f"[DB] Database initialized at {settings.db_path}")


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
