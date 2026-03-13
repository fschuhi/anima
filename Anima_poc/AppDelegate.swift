// AppDelegate.swift — Anima PoC
//
// Responds to "the app launched" by creating a window with a PDFView inside it.
// Also sets up an NSEvent monitor as a fallback for keyboard events, in case
// the PDFView subclass override doesn't fire (the same problem we had in PyObjC).

import Cocoa
import Quartz  // PDFKit lives inside the Quartz framework on macOS

class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!
    var pdfView: AnimaPDFView!
    var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {

        // --- Create the window ---
        let windowRect = NSRect(x: 100, y: 100, width: 900, height: 700)
        window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Anima PoC"
        window.center()

        // --- Create the PDF view ---
        pdfView = AnimaPDFView(frame: window.contentView!.bounds)
        pdfView.autoresizingMask = [.width, .height]  // resize with window
        pdfView.autoScales = true                       // fit to view on open
        pdfView.displayMode = .singlePageContinuous     // continuous scroll

        // --- Load the PDF ---
        let pdfPath = "./input.pdf"
        let url = URL(fileURLWithPath: pdfPath)
        if let document = PDFDocument(url: url) {
            pdfView.document = document
            print("✅ Loaded PDF: \(url.path)")
        } else {
            print("❌ Failed to load PDF: \(pdfPath)")
            print("   Make sure you run ./anima from the folder containing input.pdf")
        }

        window.contentView!.addSubview(pdfView)
        window.makeKeyAndOrderFront(nil)

        // --- Keyboard event monitor (fallback) ---
        // In PyObjC, PDFView's internal PDFDocumentView swallowed key events.
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

        // Activate the app (bring window to front)
		NSApp.setActivationPolicy(.regular)  // NEW: register as a proper GUI app
		NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true  // quit when the window is closed
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
