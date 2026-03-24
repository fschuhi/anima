# Changelog

All notable accomplishments in Anima, organized by feature area.
This file serves as the historical record — TODO.md stays forward-looking.

---

## Foundation

- Xcode project setup (.app bundle, menu bar, Cmd+Q)
- Sandbox disabled for filesystem access (PDFs + Python helper)
- Absolute path resolution for helper and PDF (Xcode DerivedData)
- Git repo on GitHub (private), PyCharm for Git operations
- `.editorconfig` (LF line endings, indentation rules)
- `make format` target (SwiftFormat + black)

## Dual-Write Architecture

- Hybrid PDFKit (render) + fitz (write) architecture
- Incremental save via fitz preserves all existing annotations
- Dual-write for highlight creation, comment editing, and deletion
- No document reload during session — scroll drift eliminated
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
- Double-click → ensure emphasis + open comment editor
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
- `scrubCommentsForPopupSuppression()` migrates `.contents` → `/AnimaComment`
  and aggressively severs all `/Popup` links before rendering
- X-Ray mode (P key toggle) rehydrates popups for debugging
- Dual-key contract threaded through SidebarExtractor, editComment,
  addInMemoryHighlight

## Navigation

- Jump to beginning/end (Cmd+Home, Cmd+End, Home, End)
- Page Up / Page Down (one screenful, Windows-style)

## Testing

### Python (pytest) — 11 tests passing
- Round-trip: create → verify → edit → verify → delete → verify
- Edge cases: invalid page, missing file, nonexistent UUID
- Incremental save preserves existing annotations
- UUID correctly written to /NM field (xref-level check)
- QuadPoints match input coordinates (multi-quad)
- Comment clearing works (empty string via xref_set_key)
- Opacity survives edit (annot.update() regression guard)

### Swift (Swift Testing) — 5 tests passing
- SidebarExtractor: golden JSON test (sidebar_basic.pdf)
- SidebarExtractor: multi-page extraction (sidebar_page_extract.pdf)
- SidebarExtractor: per-page extraction (page 0, page 1, empty page 2)
- Per-page reassembly matches document-level extraction
- In-memory annotation round-trip (guards dual-write field omissions)

## Refactoring

- Extracted AnnotationManager from AnimaPDFView — All annotation CRUD
  operations (highlight creation with quad math and dual-write, comment editing
  via CommentInputPanel, highlight deletion) moved to a dedicated class.
  AnimaPDFView is now purely event handling, hit-testing, and mode management.
  AnnotationManager is a toolbox: it holds no references to the view or document,
  receiving all context per-call. This keeps it testable and safe for future
  multi-document (tabs) support. Constants (authorName, highlightColor,
  highlightOpacity) and helpers (annotationUUID, ensurePopupExists) also
  moved. AppDelegate creates and wires the manager. Four files changed:
  AnnotationManager.swift (new, 397 lines), AnimaPDFView.swift (700→463),
  MainViewController.swift (1 reference updated), AppDelegate.swift (wiring).
