# anima -- Goals and Roadmap

(Note: "I" in the following paragraphs refer to the user, "you" to you as the AI model.)

**Charter:** This file answers: where is the project going, in what order, and what happens next. It holds the strategic vision, the phased roadmap, and goals that need a strategy discussion before they are actionable. The _Current Session Pointer_ below is the single canonical "where we are / what's next" -- keep it to a few lines, update it, don't grow it; `FIRST_PROMPT.md` sends the reader here first. Concrete, startable work lives in `TODO.md`; the resolved-work record lives in `HISTORY.md` or `CHANGELOG.md`(on the heap, out of the per-session dump); architecture, contract, and settled decisions live in `README.md`.

---

## 📍 Current Session Pointer

**Where we are:** `docs/OPEN_DIALOG_DESIGN.md` implemented and working end-to-end (2026-07-28) -- `Cmd+O` opens the collection launcher; all new unit tests pass. Two bugs found and fixed along the way are recorded in `HISTORY.md`.

**What's next:** No approved design pending. Candidates for the next strategy discussion are in `TODO.md`'s Opening PDFs section: a backchannel opening the current PDF's Obsidian bibnote, plus `OPEN_DIALOG_DESIGN.md`'s deferred items (multiple search paths, settings UI).

---

## 🎯 Strategic vision

Anima exists to serve one workflow: reading academic papers and wisdom tradition texts, highlighting passages, and adding comments. It replaces PDF-XChange Viewer in a macOS-native toolchain that flows from PDF -> highlights -> Obsidian notes. The design conviction: Anima is a scratchpad for engaged reading, not a document editor -- complexity belongs downstream in the toolchain, not in the reader.
