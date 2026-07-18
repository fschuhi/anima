# Project Goals & Roadmap

(Note: "I" in the following paragraphs refer to the user, "you" to you as the AI model.)

**Charter:** This file answers: where is the project going, in what order, and what happens next. It holds the strategic vision, the phased roadmap, and goals that need a strategy discussion before they are actionable. The _Current Session Pointer_ below is the single canonical "where we are / what's next" -- keep it to a few lines, update it, don't grow it; `FIRST_PROMPT.md` sends the reader here first. Concrete, startable work lives in `TODO.md`; the resolved-work record lives in `HISTORY.md` (on the heap, out of the per-session dump); architecture, contract, and settled decisions live in `README.md`.

---

## 📍 Current Session Pointer

**Where we are:** Phases 1 and 2 are complete. Phase 3 == `TARGET_ARCHITECTURE.md` Phase B is underway: step 4 landed 2026-07-18 -- Anima claims the `pdf` URL scheme, `application(_:open:)` separates file URLs from scheme URLs, `pdfAnnotationsRoot` sits beside `projectRoot`, and the legacy `PDFHandler.app` applet is decommissioned, so Anima is now the sole claimant of `pdf://`. Accepted from Terminal and from a real Obsidian link. The applet is in the Trash but the Trash is deliberately not yet emptied (Phase C step 11); empty it once the pipeline is genuinely in daily use.

**What's next:** Phase B step 5 -- `PdfAnnotationsBridge`, mirroring `FitzBridge`'s subprocess pattern, invoking the frozen resolver CLI (§3) through the pdf-annotations venv with `pdfAnnotationsRoot` as working directory. The contract is frozen: Anima consumes it as a subprocess (§6.2) and must not reach back into or modify it. Step 6 (opening flow) and step 7 (alert plumbing) follow, and the temporary probe alert in `AppDelegate` is what step 6 replaces.

**Open question, decide before step 6:** §6.4 requires the `pdf://` far jump to route through the shared far-jump seam, which does not exist yet -- it is the `TODO.md` Navigation item "Centralize far-jump execution before implementing JumpStack". Either build the seam first (honors §6.4, unblocks JumpStack, but inserts a five-call-site refactoring mid-Phase-B), or let step 6 call `go(to:)` directly and add the seam afterwards (links work sooner, costs a second pass through the opening flow, and defers `Cmd+R`-undo of an Obsidian jump). Step 5 is independent of this either way.

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

- **`pdf://` URL handler** -- register the scheme, resolve `pdf://HASH?page=N` via `pdf_registry.build_pdf_index`, open at page. See `TARGET_ARCHITECTURE.md`.
- **`pdf-annot` compatibility** -- verify the full extract pipeline and Obsidian bibnote generation against Anima-written annotations.
