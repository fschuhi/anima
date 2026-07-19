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

---

## Phase 1 -- Pleasant to live in (complete)

~~Phase 1 made Anima viable as the daily reader rather than merely a functional prototype. It established civilized window and split-view behavior, page-aware captions, forward-only PDF and comment search, goto-page navigation, durable bookmark persistence and creation, and the usable `Cmd+J` JumpStation navigation/deletion round trip. The known coordinate, cross-page selection, bookmark persistence, and comment-clear regression contracts are now pinned by the current Swift and Python suites.Later refinements -- including JumpStation prefix input/filtering and a possible status bar -- return to the general backlog for explicit prioritization rather than extending Phase 1 by default.~~

---

## Phase 2 -- Opening PDFs (complete)

~~Phase 2 makes switching between PDFs reliable before adding more ways to initiate an open request. Anima's near-term model remains one active PDF per process: fast document replacement, restored reading position, and later restored JumpStack state provide the practical proxy for keeping several PDFs open.~~ Safe active-document replacement complete on 2026-07-17. Last-page restoration complete on 2026-07-17.

---

## Phase 3 -- Toolchain Integration

Retire the Windows/Parallels PDF route; Anima becomes the target of the `pdf://` flow.

Scope: `TARGET_ARCHITECTURE.md` Phases A, B, and D. Its Phase C -- the far-jump seam and the JumpStack -- is Phase 4 here.

- **`pdf://` URL handler** -- register the scheme, resolve `pdf://HASH?page=N` via `pdf_registry.build_pdf_index`, open at page. See `TARGET_ARCHITECTURE.md`.
- **`pdf-annot` compatibility** -- verify the full extract pipeline and Obsidian bibnote generation against Anima-written annotations.

---

## Phase 4 -- Navigation Depth

Centralize far-jump execution, then build the JumpStack on top of it. Specced in `TARGET_ARCHITECTURE.md` §6.4 and §6.5, with the work plan and acceptance in its Phase C (steps 9-11); deliberately not restated here.

Its own phase rather than part of Phase 3 because the seam serves the five far-jump sources that predate `pdf://` -- goto-page, both finds, `F3`, bookmark jumps -- and the JumpStack was a Navigation backlog item before this architecture existed. `pdf://` is the sixth consumer, not the reason. `TODO.md`'s remaining Navigation item, JumpStation prefix input/filtering, is this phase's natural neighbour.
