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
}

class SidebarExtractor {

    /// Scans the document for highlights with non-empty comments.
    static func extractCards(from document: PDFDocument) -> [CommentCard] {
        var cards: [CommentCard] = []

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }

            var pageCards: [CommentCard] = []

            for annot in page.annotations {
                // 1. Must be a highlight
                guard annot.type == "Highlight" else { continue }

                // 2. Must have a non-empty comment
                // We trim whitespace so a comment containing just " " is treated as empty
                guard let text = annot.contents?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty else { continue }

                // 3. Must have a UUID
                guard let uuid = getUUID(for: annot) else { continue }

                // 4. Calculate anchorY (vertical midpoint of bounds in PDFKit space)
                let anchorY = Double(annot.bounds.midY)

                // Create card
                let card = CommentCard(
                    uuid: uuid,
                    text: text,
                    pageIndex: pageIndex,
                    anchorY: anchorY
                )
                pageCards.append(card)
            }

            // 5. Sort cards for this page top-to-bottom.
            // In PDFKit space, Y=0 is the bottom of the page.
            // So higher on the page = larger Y value.
            pageCards.sort { $0.anchorY > $1.anchorY }

            cards.append(contentsOf: pageCards)
        }

        return cards
    }

    /// Safely extracts the UUID from the annotation.
    /// Matches the logic used in AnimaPDFView.
    private static func getUUID(for annot: PDFAnnotation) -> String? {
        if let nm = annot.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/NM")) as? String {
            return nm
        }
        if let name = annot.userName, !name.isEmpty {
            return name
        }
        return nil
    }
}
