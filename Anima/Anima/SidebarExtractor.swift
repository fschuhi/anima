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
        // TODO: Implement actual extraction logic
        return []
    }
}
