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
//  AppKit timing note:
//    When macOS launches Anima because the user double-clicked a PDF in Finder,
//    the call sequence is:
//      1. application(_:open:)               ← file URL arrives
//      2. applicationDidFinishLaunching(_:)  ← window gets set up
//    So open stashes the URL in pendingFileURL, and
//    applicationDidFinishLaunching picks it up. If Anima is already running
//    when a second file arrives, open fires with the window fully ready —
//    but since we're single-window, we log a hint about `open -n` instead.
//
//  Path resolution:
//    A single projectRoot constant is the source of truth for all derived
//    paths (helper script, dev fallback PDF). FitzBridge independently
//    derives the venv Python path from the helperPath it receives.
//    To move the project, change projectRoot here — nothing else.
//

import Cocoa
import Quartz

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    // --- Single source of truth for project location ---
    // Change this one constant if the project moves.
    // FitzBridge derives the venv Python path from the helperPath.
    private let projectRoot = "/Users/fschuhi/Projects/anima"

    @IBOutlet var window: NSWindow!

    var mainViewController: MainViewController!
    var eventMonitor: Any?

    /// Set by application(_:open:) during cold launch, before the
    /// window exists. Consumed by applicationDidFinishLaunching.
    private var pendingFileURL: URL?

    /// Tracks whether applicationDidFinishLaunching has completed.
    /// Used by application(_:open:) to distinguish cold launch from hot open.
    private var didFinishLaunching = false

    func applicationDidFinishLaunching(_ aNotification: Notification) {

        mainViewController = MainViewController()
        window.contentViewController = mainViewController

        // --- Wire up the annotation manager ---
        let helperPath = "\(projectRoot)/tools/anima_helper.py"
        mainViewController.pdfView.annotationManager = AnnotationManager(helperPath: helperPath)

        // --- Determine which PDF to open ---
        guard let url = resolvePDFURL() else {
            Swift.print("❌ No PDF to open. Pass a .pdf path as argument, double-click a PDF, or place input.pdf in data/.")
            NSApplication.shared.terminate(nil)
            return  // never reached, but satisfies the compiler
        }

        loadDocument(url: url)

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
    /// file URLs directly — no string-to-URL conversion needed.
    ///
    /// Timing: during a cold launch this fires BEFORE applicationDidFinishLaunching.
    /// In that case we stash the URL and let applicationDidFinishLaunching pick it up.
    func application(_ application: NSApplication, open urls: [URL]) {
        Swift.print("📂 application(_:open:) called with: \(urls)")

        guard let url = urls.first else { return }

        if didFinishLaunching {
            // Hot open: Anima is already running with a document.
            // Single-window model — we don't replace the current document.
            Swift.print("ℹ️ Anima is already showing a document. Use `open -n -a Anima` for a second instance.")
        } else {
            // Cold launch: stash the URL for applicationDidFinishLaunching.
            pendingFileURL = url
        }
    }

    // MARK: - PDF Loading

    /// Loads a PDF document into the main view and updates the window title.
    private func loadDocument(url: URL) {
        guard let document = PDFDocument(url: url) else {
            Swift.print("❌ Failed to parse PDF: \(url.path)")
            NSApplication.shared.terminate(nil)
            return
        }

        mainViewController.loadPDF(document: document)
        window.title = url.lastPathComponent
        Swift.print("✅ Loaded PDF: \(url.path)")
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
