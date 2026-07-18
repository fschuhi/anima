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

- JumpStation bookmark navigation and deletion (2026-07-15): `Cmd+J` now opens the modal `JumpStationPanel`, displaying bookmark names and normal 1-based page numbers in two columns. Mouse clicks, right-clicks, and double-clicks select rows without navigating; Up/Down move selection, Enter performs the jump through `AnimaPDFView`, and `Esc` closes the panel. `Cmd+D` confirms deletion of the selected bookmark, delegates persistence to `BookmarkManager`, refreshes the displayed list from helper-authoritative state, and closes the panel if the final bookmark was removed. An empty bookmark list produces an informational alert rather than an empty picker, and stale page targets fail with a reader-facing warning. The panel deliberately owns only temporary selection and keyboard interaction; `AnimaPDFView` owns PDFKit navigation and `BookmarkManager` owns session state and persistence coordination. Prefix input/filtering remains deferred as an independent enhancement.
- Bookmark persistence and creation (2026-07-15): added named whole-page bookmarks stored as JSON in the PDF catalog's private `/AnimaBookmarks` key. The implementation deliberately leaves the document's native `/Outlines` / table of contents untouched. Stored pages use fitz-native 0-based indices; reader-facing prompts display the corresponding 1-based page number. `anima_helper.py` now provides `list-bookmarks`, `set-bookmark`, and `delete-bookmark`; pytest covers missing-key listing, case-insensitive upsert and deletion, invalid 0-based pages, deletion failure, and native-TOC preservation. On the Swift side, `FitzBridge` exposes matching operations and `BookmarkManager` owns the active session's decoded list, reloading after successful mutations so helper-owned catalog semantics remain authoritative. `testBookmarkManagerPersistenceRoundTrip` exercises the real Swift -> Python -> PDF catalog -> reload boundary. `Cmd+B` now prompts for a bookmark name on the current page, detects duplicates case-insensitively, and offers `Re-point` or `Keep Existing`; at that point, bookmark navigation and deletion remained the next active work.

## Reading Ergonomics

- Reader command-key migration (2026-07-15): persistent highlight, X-Ray, and goto-page moved from bare `H`, `P`, and `G` to `Cmd+H`, `Cmd+P`, and `Cmd+G`. This deliberately reclaims macOS's conventional Hide and Print shortcuts: Anima is a focused personal reader, print is out of scope, and hiding its only window is not useful in the intended workflow. Manual verification confirmed bare keys no longer trigger reader modes and command-modified keys do.
- Civilized main-window and split-view behavior (2026-07-14): main-window frame now persists across launches through AppKit frame autosave; split-divider position also persists through split-view autosave. The sidebar holds its current width during ordinary live window resizing while the PDF pane absorbs the change, subject to the existing minimum widths. The first-run 300-point sidebar default is applied only after layout has settled and never overwrites a restored divider position. This removed the launch-time resize/sidebar-width jitter.
- Page-aware document captions (2026-07-14): the window title now uses a compact reading handle plus `current page of total pages`, for example `(Albini 2013) -- 12 of 34`. Controlled filenames use their leading parenthesized `pdf_id`; uncontrolled filenames fall back to their stem, abbreviated through the easily tunable `AnimaPDFView.uncontrolledDocumentHandleMaximumLength` constant (currently 40). `AnimaPDFView` is the single caption formatter, so H/P toggles no longer erase the document handle, and PDFKit page-change notifications keep the page number current.

## Navigation

