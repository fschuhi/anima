# Project Goals & Roadmap

(Note: "I" in the following paragraphs refer to the user, "you" to you as the AI model.)

## Charter

This file answers: where is the project going, in what order, and what happens next. It holds the strategic vision, the phased roadmap, and goals that need a strategy discussion before they are actionable. The _Current Session Pointer_ below is the single canonical "where we are / what's next" -- keep it to a few lines, update it, don't grow it; `FIRST_PROMPT.md` sends the reader here first. Concrete, startable work lives in `TODO.md`; the resolved-work record lives in `HISTORY.md` (on the heap, out of the per-session dump); architecture, contract, and settled decisions live in `README.md`.

---

## 📍 Current Session Pointer

**Where we are:** Phases 1 and 2 are complete. Phase 3's Phase B opening flow completed on 2026-07-18. `TARGET_ARCHITECTURE.md` Phase C is now complete: the shared far-jump seam (step 9) and the JumpStack (step 10) both landed on 2026-07-19, with acceptance per `docs/JUMPSTACK_DESIGN.md` §7 verified in the reader. `Cmd+E` and `Cmd+R` walk the far-jump history; the contract lives in `README.md` §Far-Jump History. One gap surfaced and was closed along the way: reopening the file already displayed is now declined rather than reloaded.

**What's next:** `TARGET_ARCHITECTURE.md` Phase D -- step 12, the Windows server README note per its §7 -- then step 13, decommissioning `PDFHandler.app`, and step 14, re-running acceptance 8(a)-(c) afterwards, since Launch Services can misroute schemes after a handler change. Steps 13 and 14 belong together in one sitting.

---

## 🎯 Strategic vision

Anima exists to serve one workflow: reading academic papers and wisdom tradition texts, highlighting passages, and adding comments. It replaces PDF-XChange Viewer in a macOS-native toolchain that flows from PDF -> highlights -> Obsidian notes. The design conviction: Anima is a scratchpad for engaged reading, not a document editor -- complexity belongs downstream in the toolchain, not in the reader.
