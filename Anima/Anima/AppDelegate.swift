//
//  AppDelegate.swift
//  Anima
//
//  Created by Frank Schuhardt on 13.03.26.
//
//  Sets up the main window and injects the MainViewController (which holds
//  the NSSplitView). Also maintains an NSEvent monitor as a fallback for keyboard events.
//

import Cocoa
import Quartz

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet var window: NSWindow!

    var mainViewController: MainViewController!
    var eventMonitor: Any?

    func applicationDidFinishLaunching(_ aNotification: Notification) {

        // --- Set up the Main View Controller ---
        mainViewController = MainViewController()

        // In modern macOS apps, setting the contentViewController automatically
        // places its view in the window and wires up the responder chain.
        window.contentViewController = mainViewController

        // --- Load the PDF ---
        // TODO: Replace with proper file-open dialog or command-line argument.
        //       For now, use a hardcoded path for development.
        let pdfPath = NSString("~/Projects/anima/data/input.pdf").expandingTildeInPath
        let url = URL(fileURLWithPath: pdfPath)

        if let document = PDFDocument(url: url) {
            mainViewController.pdfView.document = document
            Swift.print("✅ Loaded PDF: \(url.path)")
        } else {
            Swift.print("❌ Failed to load PDF: \(pdfPath)")
        }

        // --- Keyboard event monitor (fallback) ---
        // PDFKit's internal PDFDocumentView swallows key events.
        // We try the subclass override first (AnimaPDFView.keyDown), but if
        // that doesn't fire, this monitor catches events at the app level.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self = self else { return event }

            // Route the event to the pdfView inside our controller
            if self.mainViewController.pdfView.handleKeyEvent(event) {
                return nil   // consumed — don't pass to other responders
            }
            return event     // not ours — let the system handle it
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true  // quit when the window is closed
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