- Jump to beginning/end (`Cmd+Home`, Cmd+End, Home, End)
- Page Up / Page Down (one screenful, Windows-style)
- Goto page (2026-07-14): bare `G` opens the smallest useful native AppKit page-number dialog. A valid 1-based page number in the displayed `1...pageCount` range navigates through `PDFView.go(to:)`; invalid or non-numeric input fails fast with an error that repeats the valid range and leaves the reader on its current page. This follows Anima's bare reader-command family (`H`, `P`, `G`) while deliberately leaving conventional `Cmd+G` available for future Find Next behavior.
- Clean window presentation at launch (2026-07-14): the nib-created main window is hidden until its frame autosave restoration, reader view setup, PDF load, and initial caption are complete. This removes the brief empty 480 x 360 `"Anima"` window flash; the first visible window is the configured reader.
- Cohesive forward-only search (2026-07-14): `Cmd+F` searches rendered PDF text and `Cmd+Shift+F` searches annotation comments only. Both begin at the current page and continue forward without wrapping; F3 advances the active search and reports "No more hits" at document end. PDF-text hits use PDFKit's temporary pale-green `highlightedSelections`, deliberately separate from annotation text selection, so search can never create a highlight even in persistent H mode. Comment-search matches receive thin pale-green sidebar borders, while the current F3 card receives a thicker pale-green border; moving to a result navigates to its PDF location and reveals the complete card in its local sidebar scroll view. The two search modes are mutually exclusive with annotation emphasis and with each other. Esc consistently clears the most immediate transient state -- PDF-text search, comment search, then annotation emphasis and its Delete-key target -- while clicking any annotation or card exits search and resumes normal annotation interaction.
- Per-PDF last-page persistence and restoration (2026-07-17): Anima now remembers each PDF's reading position. `anima_helper.py` gained `get-last-page`/`set-last-page`, storing a single fitz-native 0-based page index as a PDF string under the private catalog key `/AnimaLastPage` -- the same catalog mechanism as `/AnimaBookmarks`, kept as a separate scalar with its own lifecycle. `FitzBridge.getLastPage` returns the raw helper output as `String?` and `setLastPage` returns `Bool`, matching the bridge's transport-only-read / boolean-mutation convention. `AnimaPDFView` gained `currentPageIndex()` and `restore(toPageIndex:)`; the latter clamps a stale index to the last page and reuses the existing `page(at:)` + `go(to:)` primitive, and is deliberately transparent navigation outside any future JumpStack/`Cmd+R` history. `AppDelegate` orchestrates: it persists the outgoing page before the swap in `loadDocument(url:)` and the active page on quit in `applicationWillTerminate`, restores after `loadPDF`, and owns the `String -> Int` decode plus the unset (`-1`)/failure skip. Persistence happens only on replacement and on quit, not per page change, so each switch or quit appends one incremental save; the current page is read on demand from `pdfView` rather than cached. Pinned by `test_anima_helper.py::TestLastPage` (unset -> -1, round-trip, overwrite, out-of-range rejection) and `AnimaTests.testFitzBridgeLastPageRoundTrip` (the Swift -> Python -> fitz seam).

## macOS Integration

- Accept file open via command line argument
- Register as PDF viewer (Info.plist CFBundleDocumentTypes)
- Accept file open via double-click in Finder (`application(_:open:)`)
- Resolve helper/venv paths from single `projectRoot` constant
  (AppDelegate owns projectRoot; FitzBridge derives venv from helperPath)
