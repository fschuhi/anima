# History

(Note: "I" in the following paragraphs refer to the user, "you" to you as the AI model.)

- The resolved-work record: what was built and when (note date, or have the points in roughly reverse-chronological order).
- This is the trophy case -- kept in the repo, **out of the per-session filesdump** (so it no longer rides along every session).
- For *forward* work see `TODO.md`; for direction see `GOALS.md`; for the architecture as it stands see `README.md`.
- See "Workflow for the Whole Session (CRITICAL)" in `LLM_INSTRUCTIONS.md` for the interplay between `TODO.md` and this file.

---

## Foundation

- Xcode project setup (.app bundle, menu bar, Cmd+Q)
- Sandbox disabled for filesystem access (PDFs + Python helper)
- Absolute path resolution for helper and PDF (Xcode DerivedData)
- Git repo on GitHub (private), PyCharm for Git operations
- `.editorconfig` (LF line endings, indentation rules)
- `make format` target (SwiftFormat + black)
- Makefile cleanup: `black` now covers `tests/` alongside `tools/`; dead swiftc variables (SWIFT_SRC, SWIFT_FRAMEWORKS) removed (2026-07-11)

## Dual-Write Architecture

- Hybrid PDFKit (render) + fitz (write) architecture
- Incremental save via fitz preserves all existing annotations
- Dual-write for highlight creation, comment editing, and deletion
- No document reload during session -- scroll drift eliminated
- Dialog focus fix (isShowingDialog prevents duplicate Enter handling)

## Highlight Workflow

- ENTER with text selection creates highlight (dual-write)
- Persistent highlight mode (H key toggle, mouseUp = instant highlight)
- Highlight deletion via click + Delete key
- Highlights created without comment (double-click to add later)

## Sidebar (Comment Cards)

- Right-side fixed-width panel with annotation cards
- Cards sorted by vertical position, anchor-based layout
- Collision avoidance (greedy top-to-bottom algorithm)
- Per-page architecture (PageSidebarView) for efficient rebuilds
- Scroll sync (lockstep with PDF via bounds change notifications)
- Bidirectional emphasis (card ↔ highlight, toggle on single-click)
- Double-click -> ensure emphasis + open comment editor
- Emphasis unified with selectedAnnotation (Delete key targeting)
- Scroll card into view when emphasized via highlight-click
- Live sidebar updates via SidebarUpdateDelegate protocol
- Per-page re-extraction on annotation mutation
- Emphasis preserved through sidebar rebuilds
- Command comments ("link", "H1"–"H9") rendered in muted gray

## Comment Input Panel (Phase 4)

- Custom NSPanel replacing NSAlert-based dialog
- Modal, Escape to save, Enter for newlines
- Styled to match CommentCardView (fonts, colors, corner radius)
- Traffic light buttons hidden; Escape is the only exit
- Resizable and draggable
- Session-remembered geometry (position + size persists until app quit)

## Popup Suppression

- Native PDFKit yellow popup squares eliminated on load
- `/AnimaComment` custom dictionary key stores comment text
- `scrubCommentsForPopupSuppression()` migrates `.contents` -> `/AnimaComment`
  and aggressively severs all `/Popup` links before rendering
- X-Ray mode (P key toggle) rehydrates popups for debugging
- Dual-key contract threaded through SidebarExtractor, editComment,
  addInMemoryHighlight

## Bookmarks

- Bookmark persistence and creation (2026-07-15): added named whole-page bookmarks stored as JSON in the PDF catalog's private `/AnimaBookmarks` key. The implementation deliberately leaves the document's native `/Outlines` / table of contents untouched. Stored pages use fitz-native 0-based indices; reader-facing prompts display the corresponding 1-based page number. `anima_helper.py` now provides `list-bookmarks`, `set-bookmark`, and `delete-bookmark`; pytest covers missing-key listing, case-insensitive upsert and deletion, invalid 0-based pages, deletion failure, and native-TOC preservation. On the Swift side, `FitzBridge` exposes matching operations and `BookmarkManager` owns the active session's decoded list, reloading after successful mutations so helper-owned catalog semantics remain authoritative. `testBookmarkManagerPersistenceRoundTrip` exercises the real Swift -> Python -> PDF catalog -> reload boundary. `Cmd+B` now prompts for a bookmark name on the current page, detects duplicates case-insensitively, and offers `Re-point` or `Keep Existing`; bookmark navigation and deletion remain the next active work.

## Reading Ergonomics

