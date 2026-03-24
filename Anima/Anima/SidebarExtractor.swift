//
//  SidebarExtractor.swift
//  Anima
//
//  Extracts CommentCard data from a PDFDocument for the sidebar.
//

import Foundation
import Quartz

/// Represents the data backing a single card in the sidebar.
struct CommentCard: Codable, Equatable {
    let uuid: String
    let text: String
    let pageIndex: Int
    let anchorY: Double
    let author: String
    let dateString: String
}

class SidebarExtractor {

    /// Scans the entire document for highlights with non-empty comments.
    /// Delegates to the per-page method for each page.
    static func extractCards(from document: PDFDocument) -> [CommentCard] {
        var cards: [CommentCard] = []

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            cards.append(contentsOf: extractCards(from: page, at: pageIndex))
        }

        return cards
    }

    /// Extracts cards from a single page. Used by the document-level method
    /// and by the sidebar's live-update path (Phase 3) to rebuild one page
    /// without re-scanning the entire document.
    ///
    /// Cards are sorted top-to-bottom (descending anchorY in PDFKit space,
    /// where higher Y = higher on the physical page).
    static func extractCards(from page: PDFPage, at pageIndex: Int) -> [CommentCard] {
        var pageCards: [CommentCard] = []

        for annot in page.annotations {
            // 1. Must be a highlight
            guard annot.type == "Highlight" else { continue }

            // 2. Must have a non-empty comment.
            // Check our custom /AnimaComment key first (from popup suppression scrub),
            // then fall back to standard .contents.
            var rawText = annot.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/AnimaComment")) as? String

            if rawText == nil || rawText!.isEmpty {
                rawText = annot.contents
            }

            guard let text = rawText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { continue }

            // 3. Must have a UUID
            guard let uuid = getUUID(for: annot) else { continue }

            // 4. Calculate anchorY
            let anchorY = Double(annot.bounds.midY)

            // 5. Extract Author and Date
            let author = getAuthor(for: annot)
            let dateString = getDateString(for: annot)

            // Create card
            let card = CommentCard(
                uuid: uuid,
                text: text,
                pageIndex: pageIndex,
                anchorY: anchorY,
                author: author,
                dateString: dateString
            )
            pageCards.append(card)
        }

        // Sort cards for this page top-to-bottom.
        pageCards.sort { $0.anchorY > $1.anchorY }

        return pageCards
    }

    // --- Extraction Helpers ---

    private static func getUUID(for annot: PDFAnnotation) -> String? {
        if let nm = annot.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/NM")) as? String {
            return nm
        }
        if let name = annot.userName, !name.isEmpty {
            return name
        }
        return nil
    }

    private static func getAuthor(for annot: PDFAnnotation) -> String {
        // The author is typically stored in the /T (Title) field
        if let author = annot.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/T")) as? String, !author.isEmpty {
            return author
        }
        return "Unknown"
    }

    private static func getDateString(for annot: PDFAnnotation) -> String {
        // PDFKit automatically parses standard PDF dates into Swift Date objects
        if let validDate = annot.modificationDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            return formatter.string(from: validDate)
        }
        return ""
    }
}
