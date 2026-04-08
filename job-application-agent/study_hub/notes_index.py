"""
Notes indexer — scans ~/dev-notes/ for .md files, embeds them with
sentence-transformers, and stores in a FAISS index for semantic search.
"""
import re
import logging
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

logger = logging.getLogger(__name__)

NOTES_DIR = Path.home() / "dev-notes"


@dataclass
class NoteChunk:
    note_id: str        # relative path from notes_dir
    title: str
    path: str           # absolute path
    full_content: str
    chunk_text: str
    tags: list = field(default_factory=list)
    topic: str = ""
    date: str = ""


class NotesIndex:
    def __init__(self, notes_dir: Path = NOTES_DIR):
        self.notes_dir = notes_dir
        self._model = None
        self.chunks: list[NoteChunk] = []
        self._index = None
        self._built = False

    def _get_model(self):
        if self._model is None:
            from sentence_transformers import SentenceTransformer
            self._model = SentenceTransformer("all-MiniLM-L6-v2")
        return self._model

    # ── Build ─────────────────────────────────────────────────────────────── #

    def build(self) -> int:
        """Scan notes dir, embed all chunks, build FAISS index. Returns # notes."""
        import faiss

        self.chunks = []
        md_files = list(self.notes_dir.rglob("*.md"))
        logger.info(f"Indexing {len(md_files)} markdown files from {self.notes_dir}")

        for path in md_files:
            try:
                text = path.read_text(encoding="utf-8", errors="ignore")
                meta, content = self._parse_frontmatter(text)
                if not content.strip():
                    continue

                title = str(meta.get("title", "")).strip('"') or path.stem
                tags_raw = meta.get("tags", [])
                tags = self._parse_tags(tags_raw)
                topic = str(meta.get("topic", "")).strip('"')
                date = str(meta.get("date", "")).strip('"')
                note_id = str(path.relative_to(self.notes_dir))

                for chunk_text in self._chunk(content, size=600, overlap=100):
                    self.chunks.append(NoteChunk(
                        note_id=note_id,
                        title=title,
                        path=str(path),
                        full_content=content,
                        chunk_text=chunk_text,
                        tags=tags,
                        topic=topic,
                        date=date,
                    ))
            except Exception as e:
                logger.debug(f"Skipping {path}: {e}")

        if not self.chunks:
            logger.warning("No note chunks found — index is empty.")
            self._built = True
            return 0

        model = self._get_model()
        texts = [c.chunk_text for c in self.chunks]
        embeddings = model.encode(texts, show_progress_bar=False, batch_size=64)
        embeddings = np.array(embeddings, dtype="float32")

        dim = embeddings.shape[1]
        self._index = faiss.IndexFlatL2(dim)
        self._index.add(embeddings)
        self._built = True

        unique_notes = len({c.note_id for c in self.chunks})
        logger.info(f"Indexed {unique_notes} notes → {len(self.chunks)} chunks.")
        return unique_notes

    # ── Search ────────────────────────────────────────────────────────────── #

    def search(self, query: str, k: int = 8) -> list[dict]:
        """Return top-k unique notes ranked by semantic similarity."""
        if not self._built or not self._index:
            return []

        model = self._get_model()
        q_emb = model.encode([query], show_progress_bar=False).astype("float32")
        distances, indices = self._index.search(q_emb, min(k * 3, len(self.chunks)))

        seen: set[str] = set()
        results: list[dict] = []
        for dist, idx in zip(distances[0], indices[0]):
            if idx < 0 or idx >= len(self.chunks):
                continue
            chunk = self.chunks[idx]
            if chunk.note_id in seen:
                continue
            seen.add(chunk.note_id)
            results.append({
                "note_id": chunk.note_id,
                "title": chunk.title,
                "path": chunk.path,
                "snippet": chunk.chunk_text[:250].strip(),
                "score": float(1 / (1 + dist)),
                "tags": chunk.tags,
                "topic": chunk.topic,
                "date": chunk.date,
            })
            if len(results) >= k:
                break
        return results

    def get_rag_context(self, query: str, k: int = 5) -> tuple[str, list[str]]:
        """Return (context_text, source_titles) for RAG prompt injection."""
        if not self._built or not self._index:
            return "", []

        model = self._get_model()
        q_emb = model.encode([query], show_progress_bar=False).astype("float32")
        distances, indices = self._index.search(q_emb, min(k * 3, len(self.chunks)))

        seen: set[str] = set()
        parts: list[str] = []
        titles: list[str] = []
        for idx in indices[0]:
            if idx < 0 or idx >= len(self.chunks):
                continue
            chunk = self.chunks[idx]
            if chunk.note_id in seen:
                continue
            seen.add(chunk.note_id)
            parts.append(f"**Note: {chunk.title}** (topic: {chunk.topic})\n{chunk.chunk_text}")
            titles.append(chunk.title)
            if len(parts) >= k:
                break

        return "\n\n---\n\n".join(parts), titles

    def list_notes(self) -> list[dict]:
        """Return all unique notes as metadata dicts."""
        seen: set[str] = set()
        notes: list[dict] = []
        for chunk in self.chunks:
            if chunk.note_id in seen:
                continue
            seen.add(chunk.note_id)
            notes.append({
                "note_id": chunk.note_id,
                "title": chunk.title,
                "path": chunk.path,
                "preview": chunk.chunk_text[:120].strip(),
                "tags": chunk.tags,
                "topic": chunk.topic,
                "date": chunk.date,
            })
        # Sort by date desc
        notes.sort(key=lambda n: n.get("date", ""), reverse=True)
        return notes

    def get_note_content(self, note_id: str) -> dict | None:
        """Return full content of a note by its relative path id."""
        for chunk in self.chunks:
            if chunk.note_id == note_id:
                return {
                    "note_id": note_id,
                    "title": chunk.title,
                    "path": chunk.path,
                    "content": chunk.full_content,
                    "tags": chunk.tags,
                    "topic": chunk.topic,
                    "date": chunk.date,
                }
        # Try reading directly from disk
        target = self.notes_dir / note_id
        if target.exists():
            text = target.read_text(encoding="utf-8", errors="ignore")
            meta, content = self._parse_frontmatter(text)
            return {
                "note_id": note_id,
                "title": str(meta.get("title", target.stem)).strip('"'),
                "path": str(target),
                "content": content,
                "tags": self._parse_tags(meta.get("tags", [])),
                "topic": str(meta.get("topic", "")).strip('"'),
                "date": str(meta.get("date", "")).strip('"'),
            }
        return None

    # ── Helpers ───────────────────────────────────────────────────────────── #

    def _parse_frontmatter(self, text: str) -> tuple[dict, str]:
        if not text.startswith("---"):
            return {}, text
        end = text.find("\n---", 3)
        if end == -1:
            return {}, text
        fm_text = text[3:end]
        content = text[end + 4:].strip()
        meta: dict = {}
        for line in fm_text.split("\n"):
            if ":" in line:
                k, _, v = line.partition(":")
                meta[k.strip()] = v.strip()
        return meta, content

    def _parse_tags(self, raw) -> list[str]:
        if isinstance(raw, list):
            return [str(t).strip().lstrip("#") for t in raw]
        if isinstance(raw, str):
            # e.g. "[#python, #learning]"
            return [t.strip().lstrip("#[]") for t in re.split(r"[,\s]+", raw) if t.strip()]
        return []

    def _chunk(self, text: str, size: int = 600, overlap: int = 100) -> list[str]:
        paras = [p.strip() for p in text.split("\n\n") if p.strip()]
        chunks: list[str] = []
        current = ""
        for para in paras:
            if len(current) + len(para) + 2 > size and current:
                chunks.append(current.strip())
                # carry overlap
                words = current.split()
                current = " ".join(words[-overlap // 5:]) + "\n\n" + para
            else:
                current = (current + "\n\n" + para).strip()
        if current.strip():
            chunks.append(current.strip())
        return chunks or [text[:size]]


# ── Singleton ─────────────────────────────────────────────────────────────── #
_index: NotesIndex | None = None


def get_notes_index() -> NotesIndex:
    global _index
    if _index is None:
        _index = NotesIndex()
    return _index
