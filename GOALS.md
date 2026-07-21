# Project Goals & Roadmap

(Note: "I" in the following paragraphs refer to the user, "you" to you as the AI model.)

## Charter

This file answers: where is the project going, in what order, and what happens next. It holds the strategic vision, the phased roadmap, and goals that need a strategy discussion before they are actionable. The _Current Session Pointer_ below is the single canonical "where we are / what's next" -- keep it to a few lines, update it, don't grow it; `FIRST_PROMPT.md` sends the reader here first. Concrete, startable work lives in `TODO.md`; the resolved-work record lives in `HISTORY.md` (on the heap, out of the per-session dump); architecture, contract, and settled decisions live in `README.md`.

---

## 📍 Current Session Pointer

**Where we are:** Phase D (`TARGET_ARCHITECTURE.md` cleanup) complete. `windows_server/README.md` banner added in pdf-annotations; `PDFHandler.app` decommissioned and trashed; Anima re-registered as sole `pdf://` handler via Finder launch; acceptance 8(a)-(c) passed. `TARGET_ARCHITECTURE.md` moved to `docs/` and marked complete. The macOS-native toolchain -- Anima + `pdf_annot.resolve` + Obsidian -- is now fully established.

**What's next:** Here: Review `TODO.md` backlog and prioritize. Regarding `pdf-annotations`, use Anima for PDF work.

---

## 🎯 Strategic vision

Anima exists to serve one workflow: reading academic papers and wisdom tradition texts, highlighting passages, and adding comments. It replaces PDF-XChange Viewer in a macOS-native toolchain that flows from PDF -> highlights -> Obsidian notes. The design conviction: Anima is a scratchpad for engaged reading, not a document editor -- complexity belongs downstream in the toolchain, not in the reader.
