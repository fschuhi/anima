# Project Goals & Roadmap

(Note: "I" in the following paragraphs refer to the user, "you" to you as the AI model.)

**Charter:** This file answers: where is the project going, in what order, and what happens next. It holds the strategic vision, the phased roadmap, and goals that need a strategy discussion before they are actionable. The _Current Session Pointer_ below is the single canonical "where we are / what's next" -- keep it to a few lines, update it, don't grow it; `FIRST_PROMPT.md` sends the reader here first. Concrete, startable work lives in `TODO.md`; the resolved-work record lives in `HISTORY.md` (on the heap, out of the per-session dump); architecture, contract, and settled decisions live in `README.md`.

---

## 📍 Current Session Pointer

**Where we are:** Phase 1 is complete. The architecture review of the recently added navigation, search, bookmark, and PDF-opening action paths is complete. The review confirmed the existing load path as the right seam for active-document replacement, identified a small shared far-jump execution seam needed before JumpStack, and left broader search, command-controller, and multi-document abstractions parked as premature. Phase 2 has begun; active-document hot replacement is working.

**What's next (in order):**

1. Add per-PDF last-page persistence and restoration.
2. Reassess lower-priority opening entry points such as reader-window drag-and-drop and `Cmd+O`.
3. Return to navigation improvements, toolchain integration, and the remaining backlog according to visible value.

Everything else sits in `TODO.md` until it earns a place here.

---

## 🎯 Strategic vision

Anima exists to serve one workflow: reading academic papers and wisdom tradition texts, highlighting passages, and adding comments. It replaces PDF-XChange Viewer in a macOS-native toolchain that flows from PDF -> highlights -> Obsidian notes. The design conviction: Anima is a scratchpad for engaged reading, not a document editor -- complexity belongs downstream in the toolchain, not in the reader.

---

## Phase 1 -- Pleasant to live in (complete)

~~Phase 1 made Anima viable as the daily reader rather than merely a functional prototype. It established civilized window and split-view behavior, page-aware captions, forward-only PDF and comment search, goto-page navigation, durable bookmark persistence and creation, and the usable `Cmd+J` JumpStation navigation/deletion round trip. The known coordinate, cross-page selection, bookmark persistence, and comment-clear regression contracts are now pinned by the current Swift and Python suites.Later refinements -- including JumpStation prefix input/filtering and a possible status bar -- return to the general backlog for explicit prioritization rather than extending Phase 1 by default.~~

---

## Phase 2 -- Opening PDFs

Phase 2 makes switching between PDFs reliable before adding more ways to initiate an open request. Anima's near-term model remains one active PDF per process: fast document replacement, restored reading position, and later restored JumpStack state provide the practical proxy for keeping several PDFs open.

1. ~~**Safe active-document replacement.** Clicking another PDF in Finder, using "Open With", or dropping a PDF onto the Dock icon while Anima is running should replace the displayed PDF rather than merely focus the existing window. Replacement must retire document-specific search, emphasis, selection, and mutation-target state. Failed hot opens preserve the current PDF and report the failure.~~ Completed on 2026-07-17.
2. **Last-page restoration.** Persist the most recently displayed page in private PDF metadata and restore it when that PDF is reopened. This is the highest-priority enhancement after safe replacement because it makes rapid external switching useful in practice.
3. **Additional opening entry points.** Add reader-window drag-and-drop and `Cmd+O` only after replacement and restoration are reliable; neither is currently as valuable as preserving reading position.
4. **Same-process multiple documents remain parked.** Multiple windows or tabs would require first-class per-document reader sessions with independent PDF views, sidebars, bookmarks, search, emphasis, and modal ownership. Do not build that infrastructure unless replacement-based switching proves insufficient. Separate simultaneous instances remain available through `open -n`.

---

## Phase 3 -- Toolchain Integration

Retire the Windows/Parallels PDF route; Anima becomes the target of the `pdf://` flow.

- **`pdf://` URL handler** -- register the scheme, resolve `pdf://HASH?page=N` via `pdf_registry.build_pdf_index`, open at page. See `TODO.md` -> Toolchain Integration.
- **`pdf-annot` compatibility** -- verify the full extract pipeline and Obsidian bibnote generation against Anima-written annotations.
