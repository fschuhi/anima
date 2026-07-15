# Project Goals & Roadmap

(Note: "I" in the following paragraphs refer to the user, "you" to you as the AI model.)

**Charter:** This file answers: where is the project going, in what order, and what happens next. It holds the strategic vision, the phased roadmap, and goals that need a strategy discussion before they are actionable. The _Current Session Pointer_ below is the single canonical "where we are / what's next" -- keep it to a few lines, update it, don't grow it; `FIRST_PROMPT.md` sends the reader here first. Concrete, startable work lives in `TODO.md`; the resolved-work record lives in `HISTORY.md` (on the heap, out of the per-session dump); architecture, contract, and settled decisions live in `README.md`.

---

## 📍 Current Session Pointer

**Where we are:** Phase 1 is complete. Anima now has durable window behavior, core reading/navigation ergonomics, hardened annotation and bookmark persistence seams, bookmark creation, and the usable `Cmd+J` JumpStation round trip for navigation and deletion. Reader-facing page numbers remain 1-based while bookmark storage remains fitz-native 0-based.

**What's next (in order):**

1. Extend JumpStation with its keyboard-first prefix-input/filtering behavior when that enhancement wins prioritization.
2. Prioritize the backlog across UX refinements, tests, refactorings, reader chrome, and Phase 2 toolchain integration before choosing the next implementation slice.

Tabs remain deferred; separate `open -n` instances are the accepted multi-document workflow for now.

Everything else sits in `TODO.md` until it earns a place here.

---

## 🎯 Strategic vision

Anima exists to serve one workflow: reading academic papers and wisdom tradition texts, highlighting passages, and adding comments. It replaces PDF-XChange Viewer in a macOS-native toolchain that flows from PDF -> highlights -> Obsidian notes. The design conviction: Anima is a scratchpad for engaged reading, not a document editor -- complexity belongs downstream in the toolchain, not in the reader. The current gap is not capability but *habitability*: the viewer works, but it is not yet pleasant enough to pull daily reading away from the Parallels bridge. Phase 1 closes that gap; Phase 2 retires the bridge.

---

## Phase 1 -- Pleasant to live in (complete)

Phase 1 made Anima viable as the daily reader rather than merely a functional prototype. It established civilized window and split-view behavior, page-aware captions, forward-only PDF and comment search, goto-page navigation, durable bookmark persistence and creation, and the usable `Cmd+J` JumpStation navigation/deletion round trip. The known coordinate, cross-page selection, bookmark persistence, and comment-clear regression contracts are now pinned by the current Swift and Python suites.

Later refinements -- including JumpStation prefix input/filtering and a possible status bar -- return to the general backlog for explicit prioritization rather than extending Phase 1 by default.

---

## Phase 2 -- Toolchain Integration (when prioritized)

Retire the Windows/Parallels PDF route; Anima becomes the target of the `pdf://` flow.

- **`pdf://` URL handler** -- register the scheme, resolve `pdf://HASH?page=N` via `pdf_registry.build_pdf_index`, open at page. See `TODO.md` -> Toolchain Integration.
- **`pdf-annot` compatibility** -- verify the full extract pipeline and Obsidian bibnote generation against Anima-written annotations.

---

## Focus sessions -- deferred by design

Goals that need their own dedicated discussion-first session; none is scheduled, each is deliberately parked until its trigger fires.

- **FitzBridge redesign.** The subprocess seam has a latent pipe deadlock (`waitUntilExit` before reading pipes), blocks the main thread per operation, and pays interpreter-startup latency on every mutation (today: barely perceptible hesitation, not gummy). Parked per Scope Skepticism -- no observed problem yet. Trigger: latency becomes noticeable, output grows past pipe buffers, or async/batch needs arise. Scope of the session: async dispatch vs. long-running helper process vs. batching -- trade-offs first, then implement.
- **Comment set/clear lifecycle.** `cmd_edit_comment`'s ordering is fragile: fitz's `set_info` silently ignores empty strings, the xref-level `/Contents` clear must stay the last mutation before save, and a second `annot.update()` (popup creation path) runs after it. The clear-ordering pin test (Phase 1) is the guard; this session redesigns the flow so correctness is structural rather than incidental.

---

## Someday / open horizons

Backlog themes live in `TODO.md` -> Backlog. The ones with strategic weight, for the record: tabs (multi-document reading changes the single-window model -- `AnnotationManager` is already tabs-safe by design), and multiple highlight colors (changes the annotation contract with `pdf-annot`).
