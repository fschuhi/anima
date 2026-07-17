# TODO

(Note: "I" in the following paragraphs refer to the user, "you" to you as the AI model.)

## Charter
- Forward-looking only -- concrete, startable work: tasks specified well enough that next-session-me can begin within ten minutes, plus investigation items, test specs, and scratchpad ideas awaiting promotion or deletion.
- Items are unordered within their theme sections; open questions are marked _Needs investigation_ in the bullet.
- When an item is completed, record its durable outcome in `HISTORY.md` during the same session while the evidence and rationale are fresh, then strike it through in `TODO.md` with a concise handover note.
- Retain struck-through items through the next session because `TODO.md` is included in the standard filesdump while `HISTORY.md` normally is not; at the end of that next session, remove the already-archived items from `TODO.md`. Strategic direction, ordering, and milestones live in `GOALS.md` -- anything that needs a strategy discussion before it is actionable goes there.
- Architecture, contract, and settled decisions live in `README.md`.

---

## Refactoring

- ~~**Reduce size of `filesdump.txt`.** Prefer selective `manifest.lst` curation and test-file organization over splitting production code or deleting useful source comments solely to reduce prompt size. First candidate: split `AnimaTests.swift` so the self-documenting cross-boundary round trips remain in the standard filesdump while sidebar extraction mechanics and annotation geometry tests remain in the project but are normally excluded. Measure the result with `make filesdump`; do not make production ownership follow filesdump boundaries.~~
  *Completed: split `AnimaTests.swift` into integration, extraction-mechanics, and geometry files; ~6,000 tokens saved; verified with `Cmd+U` and `make filesdump`.*

- ~~**Split `AnimaTests.swift` by test concern.** Keep the self-documenting behavioral and cross-boundary round trips in `AnimaTests.swift`; move sidebar extraction mechanics to `SidebarExtractorTests.swift` and pure coordinate/QuadPoints mechanics to `AnnotationGeometryTests.swift`. Keep all current test names, assertions, and fixture contracts unchanged. Give `testInMemoryAnnotationRoundTrip` a local PDF-only fixture loader rather than coupling it to the sidebar golden-JSON helper. Add both files to the `AnimaTests` target, normally exclude them from `filesdump.txt`, run the complete Swift suite with `Cmd+U`, then measure the reduction with `make filesdump`.~~
  *Completed: integration tests remain in `AnimaTests.swift`; extraction mechanics moved to `SidebarExtractorTests.swift`; geometry tests moved to `AnnotationGeometryTests.swift`; `manifest.lst` updated; all tests pass.*

- **Centralize far-jump execution before implementing JumpStack.** `Cmd+G`, PDF find/F3, comment find/F3, and JumpStation currently resolve their targets in the correct local owners but perform the final `PDFView.go(to:)` transition through separate paths. Keep target discovery where it is, but route the final non-local transition through one small shared seam so JumpStack can consistently record the current position before every far jump. Ordinary scrolling and page changes remain outside this seam. Do not introduce a `NavigationManager` unless the seam later gains enough independent responsibility to justify one.

- **Extract `PopupController`.** Consolidate all popup suppression logic (scrubbing on load, X-Ray toggle, conditional popup handling in edit/create) into one type. Currently spread across AnimaPDFView and MainViewController. Review 2026-07-11 confirmed: `scrubCommentsForPopupSuppression` and `applyXRayModeToDocument`'s OFF-branch are near-duplicates.

- **Extract `EmphasisManager` from `MainViewController`.** The emphasis state machine (apply/clear/preserve-through-rebuild, ~100 lines) becomes its own type. MainViewController focuses on layout and scroll physics. While extracting: consolidate the triplicated UUID lookup (/NM-then-userName fallback exists in AnnotationManager.annotationUUID, SidebarExtractor.getUUID, MainViewController.findAnnotation) into one shared helper.

- **Delete `reloadDocument()` dead code in AnimaPDFView.** Nothing calls it, and it predates the sidebar: if it were ever called, pageSidebarViews would desync from the new document. Delete (git remembers); a future reload path must go through `loadPDF`.

- **FitzBridge redesign.** The subprocess seam has a latent pipe deadlock (`waitUntilExit` before reading pipes), blocks the main thread per operation, and pays interpreter-startup latency on every mutation (today: barely perceptible hesitation, not gummy). Parked per Scope Skepticism -- no observed problem yet. Trigger: latency becomes noticeable, output grows past pipe buffers, or async/batch needs arise. Scope of the session: async dispatch vs. long-running helper process vs. batching -- trade-offs first, then implement.

- **Comment set/clear lifecycle.** `cmd_edit_comment`'s ordering is fragile: fitz's `set_info` silently ignores empty strings, the xref-level `/Contents` clear must stay the last mutation before save, and a second `annot.update()` (popup creation path) runs after it.

