# History

(Note: "I" in the following paragraphs refers to the user, "you" to you as the AI model.)

## Charter

The resolved-work record: *what* shipped, *when*. This file answers exactly one question -- "has X been done already, and in which session?" -- and nothing else. It lives in the repo but **outside the per-session filesdump**: it is uploaded only at the end of a session, at the moment the conversation is longest, the context budget tightest, and the remaining work most judgement-heavy. Every word here is paid for at that most expensive moment, so this file is deliberately the tersest artefact in the project.

## Entry rules

- One bullet per resolved item: date + what shipped. One line preferred, two lines maximum.
- No rationale, no alternatives-considered, no design narrative. Durable contracts and their "why" belong in `README.md` or `TARGET_ARCHITECTURE.md`; open work in `TODO.md`; direction in `GOALS.md`. An entry may *end* with a pointer to where the reasoning lives; it may never *contain* the reasoning.
- If an entry resists compression because its reasoning exists nowhere else, the wrong file is being edited: move the reasoning to its owning artefact first, then record the one-liner here.
- Superseded or no-longer-relevant entries are deleted, not annotated. Git history preserves everything; this file describes the past only as far as it still serves the present.
- **Ownership:** I maintain this file myself, transcribing entries from the struck-through handover notes in `TODO.md` (or from a one-liner drafted together in chat when a session runs from another artefact). You draft those notes in HISTORY-ready form -- dated, one line, no rationale -- but you never edit this file directly.

See "Workflow for the Whole Session (CRITICAL)" in `LLM_INSTRUCTIONS.md` for when this file is updated. For forward work see `TODO.md`; for direction `GOALS.md`; for the architecture as it stands `README.md`.

---

## Foundation

- Xcode project setup (.app bundle, menu bar, Cmd+Q); sandbox disabled for filesystem access
- Git repo on GitHub (private); `.editorconfig`; `make format` (SwiftFormat + black)
- Makefile cleanup: `black` covers `tests/`; dead swiftc variables removed (2026-07-11)

## Dual-Write Architecture

- Hybrid PDFKit (render) + fitz (write); incremental save preserves existing annotations; no document reload during session, eliminating scroll drift (contract: `README.md` §Architecture)
- Dual-write for highlight creation, comment editing, and deletion
- Dialog focus fix (`isShowingDialog` prevents duplicate Enter handling)

## Highlight Workflow

- ENTER with text selection creates highlight; highlights start without comment (double-click to add later)
- Persistent highlight mode (toggle; mouseUp = instant highlight)
- Highlight deletion via click + Delete key

## Sidebar (Comment Cards)

- Right-side fixed-width panel; cards anchor-aligned to highlights with collision avoidance; per-page architecture for efficient rebuilds; scroll sync with PDF
- Bidirectional emphasis (card ↔ highlight), unified with the Delete-key target; emphasis preserved through rebuilds
- Live updates via `SidebarUpdateDelegate` + per-page re-extraction on mutation
- Command comments ("link", "H1"–"H9") rendered in muted gray

## Comment Input Panel

- Custom modal `NSPanel` replacing `NSAlert`: Escape saves, Enter inserts newlines; styled to match cards; resizable/draggable with session-remembered geometry

## Popup Suppression

- Native PDFKit popup squares eliminated on load; comment text migrated to custom `/AnimaComment` key, `/Popup` links severed before rendering (contract: `README.md`)
- X-Ray mode toggle rehydrates popups for debugging

## Bookmarks

- Bookmark persistence and creation (2026-07-15): named whole-page bookmarks as JSON in the PDF catalog's private `/AnimaBookmarks` key; helper commands, `FitzBridge` + `BookmarkManager`, `Cmd+B` with duplicate handling. Details: `README.md` §Bookmarks
- JumpStation (2026-07-15): `Cmd+J` modal bookmark picker with keyboard navigation and `Cmd+D` deletion; prefix filtering deferred

## Reading Ergonomics

- Reader command-key migration (2026-07-15): bare `H`/`P`/`G` moved to `Cmd+H`/`Cmd+P`/`Cmd+G`
- Window frame and split-divider persistence via autosave; sidebar width stable during live resize (2026-07-14)
- Page-aware window captions, e.g. `(Albini 2013) -- 12 of 34` (2026-07-14)

## Navigation

