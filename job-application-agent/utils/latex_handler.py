"""
LaTeX CV template handler.
- Parses .tex files to find [PLACEHOLDER] markers
- Fills placeholders with LLM-generated content
- Compiles .tex to PDF using pdflatex
"""
import logging
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

logger = logging.getLogger(__name__)

# Regex to find [PLACEHOLDER_NAME] patterns
# Match [PLACEHOLDER_NAME] — must have underscore OR be 4+ chars of uppercase
# This avoids matching LaTeX package options like [T1], [12pt] etc.
PLACEHOLDER_RE = re.compile(r'\[([A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+|[A-Z]{4,})\]')

# LaTeX special characters that must be escaped
LATEX_SPECIAL = [
    ('\\', r'\textbackslash{}'),
    ('&', r'\&'),
    ('%', r'\%'),
    ('$', r'\$'),
    ('#', r'\#'),
    ('^', r'\^{}'),
    ('~', r'\~{}'),
    ('{', r'\{'),
    ('}', r'\}'),
]


def latex_escape(text: str) -> str:
    """Escape special LaTeX characters in plain text."""
    # Handle backslash first to avoid double-escaping
    result = text.replace('\\', r'\textbackslash{}')
    for char, escaped in LATEX_SPECIAL[1:]:
        result = result.replace(char, escaped)
    return result


def find_placeholders(tex_content: str) -> list[str]:
    """Return list of unique placeholder names found in template."""
    return list(dict.fromkeys(PLACEHOLDER_RE.findall(tex_content)))


def fill_placeholders(tex_content: str, values: dict[str, str]) -> str:
    """
    Replace [PLACEHOLDER] with values.
    Escapes LaTeX chars in inserted values unless value starts with backslash
    (meaning it's already valid LaTeX).
    """
    result = tex_content
    for key, value in values.items():
        placeholder = f"[{key}]"
        # If value looks like raw LaTeX, don't escape it
        if value.startswith('\\') or r'\begin' in value or r'\item' in value:
            safe_value = value
        else:
            safe_value = latex_escape(str(value))
        result = result.replace(placeholder, safe_value)
    return result


def read_template(path: str) -> str:
    """Read a .tex template file."""
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def write_tex(content: str, output_path: str):
    """Write .tex content to file."""
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(content)


def compile_latex(tex_path: str, output_dir: str) -> tuple[bool, str]:
    """
    Compile .tex to PDF using pdflatex.
    Returns (success: bool, error_message: str).
    Runs pdflatex twice for proper references.
    """
    if not shutil.which("pdflatex"):
        return False, (
            "pdflatex not found. Install MacTeX: https://www.tug.org/mactex/ "
            "or run: brew install --cask mactex-no-gui"
        )

    os.makedirs(output_dir, exist_ok=True)
    cmd = [
        "pdflatex",
        "-interaction=nonstopmode",
        "-output-directory", output_dir,
        tex_path,
    ]

    last_error = ""
    for pass_num in range(2):
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=60,
                cwd=os.path.dirname(tex_path) or ".",
            )
            if result.returncode != 0:
                last_error = result.stderr or result.stdout
                if pass_num == 0:
                    logger.debug(f"pdflatex pass 1 warning (may be OK): {last_error[:200]}")
                else:
                    logger.error(f"pdflatex failed:\n{last_error[:500]}")
                    return False, last_error[:500]
        except subprocess.TimeoutExpired:
            return False, "pdflatex timed out after 60s"
        except Exception as e:
            return False, str(e)

    # Verify PDF was created
    tex_stem = Path(tex_path).stem
    pdf_path = os.path.join(output_dir, f"{tex_stem}.pdf")
    if os.path.exists(pdf_path):
        return True, pdf_path
    return False, f"PDF not found at expected path: {pdf_path}"


def get_pdf_path(tex_path: str, output_dir: str) -> str:
    """Get expected PDF output path for a .tex file."""
    stem = Path(tex_path).stem
    return os.path.join(output_dir, f"{stem}.pdf")
