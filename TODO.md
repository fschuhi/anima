# TODO

## Status Key
- `[ ]` To do
- `[~]` Partially done / workaround exists
- `[!]` Known issue, needs investigation

---

## Known Issues

- [!] **Highlight color/opacity mismatch between viewers**
      Highlights render with different saturation in PDFKit vs PDF-XChange
      Viewer vs PDF-XChange Editor. Stored values are identical — difference
      is in viewer interpretation. Needs investigation: compare raw annotation
      attributes, check if appearance streams override stored color, consider
      runtime color adjustment in PDFKit.

- [!] **annot.update() regenerates appearance stream**
      fitz's `annot.update()` regenerates the appearance stream. Highlights
      edited by fitz may render slightly differently in PDF-XChange Viewer.
      PDFKit renders consistently regardless. Known fitz behavior.

- [!] **Hardcoded absolute paths**
      `AppDelegate.swift`, `AnimaPDFView.swift`, and `FitzBridge.swift` use
      hardcoded paths (`/Users/fschuhi/Projects/anima/...`). Works for
      development; needs proper path resolution for distributable .app bundle.

- [!] **Clip Tools Launcher.workflow clipboard corruption**
      macOS Service injects `rm -rf` fragments into pasted text containing
      `!r` format specifiers. Check ~/Library/Services/, determine source,
      remove or disable.

---

## Refactoring

- [ ] **Extract `AnnotationManager` from `AnimaPDFView`**
      Done. `AnimaPDFView` delegates all CRUD to `AnnotationManager`.
      See CHANGELOG.md for details.

- [ ] **Extract `PopupController`**
      Consolidate all popup suppression logic (scrubbing on load, X-Ray
      toggle, conditional popup handling in edit/create) into one type.
      Currently spread across AnimaPDFView and MainViewController.

- [ ] **Extract `EmphasisManager` from `MainViewController`**
      The emphasis state machine (apply/clear/preserve-through-rebuild,
      ~100 lines) becomes its own type. MainViewController focuses on
      layout and scroll physics.

---

## Cosmetic / UX Improvements

- [ ] **Sidebar Card Polish** — Tweak padding, reduce title font to ~9pt,
      adjust comment font to ~11pt, experiment with custom grayscale
      background colors for Dark Mode contrast.
- [ ] **Status bar indicator** — Replace window title suffix with a proper
      bottom status bar (thin NSTextField below the PDF view).
- [ ] **Emphasis color tuning** — Light yellow (#FFFFE0) at 0.7 opacity
      may need adjustment for different PDF backgrounds or dark mode.

---

## Testing

### Swift — remaining
- [ ] Coordinate conversion: y-flip math for known page heights and points
- [ ] QuadPoints construction: verify PDFKit-space quad geometry
- [ ] Integration: FitzBridge round-trip against test PDF (requires venv)

---

## Milestone 2: Toolchain Integration

### macOS Integration
- [ ] Register as default PDF viewer (Info.plist CFBundleDocumentTypes)
- [ ] Accept file open via double-click in Finder
- [ ] Accept file open via command line argument
- [ ] Proper .app bundle with icon
- [ ] Resolve helper/venv paths relative to bundle (eliminate hardcoded paths)

### pdf:// URL handler (macOS native)
- [ ] Register custom `pdf://` URL scheme
- [ ] Parse `pdf://HASH?page=N` URLs
- [ ] Resolve hash to filename (reuse `pdf_registry.build_pdf_index`)
- [ ] Open PDF at specified page
- [ ] If PDF already open in a tab, switch to that tab + navigate to page
- [ ] Eliminate need for Windows PDF server + Parallels bridge

### pdf-annot compatibility
- [ ] Test with full extract.py pipeline (not just round_trip_test.py)
- [ ] Verify comment extraction with actual Obsidian bibnote generation
- [ ] Match PDF-XChange Viewer's annotation structure as closely as possible

---

## Milestone 3: Nice to Have (Backlog)

### Sidebar
- [ ] Review remove-highlight UX (which keys, confirmation?)
- [ ] Undo (remove) last highlight
- [ ] Empty-comment confirmation before clearing

### Navigation
- [ ] Cmd+F find (PDFKit native — may come free)
- [ ] Zoom via menu bar or simple widget (not pinch)

### Find
- [ ] Regex search
- [ ] "Find all" — highlight all matches, list in sidebar

### Performance
- [ ] Test with large IA PDFs (~20MB)
- [ ] Lazy annotation loading for PDFs with many highlights

### Annotation features
- [ ] Multiple highlight colors (configurable, switchable via keyboard)

### Tabs
- [ ] Browser-style tabs in single window
- [ ] Each tab: independent PDF + sidebar
- [ ] Cmd+Shift+] / Cmd+Shift+[ to switch tabs
- [ ] Tab shows filename
- [ ] Open new tab: Cmd+O or drag-drop

### Housekeeping
- [ ] Review and clean up MainMenu.xib (remove unused Font/Format/Text menus)
