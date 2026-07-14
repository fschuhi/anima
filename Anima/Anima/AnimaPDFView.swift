//
//  AnimaPDFView.swift
//  Anima
//
//  Subclass of PDFView that intercepts keyboard and mouse events.
//
//  Current capabilities:
//    - ENTER with selection → create highlight (via AnnotationManager)
//    - H key → toggle persistent highlight mode (mouseUp creates highlight)
//    - P key → toggle X-Ray mode (reveals native popups for comments)
//    - G key → go to a page through a native modal input field
//    - Double-click on highlight (or card via delegate) → edit comment (via AnnotationManager)
//    - Single-click highlight → toggle emphasis
//    - Delete key → remove the currently emphasized highlight (via AnnotationManager)
//
//  Annotation CRUD:
//    All highlight creation, comment editing, and deletion are delegated to
//    AnnotationManager. This class handles event dispatch, hit-testing, and
//    mode management. After each mutation, it notifies the sidebarDelegate
//    so the sidebar can rebuild the affected page's cards.
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
    ///   /// - pageIndex: The page index, or -1 if clicked outside any highlight
    ///   - toggle: If true (single-click), toggles emphasis on/off.
    ///             If false (double-click), ensures emphasis is on without toggling.
    func highlightWasClicked(uuid: String, onPageIndex pageIndex: Int, toggle: Bool)
}

class AnimaPDFView: PDFView {

    // --- Annotation Manager ---
    // Handles all annotation CRUD (create, edit, delete). Initialized by
    // the caller (AppDelegate or MainViewController) after the view is created.
    var annotationManager: AnnotationManager!

    // Track which highlight is currently "selected" for Delete key.
    // Unified with emphasis state: MainViewController sets these when
    // emphasis is applied (from either card-click or highlight-click)
    // and clears them when emphasis is cleared.
    var selectedAnnotation: PDFAnnotation?
    var selectedAnnotationPage: PDFPage?

    // --- Sidebar delegate ---
    weak var sidebarDelegate: SidebarUpdateDelegate?

    // --- Display Modes ---
    // When active, releasing the mouse after a text selection immediately
    // creates a highlight (no ENTER needed). Toggle with H key.
    var isHighlightMode = false

    // When active, populates standard `.contents` from our custom `/AnimaComment`
    // key, which forces PDFKit to render native yellow popup indicators. Toggle with P key.
    var isXRayMode = false

    // Uncontrolled PDF filenames can be much wider than the window caption.
    // Keep this easy to tune while experimenting with different window sizes.
    static let uncontrolledDocumentHandleMaximumLength = 40

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

        // P = toggle X-Ray mode (show popups)
        if event.keyCode == 35 { // keyCode 35 = P
            toggleXRayMode()
            lastHandledEvent = event
            return true
        }

        // G = go to page. Cmd+G remains available for future Find Next behavior.
        if event.keyCode == 5,
           event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            showGotoPageDialog()
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

    // MARK: - Modes

    func toggleHighlightMode() {
        isHighlightMode.toggle()
        updateWindowTitle()
        Swift.print(isHighlightMode ? "🟡 Highlight mode ON" : "⚪ Highlight mode OFF")
    }

    func toggleXRayMode() {
        isXRayMode.toggle()
        updateWindowTitle()
        applyXRayModeToDocument()
        Swift.print(isXRayMode ? "🦴 X-Ray mode ON (Popups visible)" : "🦴 X-Ray mode OFF (Popups hidden)")
    }

    func updateWindowTitle() {
        guard let document = document else {
            window?.title = "Anima"
            return
        }

        let handle = documentHandle(for: document)
        let pageCount = document.pageCount

        let currentPageNumber: Int
        if let currentPage = currentPage {
            currentPageNumber = document.index(for: currentPage) + 1
        } else {
            currentPageNumber = 1
        }

        window?.title = "\(handle) -- \(currentPageNumber) of \(pageCount)"
    }

    /// Returns the compact document identifier used in Anima's window caption.
    ///
    /// Controlled PDFs use the leading parenthesized pdf_id from their filename,
    /// such as "(Albini 2013)". Uncontrolled PDFs fall back to their filename
    /// stem, abbreviated to keep the current-page information visible.
    private func documentHandle(for document: PDFDocument) -> String {
        guard let documentURL = document.documentURL else {
            return "Anima"
        }

        let filenameStem = documentURL.deletingPathExtension().lastPathComponent

        if filenameStem.first == "(",
           let closingParenthesis = filenameStem.firstIndex(of: ")"),
           closingParenthesis > filenameStem.startIndex {
            return String(filenameStem[...closingParenthesis])
        }

        return abbreviatedDocumentHandle(from: filenameStem)
    }

    /// Abbreviates uncontrolled filename stems while keeping the limit easy
    /// to tune through uncontrolledDocumentHandleMaximumLength.
    private func abbreviatedDocumentHandle(from filenameStem: String) -> String {
        let maximumLength = AnimaPDFView.uncontrolledDocumentHandleMaximumLength

        guard filenameStem.count > maximumLength else {
            return filenameStem
        }

        let prefixLength = maximumLength - 3
        let prefixEndIndex = filenameStem.index(filenameStem.startIndex, offsetBy: prefixLength)
        return "\(filenameStem[..<prefixEndIndex])..."
    }

