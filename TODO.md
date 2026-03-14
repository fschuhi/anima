# Anima — TODO

## Status Key
- `[x]` Done (verified)
- `[ ]` To do
- `[~]` Partially done / workaround exists
- `[!]` Known issue, needs investigation

---

## Current: Dual-Write + Xcode Migration (DONE)

- [x] Xcode project setup (.app bundle, menu bar, Cmd+Q)
- [x] Migrated PoC Swift files into Xcode project
- [x] Sandbox disabled (filesystem access for PDFs and Python helper)
- [x] Absolute path resolution for helper and PDF (Xcode launches from DerivedData)
- [x] Dual-write: highlight creation (fitz persist + in-memory PDFAnnotation)
- [x] Dual-write: comment editing (fitz persist + in-memory update)
- [x] Dual-write: highlight deletion (fitz persist + in-memory removal)
- [x] No document reload during session — scroll drift eliminated
- [x] Dialog focus fix (isShowingDialog flag prevents duplicate Enter handling)
- [x] Git repo on GitHub (private), PyCharm for Git operations

---

## Persistent Highlight Mode (DONE)

- [x] Toggle with H key
- [x] Status indicator shows current mode (window title suffix)
- [x] In highlight mode: mouseUp after drag → immediate highlight creation
- [x] No ENTER needed — select text and release mouse to highlight
- [x] Highlight-only: no comment dialog on creation (double-click to add later)
- [x] ENTER without highlight mode still creates a highlight (legacy path)
- [x] Coexists with PDFKit's native text selection handling
- [x] Prerequisite satisfied: dual-write eliminates reload, canvas is stable
- [x] Bugfix: isShowingDialog was not reset to false after dialog dismissed

---

## Known Issues

- [!] **Highlight color/opacity mismatch between viewers**
      This is the most visible cosmetic issue. Highlights created by Anima
      (or any fitz-written highlight) render with different saturation/color
      in PDFKit vs PDF-XChange Viewer vs PDF-XChange Editor. The underlying
      stored values (color, opacity) are identical — the difference is in
      how each viewer interprets them. Needs investigation:
      — Compare raw annotation attributes across viewers
      — Determine if appearance streams override stored color values
      — If unfixable at the data level, consider runtime color adjustment
        in PDFKit (intercept rendering, modify annotation display properties)

- [!] **In-memory highlight has no popup indicator (yellow square)**
      The fitz-written annotation includes a popup annotation; the in-memory
      PDFAnnotation does not. After app restart, the popup appears (loaded
      from disk). Low priority — the sidebar (Milestone 1) replaces this
      indicator entirely.

- [!] **annot.update() regenerates appearance stream**
      When fitz calls `annot.update()`, it regenerates the annotation's
      appearance stream. Highlights edited by fitz may render slightly
      differently in PDF-XChange Viewer. Underlying data is preserved.
      PDFKit renders consistently regardless. Known fitz behavior.

- [!] **Hardcoded absolute paths**
      `AppDelegate.swift` and `AnimaPDFView.swift` use hardcoded paths
      (`/Users/fschuhi/Projects/anima/...`) for the PDF file, Python
      executable, and helper script. Works for development; needs proper
      path resolution for a distributable .app bundle (Milestone 1).

---

## Cosmetic / UX Improvements

- [ ] **Status bar indicator** — Replace window title suffix with a proper
      bottom status bar (thin NSTextField below the PDF view). Shows
      "Highlight Mode" when active, hidden/empty when not. The window title
      suffix works but a status bar is the conventional macOS location.

---

## Testing

### Python (anima_helper.py) — pytest
High value, protects the annotation contract that the whole app depends on.
- [ ] Round-trip test: create highlight → verify with fitz → edit comment →
      verify → delete → verify gone (use test PDF in `data/`)
- [ ] Edge cases: invalid page number, missing file, nonexistent UUID
- [ ] Verify incremental save preserves existing annotations
- [ ] Verify UUID is correctly written to /NM field
- [ ] Verify coordinate values in stored QuadPoints match input

### Swift — Swift Testing (XCTest for UI)
- [ ] Coordinate conversion: y-flip math for known page heights and points
- [ ] QuadPoints construction: verify PDFKit-space quad geometry
- [ ] UUID handling: annotationUUID() reads /NM from annotations
- [ ] Integration: FitzBridge round-trip against test PDF (requires venv)

---

## Milestone 1: Usable Daily Driver

### Sidebar (comment cards)
- [ ] Right-side fixed-width panel showing annotation cards
- [ ] Each card: truncated highlight excerpt as header + comment text below
- [ ] Cards sorted by vertical position on visible page(s)
- [ ] Rough vertical alignment with corresponding highlight
- [ ] Scrolls in sync with PDF (approximately)
- [ ] Double-click highlight → focus jumps to card, comment becomes editable
- [ ] Edit happens in sidebar only (no tooltips, no in-place editing)
- [ ] Clear comment text = remove comment (keep highlight)
- [ ] Cards shown for all highlights with non-empty comments
- [ ] Empty-comment highlights: no card (or minimal indicator)

### Tabs
- [ ] Browser-style tabs in single window
- [ ] Each tab: independent PDF + sidebar
- [ ] Cmd+Shift+] / Cmd+Shift+[ to switch tabs
- [ ] Ctrl+Tab mapping (for Windows muscle memory, via app or Karabiner)
- [ ] Tab shows filename
- [ ] Open new tab: Cmd+O or drag-drop

### Navigation
- [ ] Cmd+F find (PDFKit native — may come free)
- [ ] Jump to beginning: Cmd+Home or Home
- [ ] Jump to end: Cmd+End or End
- [ ] Page Up / Page Down (Windows-style: one screenful)
- [ ] Zoom via menu bar or simple widget (not pinch)

### macOS Integration
- [ ] Register as default PDF viewer (Info.plist CFBundleDocumentTypes)
- [ ] Accept file open via double-click in Finder
- [ ] Accept file open via command line argument
- [ ] Proper .app bundle with icon
- [ ] Resolve helper/venv paths relative to bundle (eliminate hardcoded paths)

---

## Milestone 2: Toolchain Integration

### pdf:// URL handler (macOS native)
- [ ] Register custom `pdf://` URL scheme
- [ ] Parse `pdf://HASH?page=N` URLs
- [ ] Resolve hash to filename (reuse `pdf_registry.build_pdf_index`)
- [ ] Open PDF at specified page
- [ ] If PDF already open in a tab, switch to that tab + navigate to page
- [ ] Eliminate need for Windows PDF server + Parallels bridge

### pdf-annot compatibility
- [x] Standard annotation format (verified in both PoCs)
- [ ] Test with full extract.py pipeline (not just round_trip_test.py)
- [ ] Verify comment extraction with actual Obsidian bibnote generation
- [ ] Match PDF-XChange Viewer's annotation structure as closely as possible

---

## Milestone 3: Nice to Have (Backlog)

### Find
- [ ] Regex search
- [ ] "Find all" — highlight all matches, list in sidebar (like Excel)

### Annotation features
- [ ] Multiple highlight colors (configurable, switchable via keyboard)

### Performance
- [ ] Test with large IA PDFs (~20MB)
- [ ] Lazy annotation loading for PDFs with many highlights

---

## Housekeeping

- [x] Add .editorconfig (LF line endings, indentation rules)
- [x] Add `make format` target (SwiftFormat + black)
- [x] Update manifest.lst for Anima/Anima/ path nesting
- [ ] Review and clean up MainMenu.xib (remove unused Font/Format/Text menus)
