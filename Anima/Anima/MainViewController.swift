//
//  MainViewController.swift
//  Anima
//
//  Manages the primary NSSplitView layout containing the PDF rendering view
//  on the left and the annotation sidebar on the right.
//

import Cocoa
import Quartz

// --- Test Pattern View ---
class TallStripedView: NSView {

    // Top-left origin (Y increases downwards)
    override var isFlipped: Bool { return true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let stripeHeight: CGFloat = 50
        let colors: [NSColor] = [
            NSColor.systemRed.withAlphaComponent(0.1),
            NSColor.systemBlue.withAlphaComponent(0.1)
        ]

        var y: CGFloat = 0
        var index = 0

        while y < bounds.height {
            colors[index % 2].setFill()
            let rect = NSRect(x: 0, y: y, width: bounds.width, height: stripeHeight)
            if dirtyRect.intersects(rect) {
                rect.fill()
            }
            y += stripeHeight
            index += 1
        }
    }
}

// --- Custom Sidebar Scroll View ---
// Hides its scrollbar and forwards trackpad/mouse wheel events to the PDF's internal scroll view
class SidebarScrollView: NSScrollView {
    weak var targetScrollView: NSScrollView?

    override func scrollWheel(with event: NSEvent) {
        if let target = targetScrollView {
            // Pass the scroll event directly to the PDF's internal scroll view
            target.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

class MainViewController: NSViewController {

    var pdfView: AnimaPDFView!
    var sidebarScrollView: SidebarScrollView!
    var splitView: NSSplitView!

    private var pdfScrollView: NSScrollView?

    override func loadView() {
        splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        pdfView = AnimaPDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous

        sidebarScrollView = SidebarScrollView()
        sidebarScrollView.hasVerticalScroller = false
        sidebarScrollView.borderType = .noBorder

        let tallView = TallStripedView(frame: NSRect(x: 0, y: 0, width: 300, height: 10000))
        sidebarScrollView.documentView = tallView

        splitView.addArrangedSubview(pdfView)
        splitView.addArrangedSubview(sidebarScrollView)

        pdfView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        sidebarScrollView.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        pdfView.translatesAutoresizingMaskIntoConstraints = false
        sidebarScrollView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            pdfView.widthAnchor.constraint(greaterThanOrEqualToConstant: 400),
            pdfView.heightAnchor.constraint(greaterThanOrEqualToConstant: 600),
            sidebarScrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: 250)
        ])

        self.view = splitView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let initialSidebarWidth: CGFloat = 300
        let totalWidth = self.view.bounds.width
        splitView.setPosition(totalWidth - initialSidebarWidth, ofDividerAt: 0)

        setupScrollSynchronization()
    }

    // --- Scroll Physics ---

    private func setupScrollSynchronization() {
        pdfScrollView = pdfView.subviews.compactMap { $0 as? NSScrollView }.first

        guard let pdfScrollView = pdfScrollView else {
            Swift.print("⚠️ Could not find internal PDF scroll view!")
            return
        }

        // Link the hover scrolling
        sidebarScrollView.targetScrollView = pdfScrollView

        pdfScrollView.contentView.postsBoundsChangedNotifications = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pdfViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: pdfScrollView.contentView
        )
    }

    @objc private func pdfViewDidScroll(_ notification: Notification) {
        guard let pdfClipView = notification.object as? NSClipView,
              let pdfDocView = pdfClipView.documentView,
              let sidebarDocView = sidebarScrollView.documentView else { return }

        // 1. Fix the "Overtaking" Parallax: Force the sidebar document to be exactly as tall as the scaled PDF document
        if sidebarDocView.frame.height != pdfDocView.frame.height {
            sidebarDocView.setFrameSize(NSSize(width: sidebarDocView.frame.width, height: pdfDocView.frame.height))
        }

        // 2. Calculate the synchronized Y position
        let pdfOriginY = pdfClipView.bounds.origin.y
        var targetY: CGFloat = 0

        if pdfDocView.isFlipped {
            // Rare, but if PDFKit ever changes to top-left origin, map it 1:1
            targetY = pdfOriginY
        } else {
            // Standard PDFKit: Bottom-left origin. We invert it to match our top-left sidebar.
            targetY = pdfDocView.bounds.height - pdfClipView.bounds.height - pdfOriginY
        }

        // 3. Apply the scroll
        let sidebarClipView = sidebarScrollView.contentView
        var newBounds = sidebarClipView.bounds
        newBounds.origin.y = targetY
        sidebarClipView.bounds = newBounds
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
