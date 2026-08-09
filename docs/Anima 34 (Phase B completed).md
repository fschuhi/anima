> [!note] User:
> Hi GPT! This is a continuation of previous conversations on `anima` (together with `pdf-annotations`). Please read the guide `FIRST_PROMPT.md`.

Assistant:
Hi Frank -- I have read `CRITICAL_RULES.md` first, then followed `FIRST_PROMPT.md`.

The `filesdump.txt` integrity check passes: its header declares **27 documents**, and its `END OF FILESDUMP` trailer also declares **27 documents**. I am treating this dump as the session's source of truth.

I understand and will follow:

-   Discuss -> Approve -> Implement, in that order.
-   No unsolicited files or code.
-   Complete drop-in replacements after approval, with only agreed changes.
-   Small, explainable steps rather than a solution dump.
-   Existing tests are the behavioral contract.
-   Inventory before reviewing/refactoring existing artefacts.
-   Your role as project manager and domain expert in Python/PDF annotation internals; my role is to provide technical judgment and teach the Swift/AppKit parts as needed.
-   The project's value-first and architecture-skepticism rules.

## Project position

The current work is Phase 3, `pdf://` integration.

`TARGET_ARCHITECTURE.md` Phase B step 5 is complete as of **July 18, 2026**: `PdfAnnotationsBridge` invokes the frozen `pdf_annot.resolve` CLI in the neighbouring project's venv, with the correct working directory, and returns either a resolved path or displayable failure prose.

The next action is Phase B **step 6**: replace `AppDelegate`'s temporary `showSchemeProbeAlert(for:)` behavior with the real `pdf://` opening pipeline described in `TARGET_ARCHITECTURE.md` section 6.3. Step 7's permanent alert plumbing follows as part of that flow, then real Obsidian-link acceptance testing in step 8.

## Local ownership for this change

The relevant seam is already correctly located in `AppDelegate`:

1.  `application(_:open:)` receives both file URLs and custom-scheme URLs.
2.  File URLs continue into the existing `loadDocument(url:)` path.
3.  Non-file URLs currently go to `showSchemeProbeAlert(for:)`.
4.  `PdfAnnotationsBridge` owns only hash -> filesystem-path resolution.
5.  `loadDocument(url:)` already owns safe replacement: parse-before-clear, outgoing last-page persistence, transient-state clearing, bookmark load, sidebar/document installation, and normal last-page restore.
6.  `AnimaPDFView` owns page navigation primitives, including `go(to:)` and `restore(toPageIndex:)`.

So this should be a localized `AppDelegate` change. The bridge, PDF loading lifecycle, and the future far-jump refactor stay separate unless the implementation proves a real missing seam.

## Two approaches

### 1\. Minimal linear pipeline in `AppDelegate` -- recommended

Replace the probe method with a private handler that directly implements section 6.3:

1.  Check the modal guard.
2.  Parse and validate `pdf://HASH?page=N`.
3.  Resolve the hash with `PdfAnnotationsBridge`.
4.  Compare the resolved path with the active document path.
5.  Same file:
    -   activate Anima;
    -   if a valid page was supplied, direct-navigate to it, with a comment marking this as the future far-jump seam call site.
6.  Different file:
    -   reuse the existing replacement machinery;
    -   ensure the URL page, when present, wins over last-page restore.

**Why this is the value-first option:** it adds the requested visible behavior without introducing a new opening-flow type, parser abstraction, or navigation coordinator prematurely.

**Main design detail to settle:** `loadDocument(url:)` currently always restores the stored last page. We would need a small optional opening-position input so URL page can override restore for a different document, while ordinary Finder opens keep existing behavior unchanged.

### 2\. Introduce a small parsed request value before wiring behavior

Create an internal `PDFLinkRequest`\-style value representing:

-   hash
-   optional 0-based page index

A parser would turn the incoming URL into that value, and a handler would consume it.

**Benefit:** malformed-link rules and 1-based -> 0-based conversion become particularly explicit and testable.

**Cost:** this is a structural layer with only one current consumer. It is clean, but may be more ceremony than Phase B needs. I would not choose it unless you specifically want the parsing logic independently unit-tested now.

## Suggested first implementation step

I recommend **Approach 1**, beginning only with the URL parsing and opening-flow design in `AppDelegate`, preserving the existing file-URL path unchanged. We should add or extend Swift tests for the decisions that can be tested without real Launch Services, then manually run the Phase B Obsidian acceptance cases after the code is in place.

Do you want to proceed with Approach 1, or do you prefer the explicit parsed-request type from Approach 2?

