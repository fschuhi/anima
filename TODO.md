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

- ~~**Jittery resize at startup.** Resolved 2026-07-14: assigned an `NSSplitView` autosave name, gave the sidebar a higher holding priority than the PDF pane, and deferred the first-run 300-point sidebar default until layout had settled. The sidebar now retains its width during ordinary resizing, the PDF pane absorbs width changes, divider position persists, and the launch-time jitter disappeared. Tests remain green: 11 Python + 9 Swift.~~

- ~~**Remember main window size/position.** Resolved 2026-07-14: `NSWindow` frame autosave now restores the main window's position, width, and height between launches. The autosave name is assigned after the main content view controller is installed, so later split-view layout does not overwrite the restored size.~~

- ~~**Highlight colors too saturated (Apple renderers).** Resolved 2026-07-13: PDF-XChange/Chromium render fitz's appearance stream, while PDFKit renders highlight annotations from their high-level properties and appeared more saturated. Persisted fitz color/opacity remain unchanged; Anima applies a PDFKit-only in-memory display color (`#FFE6EA`) to loaded and newly created highlights. Verified in Anima, PDF-XChange Viewer, Chrome, Preview, and X-Ray mode.~~

- **Status bar.** Thin bar below the PDF view. Carries: mode indicators (moves them out of the window title -- also fixes the title losing the PDF filename after the first H/P toggle, since `updateWindowTitle()` hardcodes "Anima" as base), page display, and later the goto-page entry point. Window title then shows the filename, permanently.

- **Page indicator.** Show "page N of M" in the status bar. PDFKit provides `PDFViewPageChanged` notification + `currentPage` -- nothing in the code observes these yet. Depends on: status bar.

- **Goto page.** Jump to a page number via Cmd+G (or click on the page display). `pdfView.go(to:)` does the navigation. Depends on: status bar, page indicator.

- **Bookmarks with jump stack.** JumpStation-style navigation (reference: Frank's Excel VBA JumpStation.bas / UserFormSelector.frm): a back-stack of jump targets (push current page on jump, pop with a shortcut) plus a keyboard-driven type-to-filter selector panel for named targets (e.g. "endnotes"). UI precedent in Anima: CommentInputPanel (modal, keyboard-first). Primary use case: main text <-> endnotes round trips.

---

## Refactoring

- **Extract `PopupController`.** Consolidate all popup suppression logic (scrubbing on load, X-Ray toggle, conditional popup handling in edit/create) into one type. Currently spread across AnimaPDFView and MainViewController. Review 2026-07-11 confirmed: `scrubCommentsForPopupSuppression` and `applyXRayModeToDocument`'s OFF-branch are near-duplicates.

- **Extract `EmphasisManager` from `MainViewController`.** The emphasis state machine (apply/clear/preserve-through-rebuild, ~100 lines) becomes its own type. MainViewController focuses on layout and scroll physics. While extracting: consolidate the triplicated UUID lookup (/NM-then-userName fallback exists in AnnotationManager.annotationUUID, SidebarExtractor.getUUID, MainViewController.findAnnotation) into one shared helper.

- **Delete `reloadDocument()` dead code in AnimaPDFView.** Nothing calls it, and it predates the sidebar: if it were ever called, pageSidebarViews would desync from the new document. Delete (git remembers); a future reload path must go through `loadPDF`.

---

## Cosmetic / UX Improvements

- **Sidebar Card Polish.** Tweak padding, reduce title font to ~9pt, adjust comment font to ~11pt, experiment with custom grayscale background colors for Dark Mode contrast.

- **Emphasis color tuning.** Light yellow (#FFFFE0) at 0.7 opacity may need adjustment for different PDF backgrounds or dark mode.

- **CommentInputPanel geometry persistence.** Use UserDefaults to remember panel position/size across launches (currently session-only via static var). Works across `open -n` instances too. Same mechanism family as main-window frame autosave (see UX Priorities).

---

## Testing

### Swift -- remaining

- Integration: FitzBridge round-trip against test PDF (requires venv).
- Cross-page selection: pin the page-scoped behavior -- only first-page lines produce quads, second-page lines are dropped (intended: highlights are per-page; continuation via `link` comment convention).

_Pattern established for the two closed items: extract the inline math as a pure `static func` on `AnnotationManager`, test it standalone (no PDF fixture needed), then have call sites (including existing tests) use it instead of duplicating. Worth the same treatment if either remaining item turns out to have similar inline logic._

### Python -- remaining

- edit-comment clear on a popup-less annotation: clear a comment (`--comment ""`) on an annotation without a popup, save, reopen with fitz, assert `/Contents` is empty. Pins the xref-clear ordering in `cmd_edit_comment` (the second `annot.update()` after the xref write must not resurrect the old text).

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

### Navigation

- Cmd+F find (PDFKit native -- may come free).
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

- Review and clean up MainMenu.xib (remove unused Font/Format/Text menus).