- Active-document hot replacement (2026-07-17): `AppDelegate.loadDocument(url:)` became the single seam for both cold launch and hot open, replacing the old `application(_:open:)` `open -n` hint. The incoming PDF is parsed first; on success, outgoing reader state is cleared via `MainViewController.clearOutgoingDocumentState()` -> `AnimaPDFView.clearSearchAndSelection()` (PDF-text search, comment search, annotation/card emphasis, text selection, and the Delete-key target), bookmarks are reloaded through `BookmarkManager`, and the document is installed with `MainViewController.loadPDF(document:)`. Parse failures preserve the current document and show an alert instead of terminating; modal panels block replacement via `NSApp.modalWindow != nil`. Persistent highlight mode and X-Ray mode are reset during replacement so the new document opens in the default reading state. Automated coverage / a documented manual verification matrix for state clearing and failure preservation was deferred.
- `pdf://` URL scheme claimed by Anima (2026-07-18): `Info.plist` gained a `CFBundleURLTypes` entry (`PDF Hash Link`) claiming the `pdf` scheme, alongside the pre-existing `CFBundleDocumentTypes` claim. The two are independent Launch Services records -- `lsregister -dump` shows one claim with `flags: doc-type` / `bindings: com.adobe.pdf` / `rank: Alternate` and a second with `flags: url-type` / `bindings: pdf:` / `rank: Default` -- so claiming the scheme left Finder's PDF handling untouched. `LSHandlerRank` applies only to document types; every URL-scheme claim is registered as `Default`, which is why arbitration between two claimants is arbitrary and why the legacy handler had to be retired rather than out-ranked. `AppDelegate.application(_:open:)` now guards on `url.isFileURL` before anything else: file URLs keep the existing `didFinishLaunching` / `pendingFileURL` / `loadDocument(url:)` path bit-for-bit, while non-file URLs are diverted to the temporary `showSchemeProbeAlert(for:)`, which reports scheme, host (hash), `page` query and full URL and touches no document. Without that guard a `pdf://` link would reach `PDFDocument(url:)` and be reported to the reader as a damaged file. The probe is an `NSAlert` rather than `Swift.print` because a link click launches Anima through Launch Services, where stdout is invisible without `Console.app`; `runModal()` is called unconditionally, since on cold launch the URL arrives before `applicationDidFinishLaunching` and no window exists to host a sheet. `AppDelegate` also gained a `pdfAnnotationsRoot` constant (`/Users/fschuhi/Projects/pdf-annotations`), unused until Phase B step 5. It is deliberately a second absolute path rather than a sibling derived from a shared parent: the two projects are joined by the frozen resolver CLI contract, not by a shared filesystem layout, and either may move independently. The opposing case -- that fusing both paths under one root would act as a deliberate deterrent against prematurely extracting the PDF-identity module from `pdf-annotations` -- was considered and set aside; the deterrent is recorded as reasoning in that project's `TODO.md` instead of encoded in Anima's constants. The legacy `PDFHandler.app` AppleScript applet was moved from `~/Applications` to the Trash (deliberately not emptied; the `windows_server` README carries the full rebuild recipe), retiring the macOS -> HTTP POST -> Windows VM -> PDF-XChange-Viewer route. Verified by `plutil -p` against the built bundle's `Info.plist` (confirming the key survives the build rather than being overwritten by a generated plist), by the `lsregister -dump` records above, and accepted both via `open "pdf://VQGPEHE?page=4"` from Terminal and a real Obsidian link click -- the hash arrives case-preserved. Step 6 replaces the probe body with the parse -> resolve -> open pipeline at the same seam.
- `PdfAnnotationsBridge` -- the resolver subprocess seam (2026-07-18): Anima's dependency on the neighbouring `pdf-annotations` project, implemented per `TARGET_ARCHITECTURE.md` §6.2. One static method, `resolve(hash:pdfAnnotationsRoot:)`, runs `<pdfAnnotationsRoot>/.venv/bin/python3 -m pdf_annot.resolve <HASH>` with the process working directory set to `pdfAnnotationsRoot` (§3.1), capturing stdout and stderr. No hardcoded paths: the root is passed in per call by `AppDelegate`, which owns it as a constant -- the same philosophy that keeps `FitzBridge` free of paths of its own. It returns a nested `ResolveOutcome` enum (`.resolved(path:)` / `.failed(message:)`) rather than `FitzBridge`'s `String?`, because §3.3 requires the resolver's stderr to reach the user verbatim and a `nil` return discards exactly that. Swift's `Result<String, Error>` was considered and rejected: with no exit-code taxonomy (§3.3 specifies exit 1 for everything) the error side is never inspected, only displayed, so an `Error` type would wrap a string that every caller unwraps and throws away; promoting it is the right move if a taxonomy ever arrives. The asymmetry with `FitzBridge`, which keeps logging failures through `Swift.print`, was decided rather than inherited: `FitzBridge` calls Anima's own helper in Anima's own venv, where a failure is a developer failure, while this bridge consumes another project's declared interface, where an unknown hash or a duplicate `pdf_id` is a normal outcome of everyday library hygiene and must reach the user's eyes. The pipes are read before `waitUntilExit()`, deliberately reversing `FitzBridge.runPython`'s ordering and its latent pipe deadlock (`TODO.md`, "FitzBridge redesign"); the two reads are sequential rather than concurrent, which is safe three orders of magnitude below the ~64 KB pipe buffer given one path on stdout or a few lines on stderr, and the comment says so. Two off-contract guards compose their own prose: a nonzero exit with silent stderr, and exit 0 with empty stdout. Neither should occur after Phase A acceptance, but both would otherwise surface as an empty alert or hand an empty path to the opening flow -- and because the resolver lives in another project, the guards double as reverse documentation of the CLI protocol at the point where a violation would hurt. The hash is passed through untouched: `URLComponents` lowercases the URL host, and §3.1 puts normalization on the resolver's side. `AppDelegate.showSchemeProbeAlert(for:)` was rewired from step 4's "report what arrived" to "report what the resolver said" -- an empty-host guard short-circuits before touching the subprocess, success shows the resolved path plus the `page` value explicitly labelled as not acted upon, and failure shows the resolver's stderr verbatim, which is already the permanent shape step 7 calls for. The function keeps its now slightly stale name because step 6 deletes it. The diff against the previous `AppDelegate.swift` is confined to that one function and its doc comment. Accepted via `open "pdf://HASH"`, `open "pdf://HASH?page=12"`, and `open "pdf://ZZZZZZZ"` from Terminal plus real Obsidian link clicks; the duplicate case, verified at the resolver level in the previous session, was confirmed to travel intact through the bridge and `NSAlert` with its multi-line layout preserved. Approach chosen deliberately over writing the bridge unwired: exercising it through Launch Services, rather than through Xcode, is what tests the working-directory and environment assumptions §3.1 rests on.

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