- Reader command-key migration (2026-07-15): persistent highlight, X-Ray, and goto-page moved from bare `H`, `P`, and `G` to `Cmd+H`, `Cmd+P`, and `Cmd+G`. This deliberately reclaims macOS's conventional Hide and Print shortcuts: Anima is a focused personal reader, print is out of scope, and hiding its only window is not useful in the intended workflow. Manual verification confirmed bare keys no longer trigger reader modes and command-modified keys do.
- Civilized main-window and split-view behavior (2026-07-14): main-window frame now persists across launches through AppKit frame autosave; split-divider position also persists through split-view autosave. The sidebar holds its current width during ordinary live window resizing while the PDF pane absorbs the change, subject to the existing minimum widths. The first-run 300-point sidebar default is applied only after layout has settled and never overwrites a restored divider position. This removed the launch-time resize/sidebar-width jitter.
- Page-aware document captions (2026-07-14): the window title now uses a compact reading handle plus `current page of total pages`, for example `(Albini 2013) -- 12 of 34`. Controlled filenames use their leading parenthesized `pdf_id`; uncontrolled filenames fall back to their stem, abbreviated through the easily tunable `AnimaPDFView.uncontrolledDocumentHandleMaximumLength` constant (currently 40). `AnimaPDFView` is the single caption formatter, so H/P toggles no longer erase the document handle, and PDFKit page-change notifications keep the page number current.
- Goto page (2026-07-14): bare `G` opens the smallest useful native AppKit page-number dialog. A valid 1-based page number in the displayed `1...pageCount` range navigates through `PDFView.go(to:)`; invalid or non-numeric input fails fast with an error that repeats the valid range and leaves the reader on its current page. This follows Anima's bare reader-command family (`H`, `P`, `G`) while deliberately leaving conventional `Cmd+G` available for future Find Next behavior.
- Clean window presentation at launch (2026-07-14): the nib-created main window is hidden until its frame autosave restoration, reader view setup, PDF load, and initial caption are complete. This removes the brief empty 480 x 360 `"Anima"` window flash; the first visible window is the configured reader.
- Cohesive forward-only search (2026-07-14): `Cmd+F` searches rendered PDF text and `Cmd+Shift+F` searches annotation comments only. Both begin at the current page and continue forward without wrapping; F3 advances the active search and reports "No more hits" at document end. PDF-text hits use PDFKit's temporary pale-green `highlightedSelections`, deliberately separate from annotation text selection, so search can never create a highlight even in persistent H mode. Comment-search matches receive thin pale-green sidebar borders, while the current F3 card receives a thicker pale-green border; moving to a result navigates to its PDF location and reveals the complete card in its local sidebar scroll view. The two search modes are mutually exclusive with annotation emphasis and with each other. Esc consistently clears the most immediate transient state -- PDF-text search, comment search, then annotation emphasis and its Delete-key target -- while clicking any annotation or card exits search and resumes normal annotation interaction.

## Navigation

- Jump to beginning/end (Cmd+Home, Cmd+End, Home, End)
- Page Up / Page Down (one screenful, Windows-style)

## macOS Integration

- Accept file open via command line argument
- Register as PDF viewer (Info.plist CFBundleDocumentTypes)
- Accept file open via double-click in Finder (`application(_:open:)`)
- Resolve helper/venv paths from single `projectRoot` constant
  (AppDelegate owns projectRoot; FitzBridge derives venv from helperPath)

## Testing

