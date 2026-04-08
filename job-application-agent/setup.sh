#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────
# Job Application Agent — One-time setup script
# Run this once: bash setup.sh
# ─────────────────────────────────────────────────────────
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo "══════════════════════════════════════════════════════"
echo "  Job Application Agent — Setup"
echo "══════════════════════════════════════════════════════"
echo ""

# 1. Python dependencies
echo "▶ Installing Python dependencies..."
pip3 install -q -r requirements.txt
echo "  ✓ Python packages installed"

# 2. Playwright browser
echo "▶ Installing Playwright browser..."
python3 -m playwright install chromium --quiet 2>/dev/null || true
echo "  ✓ Playwright chromium ready"

# 3. Create .env if missing
if [ ! -f ".env" ]; then
    cp .env.example .env
    echo "  ✓ Created .env (edit it to add your GROQ_API_KEY)"
else
    echo "  ✓ .env already exists"
fi

# 4. Initialise database
echo "▶ Initialising database..."
python3 -c "
import sys; sys.path.insert(0, '.')
from database.init_db import init_database
init_database()
"
echo "  ✓ Database ready"

# 5. Ollama check / suggestion
echo ""
echo "▶ LLM check..."
if command -v ollama &>/dev/null; then
    echo "  ✓ Ollama installed"
    if ollama list 2>/dev/null | grep -q "llama3.1"; then
        echo "  ✓ llama3.1 model present"
    else
        echo "  ▷ Pulling llama3.1 (this may take a few minutes)..."
        ollama pull llama3.1 && echo "  ✓ llama3.1 ready" || echo "  ! Pull failed — start ollama serve first"
    fi
else
    echo "  ! Ollama not found. Options:"
    echo "      brew install ollama && ollama pull llama3.1"
    echo "      OR: add GROQ_API_KEY to .env (https://console.groq.com)"
fi

# 6. LaTeX check
echo ""
if command -v pdflatex &>/dev/null; then
    echo "  ✓ pdflatex found — PDF output enabled"
else
    echo "  ! pdflatex not found — CVs will be .tex only"
    echo "    Install: brew install --cask mactex-no-gui"
fi

echo ""
echo "══════════════════════════════════════════════════════"
echo "  Setup complete! Next steps:"
echo ""
echo "  1. Start the backend:"
echo "       cd job-application-agent"
echo "       python3 main.py"
echo ""
echo "  2. Open the Swift app in Xcode:"
echo "       open ../JobAgentApp/JobAgentApp.xcodeproj"
echo "       Press ⌘R to build and run"
echo ""
echo "  3. Run a pipeline cycle from the app or:"
echo "       python3 main.py --headless"
echo "══════════════════════════════════════════════════════"
echo ""
