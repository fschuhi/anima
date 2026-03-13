**A minimal, no-frills PDF reader for annotation work.**

Latin *anima* — "soul": what's left when you strip everything else away.

## Core Philosophy

- Open. Read. Highlight. Comment. Save. That's it.
- No forms, no signatures, no PDF/A, no drawing, no stamps, no redaction,
  no preferences dialog, no ribbon UI, no "intelligent" features.
- Single user (Frank). Configuration in code.

## What Anima Does

1. **Opens PDFs** — including Internet Archive layered PDFs
2. **Continuous scroll** — two-finger trackpad scrolling (native macOS)
3. **Highlights text** — single color (light pink), standard PDF `/Highlight` annotations
4. **Comments on highlights** — stored in annotation `/Contents` field
5. **Shows comments in a sidebar** — right-side panel with cards per highlight
6. **Saves non-destructively** — incremental save via fitz, existing annotations untouched
7. **Tabs** — multiple PDFs in a single window, browser-style tab switching
8. **Registers as default PDF viewer** — on macOS

## What Anima Does NOT Do

- Print, sign, fill forms, edit PDF content, draw, stamp, redact
- PDF/A, PDF/B, PDF/X compliance
- Thumbnail panel, bookmarks panel
- Touch-optimized UI, finger gestures beyond standard trackpad
- Preferences dialog — all config in source code
- Anything that adds complexity without serving the highlight+comment workflow

## Architecture (proven in both PoCs)

### Core: hybrid PDFKit + fitz
- **PDFKit**: rendering, scrolling, text selection, zoom, hit-testing
- **fitz (PyMuPDF)**: writing annotations (incremental save), reading annotations
- **anima_helper.py**: CLI tool bridging fitz functionality
  (add-highlight, edit-comment, delete-highlight)

