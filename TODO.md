# Anima — TODO

## Status Key
- `[x]` Done (verified)
- `[ ]` To do
- `[~]` Partially done / workaround exists
- `[!]` Known issue, needs investigation

---

## Python PoC Results (v7, PyObjC)

### Verified Working
- [x] PDFKit renders standard and IA layered PDFs
- [x] Two-finger trackpad scrolling (native, smooth)
- [x] Text selection (drag and double-click)
- [x] Highlight creation via ENTER key (NSEvent monitor)
- [x] Comment dialog on highlight creation
- [x] Incremental save via fitz (non-destructive, ~1KB overhead)
- [x] Existing annotations fully preserved (opacity, IDs, dates, vertices)
- [x] Round-trip verified: fitz reads Anima-created annotations correctly
- [x] `extract.py` compatible annotation format
- [x] Custom UUID on annotations (via xref NM field)
- [x] Popup annotation for comment visibility in PDF-XChange Viewer
- [x] Scroll position preserved on reload
- [x] Zoom (PDFKit native)
- [x] Cmd+Q quit with pending save

### Known Issues (Python PoC)
- [!] Reload flash: PDFKit clears and redraws canvas on document reload
- [!] PDFKit renders highlight colors slightly differently from PDF-XChange Viewer
      — cosmetic only, stored colors are correct
- [!] Mouse/keyboard event handling limited by PyObjC
      — PDFView's internal PDFDocumentView swallows events
      — subclass overrides (keyDown, mouseDown) don't fire reliably
      — NSEvent monitor workaround works for keys but not for click-on-highlight
      — persistent highlight mode not achievable via PyObjC

---

## Swift PoC — Step 1: Recreate Python PoC (DONE)

### Verified Working
- [x] PDFKit renders PDF in a window
- [x] Two-finger trackpad scrolling (native, smooth)
- [x] Text selection (drag)
- [x] Keyboard events working (NSEvent monitor + keyDown override)
- [x] ENTER creates highlight from selection
- [x] Comment dialog (NSAlert with text field)
- [x] anima_helper.py CLI (add-highlight, edit-comment, delete-highlight)
- [x] Incremental save via fitz subprocess (Python .venv)
- [x] Highlight persists — visible in PDF-XChange Viewer
- [x] Round-trip compatible with extract.py pipeline
- [x] App appears in Cmd+Tab (setActivationPolicy .regular)

### Known Issues (Swift PoC)
- [!] Scroll position drifts slightly on reload
      — same issue as Python PoC, cosmetic
      — real fix: dual-write approach (no reload needed)
- [!] No app icon (black square with "exec" in Cmd+Tab)
      — expected: no app bundle yet
- [!] Cmd+Q doesn't work — no menu bar (command-line app, no bundle)
      — workaround: close window (red button) or Ctrl+C in Terminal
- [!] annot.update() regenerates appearance stream
      — changes how PDF-XChange Viewer renders existing highlights
      — underlying data (color, opacity, coords) preserved
      — visual rendering in Viewer may differ after fitz edit
      — Anima (PDFKit) renders consistently regardless

---

## Swift PoC — Step 2: Fix What PyObjC Couldn't (PARTIAL)

### Done
- [x] Double-click highlight to edit comment
      — mouseDown override fires correctly in Swift (unlike PyObjC)
      — PDFPage.annotation(at:) works for hit-testing highlights
      — bounds.contains(point) fallback also works
      — comment dialog pre-filled with existing comment
      — saves via anima_helper.py edit-comment
      — opacity preserved on edit (original value re-applied before update)
      — popup created if not already present
- [x] Click highlight + Delete to remove it
      — single-click selects annotation (stored reference)
      — Delete/Backspace triggers deletion via anima_helper.py
      — annotationUUID() reads NM field correctly
      — works even for PDF-XChange Viewer annotations (non-standard UUID format)

### Deferred: Persistent highlight mode
- [ ] Resolve reload scroll drift before implementing
      — either fix scroll restoration or implement dual-write (no reload)
      — dual-write: add PDFAnnotation to PDFKit in-memory for display,
        save via fitz for persistence, never reload during session
