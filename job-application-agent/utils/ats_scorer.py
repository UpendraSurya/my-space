"""
ATS scoring engine. Scores a CV against a job description across 4 dimensions.
Total score is out of 100.
"""
import re
import logging
from dataclasses import dataclass, field

logger = logging.getLogger(__name__)

STOPWORDS = {
    "a", "an", "the", "and", "or", "but", "in", "on", "at", "to", "for",
    "of", "with", "by", "from", "up", "about", "into", "through", "during",
    "is", "are", "was", "were", "be", "been", "being", "have", "has", "had",
    "do", "does", "did", "will", "would", "shall", "should", "may", "might",
    "must", "can", "could", "not", "no", "nor", "so", "yet", "both", "either",
    "each", "more", "most", "other", "some", "such", "than", "too", "very",
    "just", "because", "as", "until", "while", "although", "though", "since",
    "if", "then", "that", "this", "these", "those", "their", "they", "we",
    "our", "your", "its", "his", "her", "my", "i", "you", "he", "she", "it",
    "who", "which", "what", "all", "any", "few", "many", "much", "own", "same",
    "work", "experience", "years", "year", "strong", "ability", "skills",
    "knowledge", "understanding", "excellent", "good", "great", "excellent",
}

SECTION_KEYWORDS = {
    "education": ["education", r"\\section\{education\}", "degree", "university", "bachelor", "master"],
    "experience": ["experience", r"\\section\{experience\}", "employment", "work history"],
    "skills": ["skills", r"\\section\{skills\}", "technical skills", "technologies"],
    "contact": ["@", "linkedin", "github", "phone", "email"],
}


@dataclass
class ATSScoreResult:
    keyword_score: float = 0.0
    formatting_score: float = 0.0
    relevance_score: float = 0.0
    completeness_score: float = 0.0
    total_score: float = 0.0
    matched_keywords: list[str] = field(default_factory=list)
    missing_keywords: list[str] = field(default_factory=list)
    breakdown: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "keyword_score": self.keyword_score,
            "formatting_score": self.formatting_score,
            "relevance_score": self.relevance_score,
            "completeness_score": self.completeness_score,
            "total_score": self.total_score,
            "matched_keywords": self.matched_keywords,
            "missing_keywords": self.missing_keywords,
            "breakdown": self.breakdown,
        }


def _extract_keywords(text: str, top_n: int = 40) -> list[str]:
    """Extract meaningful keywords from text using simple frequency."""
    text = text.lower()
    # Remove special chars but keep hyphens in words
    words = re.findall(r'\b[a-z][a-z0-9\-\.]+\b', text)
    words = [w for w in words if w not in STOPWORDS and len(w) > 2]

    # Count frequency
    freq: dict[str, int] = {}
    for w in words:
        freq[w] = freq.get(w, 0) + 1

    # Sort by frequency, return top N
    sorted_words = sorted(freq.keys(), key=lambda w: freq[w], reverse=True)
    return sorted_words[:top_n]


def score_keywords(job_description: str, cv_text: str) -> tuple[float, list[str], list[str]]:
    """Score keyword match. Returns (score_0_to_25, matched, missing)."""
    job_keywords = set(_extract_keywords(job_description, top_n=30))
    cv_text_lower = cv_text.lower()

    matched = [kw for kw in job_keywords if kw in cv_text_lower]
    missing = [kw for kw in job_keywords if kw not in cv_text_lower]

    if not job_keywords:
        return 25.0, [], []

    ratio = len(matched) / len(job_keywords)
    score = min(ratio * 25.0, 25.0)
    return round(score, 2), matched, missing


def score_formatting(cv_tex_content: str) -> float:
    """Score CV LaTeX formatting quality. Returns score 0-25."""
    score = 0.0
    checks = {}

    # Check for essential sections
    tex_lower = cv_tex_content.lower()
    for section, patterns in SECTION_KEYWORDS.items():
        found = any(re.search(p, tex_lower) for p in patterns)
        checks[section] = found
        if found:
            score += 5.0

    # No tables (ATS parsers often fail on tables)
    if r"\begin{tabular}" not in cv_tex_content:
        score += 2.0
        checks["no_tables"] = True
    else:
        checks["no_tables"] = False

    # Has email
    if re.search(r'[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}', cv_tex_content):
        score += 3.0
        checks["has_email"] = True

    return round(min(score, 25.0), 2)


def score_completeness(cv_tex_content: str) -> float:
    """Score completeness of CV sections. Returns 0-25."""
    score = 0.0
    tex_lower = cv_tex_content.lower()

    # Email present
    if re.search(r'[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}', tex_lower):
        score += 5.0
    # Phone
    if re.search(r'\+?[\d\s\-\(\)]{7,15}', cv_tex_content):
        score += 3.0
    # LinkedIn
    if "linkedin" in tex_lower:
        score += 3.0
    # GitHub
    if "github" in tex_lower:
        score += 2.0
    # Education section
    if "education" in tex_lower:
        score += 4.0
    # Experience section
    if "experience" in tex_lower or "employment" in tex_lower:
        score += 4.0
    # Skills section
    if "skills" in tex_lower or "technologies" in tex_lower:
        score += 4.0

    return round(min(score, 25.0), 2)


async def score_relevance_llm(job_description: str, cv_summary: str) -> float:
    """Use LLM to score relevance. Returns 0-25."""
    try:
        from utils.llm_client import get_llm_client
        llm = get_llm_client()
        prompt = (
            f"Rate the relevance of this CV to this job description on a scale of 0-10.\n\n"
            f"JOB DESCRIPTION (first 1000 chars):\n{job_description[:1000]}\n\n"
            f"CV SUMMARY:\n{cv_summary[:800]}\n\n"
            f"Return JSON: {{\"score\": <0-10>, \"reason\": \"<one sentence>\"}}"
        )
        result = await llm.generate_json(prompt)
        raw_score = float(result.get("score", 5))
        return round((raw_score / 10.0) * 25.0, 2)
    except Exception as e:
        logger.warning(f"LLM relevance scoring failed: {e}, using default 12.5")
        return 12.5


async def score_cv(
    job_description: str,
    cv_tex_content: str,
    cv_text_plain: str = "",
) -> ATSScoreResult:
    """Full ATS score calculation. Returns ATSScoreResult."""
    plain = cv_text_plain or cv_tex_content

    kw_score, matched, missing = score_keywords(job_description, plain)
    fmt_score = score_formatting(cv_tex_content)
    comp_score = score_completeness(cv_tex_content)
    rel_score = await score_relevance_llm(job_description, plain[:800])

    total = kw_score + fmt_score + rel_score + comp_score

    result = ATSScoreResult(
        keyword_score=kw_score,
        formatting_score=fmt_score,
        relevance_score=rel_score,
        completeness_score=comp_score,
        total_score=round(total, 2),
        matched_keywords=matched,
        missing_keywords=missing[:15],
        breakdown={
            "keyword_40pct": kw_score,
            "formatting_30pct": fmt_score,
            "relevance_20pct": rel_score,
            "completeness_10pct": comp_score,
        },
    )
    logger.info(f"ATS Score: {result.total_score:.1f}/100 "
                f"(kw:{kw_score:.1f} fmt:{fmt_score:.1f} rel:{rel_score:.1f} "
                f"comp:{comp_score:.1f})")
    return result
