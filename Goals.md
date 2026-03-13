# Anima — Goals

### UI layer: open decision
Two PoCs have been built:

**Python/PyObjC PoC (v7):**
- (+) Frank's home language, fast iteration
- (+) Direct fitz integration (no subprocess needed)
- (−) Mouse event handling broken (PDFView subclass overrides don't fire)
- (−) Persistent highlight mode not achievable
- (−) PyObjC method signatures are fragile and poorly documented

**Swift PoC:**
- (+) Mouse events work — mouseDown override fires in PDFView subclass
- (+) Hit-testing on highlights works (PDFPage.annotation(at:) + bounds check)
- (+) Keyboard events work (NSEvent monitor + keyDown override with dedup)
- (+) Native Apple framework integration — PDFKit is a natural fit
- (+) Path to proper .app bundle, code signing, App Store (if ever wanted)
- (−) Frank is learning Swift from scratch
- (−) Requires Xcode for production app (PoC compiled with swiftc)
- (−) fitz integration via subprocess (Python helper), not direct

**Decision criteria for next session:**
- Can Swift achieve persistent highlight mode (mouse-up → immediate highlight)?
  This is the key usability feature. Deferred until dual-write eliminates reload.
- Is the Swift learning curve manageable given the rest of the project scope?
- Does the subprocess bridge to Python feel acceptable long-term?

## Integration with Existing Toolchain

- `pdf-annot` pipeline: extracts highlights+comments from PDFs into Obsidian
  - Uses `fitz` — Anima's annotations are fully compatible (verified in both PoCs)
  - Standard `/Annot` with `/Subtype /Highlight`, `/Contents` for comments
  - QuadPoints for precise multi-line highlighting
- `pdf://` URL handler: opens PDFs at specific pages from Obsidian links
  - Currently routes through Windows Parallels → PDF-XChange Viewer
  - Future: route directly to Anima on macOS (eliminates Parallels dependency)
- Obsidian "The Studio": bibnotes reference PDFs via `pdf://HASH?page=N`
