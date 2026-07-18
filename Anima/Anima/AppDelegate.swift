//
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
        if let schemeURL = pendingSchemeURL {
            pendingSchemeURL = nil
            handleSchemeURL(schemeURL)
        } else {
            // --- Determine which PDF to open ---
            guard let url = resolvePDFURL() else {
                Swift.print("❌ No PDF to open. Pass a .pdf path as argument, double-click a PDF, or place input.pdf in data/.")
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
    func application(_ application: NSApplication, open urls: [URL]) {
        Swift.print("📂 application(_:open:) called with: \(urls)")

        guard let url = urls.first else { return }

        // Two kinds of URL reach this method. File URLs are PDFs from Finder,
        // "Open With", or a Dock drop, and keep the existing behavior.
        // Custom-scheme URLs (pdf://HASH?page=N) arrive from Launch Services
        // after an Obsidian link click and must resolve before they can enter
        // the document-loading path.
        guard url.isFileURL else {
            if didFinishLaunching {
                handleSchemeURL(url)
            } else {
                pendingSchemeURL = url
            }
            return
        }

        if didFinishLaunching {
            // Hot open: replace the active document. Multiple URLs arriving
            // together are reduced to the first one.
            loadDocument(url: url)
        } else {
            // Cold launch: stash the URL for applicationDidFinishLaunching.
            pendingFileURL = url
        }
    }

    // MARK: - Custom URL Scheme

    /// Processes the complete Phase B pdf:// opening pipeline:
    /// modal guard -> parse -> resolve -> same-document check -> open or jump.
    ///
    /// The page conversion from the 1-based URL contract to Anima's internal
    /// 0-based page index occurs only in parseSchemeURL(_:). The resolver
    /// returns a filesystem path, after which AppDelegate owns reader behavior.
    private func handleSchemeURL(_ url: URL) {
        // TARGET_ARCHITECTURE.md §6.3 step 1: do not interrupt an active modal
        // interaction and do not queue the request in v1.
        guard NSApp.modalWindow == nil else {
            NSSound.beep()
            Swift.print("⚠️ pdf:// open declined while a modal dialog is active")
            return
        }

        guard let request = parseSchemeURL(url) else {
            return
        }

        switch PdfAnnotationsBridge.resolve(
            hash: request.hash,
            pdfAnnotationsRoot: pdfAnnotationsRoot
        ) {
        case let .failed(message):
            // The resolver's stderr is deliberate prose written for the user.
            // PdfAnnotationsBridge also supplies prose for off-contract process
            // failures, so this branch can show its message unedited.
            showSchemeAlert(
                title: "Could not open the linked PDF",
                message: message
            )

        case let .resolved(path):
            let resolvedURL = URL(fileURLWithPath: path).standardizedFileURL

            if isCurrentDocument(resolvedURL) {
                NSApp.activate(ignoringOtherApps: true)

                guard let pageIndex = request.pageIndex else {
                    return
                }

                guard let document = mainViewController.pdfView.document else {
                    return
                }

                guard (0..<document.pageCount).contains(pageIndex),
                      let page = document.page(at: pageIndex) else {
                    showLinkedPageOutOfRangeAlert(
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
    private func parseSchemeURL(_ url: URL) -> (hash: String, pageIndex: Int?)? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.caseInsensitiveCompare("pdf") == .orderedSame,
              let hash = components.host,
              !hash.isEmpty else {
            showSchemeAlert(
                title: "Invalid pdf:// link",
                message: "The link does not contain a PDF id.\n\n\(url.absoluteString)"
            )
            return nil
        }

        let pageItems = components.queryItems?.filter { $0.name == "page" } ?? []

        guard pageItems.count <= 1 else {
            showSchemeAlert(
                title: "Invalid pdf:// link",
                message: "The link contains more than one page value.\n\n\(url.absoluteString)"
            )
            return nil
        }

        guard let pageItem = pageItems.first else {
            return (hash: hash, pageIndex: nil)
        }

        guard let pageValue = pageItem.value,
              let displayedPageNumber = Int(pageValue),
              displayedPageNumber >= 1 else {
            showSchemeAlert(
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
    private func isCurrentDocument(_ resolvedURL: URL) -> Bool {
        guard let currentURL = mainViewController.pdfView.document?.documentURL else {
            return false
        }

        return currentURL.standardizedFileURL == resolvedURL.standardizedFileURL
    }

    /// Shows an opening-flow alert as a modal dialog. This intentionally works
    /// both before the main window is shown during a cold pdf:// launch and
    /// while an already-running Anima receives a hot link click.
    private func showSchemeAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Explains a page range failure after a resolver success. The document is
    /// left untouched: for a different resolved PDF, loadDocument validates
    /// before it clears the outgoing reader; for the current PDF, the guard in
    /// handleSchemeURL(_:) prevents the direct jump.
    private func showLinkedPageOutOfRangeAlert(
        requestedPageNumber: Int,
        pageCount: Int
    ) {
        showSchemeAlert(
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
    private func loadDocument(url: URL, preferredPageIndex: Int? = nil) {
        // Guard: don't replace while an AppKit modal window is active. That covers
        // NSAlert, CommentInputPanel, JumpStationPanel, and any future modal panel.
        if NSApp.modalWindow != nil {
            Swift.print("⚠️ Hot open declined while a modal dialog is active")
            return
        }

        let filePath = url.path

        // Parse first, before touching any outgoing state. If the file is not
        // a valid PDF, we want to preserve the current document exactly as it is.
        guard let document = PDFDocument(url: url) else {
            Swift.print("❌ Failed to parse PDF: \(filePath)")
            showLoadFailureAlert(for: filePath)
            return
        }

        // A page requested by a pdf:// link must be valid in the incoming
        // document. Do this before saving the outgoing position or clearing the
        // current reader so an invalid link is a complete no-op.
        if let preferredPageIndex = preferredPageIndex,
           !(0..<document.pageCount).contains(preferredPageIndex) {
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

        if let preferredPageIndex = preferredPageIndex {
            // TARGET_ARCHITECTURE.md §6.3 step 5: document installation is not
            // a far jump. The future JumpStack is cleared on document change,
            // so no pre-jump reader position exists to record here.
            mainViewController.pdfView.restore(toPageIndex: preferredPageIndex)
            Swift.print("🔗 pdf:// link opened \(filePath) at page \(preferredPageIndex + 1)")
        } else {
            // Ordinary Finder, command-line, and fallback opens preserve the
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
    private func persistOutgoingLastPage() {
        guard let filePath = mainViewController.pdfView.document?.documentURL?.path,
              let pageIndex = mainViewController.pdfView.currentPageIndex() else {
            return
        }

        if !FitzBridge.setLastPage(helperPath: helperPath, filePath: filePath, page: pageIndex) {
            Swift.print("⚠️ Could not persist last page for \(filePath); continuing")
        }
    }

    /// Restores the reading position stored in the freshly loaded PDF, after
    /// the document and sidebar are installed. Interprets the helper's raw
    /// output: nil (read/parse failure) or -1 (no stored position) both skip;
    /// a valid 0-based index is handed to the view, which clamps it into range.
    private func restoreLastPage(filePath: String) {
        guard let output = FitzBridge.getLastPage(helperPath: helperPath, filePath: filePath) else {
            Swift.print("⚠️ Could not read stored last page for \(filePath); staying on the default page")
            return
        }

        guard let storedIndex = Int(output), storedIndex >= 0 else {
            return  // -1 (unset) or unparseable: nothing to restore
        }

        mainViewController.pdfView.restore(toPageIndex: storedIndex)
    }

    /// Presents a sheet explaining that the requested PDF could not be read.
    /// If the main window is not yet available, falls back to a modal alert.
    private func showLoadFailureAlert(for filePath: String) {
        let fileName = URL(fileURLWithPath: filePath).lastPathComponent

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Could not open PDF"
        alert.informativeText = "Anima could not read \"\(fileName)\". The file may be damaged or not a valid PDF."
        alert.addButton(withTitle: "OK")

        if let window = window {
            alert.beginSheetModal(for: window) { _ in }
        } else {
            alert.runModal()
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
        if let pending = pendingFileURL {
            pendingFileURL = nil  // consume it
            if fileManager.fileExists(atPath: pending.path) {
                return pending
            } else {
                Swift.print("⚠️ PDF from Finder not found: \(pending.path)")
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

            if fileManager.fileExists(atPath: url.path) {
                return url
            } else {
                Swift.print("⚠️ PDF from command line not found: \(url.path)")
                return nil
            }
        }

        // --- 3. Dev fallback ---
        let fallbackURL = URL(fileURLWithPath: "\(projectRoot)/data/input.pdf")

        if fileManager.fileExists(atPath: fallbackURL.path) {
            return fallbackURL
        }

        return nil
    }

    // MARK: - Lifecycle

    func applicationWillTerminate(_ aNotification: Notification) {
        // Persist the active document's reading position on quit.
        persistOutgoingLastPage()

        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
