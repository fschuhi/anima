//
//  AnimaPDFView.swift
//  Anima
//
//  Subclass of PDFView that intercepts keyboard and mouse events.
//
//  Current capabilities:
//    - ENTER with selection → create highlight (dual-write: fitz + in-memory)
//    - H key → toggle persistent highlight mode (mouseUp creates highlight)
//    - Double-click on highlight (or card via delegate) → edit comment via CommentInputPanel
//    - Single-click highlight → toggle emphasis
//    - Delete key → remove the currently emphasized highlight
//
//  Dual-write pattern:
//    On highlight creation, we persist via fitz (anima_helper.py) AND add a
//    matching PDFAnnotation to PDFKit's in-memory document. This eliminates
//    the need to reload the document, which caused scroll drift.
//    fitz-written file is source of truth on disk; in-memory annotation is
//    display-only for the current session.
//
//  Sidebar integration:
//    After any annotation mutation (create, edit comment, delete), the
//    sidebarDelegate is notified so the sidebar can rebuild the affected
//    page's cards. The delegate receives only the page index — the sidebar
//    re-extracts all cards for that page from scratch.
//
//    Single-clicking a highlight notifies the delegate via
//    highlightWasClicked(uuid:onPageIndex:toggle:true), which toggles
//    emphasis on/off. Double-clicking calls with toggle:false to ensure
//    emphasis is on before opening the comment dialog.
//
//  NOTE: Inside a PDFView subclass, bare `print()` is ambiguous because
//  NSView has its own print() method (send to printer). We use Swift.print()
//  throughout to call the global console print function.
//

import Cocoa
import Quartz

// --- Sidebar Update Protocol ---
// AnimaPDFView notifies its delegate after any annotation mutation so
// the sidebar can rebuild the affected page's cards, and after highlight
// clicks so the sidebar can apply emphasis.
protocol SidebarUpdateDelegate: AnyObject {
    func annotationsDidChange(onPageIndex pageIndex: Int)

    /// Called when a highlight is clicked in the PDF.
    /// - Parameters:
    ///   - uuid: The annotation's UUID, or empty string if clicked outside any highlight
    ///   - pageIndex: The page index, or -1 if clicked outside any highlight
    ///   - toggle: If true (single-click), toggles emphasis on/off.
    ///             If false (double-click), ensures emphasis is on without toggling.
    func highlightWasClicked(uuid: String, onPageIndex pageIndex: Int, toggle: Bool)
}

class AnimaPDFView: PDFView {

    // Path to the Python helper — absolute path for Xcode-launched app
    let helperPath = "/Users/fschuhi/Projects/anima/tools/anima_helper.py"

    // Default author for in-memory annotations. Must match anima_helper.py's
    // DEFAULT_AUTHOR so that cards created during a session show the same
    // author as cards loaded from disk on next launch.
    static let authorName = "fschuhi"

    // Track which highlight is currently "selected" for Delete key.
    // Unified with emphasis state: MainViewController sets these when
    // emphasis is applied (from either card-click or highlight-click)
    // and clears them when emphasis is cleared.
    var selectedAnnotation: PDFAnnotation?
    var selectedAnnotationPage: PDFPage?

    // --- Sidebar delegate ---
    weak var sidebarDelegate: SidebarUpdateDelegate?

    // --- Persistent Highlight Mode ---
    // When active, releasing the mouse after a text selection immediately
    // creates a highlight (no ENTER needed). Toggle with H key.
    var isHighlightMode = false

    // --- Highlight color/opacity constants (must match anima_helper.py) ---
    // anima_helper.py: HIGHLIGHT_COLOR = [1.0, 0.75, 0.80], HIGHLIGHT_OPACITY = 0.4
    static let highlightColor = NSColor(red: 1.0, green: 0.75, blue: 0.80, alpha: 1.0)
    static let highlightOpacity: CGFloat = 0.4

    // --- Keyboard handling ---

    private var lastHandledEvent: NSEvent?
    private var isShowingDialog = false

    override func keyDown(with event: NSEvent) {
        if handleKeyEvent(event) {
            return
        }
        super.keyDown(with: event)
    }