- Phase split of `TARGET_ARCHITECTURE.md` and a new `GOALS.md` Phase 4 (2026-07-18): the far-jump seam and the JumpStack were lifted out of the `pdf://` work into their own TA Phase C (steps 9-11), with cleanup renumbered to Phase D (12-14). This dissolved the open question the `GOALS.md` pointer had been carrying -- whether to build the five-call-site seam mid-Phase-B or defer it -- by making it a sequence rather than a fork: Phase B now delivers "clicking a link opens the PDF at the requested page", Phase C adds "and the navigation is undoable". §6.4 and §6.5 were reshaped from prose MUSTs into Background plus Action Items, each naming the §6.3 amendment it will trigger, so a future session can see at a glance what is decided versus still owed. §6.3 step 4 gained the same-document page change as a direct `PDFView.go(to:)` call marked as the future seam call site -- a sixth call site rather than a rerouting of the existing five, chosen because the same-document click is the commonest case in the Obsidian-to-PDF workflow and a silent no-op there would read as a bug. §6.3 step 5 was decided to stay outside the seam permanently: the JumpStack is cleared on document change, so a jump performed while installing a new document has no pre-jump position to record. `GOALS.md` correspondingly scopes Phase 3 to TA Phases A, B, and D, and adds Phase 4 (Navigation Depth) for TA Phase C -- separate because the seam serves the five far-jump sources that predate `pdf://` and the JumpStack was a Navigation backlog item before this architecture existed; `pdf://` is the sixth consumer, not the reason. The `GOALS.md` pointer was returned to its charter length, shedding the resolved fork and the applet-Trash note that `TARGET_ARCHITECTURE.md` §7 already owns.
- Architecture review of recently added reader functionality and Phase 2 opening paths (2026-07-16): traced `Cmd+G`, PDF/comment search and `F3`, bookmark creation, JumpStation, and the end-to-end Open PDF action. Confirmed the existing `AppDelegate.loadDocument(url:)` -> `MainViewController.loadPDF(document:)` path as the correct active-document replacement seam, while identifying that replacement must explicitly retire document-specific PDF/comment search, annotation/card emphasis, selection, and Delete-target state. Promoted per-PDF last-page restoration ahead of reader-window drag-and-drop and `Cmd+O`; same-process multiple windows/tabs remain parked because they require first-class per-document reader sessions, while fast replacement plus persisted page and later JumpStack state is the chosen near-term proxy. Identified a small shared far-jump execution seam needed before JumpStack so goto, both searches/`F3`, and bookmark navigation can consistently record their origin without introducing a premature `NavigationManager`; JumpStack should retain a bounded history, provisionally five targets, in private PDF metadata. Rejected search-manager and broad command-controller extraction as premature, parked the outgrown `SidebarUpdateDelegate` name, and selected a concern-based split of `AnimaTests.swift` as the first filesdump-size improvement rather than restructuring production code for prompt size. Findings and priorities were folded into `TODO.md` and `GOALS.md`.
- Architecture review, no-code session: full read-through of all Swift and Python sources. Confirmed dual-write/coordinate/popup-suppression design; surfaced FitzBridge subprocess seam (pipe deadlock risk, per-operation latency), comment set/clear lifecycle fragility in cmd_edit_comment, cross-page selection truncation (accepted as intended page-scoped behavior), and window-title/mode-indicator conflict. Findings triaged into TODO.md and GOALS.md (2026-07-11)
- GOALS.md established: Current Session Pointer + strategic vision, added to manifest.lst (2026-07-11)
- TODO.md restructured: new UX Priorities section from first sustained daily-use feedback; review findings folded in; test specs for the comment-clear ordering and cross-page behavior added (2026-07-11)
- CHANGELOG.md renamed to HISTORY.md -- resolved-work archive, matching the session workflow in LLM_INSTRUCTIONS.md (2026-07-11)