- Jump to beginning/end (`Cmd+Home`/`Cmd+End`, `Home`/`End`); Page Up / Page Down (one screenful)
- Goto page via minimal native dialog, fails fast on invalid input (2026-07-14)
- Clean launch: window hidden until restore + load complete, no empty-window flash (2026-07-14)
- Forward-only search (2026-07-14): `Cmd+F` PDF text, `Cmd+Shift+F` comments, `F3` next hit, no wrapping; `Esc` clears transient state in ladder order; search can never create a highlight
- Per-PDF last-page persistence (2026-07-17): `/AnimaLastPage` catalog key; persisted only on document replacement and quit. Details: `README.md` §Last-Page Restoration
- Far-jump seam (2026-07-19): `AnimaPDFView.farJump(to:)` overloads are the single execution point for goto page, both finds, `F3`, bookmark jumps, and same-document `pdf://` links; `restore(toPageIndex:)` bypasses it deliberately. Details: `TARGET_ARCHITECTURE.md` §6.4
- JumpStack (2026-07-19): `Cmd+E` / `Cmd+R` walk an unbounded in-memory history of page indices, recorded by the far-jump seam for all six far-jump sources and cleared on document change; an active find is left untouched. Details: `docs/JUMPSTACK_DESIGN.md

## macOS Integration

- Open via command-line argument and Finder double-click; registered PDF viewer (`CFBundleDocumentTypes`)
- Helper/venv paths resolved from single `projectRoot` constant owned by `AppDelegate`
- Active-document hot replacement (2026-07-17): `loadDocument(url:)` is the single seam for cold launch and hot open; outgoing search/emphasis/selection state cleared, parse failure preserves the current document
- `pdf://` URL scheme claimed (2026-07-18): `CFBundleURLTypes` entry independent of the document-type claim; legacy `PDFHandler.app` route retired. Details: `README.md`, `TARGET_ARCHITECTURE.md`
- `PdfAnnotationsBridge` (2026-07-18): resolver subprocess seam per `TARGET_ARCHITECTURE.md` §6.2; `ResolveOutcome` carries the resolver's stderr verbatim to the user. Details: `README.md` §The pdf-annotations Boundary
- `pdf://` opening flow (2026-07-18): Obsidian links now resolve, activate or replace the reader document, honor explicit page targets, restore position without one, and surface resolver or URL failures. Details: `README.md`, `TARGET_ARCHITECTURE.md`
- Same-file reopen is a no-op (2026-07-19): `loadDocument(url:)` declines an unpaged open of the document already in the reader, preserving page, find, emphasis, selection, and JumpStack.
- 2026-07-19: Phase D (`TARGET_ARCHITECTURE.md` cleanup) complete. `windows_server/README.md` banner added in pdf-annotations; `PDFHandler.app` decommissioned and trashed; Anima re-registered as sole `pdf://` handler via Finder launch; acceptance 8(a)-(c) passed. `TARGET_ARCHITECTURE.md` moved to `docs/` and marked complete. The macOS-native toolchain -- Anima + `pdf_annot.resolve` + Obsidian -- is now fully established.
- Open dialog design approved. `docs/OPEN_DIALOG_DESIGN.md` written and approved; absorbs the `Cmd+O` backlog item. Key decisions: keyboard-driven launcher over the controlled collection (`NSOpenPanel` consciously rejected); modeless interaction -- letters always filter, arrows always select, the only state variables are the filter string and the selection index; snap-to-first selection after every filter change; display-only filter label as the diagnostic for the empty-match state; first-occurrence match marking; panel built as a `JumpStationPanel` sibling with duplication accepted until the JumpStation transfer yields a second concrete example; search path in `UserDefaults`, seeded via `make`; entry through the xib's existing "Open..."/`Cmd+O` item by implementing `openDocument(_:)` on `AppDelegate` -- no xib changes.
- Open dialog shipped (2026-07-28): Cmd+O launches a keyboard-filtered picker over the whole PDF collection, sorted most-recently-touched first -- any of 1,600 catalogued PDFs now one keystroke away. Two implementation bugs found and fixed: missing @IBAction bridging, NSApp.stopModal() timing trap. Details: README.md, TODO.md.

## Testing

### Python (pytest)
- Helper round-trip (create/edit/delete), edge cases, incremental-save preservation, `/NM` UUID at xref level, QuadPoints fidelity, comment clearing, opacity regression guard
- Bookmark and last-page commands covered incl. invalid pages and native-TOC preservation
- Comment-clear pinned for popup-less annotations, the guard `GOALS.md` names for the parked lifecycle redesign (2026-07-15)

### Swift (XCTest)
- `SidebarExtractor`: golden JSON, multi-page and per-page extraction, reassembly parity
- In-memory annotation round-trip; y-flip and QuadPoints construction pinned as pure-function tests (2026-07-11)
- Real subprocess boundaries pinned: `FitzBridge` add-highlight and last-page round-trips, `BookmarkManager` persistence (2026-07-15/17)
- Cross-page selection pinned as intentionally page-scoped (2026-07-15)
- JumpStack traces pinned as pure value-type unit tests (2026-07-19): `JumpStackTests.swift`, no `PDFView` and no fixture PDF.

## Refactoring

- `AnnotationManager` extracted from `AnimaPDFView`: all annotation CRUD in a context-per-call toolbox class; view reduced to events, hit-testing, mode management
- Quad math extracted as pure static functions, removing a hand-copied duplicate in tests (2026-07-11)

## Documentation & Process

- `TARGET_ARCHITECTURE.md` phase split + `GOALS.md` Phase 4 (2026-07-18): far-jump seam and JumpStack lifted into their own TA Phase C; rationale lives in those files
- Architecture review of reader functionality and Phase 2 opening paths (2026-07-16): findings and priorities folded into `TODO.md` and `GOALS.md`
- Architecture review, no-code session (2026-07-11): full source read-through; findings triaged into `TODO.md` and `GOALS.md`
- `GOALS.md` established with Current Session Pointer (2026-07-11); `TODO.md` restructured from first daily-use feedback (2026-07-11)
- `CHANGELOG.md` renamed to `HISTORY.md` (2026-07-11)
