"""
File extractor — pulls text from uploaded files and formats them
as dev notes in the standard learning-note template.
"""
import re
import logging
from datetime import date
from pathlib import Path

logger = logging.getLogger(__name__)


def extract_text(filepath: Path) -> str:
    """Extract raw text from file. Supports .md, .txt, .pdf, .docx."""
    suffix = filepath.suffix.lower()

    if suffix in (".md", ".txt"):
        return filepath.read_text(encoding="utf-8", errors="ignore")

    if suffix == ".pdf":
        text = _extract_pdf(filepath)
        if text:
            return text

    if suffix in (".docx", ".doc"):
        text = _extract_docx(filepath)
        if text:
            return text

    # Fallback: try reading as text
    try:
        return filepath.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return f"[Could not extract content from {filepath.name}]"


def _extract_pdf(path: Path) -> str:
    # Try pypdf first
    try:
        import pypdf
        reader = pypdf.PdfReader(str(path))
        pages = []
        for page in reader.pages:
            t = page.extract_text()
            if t:
                pages.append(t)
        return "\n\n".join(pages)
    except ImportError:
        pass

    # Try pdfminer
    try:
        from pdfminer.high_level import extract_text as pdfminer_extract
        return pdfminer_extract(str(path))
    except ImportError:
        pass

    # Try pdfplumber
    try:
        import pdfplumber
        with pdfplumber.open(str(path)) as pdf:
            return "\n\n".join(p.extract_text() or "" for p in pdf.pages)
    except ImportError:
        pass

    return "[PDF extraction failed — install pypdf: pip install pypdf]"


def _extract_docx(path: Path) -> str:
    try:
        import docx
        doc = docx.Document(str(path))
        return "\n".join(p.text for p in doc.paragraphs if p.text.strip())
    except ImportError:
        return "[DOCX extraction failed — install python-docx: pip install python-docx]"


def save_as_dev_note(
    title: str,
    raw_text: str,
    topic: str = "general",
    notes_dir: Path = None,
    subfolder: str = "extracted",
) -> Path:
    """
    Convert raw extracted text into a dev note and save it to ~/dev-notes/.
    Returns the saved file path.
    """
    if notes_dir is None:
        notes_dir = Path.home() / "dev-notes"

    today = date.today().isoformat()
    slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")[:50]
    filename = f"{today}_{slug}.md"

    save_dir = notes_dir / subfolder
    save_dir.mkdir(parents=True, exist_ok=True)
    out_path = save_dir / filename

    # Truncate very long content
    content_preview = raw_text.strip()
    if len(content_preview) > 6000:
        content_preview = content_preview[:6000] + "\n\n[... content truncated — full file saved ...]"

    note = f"""---
title: "{title}"
date: {today}
topic: {topic}
project: study
status: learning
reviewed: false
tags: [#extracted, #{topic}, #uploaded]
---

> [!info] What this document covers
> Extracted content from uploaded file. Review and edit the sections below.

> [!example] Full Content
{_indent(content_preview)}

> [!tip] Next steps
> - Review the content above
> - Extract key concepts and add them to topic notes
> - Add this to the relevant topic index

## Linked notes

- [[{topic}]]
- [[{today}]]
"""

    out_path.write_text(note, encoding="utf-8")
    logger.info(f"Saved extracted note to {out_path}")
    return out_path


def _indent(text: str, prefix: str = "> ") -> str:
    """Indent each line for Obsidian callout block."""
    lines = text.split("\n")
    return "\n".join(f"{prefix}{line}" if line.strip() else ">" for line in lines)
