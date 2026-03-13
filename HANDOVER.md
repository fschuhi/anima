# Anima — Handover: Swift PoC Session

## What Happened This Session

Starting from a working Python/PyObjC PoC (v7), we built a Swift PoC to test
whether Swift solves the mouse/keyboard event handling problems that PyObjC
couldn't. The answer is **yes** — Swift's PDFView subclass overrides fire
correctly for both mouse and keyboard events.

### Built

1. **`anima_helper.py`** — standalone CLI tool wrapping fitz for annotation
   management. Three subcommands:
   - `add-highlight --file --page --uuid --quads [--comment] [--author]`
   - `edit-comment --file --uuid --comment`
   - `delete-highlight --file --uuid`
   
   Coordinate contract: all coordinates in fitz space (origin top-left, y-down).
   Callers flip coordinates before calling. Incremental save preserves all
   existing annotations. Tested and verified round-trip compatible with
   `extract.py` pipeline.

2. **Swift PoC** — four files, compiled with `swiftc` (no Xcode):
   - `main.swift` — entry point, creates NSApplication
   - `AppDelegate.swift` — window creation, PDF loading, NSEvent monitor
   - `AnimaPDFView.swift` — PDFView subclass with keyboard + mouse handling
   - `FitzBridge.swift` — subprocess bridge to anima_helper.py

### Verified Working (Swift PoC)

- PDF renders in a window with trackpad scrolling and zoom
- Text selection by dragging
- ENTER with selection → comment dialog → highlight created via fitz
- Double-click on existing highlight → edit comment dialog (pre-filled)
- Single-click highlight + Delete → highlight removed
- Hit-testing works via PDFPage.annotation(at:) and bounds.contains()
- UUID reading works via annotationUUID() — even for PDF-XChange Viewer's
  non-standard UUID format (missing dashes)
- Opacity preserved on edit-comment (original value re-applied before update)
- Popup created for highlights that lack one
- App appears in Cmd+Tab (setActivationPolicy .regular)

### Known Issues

- **Scroll drift on reload**: after fitz saves and PDFKit reloads the document,
  the view shifts slightly. Same issue as Python PoC. Not a blocker — the
  dual-write approach (Milestone 1) eliminates reload entirely.

- **Appearance stream regeneration**: when fitz calls `annot.update()`, it
  regenerates the annotation's appearance stream. Highlights edited by fitz may
  render slightly differently in PDF-XChange Viewer (visual only — underlying
  data is preserved). PDFKit (Anima) renders consistently regardless.

- **No Cmd+Q**: command-line app has no menu bar. Close via window button or
  Ctrl+C. Needs menu bar setup for production.

- **No app icon**: placeholder "exec" icon in Cmd+Tab. Needs .app bundle.

---

## Key Technical Findings

### Swift vs PyObjC for PDFView

| Capability | PyObjC | Swift |
|---|---|---|
| keyDown override in PDFView subclass | ❌ Never fires | ✅ Works (with NSEvent monitor as backup) |
| mouseDown override | ❌ Swallowed by PDFDocumentView | ✅ Fires correctly |
| Hit-testing highlights | Not tested (mouse events broken) | ✅ annotation(at:) + bounds fallback |
| PDFSelection API | Works but method names mangled | ✅ Clean, documented |
| print() in NSView subclass | N/A | ⚠️ Must use Swift.print() (NSView.print = "send to printer") |
| Non-optional returns | N/A | ⚠️ guard let wrong for selectionsByLine(), index(for:) |
| App activation | Works | ⚠️ Needs setActivationPolicy(.regular) for keyboard focus |

### Architecture Pattern: CLI Helper

The `anima_helper.py` CLI tool pattern works well:
- Clean separation: Swift handles UI, Python handles PDF writing
- Testable independently from Terminal
- Coordinate contract: helper receives fitz-native coords, doesn't know about callers
- UUID passed in from Swift (caller controls identity)
- Exit code 0/non-zero for success/failure, stdout for return data, stderr for errors
- Subprocess overhead is negligible for annotation operations

### Swift Gotchas Encountered

1. `print()` inside NSView subclasses is ambiguous — use `Swift.print()`
2. `selectionsByLine()` returns `[PDFSelection]` not Optional — don't use `guard let`
3. `document.index(for:)` returns `Int` not Optional — same issue
4. Command-line GUI apps don't get keyboard focus without `setActivationPolicy(.regular)`
5. `Process.executableURL` needs absolute path — use `FileManager.default.currentDirectoryPath`
6. First `swiftc` compile is slow (type checker overhead) — normal

---

## File Inventory

### Swift PoC (`~/Projects/anima-swift-poc/`)
```
main.swift              — entry point
AppDelegate.swift       — window, PDF loading, event monitor
AnimaPDFView.swift      — PDFView subclass, keyboard + mouse handling
FitzBridge.swift        — subprocess bridge to Python helper
anima_helper.py         — CLI tool (add/edit/delete highlights via fitz)
input.pdf               — test PDF (Dzogchen article)
input_-_original.pdf    — unmodified backup
.venv/                  — Python venv with PyMuPDF
```

### Python PoC (separate folder, from previous session)
```
poc_pyobjc.py           — v7, working PyObjC PoC
round_trip_test.py      — annotation verification script
extract.py              — pdf-annot extraction module (reference)
annotation.py           — Annotation dataclass (reference)
```

### Project docs
```
GOALS.md                — project vision, architecture decision
TODO.md                 — milestone-organized task list with status
HANDOVER.md             — this file
```

---

## Open Decision: Python or Swift?

The next session should start with this discussion. Key points:

**For Swift:**
- Mouse events work — the core hypothesis is confirmed
- Path to persistent highlight mode is clear (mouseUp override + dual-write)
- Native macOS integration (app bundle, code signing, URL schemes)
- PDFKit is a natural fit in Swift
- Long-term investment in Apple ecosystem knowledge

**For Python/PyObjC:**
- Frank's expertise is in Python
- Direct fitz integration (no subprocess overhead)
- Faster iteration for prototyping
- Mouse event problems might be solvable with deeper PyObjC investigation
  (though this was not achieved in the PoC session)

**The decisive test** (not yet done): can Swift achieve persistent highlight mode?
This requires mouseUp override → get selection → create highlight → dual-write
(PDFKit in-memory + fitz save, no reload). If this works smoothly in Swift,
the case for Swift is very strong. If it requires fighting PDFKit's selection
handling, the advantage narrows.

---

## Suggested Next Steps

1. **Decide: Swift or Python** — based on PoC experience and the analysis above
2. **If Swift**: implement dual-write (eliminate reload), then persistent highlight mode
3. **If Python**: investigate deeper PyObjC mouse event solutions, or accept ENTER workflow
4. **Set up proper project structure** — Git repo, decide on single vs dual repo
   (Swift app + Python helper), define test strategy
5. **Xcode setup** (if Swift) — create a proper Xcode project, learn the IDE

---

## Frank's Collaboration Preferences

- **Discuss → Approve → Implement** framework (strictly followed)
- **Drop-in file replacements**, not code snippets for manual patching
- Professional but friendly tone
- Trace numbers cell by cell before defending financial model positions
- Uses German Excel (semicolon-delimited CSV, UTF-8 BOM)
- PyCharm for Python, will use Xcode for Swift
- macOS Tahoe, M4 MacBook
- Level 0 in Swift/Xcode — explain Apple ecosystem concepts as they come up
