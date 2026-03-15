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

        mainViewController = MainViewController()
        window.contentViewController = mainViewController

        // --- Load the PDF ---
        let pdfPath = NSString("~/Projects/anima/data/input.pdf").expandingTildeInPath
        let url = URL(fileURLWithPath: pdfPath)

        if let document = PDFDocument(url: url) {
            // Give the document to the controller so it can extract and build the sidebar
            mainViewController.loadPDF(document: document)
            Swift.print("✅ Loaded PDF: \(url.path)")
        } else {
            Swift.print("❌ Failed to load PDF: \(pdfPath)")
        }

        // --- Keyboard event monitor (fallback) ---
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self = self else { return event }

            if self.mainViewController.pdfView.handleKeyEvent(event) {
                return nil   // consumed
            }
            return event     // not ours
        }
    }

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
