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

- **Extract `PopupController`.** Consolidate all popup suppression logic (scrubbing on load, X-Ray toggle, conditional popup handling in edit/create) into one type. Currently spread across AnimaPDFView and MainViewController. Review 2026-07-11 confirmed: `scrubCommentsForPopupSuppression` and `applyXRayModeToDocument`'s OFF-branch are near-duplicates.

- **Extract `EmphasisManager` from `MainViewController`.** The emphasis state machine (apply/clear/preserve-through-rebuild, ~100 lines) becomes its own type. MainViewController focuses on layout and scroll physics. While extracting: consolidate the triplicated UUID lookup (/NM-then-userName fallback exists in AnnotationManager.annotationUUID, SidebarExtractor.getUUID, MainViewController.findAnnotation) into one shared helper.

- **Delete `reloadDocument()` dead code in AnimaPDFView.** Nothing calls it, and it predates the sidebar: if it were ever called, pageSidebarViews would desync from the new document. Delete (git remembers); a future reload path must go through `loadPDF`.

---

## Cosmetic / UX Improvements

- **Extend JumpStation with prefix input/filtering.** Add the display-only prefix panel and VBA-inspired keyboard behavior: case-insensitive prefix matching against bookmark names, repeated Backspace, selection independent from prefix text, and two-stage Escape (clear prefix, then close). Design and test the non-visual state machine before wiring it into `JumpStationPanel`.
- **Sidebar Card Polish.** Tweak padding, reduce title font to ~9pt, adjust comment font to ~11pt, experiment with custom grayscale background colors for Dark Mode contrast.
- **Emphasis color tuning.** Light yellow (#FFFFE0) at 0.7 opacity may need adjustment for different PDF backgrounds or dark mode.
- **CommentInputPanel geometry persistence.** Use UserDefaults to remember panel position/size across launches (currently session-only via static var). Works across `open -n` instances too. Same mechanism family as main-window frame autosave (see UX Priorities).

---

## Toolchain Integration

### macOS Integration

- Proper .app bundle with icon.
- Make target to regenerate AppIcon.appiconset from a source PNG (sips + iconutil) -- enables icon experiments without touching Xcode. Caveat: Launch Services may need a nudge before Finder shows changes.

### pdf:// URL handler (macOS native)

- Register custom `pdf://` URL scheme.
- Parse `pdf://HASH?page=N` URLs.
- Resolve hash to filename (reuse `pdf_registry.build_pdf_index`).
- Open PDF at specified page.
- If PDF already open in a tab, switch to that tab + navigate to page.
- Eliminate need for Windows PDF server + Parallels bridge.

### pdf-annot compatibility

- Test with full extract.py pipeline (not just round_trip_test.py).
- Verify comment extraction with actual Obsidian bibnote generation.
- Match PDF-XChange Viewer's annotation structure as closely as possible.

---

## Backlog: Nice to Have

### Sidebar

- Review remove-highlight UX (which keys, confirmation?).
- Undo (remove) last highlight.
- Empty-comment confirmation before clearing.

### Reader chrome

- **Consider a status bar.** Thin bar below the PDF view. Possible contents: mode indicators (persistent highlight, X-Ray), page display, PDF size, highlight count, or most recent bookmark target. Reassess alongside other backlog work; if added, the window title should become the filename permanently.

### Navigation

- Zoom via menu bar or simple widget (not pinch).

### Find

- Regex search.
- "Find all" -- highlight all matches, list in sidebar.

### Performance

- Test with large IA PDFs (~20MB).
- Lazy annotation loading for PDFs with many highlights.

### Annotation features

- Multiple highlight colors (configurable, switchable via keyboard).

### Tabs

- Browser-style tabs in single window.
- Each tab: independent PDF + sidebar.
- Cmd+Shift+] / Cmd+Shift+[ to switch tabs.
- Tab shows filename.
- Open new tab: Cmd+O or drag-drop.

### Housekeeping

- Review and clean up `MainMenu.xib` (remove unused Font/Format/Text menus).
