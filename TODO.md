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

- **`JumpStationPanel`'s `onJump` timing.** `OpenDialogPanel` needed a fix for calling its `onOpen` callback synchronously after `NSApp.stopModal()`, before `NSApp.modalWindow` actually clears -- a caller checking the modal guard (like `loadDocument`'s) declines. `JumpStationPanel.onJump` has the identical call order and hasn't shown the symptom only because `farJump(to:)` doesn't check `NSApp.modalWindow`. Trigger: if `onJump`'s target ever routes through something that does check the modal guard, apply the same fix (defer the callback until after `runModal(for:)` returns).

- **`MainMenu.xib` housekeeping.** Review and clean up `MainMenu.xib` (remove unused Font/Format/Text menus).

---

## Opening PDFs

- ~~**Implement the open dialog per `docs/OPEN_DIALOG_DESIGN.md`.** Modeless filter/selection state machine as a plain testable type first, then the panel as a `JumpStationPanel` sibling, then the `openDocument(_:)` entry point and the `make` target seeding the `UserDefaults` search path.~~ Done 2026-07-28 -- `Cmd+O` opens the collection launcher end to end, sorted by most-recently-touched PDF. See `HISTORY.md` for the two implementation bugs found along the way.

- **Open a PDF by dropping it onto the reader window.** Dock-icon drops already arrive through `application(_:open:)`; this item concerns registering the reader window as a drag destination.

- **Backchannel to the Obsidian bibnote (open via CLI).** From the currently displayed PDF, resolve its `pdf_id` and have Obsidian open the matching bibnote directly, instead of a manual lookup. _Needs investigation:_ a keybinding (`Cmd+P` is already X-Ray toggle -- needs a different key or a decision to repurpose it); whether the lookup runs through a new `pdf-annotations` CLI direction (path/hash -> bibnote) or Anima calls Obsidian directly; and the failure case for a PDF with no `pdf_id` (likely beep-and-log, consistent with the app's other resolve guards).

- **Multiple PDF collection search paths / recursive scanning.** Deferred in `docs/OPEN_DIALOG_DESIGN.md` v1 (§8). Revisit if the collection outgrows a single flat directory; the `UserDefaults` key would become an array of strings.

- **Open dialog settings UI.** Deferred in `docs/OPEN_DIALOG_DESIGN.md` v1 (§8); `make set-pdf-collection-path` is sufficient for a single user today.

- **Open Recent menu integration.** `docs/OPEN_DIALOG_DESIGN.md` (§8) left open whether Anima should feed the xib's stock "Open Recent" submenu -- unexamined.

- **Same-process multiple documents remain parked.** Multiple windows or tabs would require first-class per-document reader sessions with independent PDF views, sidebars, bookmarks, search, emphasis, and modal ownership. Do not build that infrastructure unless replacement-based switching proves insufficient. Separate simultaneous instances remain available through `open -n`.

---

## Navigation

- **Transfer the open-dialog UX paradigm to JumpStation.** After the open dialog has proven itself in daily use, replace the planned prefix-matching design with the tested paradigm from `docs/OPEN_DIALOG_DESIGN.md`: case-insensitive substring filter instead of prefix matching, modeless key map (letters filter, arrows select, two-stage Escape), filter label. Additionally fix: bookmark list must be ordered by page number, not by time of adding. At that point, evaluate extracting the shared filtering-panel shape from the two concrete implementations.

## Cosmetic / UX Improvements

- **Sidebar Card Polish.** Tweak padding, reduce title font to ~9pt, adjust comment font to ~11pt, experiment with custom grayscale background colors for Dark Mode contrast.
- **Emphasis color tuning.** Replace light yellow (#FFFFE0) at 0.7 opacity with dark pink.
- **CommentInputPanel geometry persistence.** Use UserDefaults to remember panel position/size across launches (currently session-only via static var). Works across `open -n` instances too. Same mechanism family as main-window frame autosave.
- **Consider a status bar.** Thin bar below the PDF view. Possible contents: mode indicators (persistent highlight, X-Ray), page display, PDF size, highlight count, or most recent bookmark target. Reassess alongside other backlog work; if added, the window title should become the filename permanently.

### App Icon

- Proper .app bundle with icon.
- Make target to regenerate AppIcon.appiconset from a source PNG (sips + iconutil) -- enables icon experiments without touching Xcode. Caveat: Launch Services may need a nudge before Finder shows changes.

### Tooling

- **`make format` does not reach the Swift tests.** SwiftFormat runs on `Anima/Anima/` only, so `Anima/AnimaTests/` drifts from the formatter. Either extend the target or decide test sources are deliberately excluded.
- **Console output has no home.** Every reader event logs through `Swift.print`, visible only with Xcode's debug area open (`Cmd+Shift+Y`) or via Console.app for a standalone launch. Decide whether to keep it developer-only, route it somewhere visible in the reader, or thin it out. Related: the parked status-bar item under Cosmetic / UX.
