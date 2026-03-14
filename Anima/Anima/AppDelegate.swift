//
//  AppDelegate.swift
//  Anima
//
//  Created by Frank Schuhardt on 13.03.26.
//
//  Sets up the main window with a PDFView and an NSEvent monitor as fallback
//  for keyboard events (PDFKit's internal PDFDocumentView captures focus).

import Cocoa
import Quartz  // PDFKit lives inside the Quartz framework on macOS

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    // The window is created by MainMenu.xib and wired via @IBOutlet.
    // No manual NSWindow creation needed — Xcode's XIB handles it.
    @IBOutlet var window: NSWindow!

    var pdfView: AnimaPDFView!
    var eventMonitor: Any?

    func applicationDidFinishLaunching(_ aNotification: Notification) {

        // --- Create the PDF view and add it to the XIB-provided window ---
        pdfView = AnimaPDFView(frame: window.contentView!.bounds)
        pdfView.autoresizingMask = [.width, .height]  // resize with window
        pdfView.autoScales = true                       // fit to view on open
        pdfView.displayMode = .singlePageContinuous     // continuous scroll

        // --- Load the PDF ---
        // TODO: Replace with proper file-open dialog or command-line argument.
        //       For now, use a hardcoded path for development.
        let pdfPath = NSString("~/Projects/anima/data/input.pdf").expandingTildeInPath
        let url = URL(fileURLWithPath: pdfPath)
        if let document = PDFDocument(url: url) {
            pdfView.document = document
            Swift.print("✅ Loaded PDF: \(url.path)")
        } else {
            Swift.print("❌ Failed to load PDF: \(pdfPath)")
        }

        window.contentView!.addSubview(pdfView)

        // --- Keyboard event monitor (fallback) ---
        // PDFKit's internal PDFDocumentView swallows key events.
        // We try the subclass override first (AnimaPDFView.keyDown), but if
        // that doesn't fire, this monitor catches events at the app level.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self = self else { return event }
            if self.pdfView.handleKeyEvent(event) {
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
