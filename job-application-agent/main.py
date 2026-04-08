"""
Entry point for the Job Application Agent backend.

Usage:
  python3 main.py               — Start FastAPI server (Swift app connects to this)
  python3 main.py --headless    — Run one pipeline cycle in terminal, no server
  python3 main.py --daemon      — Run pipeline loop continuously, no server
  python3 main.py --check       — Check dependencies and exit
"""
import argparse
import asyncio
import logging
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from config import settings


def setup_logging(level=logging.INFO):
    log_file = (
        Path(settings.logs_dir)
        / f"agent_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.log"
    )
    handlers = [
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(log_file),
    ]
    logging.basicConfig(
        level=level,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        handlers=handlers,
    )
    for lib in ("httpx", "httpcore", "playwright", "urllib3", "sqlalchemy", "uvicorn.access"):
        logging.getLogger(lib).setLevel(logging.WARNING)


def check_dependencies():
    import shutil

    print("\n── Dependency Check ─────────────────────────────────────")

    # Ollama
    try:
        import httpx, asyncio as _a
        async def _ping():
            async with httpx.AsyncClient(timeout=3.0) as c:
                r = await c.get(f"{settings.ollama_base_url}/api/tags")
                return r.status_code == 200
        ok = _a.run(_ping())
        print(f"{'[OK]' if ok else '[--]'} Ollama at {settings.ollama_base_url}"
              + ("" if ok else " — not running, will use Groq fallback"))
    except Exception:
        print(f"[--] Ollama — unavailable, will use Groq fallback")

    # Groq
    if settings.groq_api_key:
        print("[OK] Groq API key configured")
    else:
        print("[--] No GROQ_API_KEY — set it in .env if Ollama is unavailable")

    # pdflatex
    if shutil.which("pdflatex"):
        print("[OK] pdflatex — PDF generation enabled")
    else:
        print("[--] pdflatex not found — CVs saved as .tex only")
        print("     Install: brew install --cask mactex-no-gui")

    # Playwright
    try:
        import playwright
        print("[OK] Playwright installed")
    except ImportError:
        print("[--] Playwright not installed — run: pip3 install playwright && playwright install chromium")

    # FastAPI / uvicorn
    try:
        import fastapi, uvicorn
        print("[OK] FastAPI + uvicorn — API server ready")
    except ImportError:
        print("[!!] FastAPI/uvicorn missing — run: pip3 install fastapi uvicorn")

    print("─────────────────────────────────────────────────────────\n")


async def run_headless(cycles: int = 1):
    from database.init_db import init_database
    from agents.orchestrator import Orchestrator

    print(f"\n{'='*58}")
    print(" Job Application Agent — Headless Mode")
    print(f"{'='*58}\n")

    init_database()
    orc = Orchestrator()

    def on_done(summary: dict):
        print("\n── Cycle Summary ──────────────────")
        for k, v in summary.items():
            if k not in ("start_time", "end_time"):
                print(f"  {k}: {v}")
        print("───────────────────────────────────\n")

    await orc.run_autonomous(cycles=cycles, callback=on_done)

    from database.init_db import SessionLocal
    from database.models import Job, Application
    db = SessionLocal()
    try:
        total = db.query(Job).count()
        apps  = db.query(Application).count()
        ready = db.query(Job).filter(Job.status == "ready").count()
        print(f"\n{'='*58}")
        print(f"  Final report:")
        print(f"    Total jobs in DB : {total}")
        print(f"    Ready to apply   : {ready}")
        print(f"    CVs generated    : {apps}")
        print(f"    Output dir       : {settings.output_dir}")
        print(f"{'='*58}\n")
    finally:
        db.close()


def run_server():
    """Start the FastAPI backend that the Swift app talks to."""
    from database.init_db import init_database
    import uvicorn

    init_database()
    print("\n── Job Application Agent — API Server ───────────────────")
    print("  Listening on http://127.0.0.1:8000")
    print("  Open JobAgentApp.xcodeproj in Xcode and run the Swift app")
    print("  API docs: http://127.0.0.1:8000/docs")
    print("─────────────────────────────────────────────────────────\n")

    uvicorn.run(
        "api.server:app",
        host="127.0.0.1",
        port=8000,
        reload=False,
        log_level="info",
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Job Application Agent")
    parser.add_argument("--headless", action="store_true",
                        help="Run one pipeline cycle in terminal (no server)")
    parser.add_argument("--daemon", action="store_true",
                        help="Run continuous pipeline loop (no server)")
    parser.add_argument("--cycles", type=int, default=1,
                        help="Number of cycles (headless/daemon mode)")
    parser.add_argument("--check", action="store_true",
                        help="Check dependencies and exit")
    parser.add_argument("--debug", action="store_true",
                        help="Enable debug logging")
    args = parser.parse_args()

    setup_logging(logging.DEBUG if args.debug else logging.INFO)
    check_dependencies()

    if args.check:
        sys.exit(0)

    if args.headless or args.daemon:
        cycles = -1 if args.daemon else args.cycles
        asyncio.run(run_headless(cycles=cycles))
    else:
        run_server()
