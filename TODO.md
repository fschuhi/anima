# TODO

(Note: "I" in the following paragraphs refer to the user, "you" to you as the AI model.)

## Charter
- Forward-looking only -- concrete, startable work: tasks specified well enough that next-session-me can begin within ten minutes, plus investigation items, test specs, and scratchpad ideas awaiting promotion or deletion.
- Items are unordered within their theme sections; open questions are marked _Needs investigation_ in the bullet.
- When an item is completed, record its durable outcome in `HISTORY.md` during the same session while the evidence and rationale are fresh, then strike it through in `TODO.md` with a concise handover note.
- Retain struck-through items through the next session because `TODO.md` is included in the standard filesdump while `HISTORY.md` normally is not; at the end of that next session, remove the already-archived items from `TODO.md`. Strategic direction, ordering, and milestones live in `GOALS.md` -- anything that needs a strategy discussion before it is actionable goes there.
- Architecture, contract, and settled decisions live in `README.md`.

---

## UX Priorities (Session 2026-07-11 -- order is initial ranking, final prios pending review)

~~**Bookmark navigation and deletion.** Persistence and `Cmd+B` creation are complete: bookmarks live in the PDF catalog's private `/AnimaBookmarks` key, use 0-based storage with 1-based reader display, and support case-insensitive re-pointing. `Cmd+J` now opens the two-column JumpStation picker; mouse actions select only, Up/Down moves selection, Enter jumps through `PDFView.go(to:)`, Esc closes, and `Cmd+D` confirms then deletes the selected bookmark. The picker refreshes from `BookmarkManager` after deletion and closes if the final bookmark was removed.~~ Completed 2026-07-15; the later prefix-input/filtering enhancement remains active under Cosmetic / UX Improvements.

---

## Refactoring

- **Reduce size of `filesdump.txt`.** Should we exclude files from the `filesdump.txt`? Are there superfluous comments in the `*.swift` files?

- **Extract `PopupController`.** Consolidate all popup suppression logic (scrubbing on load, X-Ray toggle, conditional popup handling in edit/create) into one type. Currently spread across AnimaPDFView and MainViewController. Review 2026-07-11 confirmed: `scrubCommentsForPopupSuppression` and `applyXRayModeToDocument`'s OFF-branch are near-duplicates.

- **Extract `EmphasisManager` from `MainViewController`.** The emphasis state machine (apply/clear/preserve-through-rebuild, ~100 lines) becomes its own type. MainViewController focuses on layout and scroll physics. While extracting: consolidate the triplicated UUID lookup (/NM-then-userName fallback exists in AnnotationManager.annotationUUID, SidebarExtractor.getUUID, MainViewController.findAnnotation) into one shared helper.

- **Delete `reloadDocument()` dead code in AnimaPDFView.** Nothing calls it, and it predates the sidebar: if it were ever called, pageSidebarViews would desync from the new document. Delete (git remembers); a future reload path must go through `loadPDF`.

- **FitzBridge redesign.** The subprocess seam has a latent pipe deadlock (`waitUntilExit` before reading pipes), blocks the main thread per operation, and pays interpreter-startup latency on every mutation (today: barely perceptible hesitation, not gummy). Parked per Scope Skepticism -- no observed problem yet. Trigger: latency becomes noticeable, output grows past pipe buffers, or async/batch needs arise. Scope of the session: async dispatch vs. long-running helper process vs. batching -- trade-offs first, then implement.

- **Comment set/clear lifecycle.** `cmd_edit_comment`'s ordering is fragile: fitz's `set_info` silently ignores empty strings, the xref-level `/Contents` clear must stay the last mutation before save, and a second `annot.update()` (popup creation path) runs after it.

- **`MainMenu.xib` housekeeping.** Review and clean up `MainMenu.xib` (remove unused Font/Format/Text menus).

---

## Navigation

- **JumpStack.** A "far jump" is the target of a (a) go to page, (b) find in PDF, (c) find in comments, (d) `F3` to find next (in PDF or comment), (e) jump to bookmark. Put current position (page number) before doing the far jumps on the stack, then use Cmd+R to pop the previous position from the stack and jump there. Main use case is having an "Endnotes" bookmark. When we jump there via the JumpStation, we want to return to where we jumped from after checking the endnotes.
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