> [!note] User:
> Absolutely agree with Approach 1. First suggested implemention approved!
>
> (Exciting! I'm so happy to work with you on this really important point in the overall development. Just imagine the acceptance tests pass -- I would be able to use Anima daily, reinvigorating the motivation to dive deep into my PDF collection and truly live there!)

Assistant:
Denkt nach

Implemented the approved first step in one localized file: `AppDelegate.swift`.

What changes:

-   Keeps ordinary file URL opens on the existing `loadDocument(url:)` path.
-   Replaces the temporary `pdf://` probe alert with the real linear pipeline:
    -   modal guard
    -   parse hash and optional 1-based page
    -   resolve through `PdfAnnotationsBridge`
    -   same-document activation/jump
    -   different-document replacement through the existing safe loading flow
-   Adds cold-launch handling for `pdf://` URLs, so Anima does not accidentally load the development fallback before processing an Obsidian link.
-   Makes a URL page override last-page restoration for a different document.
-   Validates page range before clearing the current document, so an out-of-range URL leaves the active reader unchanged.
-   Leaves the direct URL same-document jump explicitly marked as the future Phase C far-jump seam call site.

No files are added. I have not changed `PdfAnnotationsBridge`, `AnimaPDFView`, tests, or documentation in this step.

`AppDelegate.swift`:

swift

```swift
`//
//  AppDelegate.swift
//  Anima
//
//  Created by Frank Schuhardt on 13.03.26.
//
//  Sets up the main window and injects the MainViewController (which holds
//  the NSSplitView). Also maintains an NSEvent monitor as a fallback for keyboard events.
//
//  PDF loading priority:
//    1. Finder double-click / "Open With" (pendingFileURL, set before launch completes)
//    2. Command-line argument (first argument ending in .pdf)
//    3. Dev fallback: projectRoot/data/input.pdf
//    4. Error message + exit if neither resolves
//
//  Hot replacement:
//    When Anima is already running, a second open request (Finder, Dock drop,
//    "Open With") replaces the displayed PDF via loadDocument(url:). The
//    outgoing document's transient reader state is cleared first; if parsing
//    fails, the current document is preserved and an alert is shown.
//
//  pdf:// opening:
//    Custom-scheme URLs follow a linear pipeline: modal guard -> parse ->
//    resolve -> same-document check -> open or jump. The resolver turns the
//    URL host into a local PDF path; AppDelegate owns all reader presentation
//    decisions after that boundary. During a cold launch, application(_:open:)
//    arrives before applicationDidFinishLaunching(_:), so the custom URL is
//    stored and handled only after the reader and persistence managers exist.
//
//  AppKit timing note:
//    When macOS launches Anima because the user double-clicked a PDF in Finder,
//    the call sequence is:
//      1. application(_:open:)               <- file URL arrives
//      2. applicationDidFinishLaunching(_:)  <- window gets set up
//    So open stashes the URL in pendingFileURL, and
//    applicationDidFinishLaunching picks it up. If Anima is already running
//    when a second file arrives, open fires with the window fully ready and
//    loadDocument(url:) performs the replacement.
//
//  Path resolution:
//    A single projectRoot constant is the source of truth for all derived
//    paths (helper script, dev fallback PDF). FitzBridge independently
//    derives the venv Python path from the helperPath it receives.
//    To move the project, change projectRoot here -- nothing else.
//    A second, independent constant (pdfAnnotationsRoot) locates the
//    neighbouring pdf-annotations project. It is deliberately not derived
//    from projectRoot: the two projects are joined by a frozen CLI contract,
//    not a shared filesystem layout.
//
import Cocoa
import Quartz
@main
class AppDelegate: NSObject, NSApplicationDelegate {
    // --- Single source of truth for project location ---
    // Change this one constant if the project moves.
    // FitzBridge derives the venv Python path from the helperPath.
    private let projectRoot = "/Users/fschuhi/Projects/anima"
    // --- Location of the pdf-annotations project ---
    // Deliberately a second absolute path rather than a sibling derived from
    // projectRoot. Anima consumes pdf-annotations only through its resolver
    // CLI (TARGET_ARCHITECTURE.md §2, §3); their co-location in ~/Projects is
    // a convenience, not part of the contract, and either project may move
    // independently. Consumed from Phase B step 5 onwards by
    // PdfAnnotationsBridge, which runs the resolver in this project's own
    // venv with this path as the process working directory.
    private let pdfAnnotationsRoot = "/Users/fschuhi/Projects/pdf-annotations"
    /// Absolute path to the Python helper, derived from projectRoot. Needed by
    /// the persistence managers at launch and by last-page persistence during
    /// document replacement and termination.
    private var helperPath: String { "\(projectRoot)/tools/anima_helper.py" }
    // Stable UserDefaults key used by AppKit to persist the main window's
    // frame between launches.
    private let mainWindowFrameAutosaveName = "AnimaMainWindow"
    @IBOutlet var window: NSWindow!
    var mainViewController: MainViewController!
    var eventMonitor: Any?
    var bookmarkManager: BookmarkManager!
    /// Set by application(_:open:) during a cold file launch, before the
    /// window exists. Consumed by applicationDidFinishLaunching.
    private var pendingFileURL: URL?
    /// Set by application(_:open:) during a cold custom-scheme launch, before
    /// the reader and its persistence managers exist. It is deliberately kept
    /// separate from pendingFileURL because a pdf:// URL is not a readable PDF
    /// file and must first cross the resolver boundary.
    private var pendingSchemeURL: URL?
    /// Tracks whether applicationDidFinishLaunching has completed.
    /// Used by application(_:open:) to distinguish cold launch from hot open.
    private var didFinishLaunching = false
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        mainViewController = MainViewController()
        window.contentViewController = mainViewController
        // Assigning this stable name makes AppKit restore the previously saved
        // frame if one exists, then keep saving later moves and resizes.
        if !window.setFrameAutosaveName(mainWindowFrameAutosaveName) {
            Swift.print("⚠️ Could not enable main-window frame autosave")
        }

        // --- Wire up the persistence managers ---
        mainViewController.pdfView.annotationManager = AnnotationManager(helperPath: helperPath)
        bookmarkManager = BookmarkManager(helperPath: helperPath)
        mainViewController.pdfView.bookmarkManager = bookmarkManager
        // A cold pdf:// launch must not fall through to command-line or dev
        // fallback opening. Its handler is responsible for either resolving
        // and loading the requested document or showing an alert with no
        // document change.
        if let schemeURL = pendingSchemeURL {            pendingSchemeURL = nil
            handleSchemeURL(schemeURL)
        } else {            // --- Determine which PDF to open ---
            guard let url = resolvePDFURL() else {                Swift.print("❌ No PDF to open. Pass a .pdf path as argument, double-click a PDF, or place input.pdf in data/.")
                NSApplication.shared.terminate(nil)
                return  // never reached, but satisfies the compiler
            }

            loadDocument(url: url)
        }

        // MainMenu.xib keeps this window hidden at launch. Present it only
        // after its restored frame, reader content, and document caption are ready.
        window.makeKeyAndOrderFront(nil)
        // --- Keyboard event monitor (fallback) ---
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self = self else { return event }
            if self.mainViewController.pdfView.handleKeyEvent(event) {
                return nil   // consumed
            }
            return event     // not ours
        }

        didFinishLaunching = true
    }

    // MARK: - Finder / Open With
    /// Called by macOS when the user double-clicks a PDF in Finder, uses
    /// "Open With", or drags a file onto the Dock icon.
    ///
    /// This is the modern URL-based variant (macOS 10.13+). macOS delivers
    /// file URLs directly -- no string-to-URL conversion needed.
    ///
    /// Timing: during a cold launch this fires BEFORE applicationDidFinishLaunching.
    /// In that case we stash the URL and let applicationDidFinishLaunching pick it up.
    /// During a hot open we replace the active document through loadDocument(url:).
    func application(_ application: NSApplication, open urls: [URL]) {        Swift.print("📂 application(_:open:) called with: \(urls)")
        guard let url = urls.first else { return }
        // Two kinds of URL reach this method. File URLs are PDFs from Finder,
        // "Open With", or a Dock drop, and keep the existing behavior.
        // Custom-scheme URLs (pdf://HASH?page=N) arrive from Launch Services
        // after an Obsidian link click and must resolve before they can enter
        // the document-loading path.
        guard url.isFileURL else {            if didFinishLaunching {                handleSchemeURL(url)
            } else {                pendingSchemeURL = url            }
            return
        }

        if didFinishLaunching {            // Hot open: replace the active document. Multiple URLs arriving
            // together are reduced to the first one.
            loadDocument(url: url)
        } else {            // Cold launch: stash the URL for applicationDidFinishLaunching.
            pendingFileURL = url        }
    }

    // MARK: - Custom URL Scheme
    /// Processes the complete Phase B pdf:// opening pipeline:
    /// modal guard -> parse -> resolve -> same-document check -> open or jump.
    ///
    /// The page conversion from the 1-based URL contract to Anima's internal
    /// 0-based page index occurs only in parseSchemeURL(_:). The resolver
    /// returns a filesystem path, after which AppDelegate owns reader behavior.
    private func handleSchemeURL(_ url: URL) {        // TARGET_ARCHITECTURE.md §6.3 step 1: do not interrupt an active modal
        // interaction and do not queue the request in v1.
        guard NSApp.modalWindow == nil else {            NSSound.beep()
            Swift.print("⚠️ pdf:// open declined while a modal dialog is active")
            return
        }

        guard let request = parseSchemeURL(url) else {            return
        }

        switch PdfAnnotationsBridge.resolve(
            hash: request.hash,
            pdfAnnotationsRoot: pdfAnnotationsRoot
        ) {
        case let .failed(message):            // The resolver's stderr is deliberate prose written for the user.
            // PdfAnnotationsBridge also supplies prose for off-contract process
            // failures, so this branch can show its message unedited.
            showSchemeAlert(
                title: "Could not open the linked PDF",
                message: message
            )

        case let .resolved(path):            let resolvedURL = URL(fileURLWithPath: path).standardizedFileURL
            if isCurrentDocument(resolvedURL) {                NSApp.activate(ignoringOtherApps: true)
                guard let pageIndex = request.pageIndex else {                    return
                }

                guard let document = mainViewController.pdfView.document else {                    return
                }

                guard (0..<document.pageCount).contains(pageIndex),
                      let page = document.page(at: pageIndex) else {                    showLinkedPageOutOfRangeAlert(
                        requestedPageNumber: pageIndex + 1,
                        pageCount: document.pageCount
                    )
                    return
                }

                // TARGET_ARCHITECTURE.md §6.3 step 4: this is intentionally a
                // direct navigation call in Phase B. Phase C replaces it with
                // the shared far-jump seam so Cmd+R can return here.
                mainViewController.pdfView.go(to: page)
                Swift.print("🔗 pdf:// link jumped within the open document to page \(pageIndex + 1)")
                return
            }

            // For a different document, loadDocument parses and validates the
            // target before it persists outgoing state or clears the reader.
            // A non-nil requested page deliberately wins over last-page restore.
            loadDocument(
                url: resolvedURL,
                preferredPageIndex: request.pageIndex
            )
        }
    }

    /// Parses one pdf:// URL into the pieces AppDelegate needs for the opening
    /// flow. The optional page is validated as a positive 1-based integer and
    /// converted immediately to Anima's internal 0-based representation.
    ///
    /// Unknown query items are ignored in v1. The contract defines only page;
    /// rejecting unrelated future additions here would make the scheme less
    /// extensible without improving today's behavior.
    private func parseSchemeURL(_ url: URL) -> (hash: String, pageIndex: Int?)? {        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.caseInsensitiveCompare("pdf") == .orderedSame,              let hash = components.host,              !hash.isEmpty else {            showSchemeAlert(
                title: "Invalid pdf:// link",
                message: "The link does not contain a PDF id.\n\n\(url.absoluteString)"
            )
            return nil
        }

        let pageItems = components.queryItems?.filter { $0.name == "page" } ?? []
        guard pageItems.count <= 1 else {            showSchemeAlert(
                title: "Invalid pdf:// link",
                message: "The link contains more than one page value.\n\n\(url.absoluteString)"
            )
            return nil
        }

        guard let pageItem = pageItems.first else {            return (hash: hash, pageIndex: nil)
        }

        guard let pageValue = pageItem.value,              let displayedPageNumber = Int(pageValue),
              displayedPageNumber >= 1 else {            showSchemeAlert(
                title: "Invalid page number",
                message: "The page in a pdf:// link must be a positive 1-based integer.\n\n\(url.absoluteString)"
            )
            return nil
        }

        return (hash: hash, pageIndex: displayedPageNumber - 1)
    }

    /// Returns true when the resolver path identifies the PDF currently shown
    /// in the reader. Standardizing both URLs handles ordinary path spelling
    /// differences without introducing symlink-resolution policy at this seam.
    private func isCurrentDocument(_ resolvedURL: URL) -> Bool {        guard let currentURL = mainViewController.pdfView.document?.documentURL else {            return false
        }

        return currentURL.standardizedFileURL == resolvedURL.standardizedFileURL    }

    /// Shows an opening-flow alert as a modal dialog. This intentionally works
    /// both before the main window is shown during a cold pdf:// launch and
    /// while an already-running Anima receives a hot link click.
    private func showSchemeAlert(title: String, message: String) {        let alert = NSAlert()
        alert.alertStyle = .warning        alert.messageText = title        alert.informativeText = message        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Explains a page range failure after a resolver success. The document is
    /// left untouched: for a different resolved PDF, loadDocument validates
    /// before it clears the outgoing reader; for the current PDF, the guard in
    /// handleSchemeURL(_:) prevents the direct jump.
    private func showLinkedPageOutOfRangeAlert(
        requestedPageNumber: Int,
        pageCount: Int
    ) {        showSchemeAlert(
            title: "Page unavailable",
            message: "The link requests page \(requestedPageNumber), but this PDF has \(pageCount) page(s)."
        )
    }

    // MARK: - PDF Loading
    /// Loads a PDF document into the main view, replacing any existing document.
    ///
    /// This is the single seam for cold-launch and hot-open file requests, and
    /// for resolved pdf:// links. It parses and validates the incoming document
    /// before clearing outgoing reader state, reloads bookmarks for the incoming
    /// file, and preserves the current document if parsing or installation fails.
    ///
    /// A preferredPageIndex comes only from a parsed pdf:// page query and is
    /// already 0-based. When supplied, it takes precedence over stored last-page
    /// restoration. The range check happens before the outgoing document changes.
    private func loadDocument(url: URL, preferredPageIndex: Int? = nil) {        // Guard: don't replace while an AppKit modal window is active. That covers
        // NSAlert, CommentInputPanel, JumpStationPanel, and any future modal panel.
        if NSApp.modalWindow != nil {            Swift.print("⚠️ Hot open declined while a modal dialog is active")
            return
        }

        let filePath = url.path
        // Parse first, before touching any outgoing state. If the file is not
        // a valid PDF, we want to preserve the current document exactly as it is.
        guard let document = PDFDocument(url: url) else {            Swift.print("❌ Failed to parse PDF: \(filePath)")
            showLoadFailureAlert(for: filePath)
            return
        }

        // A page requested by a pdf:// link must be valid in the incoming
        // document. Do this before saving the outgoing position or clearing the
        // current reader so an invalid link is a complete no-op.
        if let preferredPageIndex = preferredPageIndex,           !(0..<document.pageCount).contains(preferredPageIndex) {
            showLinkedPageOutOfRangeAlert(
                requestedPageNumber: preferredPageIndex + 1,
                pageCount: document.pageCount
            )
            return
        }

        // Capture the outgoing document's reading position before the swap, so
        // reopening that file later restores the page. Non-fatal if it fails.
        persistOutgoingLastPage()

        // From this point on we are committed to replacing the active document.
        // Clear all transient reader state tied to the outgoing document.
        mainViewController.clearOutgoingDocumentState()

        // Load bookmarks for the incoming file. A bookmark-read failure is
        // nonfatal and leaves the incoming document with an empty bookmark list.
        if !bookmarkManager.loadBookmarks(filePath: filePath) {
            Swift.print("⚠️ Could not load bookmarks for \(filePath); continuing with empty list")
        }

        // Install the new document.
        mainViewController.loadPDF(document: document)

        if let preferredPageIndex = preferredPageIndex {            // TARGET_ARCHITECTURE.md §6.3 step 5: document installation is not
            // a far jump. The future JumpStack is cleared on document change,
            // so no pre-jump reader position exists to record here.
            mainViewController.pdfView.restore(toPageIndex: preferredPageIndex)
            Swift.print("🔗 pdf:// link opened \(filePath) at page \(preferredPageIndex + 1)")
        } else {            // Ordinary Finder, command-line, and fallback opens preserve the
            // established last-page restoration behavior.
            restoreLastPage(filePath: filePath)
        }

        Swift.print("✅ Loaded PDF: \(filePath)")
    }

    /// Persists the currently displayed PDF's reading position to its private
    /// catalog metadata, so reopening that file later restores the page. Reads
    /// the page index on demand from the active pdfView (no cached observer).
    ///
    /// Non-fatal by contract: a missing document, missing URL, unreadable page,
    /// or helper failure is logged and skipped -- last-page persistence must
    /// never block a document switch or application termination.
    private func persistOutgoingLastPage() {        guard let filePath = mainViewController.pdfView.document?.documentURL?.path,
              let pageIndex = mainViewController.pdfView.currentPageIndex() else {            return
        }

        if !FitzBridge.setLastPage(helperPath: helperPath, filePath: filePath, page: pageIndex) {
            Swift.print("⚠️ Could not persist last page for \(filePath); continuing")
        }
    }

    /// Restores the reading position stored in the freshly loaded PDF, after
    /// the document and sidebar are installed. Interprets the helper's raw
    /// output: nil (read/parse failure) or -1 (no stored position) both skip;
    /// a valid 0-based index is handed to the view, which clamps it into range.
    private func restoreLastPage(filePath: String) {        guard let output = FitzBridge.getLastPage(helperPath: helperPath, filePath: filePath) else {            Swift.print("⚠️ Could not read stored last page for \(filePath); staying on the default page")
            return
        }

        guard let storedIndex = Int(output), storedIndex >= 0 else {            return  // -1 (unset) or unparseable: nothing to restore
        }

        mainViewController.pdfView.restore(toPageIndex: storedIndex)
    }

    /// Presents a sheet explaining that the requested PDF could not be read.
    /// If the main window is not yet available, falls back to a modal alert.
    private func showLoadFailureAlert(for filePath: String) {        let fileName = URL(fileURLWithPath: filePath).lastPathComponent
        let alert = NSAlert()
        alert.alertStyle = .warning        alert.messageText = "Could not open PDF"
        alert.informativeText = "Anima could not read \"\(fileName)\". The file may be damaged or not a valid PDF."
        alert.addButton(withTitle: "OK")
        if let window = window {            alert.beginSheetModal(for: window) { _ in }        } else {            alert.runModal()
        }
    }

    // MARK: - PDF URL Resolution
    /// Resolves the PDF to open, checking (in order):
    ///   1. pendingFileURL (from Finder double-click during cold launch)
    ///   2. Command-line arguments (first .pdf path found)
    ///   3. Dev fallback: projectRoot/data/input.pdf
    ///
    /// Returns nil if no valid PDF file is found.
    private func resolvePDFURL() -> URL? {
        let fileManager = FileManager.default
        // --- 1. Finder / Open With (cold launch) ---
        if let pending = pendingFileURL {            pendingFileURL = nil  // consume it
            if fileManager.fileExists(atPath: pending.path) {                return pending            } else {                Swift.print("⚠️ PDF from Finder not found: \(pending.path)")
                return nil
            }
        }

        // --- 2. Check command-line arguments ---
        // arguments[0] is the executable path; scan the rest for a .pdf path.
        let args = CommandLine.arguments.dropFirst()
        if let pdfArg = args.first(where: { $0.hasSuffix(".pdf") }) {
            // Expand ~ if present, then resolve to absolute path
            let expanded = NSString(string: pdfArg).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded).standardized
            if fileManager.fileExists(atPath: url.path) {                return url            } else {                Swift.print("⚠️ PDF from command line not found: \(url.path)")
                return nil
            }
        }

        // --- 3. Dev fallback ---
        let fallbackURL = URL(fileURLWithPath: "\(projectRoot)/data/input.pdf")
        if fileManager.fileExists(atPath: fallbackURL.path) {            return fallbackURL        }

        return nil
    }

    // MARK: - Lifecycle
    func applicationWillTerminate(_ aNotification: Notification) {        // Persist the active document's reading position on quit.
        persistOutgoingLastPage()

        if let monitor = eventMonitor {            NSEvent.removeMonitor(monitor)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {        return true
    }
}`

```

## Before testing

Please first build in Xcode with **Cmd+B**. This is the first compile check because the change uses the exact AppKit/PDFKit seams that the app owns.

Then run the existing regression suites before a commit:

bash

```bash
`make test`

```

and in Xcode:

text

```text
`Cmd+U`

```

The existing suites do not cover Launch Services delivery or the private `AppDelegate` URL handler. The next step should therefore be the focused Phase B manual acceptance pass from `TARGET_ARCHITECTURE.md` step 8, beginning with the two highest-value cases:

1.  An Obsidian `pdf://HASH?page=N` link for the already open PDF -> activate Anima and jump to page `N`.
2.  A link for a different PDF with `?page=N` -> replace the document and land on page `N`, rather than restoring its stored last page.

Once those compile and behavior checks are good, we should discuss the exact manual acceptance sequence and whether to add a small test seam for URL parsing before updating `HISTORY.md`, `TODO.md`, `GOALS.md`, and `README.md`.

> [!note] User:
> Well, it works, including `make test`, `Cmd+U`, and the two highest-value cases. Great.
>
> It would have been better if you had shown at least _a little bit_ of empathy about the moment. I don't need a hype buddy, but it's difficult to get into the flow if I feel completely ignored. Disappointing. Let's get this session over with as fast as possible then.
>
> > we should discuss the exact manual acceptance sequence and whether to add a small test seam for URL parsing
>
> Please elaborate.

Assistant:
You are right. This was a meaningful milestone: the real `pdf://` path now crosses Obsidian/Launch Services -> Anima -> resolver CLI -> safe reader replacement, and the two most important real-world cases worked. I should have explicitly recognized that rather than immediately switching into checklist mode. That omission made the collaboration feel transactional at exactly the point where the project became materially more usable. I am sorry.

On the technical question:

## What remains of Phase B acceptance

You have already passed the core of cases **8(a)** and **8(b)** from `TARGET_ARCHITECTURE.md`:

-   **8(a), same document + page:** a link activates the already open PDF and lands at its requested page.
-   **8(b), different document + page:** the active PDF is replaced and the requested URL page wins over that PDF's saved last-page position.

The remaining manual sequence is deliberately small, because the important end-to-end pipeline has now been proven.

### 1\. Complete 8(b): verify outgoing last-page persistence

This verifies the other half of the document-replacement contract.

1.  Open PDF A in Anima and go to a distinctive page, for example page 7.
2.  Open PDF B via `pdf://...?...page=N`.
3.  Reopen PDF A without a `page` query, either through its `pdf://HASH` link or an ordinary open.
4.  Expected: PDF A restores to page 7.

Why this matters: opening B must persist A's position before the replacement, while the explicit URL page for B must override B's own stored position.

### 2\. 8(c): link without a page restores last position

1.  Arrange for a PDF to have a known stored reading position.
2.  Click `pdf://HASH` with no query string.
3.  Expected: it opens that PDF and restores the saved page.
4.  Also click the same no-page link while that PDF is already open.
5.  Expected: Anima activates, but does not move from the currently displayed page.

That final same-document behavior is specified in section 6.3 step 4: no `page` means activate only.

### 3\. 8(d): unknown hash shows resolver prose

Click a deliberately nonexistent `pdf://` hash.

Expected:

-   the active document does not change;
-   an alert appears;
-   the alert body is the resolver's message verbatim, shaped like:
    `Cannot resolve pdf://XXXXXXX: no PDF with this id found in the indexed folders.`

This distinguishes normal toolchain hygiene failures from Anima's own backend failures.

### 4\. 8(e): duplicate ID shows both paths

Temporarily stage the duplicate in the indexed folders, using the exact procedure already accepted for `pdf-annotations` Phase A.

Click any `pdf://` link, including one unrelated to the duplicate.

Expected:

-   the active document stays unchanged;
-   the alert reports the duplicate-ID failure;
-   both fully qualified paths appear;
-   all resolutions fail while the duplicate remains, because strict global duplicate detection is intentional.

Then remove the staged duplicate and confirm an ordinary link resolves again.

### 5\. 8(f): malformed or out-of-range page does nothing

These are two separate checks:

-   malformed:

    -   `pdf://HASH?page=banana`
    -   `pdf://HASH?page=0`
    -   expected: "Invalid page number" alert, no document change.
-   valid integer but outside the PDF:

    -   `pdf://HASH?page=99999`
    -   expected: "Page unavailable" alert, no document change.

The especially valuable part is confirming that an invalid page for a _different_ document does not replace the currently open PDF. The implementation parses and validates the new document before persisting outgoing position or clearing state, which is the safe behavior we wanted.

## Should we add a URL-parsing test seam?

My recommendation is: **no, not in this Phase B session.**

### Why manual acceptance is sufficient here

The important behavior depends on seams that a normal Swift unit test does not naturally exercise:

-   Launch Services choosing Anima for `pdf://`;
-   `application(_:open:)` arriving before or after launch setup;
-   the real `pdf-annotations` venv and its CWD-dependent config discovery;
-   actual PDF replacement, saved-position persistence, and AppKit modal alerts.

You have just run the two strongest possible checks: real links against real PDFs in the actual installed app. Those prove more than a parser unit test would.

### What a test seam would mean

To unit-test parsing cleanly, we could extract a small pure parser -- perhaps an internal `PDFLinkRequestParser` or a static method outside `AppDelegate` -- which receives a `URL` and returns either:

-   `(hash, optional zero-based page)`; or
-   a displayable parse error.

Then we could add tests for:

-   missing host;
-   no page;
-   page `1` -> index `0`;
-   `0`, negative, non-integer, and repeated `page` values.

That extraction would be technically tidy, but it creates a new structural artifact whose sole consumer is the opening flow and whose immediate value is testing a small amount of straightforward code. Per the project's scope skepticism, I do not think it earns its keep now.

### The practical middle path

Treat the Phase B acceptance cases as the spec, record exactly which real cases you ran, and leave parser extraction parked until one of these happens:

-   URL syntax grows beyond `HASH` plus optional `page`;
-   parsing logic becomes difficult to read or changes more than once;
-   a parsing regression occurs;
-   Phase C's far-jump work needs a testable request representation for another real reason.

That retains a clean rollback point and avoids converting a small, working linear pipeline into architecture for hypothetical test coverage.

If you agree, the next step is simply to run the remaining four acceptance checks above. After they pass, we can make one small documentation-only completion step: record the completed Phase B opening-flow work in `HISTORY.md`, strike the relevant forward item if present, and update `GOALS.md` from step 6 to Phase B acceptance/cleanup or Phase C depending on your desired stopping point.

> [!note] User:
> Observations:
>
> -   Complete 8(b) works.
> -   8(c) works
> -   8(d) works
> -   Trying to open (= start Anima) with a non-existing hash shows an alert but does not terminate Anima. There is just an empty window, no PDF view, no sidebar.
> -   8(d) works (malformed, outside integer, invalid for different)
>
> Phase B is completed.
>
> Let's turn to the completion step and deal with the artefacts.
>
> Next is Phase C 9. "Introduce far-jump seam per §6.4". Please write the replacement for the "Current Session Pointer" in `GOALS.md`.
>
> Nothing to do in the `TODO.md`.
>
> Attached is `HISTORY.md`. Please draft a partial patch and tell me where to insert it.

Assistant:
Denkt nach

That is a real completion point: Phase B is no longer a probe or a partially wired bridge. Obsidian links now resolve into Anima's actual reader lifecycle, including page targeting, last-page behavior, and user-facing failure reporting. Nicely done.

One small inventory note before the artefacts:

-   **Finding:** your second "8(d)" appears to describe **8(f)** -- malformed and out-of-range page validation.
-   **Finding:** I do not see a fresh report of **8(e)**, the staged duplicate-ID alert with both paths. However, `GOALS.md` already records that the duplicate case was accepted during step 5's real-link verification on July 18, 2026. Since you have explicitly declared Phase B complete, I will not reopen that acceptance item.
-   **Finding, parked by your direction:** cold-launch failure for an unknown hash leaves Anima running with its empty window. The failure alert is correct and the app remains stable, but the resulting reader state is not ideal. Since you said there is nothing for `TODO.md`, I would not add it there or make it part of this completion record. We can deliberately revisit it only if it becomes disruptive in daily use.

## `GOALS.md` -- replacement for Current Session Pointer

Replace the two current paragraphs under `## 📍 Current Session Pointer` with:

markdown

```markdown
`**Where we are:** Phases 1 and 2 are complete. Phase 3, `pdf://` Toolchain Integration, completed its Phase B opening flow on 2026-07-18: real Obsidian links resolve through `PdfAnnotationsBridge`, safely activate or replace Anima's active document, honor explicit 1-based `page` queries over stored positions, restore last position without a page query, and surface resolver and URL validation failures to the user.
**What's next:** `TARGET_ARCHITECTURE.md` Phase C step 9 -- introduce the small shared far-jump seam described in §6.4. Keep target discovery in its existing local owners, but route the final non-local transitions for goto page, both finds, F3, bookmark jumps, and same-document `pdf://` page links through one shared execution point. Step 10 then builds the in-memory JumpStack on that seam.`

```

This makes the present position precise without claiming that Phase 3 as a whole is complete -- Phase C and the cleanup phase remain.

## `HISTORY.md` -- partial patch

Insert this one bullet in the **`## macOS Integration`** section, immediately **after** the existing `PdfAnnotationsBridge` bullet:

markdown

```markdown
`- `pdf://` opening flow (2026-07-18): Obsidian links now resolve, activate or replace the reader document, honor explicit page targets, restore position without one, and surface resolver or URL failures. Details: `README.md`, `TARGET_ARCHITECTURE.md``

```

⚠️ **PARTIAL PATCH - NOT A DROP-IN REPLACEMENT**

diff

Alle anzeigen

```diff
 `## macOS Integration
 - Open via command-line argument and Finder double-click; registered PDF viewer (`CFBundleDocumentTypes`) - Helper/venv paths resolved from single `projectRoot` constant owned by `AppDelegate` - Active-document hot replacement (2026-07-17): `loadDocument(url:)` is the single seam for cold launch and hot open; outgoing search/emphasis/selection state cleared, parse failure preserves the current document - `pdf://` URL scheme claimed (2026-07-18): `CFBundleURLTypes` entry independent of the document-type claim; legacy `PDFHandler.app` route retired. Details: `README.md`, `TARGET_ARCHITECTURE.md` - `PdfAnnotationsBridge` (2026-07-18): resolver subprocess seam per `TARGET_ARCHITECTURE.md` §6.2; `ResolveOutcome` carries the resolver's stderr verbatim to the user. Details: `README.md` §The pdf-annotations Boundary
+- `pdf://` opening flow (2026-07-18): Obsidian links now resolve, activate or replace the reader document, honor explicit page targets, restore position without one, and surface resolver or URL failures. Details: `README.md`, `TARGET_ARCHITECTURE.md`

 ## Testing`

```

The history entry is intentionally narrow and outcome-only: it records what shipped, while `README.md` and `TARGET_ARCHITECTURE.md` remain the homes for the contract and implementation rationale.

> [!note] User:
> Anything to do in the `README.md`?

Assistant:
Yes. `README.md` has two now-stale statements, plus one useful user-facing omission.

## Inventory

### 1\. `The pdf-annotations Boundary` -- must update

Its final status paragraph still says `application(_:open:)` only reports a temporary probe alert and that opening the resolved PDF is remaining work.

**Finding:** that is no longer true. This is the most important README correction.

### 2\. `Integration with Existing Toolchain` -- must update

The `pdf://` bullet says resolution works but "Opening the resolved PDF at the requested page is the remaining step."

**Finding:** also now stale. It should say that a link opens or activates the resolved PDF, with an explicit `page` target winning over stored last-page restoration.

### 3\. `Opening PDFs` -- optional but recommended

This section currently inventories only:

1.  Finder
2.  command line
3.  dev fallback

**Finding:** `pdf://HASH` and `pdf://HASH?page=N` are now a fourth real entry point, and this is where a reader would naturally look to learn how Anima receives documents.

Adding a short item would make the product behavior discoverable without repeating the resolver architecture. It should explain:

-   `pdf://HASH` opens the resolved PDF at its stored last page;
-   `pdf://HASH?page=N` opens at 1-based page `N`;
-   if it is already open, no-page activates only and page-targeted links jump in place;
-   unknown hashes, duplicates, and malformed pages produce an alert without changing the document.

## What I would not add

-   The cold-launch unknown-hash empty-reader state: it is an observed edge case, not an intended durable behavior or a settled contract.
-   Phase C far-jump/JumpStack details: they are future behavior and belong in `TARGET_ARCHITECTURE.md` and `TODO.md` until implemented.
-   Acceptance-test narrative: that belongs in `HISTORY.md`, not the README.

## Two scope options

1.  **Minimal correction:** update only the two stale status statements.

    -   Lowest-risk documentation repair.
    -   The README remains technically accurate, but `pdf://` is not listed in the practical "Opening PDFs" instructions.
2.  **Complete user-facing documentation update -- recommended:** update those two stale statements **and** add the concise fourth `pdf://` opening entry.

    -   Records the durable reader behavior where users expect it.
    -   Still a small, localized documentation change.

I recommend option 2. If you approve it, I will provide a complete drop-in replacement for `README.md`, preserving everything else byte-for-byte except the agreed documentation changes.

> [!note] User:
> Yes, please provide the complete drop-in replacement for `README.md`.

Assistant:
Below is the complete drop-in replacement for `README.md`. It makes only the agreed documentation changes:

1.  Updates the `PdfAnnotationsBridge` status from temporary probe to completed opening flow.
2.  Updates the `pdf://` integration bullet from "remaining step" to shipped behavior.
3.  Adds `pdf://` as the fourth reader-facing opening entry point.

markdown

```markdown
`# Anima
**A minimal, no-frills PDF reader for annotation work.**
Latin *anima* -- "soul": what's left when you strip everything else away.
---

## Vision
Anima exists to serve one workflow: reading academic papers and wisdom tradition texts, highlighting passages, and adding comments. It replaces PDF-XChange Viewer in a macOS-native toolchain that flows from PDF -> highlights -> Obsidian notes.

**Core Philosophy:**
- **Minimalism**: Open. Read. Highlight. Comment. Save. That's it.
- **Non-destructive**: Incremental save via fitz preserves all existing annotations.
- **Toolchain-native**: Annotations are fully compatible with the `pdf-annotations` extraction pipeline and the `pdf://` URL scheme for Obsidian integration.
- **Single user**: Built for Frank. Configuration in code, not preferences dialogs.
**Design Philosophy -- Modality and Focus:**
Anima treats modality as a feature, not a limitation. When the user edits a comment, a modal input panel enforces focus on that single annotation. There is no cancel -- Escape always saves. This reflects a deeper principle: PDF annotations in Anima are a *scratchpad*. The real intellectual work happens outside the PDF, in Obsidian's Zettelkasten ("The Studio"). Highlights and comments are raw material to be developed into idea notes, not polished artifacts in their own right. This means Anima can and should force simplicity -- one highlight, one comment, one action at a time. Complexity belongs in the knowledge management layer, not in the reading layer.
**What Anima Does NOT Do:**
Print, sign, fill forms, edit PDF content, draw, stamp, redact, PDF/A compliance, thumbnail panels, bookmarks, touch-optimized UI, preferences dialog, or anything that adds complexity without serving the highlight+comment workflow.

---

## Architecture
Anima uses a hybrid approach: **PDFKit for rendering**, **fitz for writing**.
```mermaid
graph TB
    subgraph "Anima (Swift / macOS)"        UI[AnimaPDFView]        AM[AnnotationManager]        FB[FitzBridge]        MVC[MainViewController]        SB[Sidebar + Cards]    end
    subgraph "Python Backend"        AH[anima_helper.py]        FZ[fitz / PyMuPDF]    end
    PDF[(PDF File)]
    UI -->|user action| AM    AM -->|in-memory PDFAnnotation| UI    AM -->|subprocess call| FB    UI -->|SidebarUpdateDelegate| MVC    MVC -->|emphasis, layout| SB    FB -->|CLI args + JSON| AH    AH -->|incremental save| FZ    FZ -->|read/write| PDF    UI -->|read for display| PDF    SB -->|card click -> emphasis| MVC
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
`AnnotationManager` owns the dual-write sequence. When creating, editing, or
deleting highlights during a session:

1. **Persist to disk** -- `AnnotationManager` calls `anima_helper.py` via `FitzBridge`, which uses fitz to write the annotation with incremental save.
2. **Update in-memory** -- `AnnotationManager` adds, modifies, or removes a `PDFAnnotation` in PDFKit's in-memory document for immediate display.
3. **Notify sidebar** -- `AnimaPDFView` calls `sidebarDelegate.annotationsDidChange(onPageIndex:)` after the manager returns, so the sidebar rebuilds the affected page's cards.
4. **No reload** -- the document is never reloaded during a session, eliminating the scroll drift that plagued both PoCs.
`AnnotationManager` is a toolbox class: it holds no references to the view or document, receiving all context (document, page, annotation, isXRayMode) per-call. This keeps it testable and safe for future multi-document support.
On next app launch, PDFKit loads the fitz-written file from disk. The file is the single source of truth.

### Coordinate Systems
This is the critical cross-language contract:

- **PDFKit**: origin at **bottom-left**, y increases upward
- **fitz**: origin at **top-left**, y increases downward
- **Conversion**: `y_fitz = page_height - y_pdfkit`
The coordinate flip happens in Swift (`AnimaPDFView`) before calling the helper. The helper receives fitz-native coordinates only -- it has no knowledge of PDFKit.
**Note:** PDFKit's `annot.bounds` does not directly match the raw PDF `/Rect` values. PDFKit transforms the coordinates internally. When building test fixtures, always use the values reported by PDFKit, not the raw PDF rect.
### UUID Contract
Every annotation gets a UUID stored in the PDF `/NM` field. Swift generates UUIDs, passes them to the helper via CLI arguments, and uses them for hit-testing and identification. The helper sets `/NM` via fitz's xref API (`doc.xref_set_key`).
**Important:** On in-memory annotations, `/NM` must be set explicitly via `setValue(_:forAnnotationKey:)`. PDFKit maps `userName` to `/T` (the author field), not to `/NM`. Relying on `userName` alone for UUID storage causes the author field to overwrite the UUID. See `docs/SIDEBAR_DESIGN.md` "Known Gotchas" for full details.
### Bookmarks
Named page bookmarks are persisted independently from annotations. `anima_helper.py` stores a JSON array in the PDF catalog's private `/AnimaBookmarks` key, rather than modifying the PDF's native `/Outlines` tree. This preserves any table of contents already supplied by the document.
Bookmark pages are stored as fitz-native 0-based indices. `BookmarkManager` keeps the catalog-backed list in memory for the active reader session, refreshing it after every successful helper mutation. Reader-facing UI always presents the corresponding 1-based page number.
`AppDelegate` creates `BookmarkManager` alongside `AnnotationManager`; `AnimaPDFView` owns reader key dispatch and temporary bookmark dialogs; `FitzBridge` owns the Swift -> helper subprocess calls. Bookmark persistence and state are deliberately separate from annotation CRUD, sidebar extraction, search, and emphasis.
### Last-Page Restoration
Anima remembers each PDF's most recently displayed page. `anima_helper.py` stores a single fitz-native 0-based page index as a PDF string under the catalog's private `/AnimaLastPage` key, independent of `/AnimaBookmarks` and of the document's native outline. The index is persisted only when the active document is replaced and on application termination -- never on every page change -- so switching PDFs or quitting appends at most one incremental save.
`AppDelegate` owns the sequence: it persists the outgoing document's page (read on demand from the reader, not cached) before installing a replacement, and restores the incoming document's page after the PDF and sidebar are installed. `AnimaPDFView.restore(toPageIndex:)` clamps a stale stored index -- one saved when the PDF had more pages -- to the last page rather than failing, and navigates through the same `page(at:)` + `go(to:)` primitive as goto-page and bookmark jumps. Restoring position is transparent navigation and deliberately does not participate in any future JumpStack/`Cmd+R` history.
`FitzBridge` reads return the helper's raw output (`getLastPage` -> `String?`); the caller decodes. Reader-facing page numbers remain 1-based; the stored index is 0-based.
### The pdf-annotations Boundary
Anima has a second subprocess seam, distinct from `FitzBridge`. `PdfAnnotationsBridge` calls the neighbouring `pdf-annotations` project's resolver CLI to turn a `pdf://HASH` link into a file path. The contract is the CLI, not the code (`TARGET_ARCHITECTURE.md` §3): Anima never imports `pdf_annot`, runs the resolver inside that project's own venv with its root as the working directory, and consumes stdout and stderr. Resolution is stateless -- the hash-to-path index is rebuilt per invocation from filenames, so every click sees current truth.
The two bridges deliberately differ in how they fail. `FitzBridge` calls Anima's own helper in Anima's own venv, so a failure is a developer failure and is logged through `Swift.print`. `PdfAnnotationsBridge` consumes another project's declared interface, where an unknown hash or a duplicate `pdf_id` is an everyday outcome of library hygiene; it returns `ResolveOutcome` (`.resolved(path:)` / `.failed(message:)`) and the resolver's stderr reaches the user verbatim, because that text is written to be read.
`application(_:open:)` owns the reader-facing `pdf://` pipeline: it rejects opens behind a modal dialog, parses the URL's hash and optional 1-based page, resolves the hash through `PdfAnnotationsBridge`, then either activates the already open document or replaces it through the normal safe loading path. An explicit page query wins over stored last-page restoration; a link without one restores the incoming document's last position, while a no-page link for the already open document only activates Anima. Resolver failures and malformed or unavailable pages appear in alerts without changing the reader document. The same-document page jump is a direct `go(to:)` call in Phase B and is marked as the future far-jump seam call site for Phase C.
---

## How to Use
### Highlight and comment
- **Select text + Enter** -- create a pink highlight.
- **`Cmd+H`** -- toggle persistent highlight mode. With the mode on, releasing the mouse after selecting text creates a highlight immediately.
- **Double-click a highlight** -- add or edit its comment. Escape in the comment editor saves the current text.
- **Click a highlight or comment card** -- emphasize that annotation and make it the target for Delete. Click the same emphasized highlight or card again, or press `Esc`, to clear the selection.
- **`Delete`** or **`Forward Delete`** -- remove the currently emphasized highlight.
Highlights start without comments by design. Add a comment later by double-clicking the highlight.

### Navigate
- **`Cmd+G`** -- go to a 1-based page number.
- **`Home` / `End`** and **`Cmd+Home` / `Cmd+End`** -- jump to the beginning or end of the document.
- **`Page Up` / `Page Down`** -- move by one screenful.
### Bookmarks
- **`Cmd+B`** -- add a named bookmark for the current page. The prompt identifies pages using normal 1-based reader numbering.
- Bookmark names are unique case-insensitively. If the name already exists, choose **Re-point** to move it to the current page or **Keep Existing** to leave it unchanged.
- **`Cmd+J`** -- open JumpStation. It lists bookmark names and normal 1-based page numbers in two columns. Mouse clicks, right-clicks, and double-clicks select a row only; `Up`/`Down` also move selection. `Enter` jumps to the selected bookmark and `Esc` closes the panel.
- **`Cmd+D`** -- while JumpStation is open, delete its selected bookmark after confirmation. The list refreshes immediately, and the panel closes if the final bookmark is removed.
- If no bookmarks exist, `Cmd+J` reports that state instead of opening an empty picker.
Bookmarks persist in the PDF itself and survive reopening without altering the document's native outline/table of contents.

### Search
- **`Cmd+F`** -- search PDF text from the beginning of the current page forward. The active hit appears pale green in the PDF.
- **`Cmd+Shift+F`** -- search annotation comments only from the current page forward. Matching cards receive thin pale-green borders; the current hit has a thicker pale-green border.
- **`F3`** -- advance to the next hit in the active search. Searches stop at document end and do not wrap.
- **`Esc`** -- clear the active PDF-text search, comment search, or annotation emphasis, in that order.
PDF-text search results are temporary reader selections, not annotation selections. Finding text never creates a highlight, including while persistent H mode is enabled. Starting a search clears annotation emphasis; clicking a highlight or card exits search and returns to normal annotation interaction.

### Inspect native PDF comments
- **`Cmd+P`** -- toggle X-Ray mode, which reveals native PDF popup indicators for comments. This is primarily a diagnostic view; ordinary reading keeps them suppressed in favor of the sidebar.
### Highlight Workflow
Highlights are created **without a comment**. This keeps the flow fast -- especially in persistent highlight mode where mouseUp instantly highlights. To add or edit a comment after the fact, double-click the highlight. This matches the PDF-XChange Viewer workflow where highlighting and commenting are separate actions.
Highlights are **page-scoped by design**: a selection that spans a page break creates the highlight only on the first page -- lines on the following page are dropped. This is intended behavior, not a limitation. Highlights should be specific; a continuation on the next page is its own highlight, connected via the "link" command comment per the existing annotation conventions (see `pdf-annotations` for details).
### Sidebar
The sidebar is a fixed-width panel on the right showing **comment cards** -- one per annotation with a non-empty comment. Cards are positioned vertically to align with their corresponding highlights in the PDF, using anchor-based layout with collision avoidance.
Key capabilities:
- **Live updates**: Cards appear, update, or disappear immediately when comments are added, edited, or deleted during a session.
- **Bidirectional emphasis**: Clicking a card emphasizes the corresponding highlight in the PDF (light yellow), and clicking a highlight emphasizes the corresponding card. Both directions use the same visual treatment. Emphasis is unified with the Delete key target, so the user always sees which highlight will be affected.
- **Scroll sync**: The sidebar scrolls in lockstep with the PDF.
- **Per-page architecture**: Each PDF page has its own page-sidebar container, enabling efficient per-page rebuilds on mutation.
See `SIDEBAR_DESIGN.md` for the full design document.
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
- **`pdf-annotations`**: Extracts highlights and comments from PDFs into Obsidian Markdown notes. Uses fitz -- Anima's annotations are fully compatible. Standard `/Annot` with `/Subtype /Highlight`, `/Contents` for comments, `QuadPoints` for precise multi-line highlighting.
- **`pdf://` URL scheme**: Obsidian bibnotes reference PDFs via `pdf://HASH?page=N`. Anima claims the scheme on macOS and resolves the hash through the `pdf-annotations` resolver CLI. A page query is 1-based and opens or activates the PDF at that page; without a page query, a newly opened document restores its last page while an already open document is simply activated. Unknown hashes, duplicate IDs, and malformed or unavailable pages report their failures in Anima rather than returning through the retired Windows Parallels route.
- **Obsidian "The Studio"**: The Zettelkasten knowledge management system where bibnotes, idea notes, and workbenches live. Anima serves as the PDF reading layer that feeds this system.
---

## Project Structure
The authoritative file inventory is `project_tree.txt` (generated via `make gentree`, included in every filesdump). This section is the annotated map of what matters -- curated and selective; skeleton details may lag behind the generated tree by design.
```
anima/
├── Anima/Anima/                    ← Swift source files (app target)
│   ├── AnimaPDFView.swift          ← PDFView subclass: keyboard, mouse, hit-testing
│   ├── AnnotationManager.swift     ← Annotation CRUD: create, edit, delete (dual-write)
│   ├── BookmarkManager.swift       ← Bookmark session state and catalog persistence coordination
│   ├── AppDelegate.swift           ← Window setup, PDF loading, manager wiring
│   ├── FitzBridge.swift            ← Subprocess bridge to Python helper
│   ├── PdfAnnotationsBridge.swift  ← Subprocess bridge to the pdf-annotations resolver CLI
│   ├── JumpStationPanel.swift      ← Modal bookmark navigation and deletion picker
│   ├── MainViewController.swift    ← NSSplitView layout, sidebar sync & emphasis
│   ├── SidebarExtractor.swift      ← Parses annotations into sidebar CommentCard structs
│   ├── CommentCardView.swift       ← Custom NSView for rendering sidebar cards
│   └── CommentInputPanel.swift     ← Modal comment editor (replaces NSAlert)
├── Anima/AnimaTests/               ← Swift Testing unit tests
│   ├── AnimaTests.swift            ← Cross-boundary integration tests
│   ├── SidebarExtractorTests.swift ← Sidebar extraction mechanics (normally excluded from filesdump)
│   └── AnnotationGeometryTests.swift ← Pure coordinate/geometry tests (normally excluded from filesdump)
├── tools/
│   ├── anima_helper.py             ← CLI: add-highlight, edit-comment, delete-highlight
│   ├── concat_files.py             ← Filesdump generator for LLM sessions
│   └── requirements.txt            ← Python dependencies (PyMuPDF)
├── tests/                          ← Python tests (pytest)
│   ├── conftest.py                 ← Fixtures: test_pdf, run_helper
│   └── test_anima_helper.py        ← round-trip, contracts, edge cases
├── data/
│   └── input_original.pdf          ← Test PDF (unmodified backup)
├── docs/                           ← Design notes, historical unless marked current
│   ├── BOOKMARKS_DESIGN.md         ← Bookmark and navigation design (to 2026-07-16)
│   └── SIDEBAR_DESIGN.md           ← Sidebar design and known gotchas (historical)
├── CRITICAL_RULES.md               ← Non-negotiable collaboration rules
├── GOALS.md                        ← Strategic direction & roadmap
├── HISTORY.md                      ← Resolved-work record (on the heap)
├── LLM_INSTRUCTIONS.md             ← AI session context and conventions
├── TARGET_ARCHITECTURE.md          ← `pdf://` link resolution: contract, work plan, acceptance
├── TODO.md                         ← Forward-looking task scratchpad
├── Makefile                        ← Build, setup, and utility targets
├── pyproject.toml                  ← Project metadata, pytest & black config
└── manifest.lst                    ← File list for filesdump generation
```
### Module Overview
`AnimaPDFView.swift` -- Subclasses `PDFView` to intercept keyboard and mouse events. Handles persistent highlight mode (`Cmd+H`, mouseUp auto-highlight), X-Ray mode (`Cmd+P` for popup visibility), goto page (`Cmd+G`), bookmark creation (`Cmd+B`), JumpStation presentation (`Cmd+J`), hit-testing for highlight clicks, and emphasis/selection coordination via `SidebarUpdateDelegate`. All annotation CRUD (create, edit, delete) is delegated to `AnnotationManager`; bookmark persistence is delegated to `BookmarkManager`. Defines the `SidebarUpdateDelegate` protocol and notifies its delegate after every annotation mutation and highlight click so the sidebar stays in sync.
**`AnnotationManager.swift`** -- Toolbox class that owns all annotation CRUD operations and the dual-write pattern. Creates highlights (with quad math and coordinate conversion from PDFKit to fitz space), edits comments (showing the modal `CommentInputPanel`, writing via fitz, updating in-memory `/AnimaComment`), and deletes highlights. Holds no references to the view or document -- all context is passed per-call, keeping the class testable and safe for multi-document (tabs) support. Also owns shared constants (`authorName`, `highlightColor`, `highlightOpacity`) and helpers (`annotationUUID`, `ensurePopupExists`).
**`BookmarkManager.swift`** -- Toolbox-style owner of the active document's in-memory named-page bookmark list. It decodes bookmark JSON returned by `FitzBridge`, delegates set/delete persistence to the helper, and reloads after each successful mutation so helper-owned catalog semantics remain authoritative. Bookmark page indices are 0-based internally; reader UI converts them to 1-based display values.
**`AppDelegate.swift`** -- Creates the window, loads the PDF, creates and wires the `AnnotationManager`, and sets up the NSEvent monitor as a fallback for keyboard events (PDFKit's internal `PDFDocumentView` sometimes captures keyboard focus).
**`MainViewController.swift`** -- Manages the dual-pane layout (`NSSplitView`), instantiates the `SidebarScrollView`, and coordinates the complex scrolling math and `scaleFactor` logic required to keep the sidebar perfectly synchronized with the PDF. Conforms to `SidebarUpdateDelegate` to handle live sidebar rebuilds on annotation mutation. Manages bidirectional highlight emphasis: clicking a sidebar card or a highlight in the PDF triggers the same shared emphasis logic, with toggle behavior on single-click and ensure-on behavior on double-click. Emphasis is unified with `selectedAnnotation` so the Delete key targets the visually emphasized highlight.
**`SidebarExtractor.swift`** -- The pure data layer for the sidebar. Scans the PDFDocument for highlight annotations and safely extracts their text, UUID (/NM), author (/T), modification date, and vertical anchor points. Converts this raw PDFKit data into sorted `CommentCard` structs, keeping the extraction logic completely decoupled from the UI. Supports both document-level and per-page extraction (the latter used by the live-update path to rebuild a single page efficiently). Tested with `AnimaTests.swift`.
**`FitzBridge.swift`** -- Static methods that call `anima_helper.py` via `Process()` (Swift's subprocess equivalent). Captures stdout/stderr, checks exit codes, and resolves the Python executable from the project's `.venv`. It provides annotation mutation calls, bookmark list/set/delete calls, and last-page get/set. Reads return the helper's raw stdout as `String?` and mutations return `Bool`, so decoding stays with the caller: raw bookmark-list JSON is decoded by `BookmarkManager`, which owns the Swift data model and session state, and the last-page string is decoded by `AppDelegate`.
**`PdfAnnotationsBridge.swift`** -- One static method, `resolve(hash:pdfAnnotationsRoot:)`, running the pdf-annotations resolver as a subprocess and returning `.resolved(path:)` or `.failed(message:)`. Like `FitzBridge` it holds no paths of its own: `AppDelegate` passes the project root per call. It reads both pipes before waiting for exit, and guards the two off-contract cases (nonzero exit with silent stderr, exit 0 with no path) so a protocol violation surfaces as prose rather than as an empty alert.
**`anima_helper.py`** -- Standalone CLI tool with eight subcommands across three concerns: annotations (`add-highlight`, `edit-comment`, `delete-highlight`), bookmarks (`list-bookmarks`, `set-bookmark`, `delete-bookmark`), and reading position (`get-last-page`, `set-last-page`).
**`CommentCardView.swift`** -- The visual representation of a single annotation in the sidebar. A custom NSView that uses Auto Layout to dynamically size itself based on the length of the comment text. Handles all visual styling, including the muted typography applied to structural pipeline commands (e.g., "link" or "H2"). Reports clicks via an `onClicked` closure and supports active/inactive visual states for the emphasis feature.
**`CommentInputPanel.swift`** -- A modal `NSPanel` for adding and editing highlight comments. Replaces the previous `NSAlert`-based dialog with a proper multi-line text editor (`NSTextView`). Styled to match `CommentCardView` -- same background color, corner radius, fonts, and color palette. Escape saves and closes (no cancel), Enter inserts newlines. The panel is resizable and draggable. Each invocation creates a fresh instance; the panel is not reused across calls.
**`JumpStationPanel.swift`** -- A modal `NSPanel` for bookmark navigation and deletion. It renders the active document's bookmarks in name and 1-based page columns, owns temporary table selection and local keyboard dispatch, and reports Enter-to-jump or confirmed deletion through callbacks. It deliberately has no PDFKit, file-path, or persistence knowledge: `AnimaPDFView` owns navigation and delegates deletion to `BookmarkManager`. The future prefix-input/filtering behavior will extend this panel rather than replace it.
---
## Development
### Prerequisites
- **Xcode** (macOS, with macOS SDK)
- **Python 3** with venv support
- **SwiftFormat** (`brew install swiftformat`) -- Swift code formatting
### Setup
```bash
make setup    # Create Python venv, install PyMuPDF
```
### Build & Run
Open `Anima/Anima.xcodeproj` in Xcode, then **Cmd+R** to build and run.
### Testing
```bash
make test           # Run Python tests (quiet)
make test-verbose   # Run Python tests with output
```
Python test suite (`tests/test_anima_helper.py`):
- `TestAddHighlight` -- basic round-trip, with-comment, multi-quad
- `TestEditComment` -- add-then-edit (with opacity survival check), clear-comment
- `TestDeleteHighlight` -- create-then-delete round-trip
- `TestUUIDContract` -- xref-level /NM verification
- `TestIncrementalSavePreservation` -- pre-existing annotations survive new writes
- `TestErrorHandling` -- invalid page, missing file, nonexistent UUID
- `TestBookmarks` -- catalog-backed list/set/delete, case-insensitive upsert and deletion, 0-based page validation, and native-TOC preservation
To inspect test output PDFs: `ANIMA_KEEP_TEST_OUTPUT=1 make test` (copies modified PDFs to `tmp/tests/` for manual inspection).
Swift tests run via Xcode: **Cmd+U** or **Product -> Test**.
Current Swift test suite:
- In `AnimaTests.swift` (cross-boundary / behavioral):
  - `testFitzBridgeAddHighlightRoundTrip` -- Real Swift -> Python -> fitz subprocess boundary  - `testBookmarkManagerPersistenceRoundTrip` -- Swift bookmark manager -> helper -> PDF catalog round-trip  - `testCrossPageSelectionOnlyHighlightsFirstPage` -- Page-scoped highlight creation for cross-page selections
- In `SidebarExtractorTests.swift` (extraction mechanics):
  - `testSidebarExtraction` -- Golden JSON test against `sidebar_basic.pdf`
  - `testMultiPageExtraction` -- Multi-page extraction against `sidebar_page_extract.pdf`
  - `testPerPageExtraction` -- Per-page extraction (page 0, page 1, empty page 2)  - `testPerPageConsistencyWithDocumentLevel` -- Reassembly matches document-level  - `testInMemoryAnnotationRoundTrip` -- Verifies in-memory annotations produce    correct `CommentCard` data, guarding against dual-write field omissions
- In `AnnotationGeometryTests.swift` (pure geometry):
  - `testFitzQuadYFlip` -- Pins the PDFKit -> fitz y-flip coordinate contract  - `testQuadPointsConstruction` -- Pins QuadPoints corner order and count
### Opening PDFs
Anima accepts PDFs through four entry points, checked in this order:
1. **Finder** -- Double-click a PDF (or right-click -> Open With -> Anima). Requires the Info.plist `CFBundleDocumentTypes` registration. To make Anima the default viewer: right-click any PDF -> Get Info -> Open With -> Anima -> Change All.
2. **Command line** -- Pass a PDF path as an argument:
   ```bash   open -a Anima --args ~/Papers/some-paper.pdf   ```
3. **`pdf://` links** -- Obsidian links use `pdf://HASH` or `pdf://HASH?page=N`, where `N` is a 1-based page number. Anima resolves the hash through the `pdf-annotations` resolver CLI. A link with `?page=N` opens or activates the PDF at page `N`; without `page`, a newly opened PDF restores its stored last page, while an already open PDF is only activated. Unknown hashes, duplicate IDs, malformed pages, and unavailable pages show an alert without changing the reader document.
4. **Dev fallback** -- If none of the above provides a file, Anima opens `projectRoot/data/input.pdf` automatically. If that doesn't exist either, Anima prints an error and exits.
**Hot replacement:** If Anima is already running, opening a different PDF via Finder, "Open With", or dropping a file onto the Dock icon replaces the displayed PDF. The outgoing document's search hits, comment-search state, annotation/card emphasis, text selection, and Delete-key target are cleared; bookmarks are reloaded for the new file. If the new file cannot be parsed, the current document stays open and an alert is shown.
**Multiple instances:** Anima is single-window by design. To open several PDFs simultaneously, launch separate processes with `open -n`:
```bash
open -n -a Anima --args ~/Papers/paper-a.pdf
open -n -a Anima --args ~/Papers/paper-b.pdf
```
Each instance is fully independent (separate window, sidebar, bookmarks, search, emphasis, comment panel geometry). `pdf://` links from Obsidian deliberately do not use this path: they are delivered to the running instance and will replace the active document (`TARGET_ARCHITECTURE.md` §6.3).
**Shell alias** (optional convenience for `~/.zshrc`):
```bash
alias anima='open /Users/fschuhi/Library/Developer/Xcode/DerivedData/Anima-esbrhbulontpfabyujxyeppsbgua/Build/Products/Debug/Anima.app'
```
### Path Resolution
All derived paths flow from a single `projectRoot` constant in `AppDelegate.swift`:
```
projectRoot  = /Users/fschuhi/Projects/anima
helperPath   = projectRoot + /tools/anima_helper.py      (passed to AnnotationManager)
dev fallback = projectRoot + /data/input.pdf
venv python  = derived by FitzBridge from helperPath      (two levels up + .venv/bin/python3)
```
To move the project, change `projectRoot` in AppDelegate -- nothing else.
A second constant in the same place locates the neighbouring pdf-annotations project, whose resolver CLI Anima calls as a subprocess:
```
pdfAnnotationsRoot = /Users/fschuhi/Projects/pdf-annotations
```
It is deliberately an independent absolute path, not a sibling derived from `projectRoot`. The two projects are joined by a frozen CLI contract (see `TARGET_ARCHITECTURE.md`), not by a shared filesystem layout, and either may move without the other.
### Code Formatting
```bash
make format   # Format Swift (SwiftFormat) and Python (black) files
```
### Utilities
```bash
make showtree     # Display project structure
make filesdump    # Generate context dump for LLM sessions
make help         # Show all targets
make clean        # Remove build output, venv, cache
```
---
## Technical Notes
### Swift Gotchas
- `print()` inside `NSView` subclasses is ambiguous (NSView.print = "send to printer"). Use `Swift.print()` for console output.
- `selectionsByLine()` returns `[PDFSelection]`, not Optional -- don't `guard let`.
- `document.index(for:)` returns `Int`, not Optional -- same issue.
- Command-line GUI apps need `setActivationPolicy(.regular)` for keyboard focus. Not needed in Xcode .app bundles.
- PDFKit maps `userName` to `/T` (author), not `/NM` (unique name). Set `/NM` explicitly via `setValue(_:forAnnotationKey:)` for UUID storage. Set `/T` after `userName` to avoid the mapping overwriting the author with the UUID.
### PDFKit Coordinate Note
PDFKit's `annot.bounds` values do not match the raw PDF `/Rect` midpoints. PDFKit applies an internal coordinate transformation. When comparing with fitz or raw PDF data, always verify against actual PDFKit-reported values. The test fixtures contain PDFKit values, not raw PDF values.
### Hit-Testing Note
Clicking a highlight is resolved via `PDFPage.annotation(at:)` first, with a fallback that tests the annotation's bounding rect (`annot.bounds.contains(point)`). For a multi-line highlight the bounds are the union rectangle of all quads, so a click in the visually empty area inside that union (e.g. right of a short last line) still hits the highlight. Accepted as a forgiving hit target: clicking anywhere in the highlighted range emphasizes it, and near-misses often do too.
### Highlight Rendering Compatibility
PDF-XChange Viewer and Chromium-based PDF renderers honor fitz's generated highlight appearance stream, while Apple PDFKit renders markup highlights from their high-level annotation properties and displays the same stored pink more saturated. Anima therefore deliberately maintains two representations:
- **Persisted PDF representation:** `anima_helper.py` writes the established pink `[1.0, 0.75, 0.80]` at opacity `0.4`; fitz generates the corresponding appearance stream. This remains the compatibility contract for PDF-XChange Viewer, browsers, and the downstream `pdf-annotations` workflow.
- **In-memory PDFKit display representation:** after loading, Anima changes highlight `PDFAnnotation.color` to pale `#FFE6EA`; newly created in-memory annotations use the same display color immediately. Anima never saves through PDFKit, so this display-only override does not modify the PDF file.
Do not collapse these values into one shared constant without re-running the cross-renderer comparison. The distinction is intentional renderer compatibility, not a persistence mismatch.
### Appearance Stream Caveat
When fitz calls `annot.update()`, it regenerates the annotation's appearance stream (the low-level PDF drawing instructions). Highlights edited by fitz may render slightly differently in PDF-XChange Viewer compared to annotations originally created by Viewer, even though the underlying data (color, opacity, coordinates) is identical. PDFKit renders them consistently regardless.
### fitz Empty Content Quirk
`annot.set_info()` with `info["content"] = ""` is silently ignored by fitz -- the previous content value survives. To clear a comment, use `doc.xref_set_key(annot.xref, "Contents", "()")` to write an empty PDF string directly at the xref level. This is handled in `anima_helper.py`'s `cmd_edit_comment`.
### Background
Frank is learning Swift from scratch for this project. Python and PDF annotation internals are his area of expertise. The hybrid Swift+Python architecture leverages both: Swift for native macOS UI, Python for the annotation backend where fitz knowledge is essential.`

```

> [!note] User:
> Thanks. This concludes this session.

Assistant:
Completed this session:

-   Phase B `pdf://` opening flow implemented and accepted end to end.
-   Existing Python and Swift suites passed: `make test` and `Cmd+U`.
-   Real Obsidian-link acceptance passed for same-document jumps, cross-document opens, last-page restoration, resolver failures, and malformed/out-of-range page handling.
-   Completion artefacts drafted:
    -   `GOALS.md` Current Session Pointer replacement
    -   `HISTORY.md` one-line insertion location and patch
    -   complete `README.md` drop-in replacement

Next session starts at `TARGET_ARCHITECTURE.md` Phase C, step 9: introduce the shared far-jump execution seam before building JumpStack.

Before committing, please ensure your applied documentation changes are saved, then run:

bash

```bash
`make test`

```

and in Xcode:

text

```text
`Cmd+U`

```

Thank you for the work today. The `pdf://` route is now part of Anima's real daily workflow rather than an architectural plan.
