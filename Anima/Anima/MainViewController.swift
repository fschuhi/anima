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
//  Comment search:
//    Comment-only search is coordinated here because this controller owns
//    the sidebar card views. Matches are ordered from the current PDF page
//    forward without wrapping. Matching cards receive thin pale-green borders;
//    the current F3 result receives a thick pale-green border. Comment search
//    is navigation only: it scrolls to the corresponding PDF location and
//    fully reveals the matching card, but does not emphasize an annotation or
//    make it the Delete-key target.
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

    // --- Split-view persistence and sizing policy ---
    // AppKit persists the actual divider configuration under this name.
    private static let splitViewAutosaveName = "AnimaMainSplitView"

    // On the very first launch there is no AppKit divider state to restore.
    // This marker ensures the 300-point first-run default is not applied again
    // over a divider position restored from splitViewAutosaveName.
    private static let hasInitializedDefaultDividerKey = "Anima.hasInitializedMainSplitViewDivider"

    private static let initialSidebarWidth: CGFloat = 300

    // This remains below AppKit's drag-related threshold, while being higher
    // than the PDF pane's default-low priority. Therefore ordinary window
    // resizes preserve the sidebar width and let the PDF pane absorb change.
    private static let sidebarHoldingPriority = NSLayoutConstraint.Priority(rawValue: 500)

    // --- Highlight emphasis state ---
    // Tracks the currently emphasized annotation and card so we can restore
    // their original appearance when emphasis moves or clears.
    private var emphasizedAnnotation: PDFAnnotation?
    private var emphasizedOriginalColor: NSColor?
    private var emphasizedOriginalOpacity: CGFloat?
    private var activeCardView: CommentCardView?

    // UUID of the currently emphasized annotation. Used to re-apply emphasis
    // after sidebar rebuilds (the card views are torn down and recreated,
    // so activeCardView becomes stale -- but the UUID survives).
    private var emphasizedUUID: String?
    private var emphasizedPageIndex: Int?

    // Emphasis appearance -- light yellow (#FFFFE0) at higher opacity
    private static let emphasisColor = NSColor(red: 1.0, green: 1.0, blue: 0.878, alpha: 1.0)
    private static let emphasisOpacity: CGFloat = 0.7

    // --- Comment-search state ---
    // Each result identifies a card by its stable annotation UUID and page.
    // The sidebar card views themselves are rebuilt after annotation mutation,
    // so storing view instances here would create stale references.
    private var activeCommentSearchQuery: String?
    private var commentSearchResults: [(uuid: String, pageIndex: Int)] = []
    private var activeCommentSearchResultIndex: Int?

    /// Exposed for the upcoming keyboard-routing step. A comment search is
    /// active only after it has found at least one result and displayed it.
    var hasActiveCommentSearch: Bool {
        activeCommentSearchResultIndex != nil
    }

    /// Exposed for the upcoming ordered-Esc behavior.
    var hasAnnotationEmphasis: Bool {
        emphasizedAnnotation != nil
    }

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

        // The PDF pane should absorb ordinary window-width changes. The
        // sidebar still remains draggable and retains its existing minimum.
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        splitView.setHoldingPriority(MainViewController.sidebarHoldingPriority, forSubviewAt: 1)

        // AppKit owns persistence of the divider after this point.
        splitView.autosaveName = MainViewController.splitViewAutosaveName

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

        applyInitialSidebarWidthIfNeeded()
        setupScrollSynchronization()
        setupResizeObserver()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pdfViewPageDidChange(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )
    }

    /// Applies Anima's 300-point sidebar default only for a truly new install.
    ///
    /// The asynchronous turn is deliberate: AppKit needs to finish laying out
    /// the split view before minPossiblePositionOfDivider(at:) and
    /// maxPossiblePositionOfDivider(at:) are meaningful. On later launches,
    /// the marker leaves AppKit's autosaved divider configuration untouched.
    private func applyInitialSidebarWidthIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: MainViewController.hasInitializedDefaultDividerKey) else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  !UserDefaults.standard.bool(forKey: MainViewController.hasInitializedDefaultDividerKey) else {
                return
            }

            self.splitView.layoutSubtreeIfNeeded()

            let requestedPosition = self.splitView.bounds.width - MainViewController.initialSidebarWidth
            let minimumPosition = self.splitView.minPossiblePositionOfDivider(at: 0)
            let maximumPosition = self.splitView.maxPossiblePositionOfDivider(at: 0)
            let initialPosition = min(max(requestedPosition, minimumPosition), maximumPosition)

            self.splitView.setPosition(initialPosition, ofDividerAt: 0)
            UserDefaults.standard.set(true, forKey: MainViewController.hasInitializedDefaultDividerKey)
        }
    }

    // --- Data Loading ---

    func loadPDF(document: PDFDocument) {
        // 1. Scrub comments into our custom key to suppress native popups BEFORE rendering
        scrubCommentsForPopupSuppression(in: document)

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
        pdfView.updateWindowTitle()
    }

    /// Clears document-specific transient state before loading a replacement PDF.
    /// This includes PDF-text search hits, comment-search card borders, annotation
    /// emphasis, text selection, and the Delete-key target.
    func clearOutgoingDocumentState() {
        pdfView.clearSearchAndSelection()
        pdfView.isHighlightMode = false
        pdfView.isXRayMode = false
    }

    @objc private func pdfViewPageDidChange(_ notification: Notification) {
        pdfView.updateWindowTitle()
    }

    /// Iterates through the document and moves standard `.contents` text into our
    /// custom `/AnimaComment` dictionary key, then clears `.contents`.
    /// Crucially, it aggressively severs all links to Popup annotations to force
    /// PDFKit to drop them from the rendering tree.
    private func scrubCommentsForPopupSuppression(in document: PDFDocument) {
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }

            var popupsToRemove: [PDFAnnotation] = []

            for annot in page.annotations {
                if annot.type == "Highlight" {

                    // PDFKit ignores the fitz-generated appearance stream and renders
                    // highlights more saturated than PDF-XChange Viewer and Chromium-based
                    // browsers. This affects in-memory display only; Anima never saves
                    // through PDFKit, so the persisted PDF annotation remains unchanged.
                    annot.color = AnnotationManager.pdfKitDisplayHighlightColor

                    // 1. Migrate the text
                    if let text = annot.contents, !text.isEmpty {
                        annot.setValue(text, forAnnotationKey: PDFAnnotationKey(rawValue: "/AnimaComment"))
                        annot.contents = "" // Wipe standard contents
                    }

                    // 2. Aggressively sever the Popup connection
                    if let popup = annot.popup {
                        popupsToRemove.append(popup)
                        annot.popup = nil // Break the PDFKit property link
                    }

                    // Break the low-level PDF dictionary link just to be sure
                    annot.removeValue(forAnnotationKey: PDFAnnotationKey(rawValue: "/Popup"))

                } else if annot.type == "Popup" {
                    // Catch any orphan Popup annotations on the page
                    popupsToRemove.append(annot)
                }
            }

            // 3. Purge the popups from the in-memory page
            for popup in popupsToRemove {
                page.removeAnnotation(popup)
            }
        }
        Swift.print("🧹 Scrubbed PDFKit popup contents and aggressively severed /Popup links")
    }

    // --- SidebarUpdateDelegate ---

    func annotationsDidChange(onPageIndex pageIndex: Int) {
        // A sidebar rebuild invalidates the currently stored card ordering.
        // Clear an active comment search rather than retaining stale result
        // references or misleading green borders after a mutation.
        clearCommentSearch()

        // Remember emphasis state before rebuild -- the card views will be
        // destroyed and recreated, but the PDF annotation and UUID survive.
        let preserveUUID = emphasizedUUID
        let preservePageIndex = emphasizedPageIndex

        // Clear card-side emphasis (the card view is about to be torn down).
        // Keep the PDF-side emphasis intact -- the annotation object survives
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
                scrollCardIntoViewIfNeeded(cardView)
                Swift.print("🟡 Emphasis re-applied to card after rebuild: \(uuid)")
            }
        }
    }

    func highlightWasClicked(uuid: String, onPageIndex pageIndex: Int, toggle: Bool) {
        // Empty UUID means "clicked outside any highlight" -- clear emphasis
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

    // --- Comment Search ---

    /// Starts a new comment-only search from the current PDF page forward.
    ///
    /// Results are cards, not individual substring occurrences: a card with
    /// one match and a card with several matches each appear exactly once.
    /// Returns false when no matching comment exists from the current page
    /// through the end of the document.
    @discardableResult
    func startCommentSearch(query: String) -> Bool {
        clearCommentSearch()

        guard let document = pdfView.document else { return false }

        let currentPageIndex: Int
        if let currentPage = pdfView.currentPage {
            currentPageIndex = document.index(for: currentPage)
        } else {
            currentPageIndex = 0
        }

        activeCommentSearchQuery = query

        for pageIndex in currentPageIndex..<pageSidebarViews.count {
            let pageView = pageSidebarViews[pageIndex]

            for cardView in pageView.cardViews {
                guard cardView.card.text.range(
                    of: query,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) != nil else {
                    continue
                }

                commentSearchResults.append((
                    uuid: cardView.card.uuid,
                    pageIndex: cardView.card.pageIndex
                ))
                cardView.setSearchMatch(true)
            }
        }

        guard !commentSearchResults.isEmpty else {
            activeCommentSearchQuery = nil
            return false
        }

        showCommentSearchResult(at: 0)
        return true
    }

    /// Advances to the next comment-search card without wrapping.
    ///
    /// Returns false only when no active comment search exists. If the active
    /// result is already the final one, it remains selected and this returns
    /// true so the keyboard-routing layer can show "No more hits."
    func advanceToNextCommentSearchHit() -> Bool {
        guard activeCommentSearchQuery != nil,
              let currentIndex = activeCommentSearchResultIndex else {
            return false
        }

        let nextIndex = currentIndex + 1

        guard nextIndex < commentSearchResults.count else {
            return true
        }

        showCommentSearchResult(at: nextIndex)
        return true
    }

    /// Returns true when the active result is the last available comment hit.
    /// Used by the future F3 routing to decide whether to present "No more hits."
    func isAtFinalCommentSearchHit() -> Bool {
        guard let currentIndex = activeCommentSearchResultIndex else {
            return false
        }

        return currentIndex == commentSearchResults.count - 1
    }

    /// Removes all thin/thick pale-green comment-search borders and forgets
    /// the query and F3 cursor. This does not touch annotation emphasis.
    func clearCommentSearch() {
        for pageView in pageSidebarViews {
            for cardView in pageView.cardViews {
                cardView.setSearchMatch(false)
            }
        }

        activeCommentSearchQuery = nil
        commentSearchResults.removeAll()
        activeCommentSearchResultIndex = nil
    }

    /// Displays the requested result as the current thick-green card, moves
    /// the PDF to the linked highlight's page, and reveals the complete card
    /// within its local page-sidebar scroll view.
    private func showCommentSearchResult(at resultIndex: Int) {
        guard commentSearchResults.indices.contains(resultIndex) else { return }

        if let previousIndex = activeCommentSearchResultIndex {
            let previousResult = commentSearchResults[previousIndex]
            findCardView(
                uuid: previousResult.uuid,
                onPageIndex: previousResult.pageIndex
            )?.setCurrentSearchHit(false)
        }

        let result = commentSearchResults[resultIndex]

        guard let cardView = findCardView(
            uuid: result.uuid,
            onPageIndex: result.pageIndex
        ) else {
            Swift.print("⚠️  Could not find comment-search card \(result.uuid)")
            return
        }

        cardView.setCurrentSearchHit(true)
        activeCommentSearchResultIndex = resultIndex

        navigateToCommentSearchResult(uuid: result.uuid, onPageIndex: result.pageIndex)
        scrollCardIntoViewIfNeeded(cardView)

        Swift.print(
            "🔎 Comment-search hit \(resultIndex + 1) of \(commentSearchResults.count) on page \(result.pageIndex + 1)"
        )
    }

    /// Navigates to the annotation linked to a comment-search card. This is
    /// deliberately navigation only: it does not apply yellow annotation
    /// emphasis, set an accent card border, or alter the Delete-key target.
    private func navigateToCommentSearchResult(uuid: String, onPageIndex pageIndex: Int) {
        guard let document = pdfView.document,
              let page = document.page(at: pageIndex),
              let annotation = findAnnotation(uuid: uuid, on: page) else {
            return
        }

        let destination = PDFDestination(
            page: page,
            at: NSPoint(x: annotation.bounds.midX, y: annotation.bounds.midY)
        )
        pdfView.farJump(to: destination)
    }

    /// Public seam for the approved ordered-Esc behavior. MainViewController
    /// owns the original annotation appearance and Delete-key synchronization,
    /// so other collaborators ask it to clear emphasis rather than resetting
    /// PDF or card state directly.
    func clearAnnotationEmphasis() {
        clearEmphasis()
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

    /// Sets up the onClicked and onDoubleClicked closures for a card view.
    /// Called during initial load and after page-sidebar rebuilds.
    private func wireCardClickHandler(_ cardView: CommentCardView) {
        cardView.onClicked = { [weak self] card in
            self?.handleCardClicked(card, fromCardView: cardView)
        }

        cardView.onDoubleClicked = { [weak self] card in
            self?.handleCardDoubleClicked(card, fromCardView: cardView)
        }
    }

    /// Responds to a sidebar card being single-clicked: emphasizes the corresponding
    /// highlight in the PDF and marks the card as active. Clicking any card
    /// deliberately leaves comment-search navigation before entering normal
    /// annotation-selection behavior.
    private func handleCardClicked(_ card: CommentCard, fromCardView cardView: CommentCardView) {
        clearCommentSearch()

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

    /// Responds to a sidebar card being double-clicked: ensures emphasis is ON,
    /// then delegates to AnimaPDFView to open the comment editor. A double-click
    /// is also an explicit exit from comment-search navigation.
    private func handleCardDoubleClicked(_ card: CommentCard, fromCardView cardView: CommentCardView) {
        clearCommentSearch()

        guard let document = pdfView.document,
              let page = document.page(at: card.pageIndex) else { return }

        // Find the annotation by UUID
        guard let annot = findAnnotation(uuid: card.uuid, on: page) else {
            Swift.print("⚠️  Could not find highlight for card \(card.uuid)")
            return
        }

        // Ensure emphasis is on before opening the dialog (no toggle)
        applyEmphasis(to: annot, on: page, uuid: card.uuid, pageIndex: card.pageIndex, cardView: cardView)

        // Trigger the edit flow in AnimaPDFView
        pdfView.editComment(for: annot, on: page)
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
        ) as? CGFloat ?? AnnotationManager.highlightOpacity

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
            scrollCardIntoViewIfNeeded(cardView)
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

    // --- Scroll Support ---

    /// Scrolls the page-sidebar's local scroll view to ensure the given card
    /// is fully visible. If the card is already visible (or the page-sidebar
    /// has no overflow), this is a no-op.
    private func scrollCardIntoViewIfNeeded(_ cardView: CommentCardView) {
        cardView.scrollToVisible(cardView.bounds)
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