    func handleKeyEvent(_ event: NSEvent) -> Bool {
        if event === lastHandledEvent {
            return true
        }

        // Don't handle keys while a dialog is open — the Enter that
        // dismisses the dialog would otherwise trigger a new highlight
        if isShowingDialog {
            return false
        }

        // H = toggle persistent highlight mode
        if event.keyCode == 4 {  // keyCode 4 = H
            toggleHighlightMode()
            lastHandledEvent = event
            return true
        }

        // ENTER = create highlight from current selection
        if event.keyCode == 36 || event.keyCode == 76 {
            if createHighlightFromSelection() {
                lastHandledEvent = event
                return true
            }
        }

        // DELETE / BACKSPACE = delete the selected highlight
        // keyCode 51 = Backspace, keyCode 117 = Forward Delete
        if event.keyCode == 51 || event.keyCode == 117 {
            if deleteSelectedHighlight() {
                lastHandledEvent = event
                return true
            }
        }

        return false
    }

    // --- Persistent Highlight Mode ---

    func toggleHighlightMode() {
        isHighlightMode.toggle()
        updateWindowTitle()
        Swift.print(isHighlightMode ? "🟡 Highlight mode ON" : "⚪ Highlight mode OFF")
    }

    func updateWindowTitle() {
        let base = "Anima"
        if isHighlightMode {
            self.window?.title = "\(base) — [H] Highlight Mode"
        } else {
            self.window?.title = base
        }
    }