- **Revisit the `SidebarUpdateDelegate` name if its coordination role grows further.** Added comment search and emphasis behavior have outgrown the original sidebar-update name: the protocol now coordinates rebuilds, highlight clicks, comment-search state, and annotation-emphasis state. Parked for now because it still has one consumer and one implementation; renaming or splitting it today would add ceremony without changing ownership.

- **`MainMenu.xib` housekeeping.** Review and clean up `MainMenu.xib` (remove unused Font/Format/Text menus).

---

## Opening PDFs

- **Safely replace the active PDF after a hot open request.** Route Finder, "Open With", and Dock-icon open requests through the existing `AppDelegate.loadDocument(url:)` seam; when several URLs arrive, use only the first. Decline the request while an application-modal panel or alert is active. Before exposing a successfully loaded replacement, retire the outgoing document's PDF-text search, comment search, annotation/card emphasis, text selection, and Delete-key target; reload `BookmarkManager` for the incoming file and keep X-Ray/highlight-mode state internally consistent, using whichever reset or survival policy is simplest. If parsing or installation fails, retain the current document, log the failure, and show an alert rather than terminating the app. A bookmark-read failure remains nonfatal and leaves the incoming document with an empty bookmark list. Add tests or a documented manual verification matrix for replacement-state clearing and failure preservation.

- **Persist and restore the last displayed page for each PDF.** Reuse the current-page information already observed through `.PDFViewPageChanged` for the window caption; do not add a second page-movement observer. Keep the latest 0-based page index in memory, persist the outgoing PDF's value in private PDF metadata during document replacement and application termination, and restore it after the PDF and sidebar are installed. Reader-facing page numbers remain 1-based. If persistence fails during replacement, log the failure and continue opening the requested PDF. Define safe behavior for a stale stored index when the PDF's page count has changed. This is the highest-priority Phase 2 enhancement after safe hot replacement and comes before window drag-and-drop or `Cmd+O`.

- **Open a PDF by dropping it onto the reader window.** Lower priority than hot replacement and last-page restoration. Dock-icon drops already arrive through `application(_:open:)`; this item concerns registering the reader window as a drag destination.

- **Open a PDF with `Cmd+O`.** Lower priority than hot replacement and last-page restoration. Inspect `MainMenu.xib` before designing the action or menu wiring.

---

## Navigation

- **JumpStack.** A far jump is the target of (a) go to page, (b) find in PDF, (c) find in comments, (d) `F3` in either search mode, or (e) jump to bookmark. Before executing a far jump, push the current page onto a bounded stack, provisionally retaining no more than five targets; `Cmd+R` pops the previous position and returns there. Persist the stack in private PDF metadata and restore it when reopening that PDF, so replacement-based document switching retains recent navigation context. Record only defined far jumps, not ordinary scrolling or page changes. Implement only after the Refactoring item "Centralize far-jump execution before implementing JumpStack"; design and test duplicate/consecutive-page behavior before wiring it into the reader.

- **Extend JumpStation with prefix input/filtering.** Add the display-only prefix panel and VBA-inspired keyboard behavior: case-insensitive prefix matching against bookmark names, repeated Backspace, selection independent from prefix text, and two-stage Escape (clear prefix, then close). Design and test the non-visual state machine before wiring it into `JumpStationPanel`.

## Cosmetic / UX Improvements

- **Sidebar Card Polish.** Tweak padding, reduce title font to ~9pt, adjust comment font to ~11pt, experiment with custom grayscale background colors for Dark Mode contrast.
- **Emphasis color tuning.** Replace light yellow (#FFFFE0) at 0.7 opacity with dark pink.
- **CommentInputPanel geometry persistence.** Use UserDefaults to remember panel position/size across launches (currently session-only via static var). Works across `open -n` instances too. Same mechanism family as main-window frame autosave.
- **Consider a status bar.** Thin bar below the PDF view. Possible contents: mode indicators (persistent highlight, X-Ray), page display, PDF size, highlight count, or most recent bookmark target. Reassess alongside other backlog work; if added, the window title should become the filename permanently.

---

## Toolchain Integration

### pdf:// URL handler (macOS native)

- We currently have a custom `pdf://` URL scheme registered, in the `pdf-annotation` project. The `pdf://` URLs, usually located on Obsidian pages where we collect highlights and comments from PDFs, use hashes instead of full filenames. Clicking on such a link goes to an Applescript, which connects to a server running on Windows under Parallels, which then opens the PDF in the _formerly preferred_ PDF-Xchange-Viewer.
- Because Anima is the new preferred viewer, we can now move that server to macOS, and use it directly to open PDFs, without the need for a Parallels bridge.

### macOS Integration

- Proper .app bundle with icon.
- Make target to regenerate AppIcon.appiconset from a source PNG (sips + iconutil) -- enables icon experiments without touching Xcode. Caveat: Launch Services may need a nudge before Finder shows changes.
