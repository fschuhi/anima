//
//  MainViewController.swift
//  Anima
//
//  Created by Frank Schuhardt on 15.03.26.
//


//
//  MainViewController.swift
//  Anima
//
//  Manages the primary NSSplitView layout containing the PDF rendering view
//  on the left and the annotation sidebar on the right.
//

import Cocoa
import Quartz

class MainViewController: NSViewController {

    var pdfView: AnimaPDFView!
    var sidebarView: NSView!
    var splitView: NSSplitView!

    override func loadView() {
        // 1. Create the Split View
        splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        // 2. Create and configure the PDF View
        pdfView = AnimaPDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous

        // 3. Create the placeholder Sidebar View
        sidebarView = NSView()
        sidebarView.wantsLayer = true
        // Give it a subtle background color so we can see its geometry during Phase 0
        sidebarView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // 4. Add views to the split view
        splitView.addArrangedSubview(pdfView)
        splitView.addArrangedSubview(sidebarView)

        // 5. Layout rules
        // Tell the Auto Layout engine that the PDF view should eagerly stretch to fill space,
        // and the sidebar should resist stretching.
        pdfView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        sidebarView.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        // Enforce minimum widths so neither pane can be completely collapsed
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        sidebarView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            pdfView.widthAnchor.constraint(greaterThanOrEqualToConstant: 400),
            pdfView.heightAnchor.constraint(greaterThanOrEqualToConstant: 600),
            sidebarView.widthAnchor.constraint(greaterThanOrEqualToConstant: 250)
        ])

        // The split view is the root view of this controller
        self.view = splitView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Set an initial reasonable width for the sidebar (e.g., 300 pixels)
        // by positioning the divider relative to the window's starting width.
        let initialSidebarWidth: CGFloat = 300
        let totalWidth = self.view.bounds.width
        splitView.setPosition(totalWidth - initialSidebarWidth, ofDividerAt: 0)
    }
}
