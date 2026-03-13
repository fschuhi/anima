// AnimaPDFView.swift — Anima PoC
//
// Subclass of PDFView that intercepts keyboard and mouse events.
//
// Current capabilities:
//   - ENTER with selection → create highlight (with optional comment dialog)
//   - Double-click on highlight → edit its comment
//
// NOTE: Inside a PDFView subclass, bare `print()` is ambiguous because
// NSView has its own print() method (send to printer). We use Swift.print()
// throughout to call the global console print function.

import Cocoa
import Quartz

class AnimaPDFView: PDFView {

    // Path to the Python helper (relative — run from project folder)
    let helperPath = "./anima_helper.py"

    // Track which highlight is currently "selected" (for future undo support)
    var selectedAnnotation: PDFAnnotation?
    var selectedAnnotationPage: PDFPage?

    // --- Keyboard handling ---

    private var lastHandledEvent: NSEvent?

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

    // --- Mouse handling ---

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            // Double-click: check if we hit a highlight annotation
            if handleDoubleClickOnHighlight(event) {
                return  // consumed — don't let PDFKit do word-selection
            }
        }

        if event.clickCount == 1 {
            // Single-click: check if we hit a highlight (for selecting it)
            handleSingleClickOnHighlight(event)
            // Fall through to let PDFKit handle normally (text cursor, etc.)
        }

        super.mouseDown(with: event)
    }

    // --- Hit-testing ---

    /// Convert a mouse event's window coordinates to a (PDFPage, point-on-page) pair.
    /// Returns nil if the click isn't on any page.
    func pageAndPoint(for event: NSEvent) -> (PDFPage, NSPoint)? {
        // Convert from window coordinates to PDFView coordinates
        let viewPoint = convert(event.locationInWindow, from: nil)

        // Find which page was clicked
        guard let page = page(for: viewPoint, nearest: false) else {
            return nil
        }

        // Convert to page coordinates (PDFKit space, origin bottom-left)
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
    /// PDFKit stores it in the annotationKeyValues or we can read it from
    /// the /NM key. Returns nil if no UUID is set.
    func annotationUUID(_ annot: PDFAnnotation) -> String? {
        // Try the standard PDFKit way first
        if let nm = annot.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/NM")) as? String {
            return nm
        }

        // PDFKit might not expose /NM directly. Try the annotation's name property.
        // In PDFKit, the `userName` property sometimes maps to /NM.
        let name = annot.userName
        if let name = name, !name.isEmpty {
            return name
        }

        return nil
    }

    // --- Double-click: edit comment on existing highlight ---

    func handleDoubleClickOnHighlight(_ event: NSEvent) -> Bool {
        guard let (page, pagePoint) = pageAndPoint(for: event) else {
            return false
        }

        guard let annot = highlightAnnotation(at: pagePoint, on: page) else {
            return false  // no highlight here — let PDFKit do word-selection
        }

        guard let uuid = annotationUUID(annot) else {
            Swift.print("⚠️  Highlight has no UUID — cannot edit")
            return false
        }

        // Get the existing comment
        let existingComment = annot.contents ?? ""

        Swift.print("🖱️  Double-clicked highlight: \(uuid)")
        Swift.print("   Existing comment: \(existingComment.isEmpty ? "(none)" : existingComment)")

        // Show the comment dialog, pre-filled with the existing comment
        guard let newComment = askForComment(existingText: existingComment) else {
            Swift.print("⚠️  Edit cancelled")
            return true  // consumed the event even though we cancelled
        }

        // Save the updated comment
        guard let documentURL = self.document?.documentURL else { return true }

        let success = FitzBridge.editComment(
            helperPath: helperPath,
            filePath: documentURL.path,
            uuid: uuid,
            comment: newComment
        )

        if success {
            reloadDocument()
            Swift.print("✅ Comment updated on \(uuid)")
            Swift.print("   New comment: \(newComment.isEmpty ? "(removed)" : newComment)")
        }

        return true
    }

    // --- Single-click: select a highlight (for Delete) ---

    func handleSingleClickOnHighlight(_ event: NSEvent) {
        guard let (page, pagePoint) = pageAndPoint(for: event) else {
            selectedAnnotation = nil
            selectedAnnotationPage = nil
            return
        }

        if let annot = highlightAnnotation(at: pagePoint, on: page) {
            selectedAnnotation = annot
            selectedAnnotationPage = page
            if let uuid = annotationUUID(annot) {
                Swift.print("🔵 Selected highlight: \(uuid)")
            }
        } else {
            selectedAnnotation = nil
            selectedAnnotationPage = nil
        }
    }

    // --- Delete: remove selected highlight ---

    func deleteSelectedHighlight() -> Bool {
        guard let annot = selectedAnnotation else {
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
            selectedAnnotation = nil
            selectedAnnotationPage = nil
            reloadDocument()
            Swift.print("✅ Highlight deleted: \(uuid)")
        }

        return success
    }

    // --- Comment dialog ---

    func askForComment(existingText: String = "") -> String? {
        let alert = NSAlert()
        alert.messageText = existingText.isEmpty ? "Add comment" : "Edit comment"
        alert.informativeText = "Enter a comment for this highlight (or leave empty):"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = existingText
        textField.placeholderString = "Optional comment..."
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            return textField.stringValue
        }
        return nil
    }

    // --- Highlight creation ---

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

        var quads: [[String: Double]] = []

        for lineSel in lineSelections {
            let bounds = lineSel.bounds(for: firstPage)

            if bounds.size.width < 1 || bounds.size.height < 1 {
                continue
            }

            let x0 = Double(bounds.origin.x)
            let x1 = Double(bounds.origin.x + bounds.size.width)
            let y0_fitz = Double(pageHeight - (bounds.origin.y + bounds.size.height))
            let y1_fitz = Double(pageHeight - bounds.origin.y)

            quads.append(["x0": x0, "y0": y0_fitz, "x1": x1, "y1": y1_fitz])
        }

        if quads.isEmpty {
            Swift.print("⚠️  No valid quads from selection")
            return false
        }

        guard let comment = askForComment() else {
            Swift.print("⚠️  Highlight cancelled by user")
            return false
        }

        let uuid = UUID().uuidString.lowercased()

        guard let jsonData = try? JSONSerialization.data(withJSONObject: quads),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            Swift.print("❌ Failed to serialize quads to JSON")
            return false
        }

        guard let documentURL = document.documentURL else {
            Swift.print("❌ Document has no URL")
            return false
        }
        let filePath = documentURL.path

        Swift.print("📝 Creating highlight: page=\(pageIndex), quads=\(quads.count) lines, uuid=\(uuid)")

        let success = FitzBridge.addHighlight(
            helperPath: helperPath,
            filePath: filePath,
            page: pageIndex,
            uuid: uuid,
            quadsJSON: jsonString,
            comment: comment
        )

        if success {
            reloadDocument()
            clearSelection()
            Swift.print("✅ Highlight created: \(uuid)")
            if !comment.isEmpty {
                Swift.print("   Comment: \(comment)")
            }
        }

        return success
    }

    // --- Document reload ---

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
