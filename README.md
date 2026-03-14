# Anima

**A minimal, no-frills PDF reader for annotation work.**

Latin *anima* — "soul": what's left when you strip everything else away.

---

## Vision

Anima exists to serve one workflow: reading academic papers and wisdom tradition
texts, highlighting passages, and adding comments. It replaces PDF-XChange Viewer
in a macOS-native toolchain that flows from PDF → highlights → Obsidian notes.

**Core Philosophy:**

- **Minimalism**: Open. Read. Highlight. Comment. Save. That's it.
- **Non-destructive**: Incremental save via fitz preserves all existing annotations.
- **Toolchain-native**: Annotations are fully compatible with the `pdf-annotations`
  extraction pipeline and the `pdf://` URL scheme for Obsidian integration.
- **Single user**: Built for Frank. Configuration in code, not preferences dialogs.

**What Anima Does NOT Do:**

Print, sign, fill forms, edit PDF content, draw, stamp, redact, PDF/A compliance,
thumbnail panels, bookmarks, touch-optimized UI, preferences dialog, or anything
that adds complexity without serving the highlight+comment workflow.

---

## Architecture

Anima uses a hybrid approach: **PDFKit for rendering**, **fitz for writing**.

```mermaid
graph TB
    subgraph "Anima (Swift / macOS)"
        UI[PDFView Subclass]
        DW[Dual-Write Controller]
        FB[FitzBridge]
    end

    subgraph "Python Backend"
        AH[anima_helper.py]
        FZ[fitz / PyMuPDF]
    end

    PDF[(PDF File)]

    UI -->|user action| DW
    DW -->|in-memory PDFAnnotation| UI
    DW -->|subprocess call| FB
    FB -->|CLI args + JSON| AH
    AH -->|incremental save| FZ
    FZ -->|read/write| PDF
    UI -->|read for display| PDF
```

### Why Hybrid?

PDFKit's `writeToURL` is destructive to existing annotations:
- Loses opacity values (-1 instead of 0.4)
- Loses annotation IDs (the `/NM` field)
- Converts timezone representations in dates
- Doubles file size (full rewrite instead of incremental)
- Subtly shifts annotation rect coordinates

fitz's `save(incremental=True)` preserves everything. PDFKit remains ideal for
rendering, scrolling, text selection, zoom, and hit-testing.

### Dual-Write Pattern

When creating, editing, or deleting highlights during a session:

1. **Persist to disk** — call `anima_helper.py` via subprocess, which uses fitz
   to write the annotation with incremental save.
2. **Update in-memory** — add, modify, or remove a `PDFAnnotation` in PDFKit's
   in-memory document for immediate display.
3. **No reload** — the document is never reloaded during a session, eliminating
   the scroll drift that plagued both PoCs.

On next app launch, PDFKit loads the fitz-written file from disk. The file is
the single source of truth.

### Coordinate Systems

This is the critical cross-language contract:

- **PDFKit**: origin at **bottom-left**, y increases upward
- **fitz**: origin at **top-left**, y increases downward
- **Conversion**: `y_fitz = page_height - y_pdfkit`

The coordinate flip happens in Swift (`AnimaPDFView`) before calling the helper.
The helper receives fitz-native coordinates only — it has no knowledge of PDFKit.

### UUID Contract

Every annotation gets a UUID stored in the PDF `/NM` field. Swift generates UUIDs,
passes them to the helper via CLI arguments, and uses them for hit-testing and
identification. The helper sets `/NM` via fitz's xref API (`doc.xref_set_key`).

---

## Current Status

| Feature                  | Status      | Notes                                              |
|--------------------------|-------------|----------------------------------------------------|
| **PDF Rendering**        | ✅ Complete  | PDFKit, including Internet Archive layered PDFs    |
| **Continuous Scroll**    | ✅ Complete  | Native trackpad scrolling                          |
| **Text Selection**       | ✅ Complete  | Drag to select, per-line quad extraction           |
| **Highlight Creation**   | ✅ Complete  | ENTER with selection, dual-write, no reload        |
| **Comment Dialog**       | ✅ Complete  | Add/edit comments via NSAlert                      |
| **Comment Editing**      | ✅ Complete  | Double-click highlight, dual-write update          |
| **Highlight Deletion**   | ✅ Complete  | Click + Delete key, dual-write removal             |
| **Incremental Save**     | ✅ Complete  | fitz preserves all existing annotations            |
| **pdf-annot Compatible** | ✅ Complete  | Round-trip verified with extraction pipeline       |
| **Xcode Project**        | ✅ Complete  | .app bundle, menu bar, Cmd+Q                       |
| **Persistent Highlight** | 🔜 Next     | mouseUp → immediate highlight (no ENTER needed)    |
| **Sidebar**              | 🚧 Planned  | Comment cards panel (Milestone 1)                  |
| **Tabs**                 | 🚧 Planned  | Multi-PDF in single window (Milestone 1)           |
| **pdf:// URL Handler**   | 🚧 Planned  | Open PDFs from Obsidian links (Milestone 2)        |

---

## Integration with Existing Toolchain

Anima is one piece of a larger workflow for academic study and contemplative practice:

```
PDF reading + highlighting (Anima)
        ↓
Annotation extraction (pdf-annotations)
        ↓
Obsidian bibnotes with highlights + comments
        ↓
Zettelkasten: idea notes, workbenches, Folgezettel sequences
```