    /// Iterates the document to instantly show or hide the native PDFKit popup indicators.
    private func applyXRayModeToDocument() {
        guard let document = self.document else { return }

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            var popupsToRemove: [PDFAnnotation] = []

            for annot in page.annotations {
                if annot.type == "Highlight" {
                    let animaComment = annot.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/AnimaComment")) as? String ?? ""

                    if isXRayMode {
                        // Restore standard contents and manually rebuild the missing popup object
                        if !animaComment.isEmpty {
                            annot.contents = animaComment
                            annotationManager.ensurePopupExists(for: annot, on: page)
                        }
                    } else {
                        // Wipe standard contents to kill popups
                        annot.contents = ""
                        if let popup = annot.popup {
                            popupsToRemove.append(popup)
                            annot.popup = nil
                        }
                        annot.removeValue(forAnnotationKey: PDFAnnotationKey(rawValue: "/Popup"))
                    }
                } else if !isXRayMode && annot.type == "Popup" {
                    // Catch explicit popups when turning X-Ray OFF
                    popupsToRemove.append(annot)
                }
            }

            // Purge the collected popups from the page
            if !isXRayMode {
                for popup in popupsToRemove {
                    page.removeAnnotation(popup)
                }
            }
        }
        // Force visual update
        self.setNeedsDisplay(self.bounds)
    }

    // MARK: - Navigation

    /// Shows the smallest useful native page-navigation interaction.
    /// The user enters a 1-based page number. Invalid input fails fast:
    /// the input alert closes, an error reports the valid range, and the
    /// PDF view remains on its current page.
    private func showGotoPageDialog() {
        guard let document = document else { return }

        let pageCount = document.pageCount
        let pageField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        pageField.placeholderString = "Page number"

        let alert = NSAlert()
        alert.messageText = "Go to Page"
        alert.informativeText = "Enter a page from 1 to \(pageCount)."
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = pageField
        alert.layout()
        alert.window.initialFirstResponder = pageField
        alert.window.makeFirstResponder(pageField)

        isShowingDialog = true
        let response = alert.runModal()
        isShowingDialog = false

        guard response == .alertFirstButtonReturn else {
            return
        }

        let pageText = pageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let pageNumber = Int(pageText),
              (1...pageCount).contains(pageNumber),
              let page = document.page(at: pageNumber - 1) else {
            showGotoPageError(validPageRange: 1...pageCount)
            return
        }

        go(to: page)
        Swift.print("📖 Navigated to page \(pageNumber) of \(pageCount)")
    }

    /// Reports invalid goto-page input after the input dialog has already
    /// closed, returning the user directly to the reader after dismissal.
    private func showGotoPageError(validPageRange: ClosedRange<Int>) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Invalid page number"
        alert.informativeText = "Enter a page from \(validPageRange.lowerBound) to \(validPageRange.upperBound)."
        alert.addButton(withTitle: "OK")

        isShowingDialog = true
        alert.runModal()
        isShowingDialog = false
    }

    // MARK: - Mouse Handling

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

    // MARK: - Hit-Testing

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

    // MARK: - Double-Click / Edit Comment

    func handleDoubleClickOnHighlight(_ event: NSEvent) -> Bool {
        guard let (page, pagePoint) = pageAndPoint(for: event) else {
            return false
        }

        guard let annot = highlightAnnotation(at: pagePoint, on: page) else {
            return false
        }

        guard let uuid = annotationManager.annotationUUID(annot) else {
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

        editComment(for: annot, on: page)

        return true
    }

    /// Public method to edit an annotation's comment. Called both internally
    /// by double-clicks on the PDF canvas, and externally by the sidebar when
    /// a card is double-clicked.
    func editComment(for annot: PDFAnnotation, on page: PDFPage) {
        guard let document = self.document else { return }

        isShowingDialog = true
        let changed = annotationManager.editComment(
            document: document,
            annotation: annot,
            page: page,
            isXRayMode: isXRayMode
        )
        isShowingDialog = false

        if changed {
            // Notify sidebar to rebuild this page's cards.
            // annotationsDidChange will preserve emphasis on the current
            // annotation so the user sees the card they just edited.
            let pageIndex = document.index(for: page)
            sidebarDelegate?.annotationsDidChange(onPageIndex: pageIndex)
        }
    }

    // MARK: - Single-Click: Toggle Emphasis

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
            if let uuid = annotationManager.annotationUUID(annot) {
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

    // MARK: - Delete Selected Highlight

    func deleteSelectedHighlight() -> Bool {
        guard let annot = selectedAnnotation,
              let page = selectedAnnotationPage else {
            Swift.print("⚠️  No highlight selected — click a highlight first")
            return false
        }

        guard let document = self.document else { return false }

        let success = annotationManager.deleteHighlight(
            document: document,
            annotation: annot,
            page: page
        )

        if success {
            selectedAnnotation = nil
            selectedAnnotationPage = nil

            // Notify sidebar to rebuild this page's cards
            let pageIndex = document.index(for: page)
            sidebarDelegate?.annotationsDidChange(onPageIndex: pageIndex)
        }

        return success
    }

    // MARK: - Highlight Creation (from Selection)

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

        // Extract per-line bounds in PDFKit coordinate space
        var selectionBounds: [NSRect] = []
        for lineSel in lineSelections {
            let bounds = lineSel.bounds(for: firstPage)
            selectionBounds.append(bounds)
        }

        let uuid = annotationManager.createHighlight(
            document: document,
            page: firstPage,
            pageIndex: pageIndex,
            selectionBounds: selectionBounds,
            isXRayMode: isXRayMode
        )

        if uuid != nil {
            clearSelection()

            // Notify sidebar — currently a no-op since highlights start without
            // comments (no card to show), but this ensures the sidebar stays
            // correct if we ever change the default or add in-place editing.
            sidebarDelegate?.annotationsDidChange(onPageIndex: pageIndex)
            return true
        }

        return false
    }

    // MARK: - Document Reload (kept for edge cases, no longer used for highlight creation)

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
