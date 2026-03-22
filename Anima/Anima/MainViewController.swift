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
//  Highlight emphasis (bidirectional):
//    Clicking a sidebar card OR clicking a highlight in the PDF both
//    trigger the same emphasis logic via applyEmphasis(to:on:cardView:).
//    The emphasized highlight gets a light yellow color/opacity change,
//    and the corresponding card (if any) gets an accent border.
//
//    Only one highlight/card pair can be emphasized at a time. Clicking
//    the same highlight or card again clears the emphasis (toggle).
//    Double-clicking ensures emphasis is on (no toggle) before opening
//    the comment dialog.
//
//    The emphasis state is unified with AnimaPDFView's selectedAnnotation
//    so that the Delete key always targets the visually emphasized highlight.
//
//    Emphasis survives sidebar rebuilds after annotation mutations (e.g.
//    after editing a comment via double-click). The UUID of the emphasized
//    annotation is remembered, and emphasis is re-applied to the (possibly
//    rebuilt) card after the rebuild completes.
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

    // UUID of the currently emphasized annotation. Used to re-apply emphasis
    // after sidebar rebuilds (the card views are torn down and recreated,
    // so activeCardView becomes stale — but the UUID survives).
    private var emphasizedUUID: String?
    private var emphasizedPageIndex: Int?

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
        // Remember emphasis state before rebuild — the card views will be
        // destroyed and recreated, but the PDF annotation and UUID survive.
        let preserveUUID = emphasizedUUID
        let preservePageIndex = emphasizedPageIndex

        // Clear card-side emphasis (the card view is about to be torn down).
        // Keep the PDF-side emphasis intact — the annotation object survives
        // the rebuild, so we don't need to save/restore its color.
        activeCardView?.setInactive()
        activeCardView = nil

        rebuildPageSidebar(at: pageIndex)
        updateSidebarLayout()

        // Re-apply card-side emphasis if the annotation is still emphasized.
        // This handles the double-click flow: user edits a comment, sidebar
        // rebuilds, and the newly created/updated card should show as active.
        if let uuid = preserveUUID, let pi = preservePageIndex {
            if let cardView = findCardView(uuid: uuid, onPageIndex: pi) {
                activeCardView = cardView
                cardView.setActive()
                Swift.print("🟡 Emphasis re-applied to card after rebuild: \(uuid)")
            }
        }
    }

    func highlightWasClicked(uuid: String, onPageIndex pageIndex: Int, toggle: Bool) {
        // Empty UUID means "clicked outside any highlight" — clear emphasis
        if uuid.isEmpty {
            clearEmphasis()
            Swift.print("⚪ Emphasis cleared (clicked outside highlight)")
            return
        }

        guard let document = pdfView.document,
              let page = document.page(at: pageIndex) else { return }

        // Find the annotation by UUID
        guard let annot = findAnnotation(uuid: uuid, on: page) else {
            Swift.print("⚠️  Could not find highlight for UUID \(uuid)")
            return
        }

        // Toggle mode (single-click): if clicking the already-emphasized
        // annotation, clear it. Non-toggle mode (double-click): if already
        // emphasized on this annotation, it's a no-op.
        if annot === emphasizedAnnotation {
            if toggle {
                clearEmphasis()
                Swift.print("⚪ Emphasis cleared (same highlight clicked)")
            }
            return
        }

        // Find the corresponding card view (may be nil if highlight has no comment)
        let cardView = findCardView(uuid: uuid, onPageIndex: pageIndex)

        // Apply emphasis to both highlight and card (if any)
        applyEmphasis(to: annot, on: page, uuid: uuid, pageIndex: pageIndex, cardView: cardView)

        Swift.print("🟡 Emphasis applied to \(uuid) on page \(pageIndex)")
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

    // --- Card Click Handler ---

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
        guard let annot = findAnnotation(uuid: card.uuid, on: page) else {
            Swift.print("⚠️  Could not find highlight for card \(card.uuid)")
            return
        }

        // Toggle: if clicking the already-emphasized annotation, clear it
        if annot === emphasizedAnnotation {
            clearEmphasis()
            Swift.print("⚪ Emphasis cleared (same card clicked)")
            return
        }

        // Apply emphasis to both highlight and card
        applyEmphasis(to: annot, on: page, uuid: card.uuid, pageIndex: card.pageIndex, cardView: cardView)

        Swift.print("🟡 Emphasis applied to \(card.uuid) on page \(card.pageIndex) (from card click)")
    }

    // --- Shared Emphasis Logic ---
    // Used by both card-click and highlight-click paths.

    /// Find an annotation by UUID on a specific page.
    private func findAnnotation(uuid: String, on page: PDFPage) -> PDFAnnotation? {
        for annot in page.annotations {
            if annot.type == "Highlight" {
                // Check /NM first
                if let nm = annot.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/NM")) as? String,
                   nm == uuid {
                    return annot
                }
                // Fallback: userName
                if let name = annot.userName, name == uuid {
                    return annot
                }
            }
        }
        return nil
    }

    /// Find the CommentCardView for a given UUID on a given page.
    /// Returns nil if no card exists (e.g. highlight has no comment).
    private func findCardView(uuid: String, onPageIndex pageIndex: Int) -> CommentCardView? {
        guard pageIndex < pageSidebarViews.count else { return nil }
        let pageView = pageSidebarViews[pageIndex]
        return pageView.cardViews.first { $0.card.uuid == uuid }
    }

    /// Apply emphasis to a highlight annotation and optionally its sidebar card.
    /// Saves original appearance for later restoration, updates the PDF view,
    /// and unifies with AnimaPDFView's selectedAnnotation for Delete key support.
    ///
    /// - Parameters:
    ///   - annot: The PDFAnnotation to emphasize
    ///   - page: The page the annotation lives on
    ///   - uuid: The annotation's UUID (stored for surviving sidebar rebuilds)
    ///   - pageIndex: The page index (stored for surviving sidebar rebuilds)
    ///   - cardView: The corresponding CommentCardView, or nil if the highlight has no comment
    private func applyEmphasis(to annot: PDFAnnotation, on page: PDFPage, uuid: String, pageIndex: Int, cardView: CommentCardView?) {
        // Clear any existing emphasis first
        clearEmphasis()

        // Save originals so we can restore later
        emphasizedAnnotation = annot
        emphasizedOriginalColor = annot.color
        emphasizedOriginalOpacity = annot.value(
            forAnnotationKey: PDFAnnotationKey(rawValue: "/CA")
        ) as? CGFloat ?? AnimaPDFView.highlightOpacity

        // Remember UUID/page for surviving sidebar rebuilds
        emphasizedUUID = uuid
        emphasizedPageIndex = pageIndex

        // Apply highlight emphasis
        annot.color = MainViewController.emphasisColor
        annot.setValue(MainViewController.emphasisOpacity,
                       forAnnotationKey: PDFAnnotationKey(rawValue: "/CA"))

        // Apply card emphasis (if card exists)
        if let cardView = cardView {
            activeCardView = cardView
            cardView.setActive()
        }

        // Unify with selectedAnnotation so Delete key targets the emphasized highlight
        pdfView.selectedAnnotation = annot
        pdfView.selectedAnnotationPage = page

        // Force PDF redraw
        pdfView.setNeedsDisplay(pdfView.bounds)
    }

    /// Restores the previously emphasized annotation and card to their
    /// normal appearance, and clears the selectedAnnotation state.
    private func clearEmphasis() {
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

        // Clear emphasis state
        emphasizedAnnotation = nil
        emphasizedOriginalColor = nil
        emphasizedOriginalOpacity = nil
        activeCardView = nil
        emphasizedUUID = nil
        emphasizedPageIndex = nil

        // Clear selectedAnnotation (unified with emphasis)
        pdfView.selectedAnnotation = nil
        pdfView.selectedAnnotationPage = nil
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