### Python (pytest)
- Round-trip: create -> verify -> edit -> verify -> delete -> verify
- Edge cases: invalid page, missing file, nonexistent UUID
- Incremental save preserves existing annotations
- UUID correctly written to /NM field (xref-level check)
- QuadPoints match input coordinates (multi-quad)
- Comment clearing works (empty string via xref_set_key)
- Opacity survives edit (annot.update() regression guard)
- `test_clear_comment_on_popupless_annotation` -- pins the comment-clear path for a popup-less annotation, the case `test_clear_comment` cannot reach because add-highlight always creates a popup (so `cmd_edit_comment`'s popup-creation branch, and the second `annot.update()` it runs after the xref-level `/Contents` clear, are skipped there). The precondition -- a highlight that carries a comment but has no popup -- is built directly with fitz, then cleared through the helper via `edit-comment --comment ""`. Green: the second `annot.update()` does not resurrect the old text and `/Contents` is verified empty at the xref level, so the popup-less path is now pinned alongside the popup-having one. This is the guard `GOALS.md` names for the parked "comment set/clear lifecycle" redesign (2026-07-15)

### Swift (Swift Testing)
- SidebarExtractor: golden JSON test (sidebar_basic.pdf)
- SidebarExtractor: multi-page extraction (sidebar_page_extract.pdf)
- SidebarExtractor: per-page extraction (page 0, page 1, empty page 2)
- Per-page reassembly matches document-level extraction
- In-memory annotation round-trip (guards dual-write field omissions)
- `testFitzQuadYFlip` -- pins the PDFKit->fitz y-flip contract (known page/rect, round-trip identity, non-standard page height, x unaffected) (2026-07-11)
- `testQuadPointsConstruction` -- pins QuadPoints corner order and count (single rect, multi-rect flattening, degenerate zero-width/height rects) (2026-07-11)
- - `testFitzBridgeAddHighlightRoundTrip` -- exercises the real Swift -> Python -> fitz subprocess boundary (distinct from `testInMemoryAnnotationRoundTrip`'s in-memory simulation): `FitzBridge.addHighlight` against a disposable copy of `sidebar_basic.pdf`, verified by reload. Project root located via `#filePath` self-location on the test file rather than an Xcode scheme environment variable (2026-07-15)
- `testCrossPageSelectionOnlyHighlightsFirstPage` -- pins the intentional page-scoped behavior of `AnimaPDFView.createHighlightFromSelection()`: a genuine cross-page `PDFSelection` (via `PDFDocument.selection(from:atCharacterIndex:to:atCharacterIndex:)`) produces a highlight confined to the first page; the second page's portion is silently dropped by design (cross-page stitching is `pdf-annotations`' downstream `link` comment convention, out of Anima's scope). Verification reads `PDFAnnotation`s directly via `AnnotationManager.annotationUUID(_:)` rather than `SidebarExtractor`, since highlights created this way start without a comment and `SidebarExtractor` only surfaces commented highlights (2026-07-15)

### Fixes found along the way (2026-07-11)
- Fixed stale test reference: `testInMemoryAnnotationRoundTrip` referenced `AnimaPDFView.highlightColor`/`highlightOpacity`, which live on `AnnotationManager` -- predated this session, caught by a clean build
- Added `nonisolated` to `CommentCard` (`SidebarExtractor.swift`) to resolve a Default Actor Isolation compile error that appeared after an Xcode update to 26.3

## Refactoring

- Extracted `AnnotationManager` from `AnimaPDFView` -- All annotation CRUD operations (highlight creation with quad math and dual-write, comment editing via `CommentInputPanel`, highlight deletion) moved to a dedicated class. `AnimaPDFView` is now purely event handling, hit-testing, and mode management. `AnnotationManager` is a toolbox: it holds no references to the view or document, receiving all context per-call. This keeps it testable and safe for future multi-document (tabs) support. Constants (`authorName`, `highlightColor`, `highlightOpacity`) and helpers (`annotationUUID`, `ensurePopupExists`) also moved. `AppDelegate` creates and wires the manager. Four files changed: `AnnotationManager.swift` (new, 397 lines), `AnimaPDFView.swift` (700->463), `MainViewController.swift` (1 reference updated), `AppDelegate.swift` (wiring).
- Extracted `AnnotationManager.fitzQuad(from:pageHeight:)` and `AnnotationManager.quadPoints(for:)` as pure static functions, replacing inline math in `createHighlight`/`addInMemoryHighlight` and removing a hand-copied duplicate of the QuadPoints corner construction in `testInMemoryAnnotationRoundTrip` (2026-07-11)

## Documentation & Process

- Architecture review, no-code session: full read-through of all Swift and Python sources. Confirmed dual-write/coordinate/popup-suppression design; surfaced FitzBridge subprocess seam (pipe deadlock risk, per-operation latency), comment set/clear lifecycle fragility in cmd_edit_comment, cross-page selection truncation (accepted as intended page-scoped behavior), and window-title/mode-indicator conflict. Findings triaged into TODO.md and GOALS.md (2026-07-11)
- GOALS.md established: Current Session Pointer + strategic vision, added to manifest.lst (2026-07-11)
- TODO.md restructured: new UX Priorities section from first sustained daily-use feedback; review findings folded in; test specs for the comment-clear ordering and cross-page behavior added (2026-07-11)
- CHANGELOG.md renamed to HISTORY.md -- resolved-work archive, matching the session workflow in LLM_INSTRUCTIONS.md (2026-07-11)