- **`pdf-annotations`**: Extracts highlights and comments from PDFs into Obsidian
  Markdown notes. Uses fitz — Anima's annotations are fully compatible. Standard
  `/Annot` with `/Subtype /Highlight`, `/Contents` for comments, `QuadPoints`
  for precise multi-line highlighting.

- **`pdf://` URL scheme**: Obsidian bibnotes reference PDFs via `pdf://HASH?page=N`.
  Currently routes through a Windows Parallels bridge to PDF-XChange Viewer.
  Milestone 2 registers Anima as the native macOS handler, eliminating the
  Parallels dependency entirely.

- **Obsidian "The Studio"**: The Zettelkasten knowledge management system where
  bibnotes, idea notes, and workbenches live. Anima serves as the PDF reading
  layer that feeds this system.

---

## Project Structure

```
anima/
├── Anima/                          ← Xcode project container
│   ├── Anima/                      ← Swift source files (app target)
│   │   ├── AnimaPDFView.swift      ← PDFView subclass: keyboard, mouse, dual-write
│   │   ├── AppDelegate.swift       ← Window setup, PDF loading, event monitor
│   │   ├── FitzBridge.swift        ← Subprocess bridge to Python helper
│   │   ├── Assets.xcassets/        ← App icon and colors
│   │   └── Base.lproj/            ← MainMenu.xib (menu bar)
│   ├── Anima.xcodeproj/           ← Xcode project file
│   ├── AnimaTests/                ← Swift Testing unit tests
│   └── AnimaUITests/              ← UI tests (unused)
├── tools/
│   ├── anima_helper.py            ← CLI: add-highlight, edit-comment, delete-highlight
│   ├── concat_files.py            ← Filesdump generator for LLM sessions
│   └── requirements.txt           ← Python dependencies (PyMuPDF)
├── data/
│   └── input_original.pdf         ← Test PDF (unmodified backup)
├── tests/                         ← Python tests (future)
├── .venv/                         ← Python virtual environment
├── CRITICAL_RULES.md              ← Non-negotiable collaboration rules
├── LLM-instructions.md            ← AI session context and conventions
├── TODO.md                        ← Task list with milestones
├── HANDOVER.md                    ← Session handover notes
├── Makefile                       ← Build, setup, and utility targets
├── manifest.lst                   ← File list for filesdump generation
├── .editorconfig                  ← Editor settings (LF line endings, indentation)
└── .gitignore
```

### Module Overview

**`AnimaPDFView.swift`** — The core of the app. Subclasses `PDFView` to intercept
keyboard and mouse events. Handles highlight creation (with dual-write), comment
editing, highlight deletion, hit-testing, and coordinate conversion from PDFKit
space to fitz space.

**`AppDelegate.swift`** — Creates the window, loads the PDF, sets up the NSEvent
monitor as a fallback for keyboard events (PDFKit's internal `PDFDocumentView`
sometimes captures keyboard focus).

**`FitzBridge.swift`** — Static methods that call `anima_helper.py` via `Process()`
(Swift's subprocess equivalent). Captures stdout/stderr, checks exit codes, and
resolves the Python executable from the project's `.venv`.

**`anima_helper.py`** — Standalone CLI tool with three subcommands: `add-highlight`,
`edit-comment`, `delete-highlight`. All coordinates in fitz space. Incremental save
preserves existing annotations. Tested independently from Terminal.

---

## Development

### Prerequisites

- **Xcode** (macOS, with macOS SDK)
- **Python 3** with venv support
- **SwiftFormat** (`brew install swiftformat`) — Swift code formatting

### Setup

```bash
make setup    # Create Python venv, install PyMuPDF
```

### Build & Run

Open `Anima/Anima.xcodeproj` in Xcode, then **Cmd+R** to build and run.

For command-line Swift builds (without Xcode):
```bash
make build    # Compile via swiftc
make run      # Build + run
```

### Testing

```bash
make test           # Run Python tests (quiet)
make test-verbose   # Run Python tests with output
```

Swift tests run via Xcode: **Cmd+U** or **Product → Test**.

### Code Formatting

```bash
make format   # Format Swift (SwiftFormat) and Python (black) files
```

### Utilities

```bash
make showtree     # Display project structure
make filesdump    # Generate context dump for LLM sessions
make clean        # Remove build output, venv, cache
make help         # Show all targets
```

---

## Technical Notes

### Swift Gotchas

- `print()` inside `NSView` subclasses is ambiguous (NSView.print = "send to
  printer"). Use `Swift.print()` for console output.
- `selectionsByLine()` returns `[PDFSelection]`, not Optional — don't `guard let`.
- `document.index(for:)` returns `Int`, not Optional — same issue.
- Command-line GUI apps need `setActivationPolicy(.regular)` for keyboard focus.
  Not needed in Xcode .app bundles.

### Appearance Stream Caveat

When fitz calls `annot.update()`, it regenerates the annotation's appearance stream
(the low-level PDF drawing instructions). Highlights edited by fitz may render
slightly differently in PDF-XChange Viewer compared to annotations originally
created by Viewer, even though the underlying data (color, opacity, coordinates)
is identical. PDFKit renders them consistently regardless.

### Background

Frank is learning Swift from scratch for this project. Python and PDF annotation
internals are his area of expertise. The hybrid Swift+Python architecture
leverages both: Swift for native macOS UI, Python for the annotation backend
where fitz knowledge is essential.
