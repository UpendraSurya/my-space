# YOLO Project — Full Documentation

**Author:** Upendra Surya
**Date:** 2026-04-08
**Stack:** Python (FastAPI + SQLAlchemy + FAISS) + Swift (SwiftUI macOS)

---

## Table of Contents

1. [What This Project Is](#1-what-this-project-is)
2. [High-Level Architecture](#2-high-level-architecture)
3. [Folder Structure](#3-folder-structure)
4. [Python Backend](#4-python-backend)
   - 4.1 Config
   - 4.2 Database Models
   - 4.3 LLM Client
   - 4.4 Job Scrapers
   - 4.5 ATS Scorer
   - 4.6 LaTeX Handler
   - 4.7 Agents
   - 4.8 Study Hub
   - 4.9 FastAPI Server (all routes)
5. [Swift macOS App](#5-swift-macos-app)
   - 5.1 Entry Point
   - 5.2 HomeView
   - 5.3 Jobs Module (ContentView → Dashboard → Jobs → Tracker → Profile)
   - 5.4 Study Hub Module
   - 5.5 Shared Components & Theme
   - 5.6 AppState
   - 5.7 APIClient
6. [Data Flow — End to End](#6-data-flow-end-to-end)
7. [How to Run](#7-how-to-run)
8. [API Reference](#8-api-reference)
9. [Key Design Decisions](#9-key-design-decisions)
10. [What Each File Does — Quick Reference](#10-what-each-file-does--quick-reference)

---

## 1. What This Project Is

This is a **personal macOS super-app** that currently has two active modules:

### Module 1 — Job Applications
An **autonomous AI job application agent**. It:
- Scrapes job listings from Remotive, Indeed, and LinkedIn
- Uses an LLM (local Ollama or cloud Groq) to analyze each job and score how well it matches your target roles
- Tailors your LaTeX CV for each job by filling in `[PLACEHOLDER]` markers with job-specific content
- Scores your tailored CV against ATS (Applicant Tracking System) criteria
- Lets you track applications through a Kanban board (Applied → Interviewing → Offer)

### Module 2 — Study Hub
A **personal AI study assistant** connected to your `~/dev-notes/` Obsidian vault. It:
- Indexes all your markdown notes using sentence-transformer embeddings + FAISS vector search
- Lets you search notes semantically (ask a question, get the most relevant notes — not just keyword matching)
- Has an AI chat where you ask questions and the AI answers using your actual notes as context (RAG — Retrieval Augmented Generation)
- Lets you upload PDF/DOCX/TXT files to extract their content and save it as a formatted dev note

### Future modules (Coming Soon cards on home screen)
- Finance Tracker
- Habit Tracker

---

## 2. High-Level Architecture

```
┌─────────────────────────────────────────────┐
│           macOS SwiftUI App                  │
│                                             │
│  HomeView (US initials + module cards)      │
│     ├── Job Applications → ContentView      │
│     │      └── Dashboard / Jobs /           │
│     │          Tracker / Profile            │
│     ├── Study Hub → StudyHubView            │
│     │      └── NoteList / NoteDetail /      │
│     │          StudyChatView / UploadSheet  │
│     ├── Finance (coming soon)               │
│     └── Habits (coming soon)               │
└──────────────┬──────────────────────────────┘
               │ HTTP (localhost:8000)
               │ URLSession / actor APIClient
               │
┌──────────────▼──────────────────────────────┐
│        FastAPI Server (Python)               │
│                                             │
│  /stats  /jobs  /pipeline/*  /profile       │
│  /study/notes  /study/search                │
│  /study/chat   /study/upload                │
└──────────────┬──────────────────────────────┘
               │
    ┌──────────┼──────────┐
    │          │          │
┌───▼──┐  ┌───▼───┐  ┌───▼────────────┐
│SQLite│  │Ollama │  │ FAISS Index    │
│(jobs │  │(local │  │ (~/dev-notes/  │
│ db)  │  │ LLM)  │  │  embeddings)   │
└──────┘  └───────┘  └────────────────┘
               │
         ┌─────▼─────┐
         │ Groq API  │
         │ (fallback)│
         └───────────┘
```

**Key principle:** The Swift app never talks to Ollama/Groq directly. All AI logic lives in Python. Swift only calls FastAPI over localhost HTTP.

---

## 3. Folder Structure

```
YOLO-project/
├── job-application-agent/          ← Python backend
│   ├── .env                        ← API keys (Groq, etc.)
│   ├── config.py                   ← All settings (pydantic-settings)
│   ├── main.py                     ← Entry point, starts FastAPI
│   ├── requirements.txt
│   ├── api/
│   │   └── server.py               ← FastAPI app, all HTTP routes
│   ├── database/
│   │   ├── models.py               ← SQLAlchemy ORM models
│   │   └── init_db.py              ← Create tables, seed profile
│   ├── agents/
│   │   ├── orchestrator.py         ← Pipeline coordinator
│   │   ├── job_finder.py           ← Scraping agent
│   │   ├── job_analyzer.py         ← LLM analysis agent
│   │   ├── cv_tailor.py            ← LaTeX CV customisation agent
│   │   └── ats_optimizer.py        ← ATS score improvement agent
│   ├── utils/
│   │   ├── llm_client.py           ← Ollama + Groq wrapper
│   │   ├── scraper.py              ← Web scrapers (Remotive/Indeed/LinkedIn)
│   │   ├── ats_scorer.py           ← ATS scoring logic
│   │   └── latex_handler.py        ← LaTeX placeholder filling + compilation
│   ├── study_hub/
│   │   ├── notes_index.py          ← FAISS vector index of ~/dev-notes/
│   │   ├── chat_agent.py           ← RAG chat (retrieve → inject → generate)
│   │   └── file_extractor.py       ← PDF/DOCX/TXT text extraction
│   ├── cv_templates/
│   │   └── base_template.tex       ← Your base LaTeX CV
│   └── output/
│       └── cvs/                    ← Generated PDFs saved here
│
└── JobAgentApp/                    ← Swift macOS app
    └── JobAgentApp/
        ├── JobAgentApp.swift       ← @main entry point → HomeView
        ├── Models/
        │   └── Models.swift        ← All Codable structs (Jobs, Study, etc.)
        ├── Services/
        │   ├── APIClient.swift     ← Jobs API (actor, URLSession)
        │   ├── StudyAPIClient.swift← Study Hub API (actor, URLSession)
        │   └── AppState.swift      ← @MainActor ObservableObject, all state
        ├── Views/
        │   ├── HomeView.swift      ← Landing screen with module cards
        │   ├── ContentView.swift   ← Jobs module shell (NavigationSplitView)
        │   ├── DashboardView.swift ← Stats + pipeline log
        │   ├── JobsView.swift      ← Job list + detail panel
        │   ├── TrackerView.swift   ← Kanban board
        │   ├── ProfileView.swift   ← Edit profile/skills
        │   ├── StudyHubView.swift  ← Notes browser + search + upload
        │   └── StudyChatView.swift ← AI chat interface
        └── Components/
            ├── SharedComponents.swift ← Theme, SidebarView, StatCard, etc.
            └── PixelArtView.swift     ← Canvas-based pixel art renderer
```

---

## 4. Python Backend

### 4.1 Config — `config.py`

Uses `pydantic-settings`. Reads from `.env` file automatically.

| Setting | Default | Description |
|---|---|---|
| `OLLAMA_BASE_URL` | `http://localhost:11434` | Local Ollama server |
| `OLLAMA_MODEL` | `llama3.1` | Model to use |
| `GROQ_API_KEY` | (from .env) | Cloud fallback LLM |
| `GROQ_MODEL` | `llama-3.1-8b-instant` | Groq model |
| `DB_PATH` | `database/jobs.db` | SQLite database |
| `OUTPUT_DIR` | `output/` | Where PDFs go |
| `MIN_MATCH_SCORE` | `0.5` | Minimum score (0–1) to consider a job |
| `ATS_TARGET_SCORE` | `70.0` | ATS score to aim for |
| `TARGET_ROLES` | Data Engineer, DS, DA, Analytics Eng, ML Eng | Job titles to search |
| `SEARCH_INTERVAL_HOURS` | `6` | Gap between autonomous pipeline cycles |

---

### 4.2 Database Models — `database/models.py`

SQLAlchemy ORM with SQLite. Four tables:

#### `jobs` table
```
id              INT  PK
title           TEXT
company         TEXT
location        TEXT
salary          TEXT
url             TEXT UNIQUE
source          TEXT  (linkedin / indeed / remotive)
raw_description TEXT
requirements    TEXT
posted_date     TEXT
found_date      DATETIME
status          ENUM  (new → analyzed → cv_tailored → ats_optimized → ready → applied → rejected → interviewing → offer → skipped)
match_score     FLOAT (0.0–1.0)
analysis_json   JSON  (structured LLM output)
```

#### `applications` table
```
id                  INT  PK
job_id              FK → jobs.id
cv_path             TEXT  (path to generated PDF)
tex_path            TEXT  (path to .tex source)
ats_score           FLOAT
created_date        DATETIME
applied_date        DATETIME
status              TEXT  (draft / applied)
modifications_json  JSON  (what the LLM changed)
```

#### `ats_scores` table
```
id                  INT  PK
application_id      FK → applications.id
keyword_score       FLOAT (0–25)
formatting_score    FLOAT (0–25)
relevance_score     FLOAT (0–25)
completeness_score  FLOAT (0–25)
total_score         FLOAT (0–100)
iteration           INT
breakdown_json      JSON
```

#### `user_profiles` table
```
id            INT  PK
name          TEXT
email         TEXT
phone         TEXT
linkedin      TEXT
github        TEXT
base_cv_path  TEXT
skills_json   JSON  (list of strings)
```

---

### 4.3 LLM Client — `utils/llm_client.py`

**`LLMClient` class** — wraps both Ollama and Groq with automatic fallback.

```
generate(prompt, system_prompt) → str
  1. Check if Ollama is available (GET /api/tags, cached after first check)
  2. If yes → POST to http://localhost:11434/api/chat (stream=False)
  3. If no → Use Groq SDK (AsyncGroq) with configured model

generate_json(prompt, system_prompt) → dict
  Same as generate() but:
  1. Strips markdown code fences (```json ... ```)
  2. Tries json.loads()
  3. Falls back to regex r'\{.*\}' to extract JSON object
  4. On failure, retries up to 2 times with "fix your JSON" message
```

**Singleton:** `get_llm_client()` creates one instance and reuses it.

---

### 4.4 Job Scrapers — `utils/scraper.py`

Three scrapers, all subclass `JobScraper` ABC:

| Scraper | Method | Notes |
|---|---|---|
| `RemotiveScraper` | Remotive public API (no JS needed) | Most reliable |
| `IndeedScraper` | Playwright headless browser | Rate-limit sensitive |
| `LinkedInPublicScraper` | Playwright headless browser | Public listings only |

All scrapers:
- Use random user-agent rotation
- Add random 2–6s delays between requests
- Call `normalize_url()` to strip tracking params before saving
- Return `JobData` objects (title, company, url, description, salary, location, source)

The `ScraperRegistry` maps string names to scraper classes.

---

### 4.5 ATS Scorer — `utils/ats_scorer.py`

Scores a CV against a job description. Max 100 points total:

| Dimension | Max | How |
|---|---|---|
| `keyword_score` | 25 | Count matching keywords from job description in CV text |
| `formatting_score` | 25 | Check for sections (Experience, Education, Skills), bullet points, dates |
| `relevance_score` | 25 | LLM call: "score how relevant this CV is to this job (0–25)" |
| `completeness_score` | 25 | Check that all `[PLACEHOLDER]` markers have been filled |

Returns `ATSScoreResult` dataclass.

---

### 4.6 LaTeX Handler — `utils/latex_handler.py`

Manages the LaTeX CV template system.

**Placeholder regex:**
```python
PLACEHOLDER_RE = re.compile(r'\[([A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+|[A-Z]{4,})\]')
```
This matches `[CANDIDATE_NAME]`, `[EMAIL]`, `[SKILLS_LIST]` etc. but NOT `[T1]` or `[utf8]` (LaTeX package options) — requires underscore OR 4+ uppercase chars.

**CV Placeholders in `base_template.tex`:**
- `[CANDIDATE_NAME]` — your name
- `[EMAIL]`, `[PHONE]`, `[LINKEDIN]`, `[GITHUB]`
- `[PROFESSIONAL_SUMMARY]` — 2–3 sentence tailored intro
- `[SKILLS_LIST]` — comma-separated skills relevant to the job
- `[EXPERIENCE_SECTION]` — tailored bullet points
- `[PROJECT_DESCRIPTIONS]` — tailored projects
- `[EDUCATION_SECTION]`

**`compile_latex(tex_path)`** — runs `pdflatex` twice (second pass for references), returns PDF path.

---

### 4.7 Agents — `agents/`

#### `job_finder.py` — `JobFinderAgent`
- Takes a list of role queries and a location
- Runs all configured scrapers concurrently with `asyncio.gather()`
- Deduplicates by URL
- Saves new jobs to SQLite with status `NEW`

#### `job_analyzer.py` — `JobAnalyzerAgent`
- Fetches all `NEW` jobs from DB
- For each job, sends raw description to LLM with a structured prompt
- LLM returns JSON with: `required_skills`, `preferred_skills`, `tech_stack`, `key_responsibilities`, `seniority_level`, `is_remote`, `summary`, `red_flags`, `match_score`
- Saves `analysis_json` and `match_score` to DB, updates status to `ANALYZED`
- Jobs below `MIN_MATCH_SCORE` → status `SKIPPED`

#### `cv_tailor.py` — `CVTailorAgent`
- Fetches `ANALYZED` jobs with `match_score >= min_match_score`
- Reads `base_template.tex`
- For each job, asks LLM to generate content for each placeholder based on the job analysis
- Fills placeholders with `fill_placeholders()`
- Compiles PDF with `pdflatex`
- Saves Application record, updates job status to `CV_TAILORED`

#### `ats_optimizer.py` — `ATSOptimizerAgent`
- Fetches `CV_TAILORED` jobs
- Runs `ats_scorer.py` on the generated CV
- If score < `ATS_TARGET_SCORE`, asks LLM for improvement suggestions, re-fills, re-compiles
- Iterates up to `MAX_ATS_ITERATIONS` times
- Saves final ATS score, updates status to `ATS_OPTIMIZED` then `READY`

#### `orchestrator.py` — `Orchestrator`
- Runs all 4 agents in sequence: find → analyze → tailor → optimize
- Emits `PipelineEvent` objects to an `asyncio.Queue` during execution
- The FastAPI server patches `_emit()` to relay events to its `pipeline_log` list
- `run_autonomous()` loops every `SEARCH_INTERVAL_HOURS`

---

### 4.8 Study Hub — `study_hub/`

#### `notes_index.py` — `NotesIndex`

The core of the Study Hub. Turns your markdown notes into a searchable AI knowledge base.

**How it builds the index:**
1. Scans `~/dev-notes/` recursively for all `.md` files
2. Parses YAML frontmatter (title, topic, date, tags) from each file
3. Splits each note into overlapping ~600-character chunks (paragraph-aware)
4. Embeds each chunk using `sentence-transformers` model `all-MiniLM-L6-v2` → 384-dimensional float vector
5. Stores all vectors in a `faiss.IndexFlatL2` (exact nearest-neighbour, L2 distance)

**Key methods:**
```
build() → int                          # Build/rebuild the full index
search(query, k=8) → list[dict]        # Semantic search, returns k unique notes
get_rag_context(query, k=5)            # Returns (context_text, source_titles) for LLM injection
list_notes() → list[dict]              # All notes sorted by date
get_note_content(note_id) → dict       # Full content of one note
```

**Singleton:** `get_notes_index()` — one index per server process.

#### `chat_agent.py`

RAG chat flow:
1. Call `notes_index.get_rag_context(query, k=5)` → gets top-5 relevant note chunks
2. Build prompt: inject context chunks + last 8 messages of conversation history + user query
3. Call `LLMClient.generate(prompt, system_prompt=STUDY_SYSTEM_PROMPT)`
4. Return `{"answer": str, "sources": list[str]}`

If no relevant notes found → answers from general knowledge and says so.

#### `file_extractor.py`

**`extract_text(filepath)`** — supports:
- `.md`, `.txt` — read directly
- `.pdf` — tries `pypdf` → `pdfminer` → `pdfplumber` in order
- `.docx` — uses `python-docx`

**`save_as_dev_note(title, raw_text, topic)`** — formats extracted text into the standard 7-section dev note template with YAML frontmatter, saves to `~/dev-notes/extracted/YYYY-MM-DD_slug.md`.

---

### 4.9 FastAPI Server — `api/server.py`

Starts on `http://127.0.0.1:8000`. All routes:

#### Jobs Routes
| Method | Path | Description |
|---|---|---|
| `GET` | `/stats` | Total jobs, new/analyzed/ready/applied counts, avg ATS score, CVs generated |
| `GET` | `/jobs` | List jobs. Query params: `status`, `source`, `min_score`, `limit`, `offset` |
| `GET` | `/jobs/{id}` | Full job detail including raw description and analysis JSON |
| `PATCH` | `/jobs/{id}/status` | Update status: `{"status": "applied"}` |
| `GET` | `/jobs/{id}/application` | Get the Application record for a job |
| `GET` | `/jobs/{id}/ats` | Get ATS score breakdown for a job |

#### Pipeline Routes
| Method | Path | Description |
|---|---|---|
| `POST` | `/pipeline/run` | Start pipeline in background (returns immediately) |
| `GET` | `/pipeline/status` | `{"running": bool, "log": [...last 50 events]}` |

#### Profile Routes
| Method | Path | Description |
|---|---|---|
| `GET` | `/profile` | Get user profile |
| `PATCH` | `/profile` | Update profile fields |

#### Study Hub Routes
| Method | Path | Description |
|---|---|---|
| `GET` | `/study/notes` | List all notes (metadata only) |
| `GET` | `/study/notes/{note_id}` | Full note content (note_id is relative path, e.g. `projects/yolo/2026-04-08_foo.md`) |
| `POST` | `/study/search` | `{"query": "...", "k": 8}` → semantic search results |
| `POST` | `/study/chat` | `{"query": "...", "history": [...]}` → RAG answer + sources |
| `POST` | `/study/reindex` | Re-scan and re-embed all notes |
| `POST` | `/study/upload` | Multipart: file + title + topic → extracts and saves as dev note |

#### Health
| Method | Path | Description |
|---|---|---|
| `GET` | `/health` | `{"status": "ok", "time": "..."}` |

**Study index lifecycle:** Built in a background thread at server startup. `POST /study/reindex` or uploading a file both trigger a full rebuild.

---

## 5. Swift macOS App

### 5.1 Entry Point — `JobAgentApp.swift`

```swift
@main
struct JobAgentApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
                .frame(minWidth: 900, minHeight: 650)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
```

No global AppState here. Each module creates its own when it opens.

---

### 5.2 HomeView — `Views/HomeView.swift`

The landing screen. Shows:
- **"US" initials** — 96pt bold italic serif, spring-animated on appear
- **"Upendra Surya"** subtitle
- **Profile cards grid** — 2-column LazyVGrid, one card per module
- **"Add Profile" card** — dashed border placeholder

**`AppProfile` struct** holds each card's:
- `id: String` — used for routing
- `name`, `description`
- `cardColor`, `accentColor` — the dark card background + highlight colour
- `pixelArt: [[Int]]` — the pixel art grid (0=transparent, 1=dark, 2=accent)
- `destination: some View` — where tapping navigates to

**Routing logic:**
```swift
switch id {
case "jobs":  ContentView()
case "study": StudyHubView()
default:      ComingSoonView(profile: self)
}
```

**`PixelArtView`** (in `Components/`) renders the pixel art using SwiftUI `Canvas`. Each cell is drawn as a filled rectangle. Size auto-calculated from GeometryReader.

---

### 5.3 Jobs Module

#### `ContentView.swift`
Shell for the Jobs module. Creates `@StateObject private var appState = AppState()`. Uses `NavigationSplitView` — sidebar on left, detail on right.

Routes `appState.selectedTab` to:
- `.dashboard` → `DashboardView()`
- `.jobs` → `JobsView()`
- `.tracker` → `TrackerView()`
- `.profile` → `ProfileView()`

Toolbar shows `BackendStatusBadge`.

#### `DashboardView.swift`
- Shows stats grid: Total Jobs, Ready to Apply, Avg ATS Score, CVs Generated (4-column), then New/Analyzed/Applied (3-column)
- Shows pipeline log: scrollable list of timestamped events with colour-coded stage labels
- Refresh button top-right
- Error banner if `appState.errorMessage` is set
- ATS colour coding: green ≥75, amber ≥55, red <55

#### `JobsView.swift`
- Left panel: search bar + filter chips (all/new/analyzed/ready/applied/rejected) + scrollable job list
- Right panel: job detail — title, company, analysis breakdown, skills tags, ATS ring, application info, status dropdown, "Open Job" button, "Open CV" button
- `HSplitView` layout
- Filter chips call `appState.applyStatusFilter()`

#### `TrackerView.swift`
- Horizontal scrolling Kanban board
- 4 columns: Applied / Interviewing / Offer / Rejected
- Each `KanbanCard` shows title, company, ATS score, external link button
- Column header shows count badge

#### `ProfileView.swift`
- Edit mode / view mode toggle
- Fields: Full Name, Email, Phone, LinkedIn, GitHub (2-column grid)
- Skills as tags with remove buttons in edit mode, add skill text field
- "Open base_template.tex" button opens your LaTeX CV in default app
- Save shows animated "Saved ✓" confirmation

---

### 5.4 Study Hub Module

#### `StudyHubView.swift`

`NavigationSplitView` layout:

**Left sidebar:**
- Header with note count
- Search bar (semantic search, debounced 400ms)
- Topic filter chips (auto-generated from note metadata)
- Note list (`NoteRow` — shows title, 2-line preview, topic chip, date)

**Right detail:**
- `NoteDetailView` — shows title, topic, date, tags, then full note content rendered as Markdown via `AttributedString(markdown:)`
- "Ask AI" button in top-right of note header → opens `StudyChatView` sheet

**Toolbar buttons:**
- Reindex — calls `POST /study/reindex`, refreshes list
- Upload File — opens `UploadFileSheet`
- Ask AI — opens `StudyChatView`

**`UploadFileSheet`:**
- `NSOpenPanel` file picker (PDF/DOCX/TXT/MD)
- Title field (auto-filled from filename)
- Topic picker (dropdown: general/python/javascript/frontend/swift/ml/data/devops)
- Extract & Save Note button → calls `POST /study/upload`

**`StudyHubViewModel` (@MainActor ObservableObject):**
- `loadNotes()` — `GET /study/notes`
- `search()` — `POST /study/search` with debounce
- `selectNote()` — `GET /study/notes/{id}`
- `reindex()`, `uploadFile()`
- `displayedNotes` — computed from either search results or full list, filtered by topic

#### `StudyChatView.swift`

Full-screen chat interface (presented as `.sheet`):

- Header: "Ask AI" + note context label + trash (clear) + close
- Messages: scrollable `LazyVStack` of `ChatBubble` views
- Sources bar: shows which notes were used to answer (appears after AI responds)
- Input bar: multi-line `TextField` + send button
- Empty state: 3–4 suggestion prompts that send on tap
- `ThinkingBubble`: animated 3-dot indicator while waiting

**`ChatBubble`:**
- User messages: dark background, right-aligned, "U" avatar
- AI messages: card background, left-aligned, "AI" avatar circle, renders Markdown

**`StudyChatViewModel`:**
- `send(text)` → appends user message → calls `StudyAPIClient.shared.chat()` → appends AI response
- `clear()` → empties message history

---

### 5.5 Shared Components & Theme — `Components/SharedComponents.swift`

#### `Theme` enum
All colours defined as static properties. Beige/black palette:

| Name | Hex | Purpose |
|---|---|---|
| `bg` | `#F5F0E8` | Page background |
| `card` | `#FDFAF4` | Card background |
| `surface` | `#EDE6D6` | Input backgrounds, chips |
| `ink` | `#1A1705` | Primary text, dark buttons |
| `inkSecondary` | `#7A6E58` | Subtitle text |
| `inkMuted` | `#B0A48A` | Labels, placeholders |
| `accent` | `#C8963E` | Amber highlight |
| `accentSoft` | `#F0DEB8` | Selected row backgrounds |
| `border` | `#D8CEB8` | All borders |
| `green` | `#4A7C59` | Success, offers |
| `red` | `#9B3A2E` | Errors, rejected |
| `purple` | `#5C4A8A` | ATS/CVs, interviewing |
| `teal` | `#3A6B6B` | Analysis |

`Color(hex:)` extension converts hex strings to SwiftUI Colors.

#### Reusable components
- `SidebarView` — left nav for Jobs module. Shows "US" back button, tabs with icons, "Run Pipeline" button, `BackendStatusBadge`
- `StatCard` — icon + number + title card
- `JobStatusBadge` — colour-coded status pill
- `ATSRing` — circular progress ring for ATS score
- `ScoreBar` — horizontal progress bar
- `ErrorBanner` — dismissible red banner
- `SectionHeader` — section title + refresh button
- `FlowLayout` — wrapping horizontal layout for tags/chips

---

### 5.6 AppState — `Services/AppState.swift`

`@MainActor class AppState: ObservableObject`

**State:**
- `stats: AppStats?` — dashboard numbers
- `jobs: [JobSummary]` — current job list
- `selectedJobId: Int?`
- `selectedTab: SidebarTab`
- `isBackendOnline: Bool`
- `isPipelineRunning: Bool`
- `pipelineLog: [PipelineLogEntry]`
- `errorMessage: String?`
- `statusFilter: String`
- `profile: UserProfile?`

**Startup:** Checks backend health. If offline, retries every 3s until it comes online. When online, calls `refreshAll()` and starts 15s polling loop.

**Pipeline polling:** When pipeline is running, polls every 2s (up to 2 minutes) instead of 15s.

---

### 5.7 APIClient — `Services/APIClient.swift`

`actor APIClient` — Swift actor guarantees all calls are serialised (no data races).

Generic helpers:
- `fetch<T: Decodable>(_ path)` — GET request
- `post<T: Decodable>(_ path, body)` — POST with JSON body
- `patch<T: Decodable>(_ path, body)` — PATCH with JSON body

Translates `URLError.cannotConnectToHost` → `APIError.offline` so the UI shows a meaningful message.

`StudyAPIClient` — identical actor pattern but for study routes. Also handles multipart form upload for file upload.

---

## 6. Data Flow — End to End

### Job Pipeline Flow
```
User clicks "Run Pipeline"
  → AppState.runPipeline()
  → APIClient POST /pipeline/run
  → FastAPI starts _run_pipeline_bg() as BackgroundTask
  → Returns 200 immediately

Background:
  Orchestrator.run_cycle()
    → JobFinderAgent → scrapes Remotive/Indeed/LinkedIn → saves NEW jobs to SQLite
    → JobAnalyzerAgent → LLM analyzes each job → saves analysis_json, updates status
    → CVTailorAgent → LLM fills placeholders in base_template.tex → pdflatex → saves PDF
    → ATSOptimizerAgent → scores CV → re-tailors if needed → marks READY

Swift app polls GET /pipeline/status every 2s
  → Updates pipelineLog, isPipelineRunning
  → When done, refreshes jobs list
```

### Study Chat Flow
```
User types question in StudyChatView
  → StudyAPIClient POST /study/chat {query, history}
  → FastAPI calls study_hub/chat_agent.chat()
    → NotesIndex.get_rag_context(query, k=5)
      → Embed query with all-MiniLM-L6-v2
      → FAISS finds 5 closest note chunks
    → Build prompt: [5 note chunks] + [conversation history] + [user query]
    → LLMClient.generate(prompt) → Ollama or Groq
    → Return {answer, sources}
  → Swift displays answer as ChatBubble
  → Sources shown in sources bar below
```

### File Upload Flow
```
User picks file in UploadFileSheet
  → StudyAPIClient.uploadFile(url, title, topic)
  → POST /study/upload (multipart form)
  → FastAPI saves to temp file
  → file_extractor.extract_text() → raw text
  → file_extractor.save_as_dev_note() → saves to ~/dev-notes/extracted/
  → NotesIndex.build() → full reindex
  → Swift refreshes note list
```

---

## 7. How to Run

### Prerequisites
```bash
# Python dependencies
cd job-application-agent
pip install fastapi uvicorn sqlalchemy pydantic-settings httpx
pip install playwright beautifulsoup4 requests
pip install sentence-transformers faiss-cpu
pip install pypdf python-docx  # for file extraction

# For Playwright scrapers
playwright install chromium

# Optional: install Ollama for local LLM
# https://ollama.ai → then: ollama pull llama3.1
```

### Environment
The `.env` file at `job-application-agent/.env` contains:
```
GROQ_API_KEY=your_key_here
GROQ_MODEL=llama-3.1-8b-instant
OLLAMA_BASE_URL=http://localhost:11434
OLLAMA_MODEL=llama3.1
```

### Start the backend
```bash
cd job-application-agent
python3 main.py
# Server starts on http://127.0.0.1:8000
# Study index built in background (~2–5s for your notes)
```

### Open the app
- Open `/Applications/JobAgentApp.app`
- Or build from source: `cd JobAgentApp && xcodebuild ...`
- Home screen appears → tap a module card

### Add your CV content
Edit `job-application-agent/cv_templates/base_template.tex`. Replace the placeholder markers with your real content. The AI will customise the `[PLACEHOLDER]` sections per job.

---

## 8. API Reference

Full list of endpoints at `http://127.0.0.1:8000/docs` (FastAPI auto-generates Swagger UI).

### Request/Response examples

**GET /stats**
```json
{
  "total_jobs": 42,
  "new_jobs": 5,
  "analyzed_jobs": 12,
  "ready_jobs": 8,
  "applied_jobs": 3,
  "avg_ats_score": 74.2,
  "cvs_generated": 11
}
```

**POST /study/search**
```json
// Request
{"query": "how does FAISS work", "k": 5}

// Response
{
  "query": "how does FAISS work",
  "results": [
    {
      "note_id": "projects/yolo-app/2026-04-08_study-hub-rag-feature.md",
      "title": "Study Hub — RAG Chat + Vector Search + File Extraction",
      "snippet": "FAISS (Facebook AI Similarity Search) — a library that can find...",
      "score": 0.87,
      "tags": ["python", "rag", "vector-db"],
      "topic": "python",
      "date": "2026-04-08"
    }
  ]
}
```

**POST /study/chat**
```json
// Request
{
  "query": "What did I learn about SwiftUI navigation?",
  "history": [
    {"role": "user", "content": "Tell me about the yolo project"},
    {"role": "assistant", "content": "The yolo project is..."}
  ]
}

// Response
{
  "answer": "Based on your notes, you learned that SwiftUI uses NavigationSplitView...",
  "sources": ["Study Hub — RAG Chat feature", "HomeView Entry Point redesign"]
}
```

---

## 9. Key Design Decisions

### Why FastAPI not direct Swift-to-LLM?
All AI logic in Python keeps the Swift app simple. Python has much better ML/AI libraries (sentence-transformers, FAISS, pdflatex integration). Swift app just does UI.

### Why FAISS not a cloud vector DB?
FAISS runs locally, free, offline, instant. For ~1000 notes it's plenty fast. No API keys, no latency, no cost.

### Why SQLite not PostgreSQL?
Single-user personal app. SQLite is zero-config, the db file lives in the project folder, and SQLAlchemy makes swapping it out trivial if needed.

### Why actor for APIClient?
Swift actors prevent data races. Multiple async calls from different parts of the UI can safely share one URLSession without locks.

### Why LaTeX for CVs?
LaTeX produces pixel-perfect PDFs. The `[PLACEHOLDER]` system means the AI only needs to fill in specific sections rather than regenerating the entire document.

### Why sentence-transformers `all-MiniLM-L6-v2`?
Fast, small (80MB), runs on CPU, good enough semantic understanding for personal notes. Better models exist but this one needs no GPU.

### Why chunk notes rather than embed whole files?
LLM embedding models have a token limit (~512 tokens). Long notes would be truncated. Chunking ensures every part of a long note is searchable, with overlap to preserve context at chunk boundaries.

---

## 10. What Each File Does — Quick Reference

| File | One-line purpose |
|---|---|
| `config.py` | All settings, reads `.env` |
| `database/models.py` | SQLAlchemy tables: Job, Application, ATSScore, UserProfile |
| `database/init_db.py` | Create tables on startup, seed default profile |
| `utils/llm_client.py` | LLM wrapper: Ollama primary, Groq fallback |
| `utils/scraper.py` | Web scrapers for Remotive, Indeed, LinkedIn |
| `utils/ats_scorer.py` | Score a CV against a job description (0–100) |
| `utils/latex_handler.py` | Fill placeholders in .tex, compile PDF |
| `agents/job_finder.py` | Run scrapers, save new jobs to DB |
| `agents/job_analyzer.py` | LLM-analyze jobs, compute match score |
| `agents/cv_tailor.py` | LLM-fill CV template, compile PDF |
| `agents/ats_optimizer.py` | Score and iteratively improve CVs |
| `agents/orchestrator.py` | Run all 4 agents in sequence, emit events |
| `study_hub/notes_index.py` | FAISS vector index of ~/dev-notes/ |
| `study_hub/chat_agent.py` | RAG: retrieve notes → inject → LLM answer |
| `study_hub/file_extractor.py` | Extract text from PDF/DOCX, save as dev note |
| `api/server.py` | All FastAPI routes, pipeline state management |
| `main.py` | Entry point, starts uvicorn |
| `JobAgentApp.swift` | @main, opens HomeView |
| `Models/Models.swift` | All Codable structs for API responses |
| `Services/APIClient.swift` | HTTP client for Jobs API (actor) |
| `Services/StudyAPIClient.swift` | HTTP client for Study Hub API (actor) |
| `Services/AppState.swift` | Global state for Jobs module, polling |
| `Components/SharedComponents.swift` | Theme, SidebarView, reusable UI pieces |
| `Components/PixelArtView.swift` | Canvas renderer for pixel art on home cards |
| `Views/HomeView.swift` | Landing screen, module cards, pixel art |
| `Views/ContentView.swift` | Jobs module shell, NavigationSplitView |
| `Views/DashboardView.swift` | Stats grid + pipeline log |
| `Views/JobsView.swift` | Job list + detail panel |
| `Views/TrackerView.swift` | Kanban board |
| `Views/ProfileView.swift` | Edit profile and skills |
| `Views/StudyHubView.swift` | Notes browser, search, upload sheet |
| `Views/StudyChatView.swift` | AI chat interface |
