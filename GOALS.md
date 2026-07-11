# Project Goals & Roadmap

(Note: "I" in the following paragraphs refer to the user, "you" to you as the AI model.)

**Charter:** This file answers: where is the project going, in what order, and what happens next. It holds the strategic vision, the phased roadmap, and goals that need a strategy discussion before they are actionable. The _Current Session Pointer_ below is the single canonical "where we are / what's next" -- keep it to a few lines, update it, don't grow it; `FIRST_PROMPT.md` sends the reader here first. Concrete, startable work lives in `TODO.md`; the resolved-work record lives in `HISTORY.md` (on the heap, out of the per-session dump); architecture, contract, and settled decisions live in `README.md`.

---

## 📍 Current Session Pointer

**Where we are:** Documentation and direction overhauled (2026-07-11). Full no-code architecture review: dual-write / coordinate / popup-suppression design confirmed sound; findings triaged into `TODO.md` and the deferred goals below. `TODO.md` restructured (charter, theme sections, UX priorities from first sustained daily-use feedback), `CHANGELOG.md` renamed to `HISTORY.md`, `GOALS.md` established, `Makefile` cleaned. No code changed; 16 tests green (11 Python + 5 Swift).

**What's next (in order):**

1. Close the Swift test gaps -- coordinate y-flip, QuadPoints geometry, FitzBridge round-trip, cross-page pin. See `TODO.md` -> Testing / Swift.
2. Close the Python test gap -- the edit-comment clear-ordering pin. See `TODO.md` -> Testing / Python.
3. The UX priority list, in its listed order (resize -> window persistence -> colors -> status bar -> page indicator -> goto page -> jump stack). See `TODO.md` -> UX Priorities.

Everything else sits in `TODO.md` until it earns a place here.

---

## 🎯 Strategic vision

Anima exists to serve one workflow: reading academic papers and wisdom tradition texts, highlighting passages, and adding comments. It replaces PDF-XChange Viewer in a macOS-native toolchain that flows from PDF -> highlights -> Obsidian notes. The design conviction: Anima is a scratchpad for engaged reading, not a document editor -- complexity belongs downstream in the toolchain, not in the reader. The current gap is not capability but *habitability*: the viewer works, but it is not yet pleasant enough to pull daily reading away from the Parallels bridge. Phase 1 closes that gap; Phase 2 retires the bridge.

---

## Phase 1 -- Pleasant to live in (current)

Make Anima the place where reading actually happens. Two strands, in order:

- **Test-first hardening.** Close the known Swift and Python test gaps before touching UI code, so the coordinate and comment-lifecycle contracts are pinned when the UI work starts. See `TODO.md` -> Testing.
- **Reading ergonomics.** The seven UX priorities: civilized window behavior (resize, frame persistence), faithful rendering (the saturation investigation), and page awareness (status bar -> page indicator -> goto page -> jump stack). See `TODO.md` -> UX Priorities.

---

## Phase 2 -- Toolchain Integration (next)

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
