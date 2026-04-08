# Job Application Agent

Autonomous multi-agent system that finds jobs, tailors your CV, and optimizes for ATS — running in the background while you're away.

## Architecture

```
Job Finder → Job Analyzer → CV Tailor → ATS Optimizer → MacOS Review App
```

Each agent is independent. The orchestrator coordinates them in a loop.

## Setup

### 1. Install Python dependencies

```bash
cd job-application-agent
pip3 install -r requirements.txt
playwright install chromium
```

### 2. Configure LLM (choose one)

**Option A — Ollama (local, free, private):**
```bash
brew install ollama
ollama pull llama3.1
ollama serve   # runs at localhost:11434
```

**Option B — Groq (cloud, free tier):**
```bash
cp .env.example .env
# Add your GROQ_API_KEY from https://console.groq.com
```

### 3. (Optional) Install LaTeX for PDF generation

```bash
brew install --cask mactex-no-gui
```

Without LaTeX, CVs are saved as `.tex` files only.

### 4. Customize your profile

Edit `database/init_db.py` to set your real name, email, skills, etc.
Or update the `user_profiles` table in the SQLite DB after first run.

### 5. Customize the CV template

Edit `cv_templates/base_template.tex`.
Use `[PLACEHOLDER_NAME]` for sections the LLM will fill.
Keep all LaTeX structure outside the brackets.

## Run

```bash
# Launch MacOS desktop app
python3 main.py

# Run one pipeline cycle in terminal (headless)
python3 main.py --headless

# Run continuously (every 6 hours)
python3 main.py --daemon

# Check dependencies
python3 main.py --check
```

## CV Template Placeholders

| Placeholder | Description |
|---|---|
| `[CANDIDATE_NAME]` | Your full name (from profile) |
| `[EMAIL]` | Your email (from profile) |
| `[PHONE]` | Your phone (from profile) |
| `[LINKEDIN]` | LinkedIn URL (from profile) |
| `[GITHUB]` | GitHub URL (from profile) |
| `[PROFESSIONAL_SUMMARY]` | LLM-written 3-sentence summary |
| `[SKILLS_LIST]` | LLM-tailored skills section |
| `[EXPERIENCE_SECTION]` | LLM-tailored experience bullets |
| `[PROJECT_DESCRIPTIONS]` | LLM-tailored project descriptions |
| `[EDUCATION_SECTION]` | LLM-written education section |

## ATS Scoring

| Dimension | Weight | What it checks |
|---|---|---|
| Keyword Match | 40% | Required skills from job description found in CV |
| Formatting | 30% | Standard sections, no tables, clean LaTeX |
| Relevance | 20% | LLM-assessed fit for the role |
| Completeness | 10% | Email, phone, LinkedIn, GitHub, all sections |

Target: 70+/100. System iterates up to 3 times to improve score.

## Output

```
output/
├── cvs/
│   ├── cv_Company_Role_20260407.tex   # LaTeX source
│   └── cv_Company_Role_20260407.pdf   # Compiled PDF (if LaTeX installed)
└── logs/
    └── agent_20260407_120000.log       # Full pipeline log
```

## Database

SQLite at `database/jobs.db`. Open with any SQLite browser to inspect.

Job statuses: `new → analyzed → cv_tailored → ats_optimized → ready → applied`

## Troubleshooting

- **Scrapers finding 0 jobs**: Job sites may have changed their HTML. Check logs. Remotive API is most reliable.
- **LLM not responding**: Make sure Ollama is running (`ollama serve`) or set `GROQ_API_KEY` in `.env`.
- **pdflatex error**: Install MacTeX. CVs still work as `.tex` files without it.
- **Playwright timeout**: Sites may be rate-limiting. Increase `SCRAPE_DELAY_MIN/MAX` in `.env`.
