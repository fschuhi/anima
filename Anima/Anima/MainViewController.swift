//
//  MainViewController.swift
//  Anima
//
//  Manages the primary NSSplitView layout containing the PDF rendering view
//  on the left and the annotation sidebar on the right.
//
//  Sidebar update flow:
//    AnimaPDFView mutates an annotation (create/edit/delete) and calls
//    sidebarDelegate.annotationsDidChange(onPageIndex:). This triggers
//    rebuildPageSidebar(at:), which tears down the affected page's card
//    views, re-extracts cards via SidebarExtractor, rebuilds the views,
//    and re-runs the layout algorithm. All within one run loop cycle,
//    so the user sees a single atomic visual update.
//
//  Highlight emphasis:
//    Clicking a sidebar card emphasizes the corresponding highlight in the
//    PDF by temporarily changing its color/opacity, and visually marks the
//    card as active. Only one highlight/card pair can be emphasized at a
//    time. Clicking the same card again clears the emphasis.
//

import Cocoa
import Quartz

// --- Sidebar Master Container ---
class SidebarDocumentView: NSView {
    // Top-left origin makes layout math easier
    override var isFlipped: Bool { return true }
}

// --- Page-Sidebar Internal Canvas ---
class PageDocumentView: NSView {
    override var isFlipped: Bool { return true }
}

// --- Page-Sidebar Container ---
class PageSidebarView: NSScrollView {
    let pageIndex: Int
    var cardViews: [CommentCardView] = []

    init(pageIndex: Int) {
        self.pageIndex = pageIndex
        super.init(frame: .zero)

        self.hasVerticalScroller = true
        self.hasHorizontalScroller = false
        self.autohidesScrollers = true
        self.drawsBackground = false
        self.borderType = .noBorder
        self.documentView = PageDocumentView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func addCardView(_ cardView: CommentCardView) {
        self.documentView?.addSubview(cardView)
        self.cardViews.append(cardView)
    }

    /// Remove all card views and reset the list.
    func removeAllCardViews() {
        for cardView in cardViews {
            cardView.removeFromSuperview()
        }
        cardViews.removeAll()
    }

    // Smart Scroll Routing
    override func scrollWheel(with event: NSEvent) {
        if let docView = documentView, docView.frame.height <= self.bounds.height {
            // Content fits perfectly. Pass the scroll event up to the master sidebar/PDF!
            self.nextResponder?.scrollWheel(with: event)
        } else {
            // Cards are overflowing. Let this local scroll view handle it.
            super.scrollWheel(with: event)
        }
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

class MainViewController: NSViewController, SidebarUpdateDelegate {

    var pdfView: AnimaPDFView!
    var sidebarScrollView: SidebarScrollView!
    var splitView: NSSplitView!

    private var pdfScrollView: NSScrollView?
    private var pageSidebarViews: [PageSidebarView] = []

    // --- Highlight emphasis state ---
    // Tracks the currently emphasized annotation and card so we can restore
    // their original appearance when emphasis moves or clears.
    private var emphasizedAnnotation: PDFAnnotation?
    private var emphasizedOriginalColor: NSColor?
    private var emphasizedOriginalOpacity: CGFloat?
    private var activeCardView: CommentCardView?

    // Emphasis appearance — light yellow (#FFFFE0) at higher opacity
    private static let emphasisColor = NSColor(red: 1.0, green: 1.0, blue: 0.878, alpha: 1.0)
    private static let emphasisOpacity: CGFloat = 0.7

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

        // Wire up the sidebar delegate so annotation mutations trigger rebuilds
        pdfView.sidebarDelegate = self

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
                    wireCardClickHandler(cardView)
                    pageView.addCardView(cardView)
                }
            }

            sidebarDocView.addSubview(pageView)
            pageSidebarViews.append(pageView)
        }

