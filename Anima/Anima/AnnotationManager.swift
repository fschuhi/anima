//
//  AnnotationManager.swift
//  Anima
//
//  Manages annotation CRUD operations: creating highlights, editing comments,
//  and deleting highlights. Owns the dual-write pattern (fitz persist + in-memory
//  PDFAnnotation) and the coordinate conversion from PDFKit space to fitz space.
//
//  Design:
//    This is a toolbox class — it does not hold references to the PDFView,
//    the document, or any UI state. All context is passed per-call. This keeps
//    the class testable and avoids stale references if multi-document support
//    (tabs) is added later.
//
//    The caller (AnimaPDFView) is responsible for:
//      - Obtaining the current selection / annotation / page
//      - Setting isShowingDialog before/after editComment calls
//      - Notifying the sidebarDelegate after mutations
//      - Managing emphasis state
//
//  Popup suppression:
//    Comments are stored in a custom /AnimaComment dictionary key to prevent
//    PDFKit from rendering native yellow popup squares. The standard .contents
//    field is kept empty unless X-Ray mode is active. The isXRayMode parameter
//    on relevant methods controls this behavior. See README.md "Popup Suppression"
//    for the full contract.
//

import Cocoa
import Quartz

class AnnotationManager {

    // Path to the Python helper — absolute path for Xcode-launched app
    let helperPath: String

    // Default author for in-memory annotations. Must match anima_helper.py's
    // DEFAULT_AUTHOR so that cards created during a session show the same
    // author as cards loaded from disk on next launch.
    static let authorName = "fschuhi"

    // --- Highlight color/opacity constants (must match anima_helper.py) ---
    // anima_helper.py: HIGHLIGHT_COLOR = [1.0, 0.75, 0.80], HIGHLIGHT_OPACITY = 0.4
    static let highlightColor = NSColor(red: 1.0, green: 0.75, blue: 0.80, alpha: 1.0)
    static let highlightOpacity: CGFloat = 0.4

    init(helperPath: String) {
        self.helperPath = helperPath
    }

    // MARK: - Create Highlight

    /// Create a highlight from PDFKit selection line bounds.
    ///
    /// Performs the full dual-write sequence:
    ///   1. Convert PDFKit-space bounds to fitz-space quads
    ///   2. Call anima_helper.py to persist via fitz (incremental save)
    ///   3. Add a matching in-memory PDFAnnotation for immediate display
    ///
    /// - Parameters:
    ///   - document: The PDFDocument (needed for URL and page index)
    ///   - page: The PDFPage to add the highlight to
    ///   - pageIndex: The 0-based page index
    ///   - selectionBounds: Per-line bounding rects in PDFKit coordinate space
    ///   - isXRayMode: Whether popups should be visible (affects .contents handling)
    /// - Returns: The UUID of the created highlight, or nil on failure
    func createHighlight(
        document: PDFDocument,
        page: PDFPage,
        pageIndex: Int,
        selectionBounds: [NSRect],
        isXRayMode: Bool
    ) -> String? {

        let pageHeight = page.bounds(for: .mediaBox).height

        // Build quads in both coordinate systems:
        // - fitzQuads: for anima_helper.py (fitz space, origin top-left)
        // - pdfkitBounds: for in-memory PDFAnnotation (PDFKit space, origin bottom-left)
        var fitzQuads: [[String: Double]] = []
        var pdfkitBounds: [NSRect] = []

        for bounds in selectionBounds {
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
            return nil
        }

        // Highlights are created without a comment. To add or edit a comment
        // later, double-click the highlight (matches PDF-XChange Viewer workflow).
        let comment = ""

        let uuid = UUID().uuidString.lowercased()

        guard let jsonData = try? JSONSerialization.data(withJSONObject: fitzQuads),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            Swift.print("❌ Failed to serialize quads to JSON")
            return nil
        }

