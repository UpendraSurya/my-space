import os
from pathlib import Path
from pydantic_settings import BaseSettings
from pydantic import Field


BASE_DIR = Path(__file__).parent


class Settings(BaseSettings):
    # LLM configuration
    ollama_base_url: str = "http://localhost:11434"
    ollama_model: str = "llama3.1"
    groq_api_key: str = ""
    groq_model: str = "llama-3.1-8b-instant"

    # Database
    db_path: str = str(BASE_DIR / "database" / "jobs.db")

    # Output directories
    output_dir: str = str(BASE_DIR / "output")
    logs_dir: str = str(BASE_DIR / "output" / "logs")
    cvs_dir: str = str(BASE_DIR / "output" / "cvs")
    cv_templates_dir: str = str(BASE_DIR / "cv_templates")

    # Scraping
    scrape_delay_min: float = 2.0
    scrape_delay_max: float = 6.0
    max_concurrent_scrapes: int = 3
    max_results_per_site: int = 20

    # Pipeline
    min_match_score: float = 0.5
    ats_target_score: float = 70.0
    max_ats_iterations: int = 3
    search_interval_hours: int = 6

    # Job search targets
    target_roles: list[str] = [
        "Data Engineer",
        "Data Scientist",
        "Data Analyst",
        "Analytics Engineer",
        "ML Engineer",
    ]

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"


settings = Settings()

# Ensure output directories exist
for d in [settings.output_dir, settings.logs_dir, settings.cvs_dir]:
    os.makedirs(d, exist_ok=True)
os.makedirs(Path(settings.db_path).parent, exist_ok=True)