    // --- Mouse handling ---

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            // Double-click: check if we hit a highlight annotation
            if handleDoubleClickOnHighlight(event) {
                return  // consumed — don't let PDFKit do word-selection
            }
        }

        if event.clickCount == 1 {
            // Single-click: check if we hit a highlight (toggle emphasis)
            handleSingleClickOnHighlight(event)
            // Fall through to let PDFKit handle normally (text cursor, etc.)
        }

        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)

        // In highlight mode, automatically create a highlight from the
        // current selection when the mouse is released after a drag.
        if isHighlightMode && currentSelection != nil {
            _ = createHighlightFromSelection()
        }
    }

    // --- Hit-testing ---

    /// Convert a mouse event's window coordinates to a (PDFPage, point-on-page) pair.
    /// Returns nil if the click isn't on any page.
    func pageAndPoint(for event: NSEvent) -> (PDFPage, NSPoint)? {
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let page = page(for: viewPoint, nearest: false) else {
            return nil
        }
        let pagePoint = convert(viewPoint, to: page)
        return (page, pagePoint)
    }

    /// Find a highlight annotation at the given point on the given page.
    /// Returns nil if no highlight exists at that location.
    func highlightAnnotation(at point: NSPoint, on page: PDFPage) -> PDFAnnotation? {
        // PDFPage.annotation(at:) returns the topmost annotation at the point
        if let annot = page.annotation(at: point) {
            if annot.type == "Highlight" {
                return annot
            }
        }

        // annotation(at:) might not work for highlights (they're markup, not
        // rectangular widgets). Fallback: check all annotations on the page
        // and test if the point falls within their bounds.
        for annot in page.annotations {
            if annot.type == "Highlight" && annot.bounds.contains(point) {
                return annot
            }
        }

        return nil
    }

    /// Get the UUID (NM field) of an annotation.
    func annotationUUID(_ annot: PDFAnnotation) -> String? {
        // Try the standard PDFKit way first
        if let nm = annot.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/NM")) as? String {
            return nm
        }

        // PDFKit might not expose /NM directly. Try the annotation's name property.
        let name = annot.userName
        if let name = name, !name.isEmpty {
            return name
        }

        return nil
    }

    // --- Double-click / Edit Comment Logic ---

    func handleDoubleClickOnHighlight(_ event: NSEvent) -> Bool {
        guard let (page, pagePoint) = pageAndPoint(for: event) else {
            return false
        }

        guard let annot = highlightAnnotation(at: pagePoint, on: page) else {
            return false
        }

        guard let uuid = annotationUUID(annot) else {
            Swift.print("⚠️  Highlight has no UUID — cannot edit")
            return false
        }

        // Ensure emphasis is on before opening the dialog (toggle: false
        // means "ensure on" — if already emphasized on this annotation,
        // it's a no-op rather than toggling off).
        if let document = self.document {
            let pageIndex = document.index(for: page)
            sidebarDelegate?.highlightWasClicked(uuid: uuid, onPageIndex: pageIndex, toggle: false)
        }

        editComment(for: annot, uuid: uuid, on: page)

        return true
    }

    /// Public method to edit an annotation's comment. Called both internally
    /// by double-clicks on the PDF canvas, and externally by the sidebar when
    /// a card is double-clicked.
    func editComment(for annot: PDFAnnotation, uuid: String, on page: PDFPage) {
        let existingComment = annot.contents ?? ""

        Swift.print("🖱️  Editing comment: \(uuid)")
        Swift.print("   Existing comment: \(existingComment.isEmpty ? "(none)" : existingComment)")

        // Show the modal input panel. The panel always returns a string —
        // there is no "cancel". Escape saves whatever text is in the editor.
        isShowingDialog = true
        let newComment = CommentInputPanel.showModal(existingText: existingComment)
        isShowingDialog = false

        // If the comment didn't change, skip the fitz write and sidebar rebuild.
        if newComment == existingComment {
            Swift.print("ℹ️  Comment unchanged, skipping save")
            return
        }

        guard let documentURL = self.document?.documentURL else { return }

        let success = FitzBridge.editComment(
            helperPath: helperPath,
            filePath: documentURL.path,
            uuid: uuid,
            comment: newComment
        )

        if success {
            // Dual-write: update the in-memory annotation's comment directly
            annot.contents = newComment
            Swift.print("✅ Comment updated on \(uuid)")
            Swift.print("   New comment: \(newComment.isEmpty ? "(removed)" : newComment)")

            // Notify sidebar to rebuild this page's cards.
            // annotationsDidChange will preserve emphasis on the current
            // annotation so the user sees the card they just edited.
            if let document = self.document {
                let pageIndex = document.index(for: page)
                sidebarDelegate?.annotationsDidChange(onPageIndex: pageIndex)
            }
        }
    }

    // --- Single-click: toggle emphasis on highlight ---

    func handleSingleClickOnHighlight(_ event: NSEvent) {
        guard let (page, pagePoint) = pageAndPoint(for: event) else {
            // Clicked outside any page — clear emphasis
            sidebarDelegate?.highlightWasClicked(uuid: "", onPageIndex: -1, toggle: true)
            selectedAnnotation = nil
            selectedAnnotationPage = nil
            return
        }

        if let annot = highlightAnnotation(at: pagePoint, on: page) {
            // Hit a highlight — notify delegate for emphasis toggle.
            // selectedAnnotation/Page will be set by MainViewController
            // via applyEmphasis/clearEmphasis (unified with emphasis state).
            if let uuid = annotationUUID(annot) {
                if let document = self.document {
                    let pageIndex = document.index(for: page)
                    sidebarDelegate?.highlightWasClicked(uuid: uuid, onPageIndex: pageIndex, toggle: true)
                }
                Swift.print("🔵 Clicked highlight: \(uuid)")
            }
        } else {
            // Clicked on page but not on a highlight — clear emphasis
            sidebarDelegate?.highlightWasClicked(uuid: "", onPageIndex: -1, toggle: true)
            selectedAnnotation = nil
            selectedAnnotationPage = nil
        }
    }

    // --- Delete: remove selected highlight ---

    func deleteSelectedHighlight() -> Bool {
        guard let annot = selectedAnnotation,
              let page = selectedAnnotationPage else {
            Swift.print("⚠️  No highlight selected — click a highlight first")
            return false
        }

        guard let uuid = annotationUUID(annot) else {
            Swift.print("⚠️  Selected highlight has no UUID — cannot delete")
            return false
        }

        guard let documentURL = self.document?.documentURL else { return false }

        Swift.print("🗑️  Deleting highlight: \(uuid)")

        let success = FitzBridge.deleteHighlight(
            helperPath: helperPath,
            filePath: documentURL.path,
            uuid: uuid
        )

        if success {
            // Dual-write: remove the in-memory annotation from the page
            page.removeAnnotation(annot)
            selectedAnnotation = nil
            selectedAnnotationPage = nil
            Swift.print("✅ Highlight deleted: \(uuid)")

            // Notify sidebar to rebuild this page's cards
            if let document = self.document {
                let pageIndex = document.index(for: page)
                sidebarDelegate?.annotationsDidChange(onPageIndex: pageIndex)
            }
        }

        return success
    }

    // --- Highlight creation (dual-write) ---

    func createHighlightFromSelection() -> Bool {
        guard let selection = currentSelection else {
            Swift.print("⚠️  No text selected")
            return false
        }

        guard let document = self.document else { return false }

        let lineSelections = selection.selectionsByLine()

        if lineSelections.isEmpty {
            Swift.print("⚠️  Could not split selection into lines")
            return false
        }

        guard let firstPage = selection.pages.first else { return false }
        let pageIndex = document.index(for: firstPage)
        let pageHeight = firstPage.bounds(for: .mediaBox).height

        // Build quads in both coordinate systems:
        // - fitzQuads: for anima_helper.py (fitz space, origin top-left)
        // - pdfkitBounds: for in-memory PDFAnnotation (PDFKit space, origin bottom-left)
        var fitzQuads: [[String: Double]] = []
        var pdfkitBounds: [NSRect] = []

        for lineSel in lineSelections {
            let bounds = lineSel.bounds(for: firstPage)

            if bounds.size.width < 1 || bounds.size.height < 1 {
                continue
            }

            // PDFKit-space bounds — keep as-is for in-memory annotation
            pdfkitBounds.append(bounds)

            // Fitz-space quads — flip y for the helper
            let x0 = Double(bounds.origin.x)
            let x1 = Double(bounds.origin.x + bounds.size.width)
            let y0_fitz = Double(pageHeight - (bounds.origin.y + bounds.size.height))
            let y1_fitz = Double(pageHeight - bounds.origin.y)

            fitzQuads.append(["x0": x0, "y0": y0_fitz, "x1": x1, "y1": y1_fitz])
        }

        if fitzQuads.isEmpty {
            Swift.print("⚠️  No valid quads from selection")
            return false
        }

        // Highlights are created without a comment. To add or edit a comment
        // later, double-click the highlight (matches PDF-XChange Viewer workflow).
        let comment = ""

        let uuid = UUID().uuidString.lowercased()

        guard let jsonData = try? JSONSerialization.data(withJSONObject: fitzQuads),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            Swift.print("❌ Failed to serialize quads to JSON")
            return false
        }

        guard let documentURL = document.documentURL else {
            Swift.print("❌ Document has no URL")
            return false
        }

        Swift.print("📝 Creating highlight: page=\(pageIndex), quads=\(fitzQuads.count) lines, uuid=\(uuid)")

        // Step 1: Persist to disk via fitz
        let success = FitzBridge.addHighlight(
            helperPath: helperPath,
            filePath: documentURL.path,
            page: pageIndex,
            uuid: uuid,
            quadsJSON: jsonString,
            comment: comment
        )

        if success {
            // Step 2: Add in-memory annotation for immediate display (no reload)
            addInMemoryHighlight(
                page: firstPage,
                bounds: pdfkitBounds,
                uuid: uuid,
                comment: comment
            )
            clearSelection()
            Swift.print("✅ Highlight created (dual-write): \(uuid)")

            // Notify sidebar — currently a no-op since highlights start without
            // comments (no card to show), but this ensures the sidebar stays
            // correct if we ever change the default or add in-place editing.
            sidebarDelegate?.annotationsDidChange(onPageIndex: pageIndex)
        }

        return success
    }

    // --- In-memory annotation (display-only, not persisted) ---

    /// Create a PDFAnnotation in PDFKit's in-memory document for immediate display.
    /// The annotation matches what fitz wrote to disk. On next app launch, PDFKit
    /// will load the fitz-written version from the file.
    ///
    /// Fields set here must match what anima_helper.py writes via fitz:
    ///   - bounds, QuadPoints, color, opacity  (geometry + appearance)
    ///   - /NM                                  (UUID for identification)
    ///   - userName                             (backup UUID for hit-testing)
    ///   - /T                                   (author for sidebar cards)
    ///   - contents                             (comment text)
    ///
    /// IMPORTANT: /NM must be set explicitly. PDFKit maps userName to /T
    /// internally, so relying on userName alone for UUID storage causes /T
    /// (author) writes to overwrite the UUID. Setting /NM directly ensures
    /// annotationUUID() finds the UUID on its first check, independent of
    /// the userName ↔ /T mapping.
    ///
    /// - Parameters:
    ///   - page: The PDFPage to add the annotation to
    ///   - bounds: Array of NSRect per selection line (PDFKit coordinate space)
    ///   - uuid: The annotation's UUID (matches what fitz wrote to /NM)
    ///   - comment: The annotation's comment text
    func addInMemoryHighlight(page: PDFPage, bounds: [NSRect], uuid: String, comment: String) {

        // Calculate the overall bounding rect (union of all line rects)
        var overallBounds = bounds[0]
        for i in 1..<bounds.count {
            overallBounds = overallBounds.union(bounds[i])
        }

        // Create the highlight annotation
        let annot = PDFAnnotation(
            bounds: overallBounds,
            forType: .highlight,
            withProperties: nil
        )

        // Set color and opacity to match anima_helper.py constants
        annot.color = AnimaPDFView.highlightColor
        annot.setValue(AnimaPDFView.highlightOpacity, forAnnotationKey: PDFAnnotationKey(rawValue: "/CA"))

        // Set comment
        if !comment.isEmpty {
            annot.contents = comment
        }

        // Set UUID — both via /NM (primary, used by annotationUUID) and
        // userName (backup). /NM must be set explicitly because PDFKit
        // does not populate it from userName.
        annot.setValue(uuid, forAnnotationKey: PDFAnnotationKey(rawValue: "/NM"))
        annot.userName = uuid

        // Set author — matches anima_helper.py's DEFAULT_AUTHOR.
        // Must be set AFTER userName to avoid PDFKit's internal
        // userName ↔ /T mapping from overwriting the author with the UUID.
        annot.setValue(AnimaPDFView.authorName, forAnnotationKey: PDFAnnotationKey(rawValue: "/T"))

        // Build QuadPoints — PDFKit expects an array of NSValue-wrapped NSPoints,
        // four points per quad (one quad per selection line).
        // Order: bottom-left, bottom-right, top-left, top-right
        // (This is the PDF spec order for QuadPoints)
        var quadPoints: [NSValue] = []
        for rect in bounds {
            let bottomLeft  = NSPoint(x: rect.minX, y: rect.minY)
            let bottomRight = NSPoint(x: rect.maxX, y: rect.minY)
            let topLeft     = NSPoint(x: rect.minX, y: rect.maxY)
            let topRight    = NSPoint(x: rect.maxX, y: rect.maxY)

            quadPoints.append(NSValue(point: bottomLeft))
            quadPoints.append(NSValue(point: bottomRight))
            quadPoints.append(NSValue(point: topLeft))
            quadPoints.append(NSValue(point: topRight))
        }

        // Set QuadPoints via the annotation key
        annot.setValue(quadPoints, forAnnotationKey: PDFAnnotationKey(rawValue: "/QuadPoints"))

        // Add to the page — PDFKit renders it immediately
        page.addAnnotation(annot)

        Swift.print("🔧 In-memory annotation added: \(uuid) (\(bounds.count) quads, bounds=\(overallBounds))")
    }

    // --- Document reload (kept for edge cases, no longer used for highlight creation) ---

    func reloadDocument() {
        guard let document = self.document,
              let url = document.documentURL else { return }

        let visibleRect = self.visibleRect
        let centerPoint = NSPoint(
            x: visibleRect.midX,
            y: visibleRect.midY
        )
        let currentPage = self.page(for: centerPoint, nearest: true)
        let pagePoint = currentPage.map { self.convert(centerPoint, to: $0) }

        if let newDocument = PDFDocument(url: url) {
            self.document = newDocument

            if let page = currentPage,
               let point = pagePoint {
                let pageIndex = document.index(for: page)
                if pageIndex < newDocument.pageCount,
                   let restoredPage = newDocument.page(at: pageIndex) {
                    let destination = PDFDestination(page: restoredPage, at: point)
                    self.go(to: destination)
                }
            }
        }
    }
}