        guard let documentURL = document.documentURL else {
            Swift.print("❌ Document has no URL")
            return nil
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
                page: page,
                bounds: pdfkitBounds,
                uuid: uuid,
                comment: comment,
                isXRayMode: isXRayMode
            )
            Swift.print("✅ Highlight created (dual-write): \(uuid)")
            return uuid
        }

        return nil
    }

    // MARK: - Edit Comment

    /// Edit an annotation's comment via the modal CommentInputPanel.
    ///
    /// Shows the input panel, writes the new comment via fitz, and updates
    /// the in-memory annotation. The caller is responsible for setting
    /// isShowingDialog before this call and clearing it after.
    ///
    /// - Parameters:
    ///   - document: The PDFDocument (needed for URL)
    ///   - annotation: The highlight annotation to edit
    ///   - page: The page the annotation lives on
    ///   - isXRayMode: Whether popups should be visible
    /// - Returns: true if the comment was changed, false if unchanged or failed
    func editComment(
        document: PDFDocument,
        annotation: PDFAnnotation,
        page: PDFPage,
        isXRayMode: Bool
    ) -> Bool {

        guard let uuid = annotationUUID(annotation) else {
            Swift.print("⚠️  Highlight has no UUID — cannot edit")
            return false
        }

        // Read from our custom key first, fallback to .contents
        var existingComment = annotation.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/AnimaComment")) as? String ?? ""
        if existingComment.isEmpty {
            existingComment = annotation.contents ?? ""
        }

        Swift.print("🖱️  Editing comment: \(uuid)")
        Swift.print("   Existing comment: \(existingComment.isEmpty ? "(none)" : existingComment)")

        // Show the modal input panel. The panel always returns a string —
        // there is no "cancel". Escape saves whatever text is in the editor.
        let newComment = CommentInputPanel.showModal(existingText: existingComment)

        // If the comment didn't change, skip the fitz write and sidebar rebuild.
        if newComment == existingComment {
            Swift.print("ℹ️  Comment unchanged, skipping save")
            return false
        }

        guard let documentURL = document.documentURL else { return false }

        let success = FitzBridge.editComment(
            helperPath: helperPath,
            filePath: documentURL.path,
            uuid: uuid,
            comment: newComment
        )

        if success {
            // Dual-write: update the custom key.
            annotation.setValue(newComment, forAnnotationKey: PDFAnnotationKey(rawValue: "/AnimaComment"))

            // Sync standard contents based on active X-Ray Mode
            if isXRayMode {
                annotation.contents = newComment
                if !newComment.isEmpty {
                    ensurePopupExists(for: annotation, on: page)
                }
            } else {
                annotation.contents = ""
                // Destroy popup if PDFKit aggressively re-spawned one
                if let popup = annotation.popup {
                    page.removeAnnotation(popup)
                    annotation.popup = nil
                }
                annotation.removeValue(forAnnotationKey: PDFAnnotationKey(rawValue: "/Popup"))
            }

            Swift.print("✅ Comment updated on \(uuid)")
            Swift.print("   New comment: \(newComment.isEmpty ? "(removed)" : newComment)")
            return true
        }

        return false
    }

    // MARK: - Delete Highlight

    /// Delete a highlight annotation entirely.
    ///
    /// Calls anima_helper.py to remove from the PDF file, then removes the
    /// in-memory annotation from the page.
    ///
    /// - Parameters:
    ///   - document: The PDFDocument (needed for URL)
    ///   - annotation: The highlight annotation to delete
    ///   - page: The page the annotation lives on
    /// - Returns: true on success, false on failure
    func deleteHighlight(
        document: PDFDocument,
        annotation: PDFAnnotation,
        page: PDFPage
    ) -> Bool {

        guard let uuid = annotationUUID(annotation) else {
            Swift.print("⚠️  Highlight has no UUID — cannot delete")
            return false
        }

        guard let documentURL = document.documentURL else { return false }

        Swift.print("🗑️  Deleting highlight: \(uuid)")

        let success = FitzBridge.deleteHighlight(
            helperPath: helperPath,
            filePath: documentURL.path,
            uuid: uuid
        )

        if success {
            // Dual-write: remove the in-memory annotation from the page
            page.removeAnnotation(annotation)
            Swift.print("✅ Highlight deleted: \(uuid)")
        }

        return success
    }

    // MARK: - In-Memory Annotation (Private)

    /// Create a PDFAnnotation in PDFKit's in-memory document for immediate display.
    /// The annotation matches what fitz wrote to disk. On next app launch, PDFKit
    /// will load the fitz-written version from the file.
    ///
    /// Fields set here must match what anima_helper.py writes via fitz:
    ///   - bounds, QuadPoints, color, opacity  (geometry + appearance)
    ///   - /NM                                  (UUID for identification)
    ///   - userName                             (backup UUID for hit-testing)
    ///   - /T                                   (author for sidebar cards)
    ///   - /AnimaComment                        (custom comment text key to suppress popups)
    ///
    /// IMPORTANT: /NM must be set explicitly. PDFKit maps userName to /T
    /// internally, so relying on userName alone for UUID storage causes /T
    /// (author) writes to overwrite the UUID. Setting /NM directly ensures
    /// annotationUUID() finds the UUID on its first check, independent of
    /// the userName ↔ /T mapping.
    private func addInMemoryHighlight(
        page: PDFPage,
        bounds: [NSRect],
        uuid: String,
        comment: String,
        isXRayMode: Bool
    ) {
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
        annot.color = AnnotationManager.highlightColor
        annot.setValue(AnnotationManager.highlightOpacity, forAnnotationKey: PDFAnnotationKey(rawValue: "/CA"))

        // Handle comment based on X-Ray mode
        if !comment.isEmpty {
            annot.setValue(comment, forAnnotationKey: PDFAnnotationKey(rawValue: "/AnimaComment"))
            annot.contents = isXRayMode ? comment : ""
        }

        // Set UUID — both via /NM (primary, used by annotationUUID) and
        // userName (backup). /NM must be set explicitly because PDFKit
        // does not populate it from userName.
        annot.setValue(uuid, forAnnotationKey: PDFAnnotationKey(rawValue: "/NM"))
        annot.userName = uuid

        // Set author — matches anima_helper.py's DEFAULT_AUTHOR.
        // Must be set AFTER userName to avoid PDFKit's internal
        // userName ↔ /T mapping from overwriting the author with the UUID.
        annot.setValue(AnnotationManager.authorName, forAnnotationKey: PDFAnnotationKey(rawValue: "/T"))

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

        // Now that it's on the page, link the popup if necessary
        if isXRayMode && !comment.isEmpty {
            ensurePopupExists(for: annot, on: page)
        }

        Swift.print("🔧 In-memory annotation added: \(uuid) (\(bounds.count) quads, bounds=\(overallBounds))")
    }

    // MARK: - Popup Helpers

    /// Manually rebuilds a PDFAnnotationPopup and links it to the highlight.
    /// Because we aggressively destroy popups on load to prevent them from rendering,
    /// setting `.contents` later isn't enough; PDFKit requires the actual object to exist.
    func ensurePopupExists(for annot: PDFAnnotation, on page: PDFPage) {
        if annot.popup == nil {
            // Provide a sensible default size/location. PDFKit handles the yellow icon
            // placement automatically, but this dictates where the actual text box opens if clicked.
            let popupBounds = NSRect(x: annot.bounds.maxX, y: annot.bounds.maxY, width: 200, height: 150)
            let popup = PDFAnnotation(bounds: popupBounds, forType: .popup, withProperties: nil)
            annot.popup = popup
            page.addAnnotation(popup)
        }
    }

    // MARK: - UUID Helper

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
}
