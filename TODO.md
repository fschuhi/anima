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

- **Extract `PopupController`.** Consolidate all popup suppression logic (scrubbing on load, X-Ray toggle, conditional popup handling in edit/create) into one type. Currently spread across AnimaPDFView and MainViewController. Review 2026-07-11 confirmed: `scrubCommentsForPopupSuppression` and `applyXRayModeToDocument`'s OFF-branch are near-duplicates.

- **Extract `EmphasisManager` from `MainViewController`.** The emphasis state machine (apply/clear/preserve-through-rebuild, ~100 lines) becomes its own type. MainViewController focuses on layout and scroll physics. While extracting: consolidate the triplicated UUID lookup (/NM-then-userName fallback exists in AnnotationManager.annotationUUID, SidebarExtractor.getUUID, MainViewController.findAnnotation) into one shared helper.

- **Delete `reloadDocument()` dead code in AnimaPDFView.** Nothing calls it, and it predates the sidebar: if it were ever called, pageSidebarViews would desync from the new document. Delete (git remembers); a future reload path must go through `loadPDF`.

- **FitzBridge redesign.** The subprocess seam has a latent pipe deadlock (`waitUntilExit` before reading pipes), blocks the main thread per operation, and pays interpreter-startup latency on every mutation (today: barely perceptible hesitation, not gummy). Parked per Scope Skepticism -- no observed problem yet. Trigger: latency becomes noticeable, output grows past pipe buffers, or async/batch needs arise. Scope of the session: async dispatch vs. long-running helper process vs. batching -- trade-offs first, then implement.

- **`FitzBridge` error surfacing.** `FitzBridge` reports every failure through `Swift.print` only. A helper failure during a highlight, comment edit, or bookmark write is therefore invisible in the reader, which still shows the in-memory half of the dual write as having succeeded -- screen and disk diverge silently until the next launch. Decided 2026-07-18 to leave as is: `FitzBridge` calls Anima's own helper in Anima's own venv, so its failures are developer failures, unlike `PdfAnnotationsBridge`, whose failures (unknown hash, duplicate `pdf_id`) are everyday library-hygiene outcomes and reach the user through an alert. The asymmetry is a decision, not an oversight. Trigger for revisiting: a helper failure actually occurs in daily use. Scope of that session: which failures deserve an alert versus a quieter indicator, and whether the in-memory half should be rolled back when the write fails.

- **Comment set/clear lifecycle.** `cmd_edit_comment`'s ordering is fragile: fitz's `set_info` silently ignores empty strings, the xref-level `/Contents` clear must stay the last mutation before save, and a second `annot.update()` (popup creation path) runs after it.

- **Revisit the `SidebarUpdateDelegate` name if its coordination role grows further.** Added comment search and emphasis behavior have outgrown the original sidebar-update name: the protocol now coordinates rebuilds, highlight clicks, comment-search state, and annotation-emphasis state. Parked for now because it still has one consumer and one implementation; renaming or splitting it today would add ceremony without changing ownership.

- **`MainMenu.xib` housekeeping.** Review and clean up `MainMenu.xib` (remove unused Font/Format/Text menus).

---

## Opening PDFs

- **Open a PDF by dropping it onto the reader window.** Dock-icon drops already arrive through `application(_:open:)`; this item concerns registering the reader window as a drag destination.

- **Open a PDF with `Cmd+O`.** Inspect `MainMenu.xib` before designing the action or menu wiring.

- **Same-process multiple documents remain parked.** Multiple windows or tabs would require first-class per-document reader sessions with independent PDF views, sidebars, bookmarks, search, emphasis, and modal ownership. Do not build that infrastructure unless replacement-based switching proves insufficient. Separate simultaneous instances remain available through `open -n`.

---

## Navigation

- **Centralize far-jump execution before implementing JumpStack.** `Cmd+G`, PDF find/F3, comment find/F3, and JumpStation currently resolve their targets in the correct local owners but perform the final `PDFView.go(to:)` transition through separate paths. Keep target discovery where it is, but route the final non-local transition through one small shared seam so JumpStack can consistently record the current position before every far jump. Ordinary scrolling and page changes remain outside this seam. Do not introduce a `NavigationManager` unless the seam later gains enough independent responsibility to justify one. **NOTE** that this is `TARGET_ARCHITECTURE.md` Phase C step 9, specced in its §6.4. It is deliberately no longer a prerequisite for the `pdf://` opening flow: §6.3 step 4 changes the page through a direct `go(to:)` call marked in the code as the future seam call site, so this item reroutes six sources rather than five. §6.3 step 5 stays outside the seam permanently -- a jump performed while installing a new document has no pre-jump position to record, since the stack is cleared on document change.

- **JumpStack.** A far jump is the target of (a) go to page, (b) find in PDF, (c) find in comments, (d) `F3` in either search mode, or (e) jump to bookmark. Before executing a far jump, push the current page onto a bounded stack, provisionally retaining no more than five targets; `Cmd+R` pops the previous position and returns there. In-memory only, cleared on document change (`TARGET_ARCHITECTURE.md` §6.5, which supersedes the earlier plan to persist the stack in private PDF metadata; persistence is deferred and recorded in its §9 ledger). `Cmd+R` is therefore within-document by construction, and last-page restore is the cross-document return path. Record only defined far jumps, not ordinary scrolling or page changes. Implement only after the Refactoring item "Centralize far-jump execution before implementing JumpStack"; design and test duplicate/consecutive-page behavior before wiring it into the reader. This is `TARGET_ARCHITECTURE.md` Phase C step 10, with acceptance in its step 11.

- **Extend JumpStation with prefix input/filtering.** Add the display-only prefix panel and VBA-inspired keyboard behavior: case-insensitive prefix matching against bookmark names, repeated Backspace, selection independent from prefix text, and two-stage Escape (clear prefix, then close). Design and test the non-visual state machine before wiring it into `JumpStationPanel`.

## Cosmetic / UX Improvements

- **Sidebar Card Polish.** Tweak padding, reduce title font to ~9pt, adjust comment font to ~11pt, experiment with custom grayscale background colors for Dark Mode contrast.
- **Emphasis color tuning.** Replace light yellow (#FFFFE0) at 0.7 opacity with dark pink.
- **CommentInputPanel geometry persistence.** Use UserDefaults to remember panel position/size across launches (currently session-only via static var). Works across `open -n` instances too. Same mechanism family as main-window frame autosave.
- **Consider a status bar.** Thin bar below the PDF view. Possible contents: mode indicators (persistent highlight, X-Ray), page display, PDF size, highlight count, or most recent bookmark target. Reassess alongside other backlog work; if added, the window title should become the filename permanently.

### App Icon

- Proper .app bundle with icon.
- Make target to regenerate AppIcon.appiconset from a source PNG (sips + iconutil) -- enables icon experiments without touching Xcode. Caveat: Launch Services may need a nudge before Finder shows changes.