        pdfView.layoutDocumentView()
        updateSidebarLayout()
    }

    // --- SidebarUpdateDelegate ---

    func annotationsDidChange(onPageIndex pageIndex: Int) {
        // Clear emphasis — the underlying annotation may have been deleted
        // or its comment changed, so the emphasis state could be stale.
        clearHighlightEmphasis()
        rebuildPageSidebar(at: pageIndex)
        updateSidebarLayout()
    }

    // --- Page-Sidebar Rebuild ---

    /// Tears down all card views for the given page, re-extracts cards from
    /// the PDFDocument's current in-memory annotations, and rebuilds the
    /// card views. Called after any annotation mutation on that page.
    private func rebuildPageSidebar(at pageIndex: Int) {
        guard let document = pdfView.document,
              let page = document.page(at: pageIndex) else { return }

        // Find the PageSidebarView for this page index
        guard pageIndex < pageSidebarViews.count else { return }
        let pageView = pageSidebarViews[pageIndex]

        // Tear down existing cards
        pageView.removeAllCardViews()

        // Re-extract cards from the page's current annotations
        let cards = SidebarExtractor.extractCards(from: page, at: pageIndex)

        // Rebuild card views
        for card in cards {
            let cardView = CommentCardView(card: card)
            wireCardClickHandler(cardView)
            pageView.addCardView(cardView)
        }

        Swift.print("🔄 Sidebar rebuilt for page \(pageIndex): \(cards.count) card(s)")
    }

    // --- Card Click → Highlight Emphasis ---

    /// Sets up the onClicked closure for a card view. Called during initial
    /// load and after page-sidebar rebuilds.
    private func wireCardClickHandler(_ cardView: CommentCardView) {
        cardView.onClicked = { [weak self] card in
            self?.handleCardClicked(card, fromCardView: cardView)
        }
    }

    /// Responds to a sidebar card being clicked: emphasizes the corresponding
    /// highlight in the PDF and marks the card as active. Clicking the same
    /// card again clears the emphasis.
    private func handleCardClicked(_ card: CommentCard, fromCardView cardView: CommentCardView) {
        guard let document = pdfView.document,
              let page = document.page(at: card.pageIndex) else { return }

        // Find the annotation by UUID
        var targetAnnot: PDFAnnotation?
        for annot in page.annotations {
            if annot.type == "Highlight" {
                // Check /NM first
                if let nm = annot.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/NM")) as? String,
                   nm == card.uuid {
                    targetAnnot = annot
                    break
                }
                // Fallback: userName
                if let name = annot.userName, name == card.uuid {
                    targetAnnot = annot
                    break
                }
            }
        }

        guard let annot = targetAnnot else {
            Swift.print("⚠️  Could not find highlight for card \(card.uuid)")
            return
        }

        // Toggle: if clicking the already-emphasized annotation, clear it
        if annot === emphasizedAnnotation {
            clearHighlightEmphasis()
            Swift.print("⚪ Emphasis cleared (same card clicked)")
            return
        }

        // Clear any existing emphasis first
        clearHighlightEmphasis()

        // Apply highlight emphasis — save originals so we can restore later
        emphasizedAnnotation = annot
        emphasizedOriginalColor = annot.color
        emphasizedOriginalOpacity = annot.value(
            forAnnotationKey: PDFAnnotationKey(rawValue: "/CA")
        ) as? CGFloat ?? AnimaPDFView.highlightOpacity

        annot.color = MainViewController.emphasisColor
        annot.setValue(MainViewController.emphasisOpacity,
                       forAnnotationKey: PDFAnnotationKey(rawValue: "/CA"))

        // Apply card emphasis
        activeCardView = cardView
        cardView.setActive()

        // Force PDF redraw
        pdfView.setNeedsDisplay(pdfView.bounds)

        Swift.print("🟡 Emphasis applied to \(card.uuid) on page \(card.pageIndex)")
    }

    /// Restores the previously emphasized annotation and card to their
    /// normal appearance.
    private func clearHighlightEmphasis() {
        // Restore highlight
        if let annot = emphasizedAnnotation {
            if let originalColor = emphasizedOriginalColor {
                annot.color = originalColor
            }
            if let originalOpacity = emphasizedOriginalOpacity {
                annot.setValue(originalOpacity,
                              forAnnotationKey: PDFAnnotationKey(rawValue: "/CA"))
            }
            pdfView.setNeedsDisplay(pdfView.bounds)
        }

        // Restore card
        activeCardView?.setInactive()

        emphasizedAnnotation = nil
        emphasizedOriginalColor = nil
        emphasizedOriginalOpacity = nil
        activeCardView = nil
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

        let scaledDocHeight = pdfDocView.bounds.height * scale
        if sidebarDocView.frame.height != scaledDocHeight {
            sidebarDocView.setFrameSize(NSSize(width: sidebarWidth, height: scaledDocHeight))
        }

        for pageView in pageSidebarViews {
            guard let page = document.page(at: pageView.pageIndex) else { continue }

            let pageBounds = page.bounds(for: pdfView.displayBox)
            let pdfTopLeft = NSPoint(x: pageBounds.minX, y: pageBounds.maxY)
            let pdfBottomLeft = NSPoint(x: pageBounds.minX, y: pageBounds.minY)

            let docTopLeft = pdfView.convert(pdfView.convert(pdfTopLeft, from: page), to: pdfDocView)
            let docBottomLeft = pdfView.convert(pdfView.convert(pdfBottomLeft, from: page), to: pdfDocView)

            let unscaledTopY = pdfDocView.bounds.height - docTopLeft.y
            let unscaledBottomY = pdfDocView.bounds.height - docBottomLeft.y
            let unscaledPageHeight = unscaledBottomY - unscaledTopY

            let scaledTopY = unscaledTopY * scale
            let scaledPageHeight = unscaledPageHeight * scale

            pageView.frame = NSRect(x: 0, y: scaledTopY, width: sidebarWidth, height: scaledPageHeight)

            // --- COLLISION AVOIDANCE ALGORITHM ---
            var previousCardBottomEdge: CGFloat = 0
            let cardPadding: CGFloat = 8

            let cardWidth = sidebarWidth - 16

            for cardView in pageView.cardViews {
                let card = cardView.card

                let distanceFromTop = pageBounds.maxY - card.anchorY
                let localCenterY = distanceFromTop * scale

                cardView.frame.size.width = cardWidth
                let fittingHeight = cardView.fittingSize.height

                var finalY = localCenterY - (fittingHeight / 2)

                if finalY < previousCardBottomEdge {
                    finalY = previousCardBottomEdge
                }

                cardView.frame = NSRect(x: 0, y: finalY, width: cardWidth, height: fittingHeight)

                previousCardBottomEdge = finalY + fittingHeight + cardPadding
            }

            // --- OVERFLOW HANDLING ---
            if let docView = pageView.documentView {
                let requiredHeight = max(scaledPageHeight, previousCardBottomEdge)
                docView.setFrameSize(NSSize(width: sidebarWidth, height: requiredHeight))
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
