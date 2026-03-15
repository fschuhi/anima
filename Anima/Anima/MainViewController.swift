//
//  MainViewController.swift
//  Anima
//
//  Manages the primary NSSplitView layout containing the PDF rendering view
//  on the left and the annotation sidebar on the right.
//

import Cocoa
import Quartz

// --- Sidebar Master Container ---
class SidebarDocumentView: NSView {
    // Top-left origin makes layout math easier
    override var isFlipped: Bool { return true }
}

// --- Page-Sidebar Container ---
class PageSidebarView: NSView {
    let pageIndex: Int
    var cardViews: [CommentCardView] = []

    override var isFlipped: Bool { return true }

    init(pageIndex: Int) {
        self.pageIndex = pageIndex
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func addCardView(_ cardView: CommentCardView) {
        self.addSubview(cardView)
        self.cardViews.append(cardView)
    }
}

// --- Custom Sidebar Scroll View ---
class SidebarScrollView: NSScrollView {
    weak var targetScrollView: NSScrollView?

    override func scrollWheel(with event: NSEvent) {
        if let target = targetScrollView {
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
    private var pageSidebarViews: [PageSidebarView] = []

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

        let sidebarDocView = SidebarDocumentView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        sidebarScrollView.documentView = sidebarDocView

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
        setupResizeObserver()
    }

    // --- Data Loading ---

    func loadPDF(document: PDFDocument) {
        pdfView.document = document

        let cards = SidebarExtractor.extractCards(from: document)
        guard let sidebarDocView = sidebarScrollView.documentView else { return }

        sidebarDocView.subviews.forEach { $0.removeFromSuperview() }
        pageSidebarViews.removeAll()

        let cardsByPage = Dictionary(grouping: cards, by: { $0.pageIndex })

        for pageIndex in 0..<document.pageCount {
            let pageView = PageSidebarView(pageIndex: pageIndex)

            if let pageCards = cardsByPage[pageIndex] {
                for card in pageCards {
                    let cardView = CommentCardView(card: card)
                    pageView.addCardView(cardView)
                }
            }

            sidebarDocView.addSubview(pageView)
            pageSidebarViews.append(pageView)
        }

        pdfView.layoutDocumentView()
        updateSidebarLayout()
    }

    // --- Scroll Physics ---

    private func setupScrollSynchronization() {
        pdfScrollView = pdfView.subviews.compactMap { $0 as? NSScrollView }.first
        guard let pdfScrollView = pdfScrollView else { return }
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
              let pdfDocView = pdfClipView.documentView else { return }

        let scale = pdfView.scaleFactor
        let pdfOriginY = pdfClipView.bounds.origin.y
        let unscaledDocHeight = pdfDocView.bounds.height
        let unscaledClipHeight = pdfClipView.bounds.height

        // Calculate unscaled target, then multiply by zoom factor
        let unscaledTargetY = pdfDocView.isFlipped ? pdfOriginY : (unscaledDocHeight - unscaledClipHeight - pdfOriginY)
        let scaledTargetY = unscaledTargetY * scale

        let sidebarClipView = sidebarScrollView.contentView
        var newBounds = sidebarClipView.bounds
        newBounds.origin.y = scaledTargetY
        sidebarClipView.bounds = newBounds
    }

    // --- Layout & Coordinate Math ---

    private func setupResizeObserver() {
        pdfView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pdfViewDidResize(_:)),
            name: NSView.frameDidChangeNotification,
            object: pdfView
        )
    }

    @objc private func pdfViewDidResize(_ notification: Notification) {
        updateSidebarLayout()
    }

    private func updateSidebarLayout() {
        guard let document = pdfView.document,
              let pdfDocView = pdfScrollView?.documentView,
              let sidebarDocView = sidebarScrollView.documentView else { return }

        let sidebarWidth = sidebarScrollView.contentSize.width
        let scale = pdfView.scaleFactor

        // 1. Scale the master sidebar document view
        let scaledDocHeight = pdfDocView.bounds.height * scale
        if sidebarDocView.frame.height != scaledDocHeight {
            sidebarDocView.setFrameSize(NSSize(width: sidebarWidth, height: scaledDocHeight))
        }

        // 2. Position pages using scaled math
        for pageView in pageSidebarViews {
            guard let page = document.page(at: pageView.pageIndex) else { continue }

            let pageBounds = page.bounds(for: pdfView.displayBox)
            let pdfTopLeft = NSPoint(x: pageBounds.minX, y: pageBounds.maxY)
            let pdfBottomLeft = NSPoint(x: pageBounds.minX, y: pageBounds.minY)

            // Convert to unscaled document coordinates
            let docTopLeft = pdfView.convert(pdfView.convert(pdfTopLeft, from: page), to: pdfDocView)
            let docBottomLeft = pdfView.convert(pdfView.convert(pdfBottomLeft, from: page), to: pdfDocView)

            let unscaledTopY = pdfDocView.bounds.height - docTopLeft.y
            let unscaledBottomY = pdfDocView.bounds.height - docBottomLeft.y
            let unscaledPageHeight = unscaledBottomY - unscaledTopY

            // Multiply by scale factor to get physical screen pixels
            let scaledTopY = unscaledTopY * scale
            let scaledPageHeight = unscaledPageHeight * scale

            pageView.frame = NSRect(x: 0, y: scaledTopY, width: sidebarWidth, height: scaledPageHeight)

            // 3. Position cards locally inside the scaled page container
            for cardView in pageView.cardViews {
                let card = cardView.card

                // Distance from top of page * scale factor
                let distanceFromTop = pageBounds.maxY - card.anchorY
                let localCenterY = distanceFromTop * scale

                // Let the card calculate its own height
                cardView.frame.size.width = sidebarWidth
                let fittingHeight = cardView.fittingSize.height

                let finalY = localCenterY - (fittingHeight / 2)
                cardView.frame = NSRect(x: 0, y: finalY, width: sidebarWidth, height: fittingHeight)
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