- [ ] Toggle with H key, status indicator shows current mode
- [ ] In highlight mode: mouse-up after drag immediately creates highlight
- [ ] No ENTER needed — select text and it's highlighted
- [ ] Must coexist with PDFKit's native mouse handling
- [ ] This is the KEY usability feature for the final app
- [ ] Rationale for deferral: needs "stable canvas" — no scroll jumping
      after highlight creation. Dual-write approach solves both problems.

---

## Milestone 1: Usable Daily Driver (after PoC decision)

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

### Save — eliminate reload flash
- [ ] Dual-write approach:
      — add PDFAnnotation to PDFKit in-memory for immediate display
      — save via fitz for correct persistence
      — no document reload during session
      — on next open, fitz's saved version is the source of truth
- [ ] Auto-save on every change

### Tabs
- [ ] Browser-style tabs in single window
- [ ] Each tab: independent PDF + sidebar
- [ ] Cmd+Shift+] / Cmd+Shift+[ to switch tabs
- [ ] Ctrl+Tab mapping (for Windows muscle memory, via app or Karabiner)
- [ ] Tab shows filename
- [ ] Open new tab: Cmd+O or drag-drop

### Navigation
- [ ] Cmd+F find (PDFKit native — may come free)
- [ ] Cmd+Q quit (requires menu bar setup)
- [ ] Jump to beginning: Cmd+Home or Home
- [ ] Jump to end: Cmd+End or End
- [ ] Page Up / Page Down (Windows-style: one screenful)
- [ ] Zoom via menu bar or simple widget (not pinch)

### macOS Integration
- [ ] Register as default PDF viewer (Info.plist CFBundleDocumentTypes)
- [ ] Accept file open via double-click in Finder
- [ ] Accept file open via command line argument
- [ ] Proper .app bundle with icon

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

## Architecture Notes

### Why hybrid PDFKit + fitz?
PDFKit's `writeToURL_` is destructive to existing annotations:
- Loses opacity values (-1 instead of 0.4)
- Loses annotation IDs
- Converts timezone representations in dates
- Doubles file size (full rewrite instead of incremental)
- Subtly shifts annotation rect coordinates

fitz's `save(incremental=True)` preserves everything.
PDFKit remains ideal for rendering and interaction.

### Appearance stream caveat
When fitz calls `annot.update()`, it regenerates the annotation's appearance
stream (the low-level PDF drawing instructions). This means annotations
edited by fitz may render slightly differently in PDF-XChange Viewer compared
to annotations originally created by Viewer, even though the underlying data
(color, opacity, coordinates) is identical. PDFKit (Anima) renders them
consistently regardless. This is a known fitz behavior.

### Swift PoC architecture
- `main.swift` — entry point, creates NSApplication
- `AppDelegate.swift` — creates window, loads PDF, NSEvent monitor fallback
- `AnimaPDFView.swift` — PDFView subclass, keyboard/mouse handling
- `FitzBridge.swift` — subprocess bridge to anima_helper.py
- `anima_helper.py` — CLI tool: add-highlight, edit-comment, delete-highlight

### Coordinate systems
- PDFKit: origin at **bottom-left** of page
- fitz: origin at **top-left** of page
- Conversion: `y_fitz = page_height - y_pdfkit`
- Coordinate flip happens in Swift (AnimaPDFView) before calling helper
- Helper receives fitz-native coordinates only

### Key event handling (Swift)
PDFKit's internal `PDFDocumentView` captures keyboard focus.
In Swift, keyDown override fires via NSEvent monitor fallback.
Both paths call handleKeyEvent() with deduplication.
mouseDown override DOES fire in Swift — this is the key advantage over PyObjC.

### Compilation (PoC, no Xcode)
```bash
swiftc -o anima \
  -framework Cocoa \
  -framework Quartz \
  main.swift AppDelegate.swift AnimaPDFView.swift FitzBridge.swift
```
