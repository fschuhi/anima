//
//  BookmarkManager.swift
//  Anima
//
//  Owns Anima's session-local named page bookmarks.
//
//  Bookmarks are persisted by anima_helper.py in the PDF catalog's private
//  /AnimaBookmarks key. This manager loads that JSON when a document opens
//  and becomes the in-memory source of truth for the rest of that reader
//  session.
//
//  Design:
//    Like AnnotationManager, this is a toolbox-style class. It holds no
//    references to PDFView, PDFDocument, or UI objects. The caller supplies
//    file context per operation, keeping persistence and UI ownership separate.
//
//  Page-index contract:
//    Bookmark.page is fitz-native and therefore 0-based. Future reader UI
//    must display page + 1 to the user.
//

import Foundation

struct Bookmark: Codable, Equatable {
    let name: String
    let page: Int
}

final class BookmarkManager {

    let helperPath: String

    /// The current document's bookmarks, in the order persisted by the helper.
    /// This is read-only to collaborators. Mutation methods replace the list
    /// only after the corresponding helper operation succeeds.
    private(set) var bookmarks: [Bookmark] = []

    init(helperPath: String) {
        self.helperPath = helperPath
    }

    /// Replaces the session-local bookmark list with the JSON currently stored
    /// in the PDF catalog. A helper or decode failure leaves the manager empty
    /// rather than accidentally retaining bookmarks from a previously loaded
    /// document.
    ///
    /// - Parameter filePath: Absolute path of the PDF being opened.
    /// - Returns: true if the helper returned valid bookmark JSON; false otherwise.
    @discardableResult
    func loadBookmarks(filePath: String) -> Bool {
        bookmarks = []

        guard let bookmarksJSON = FitzBridge.listBookmarks(
            helperPath: helperPath,
            filePath: filePath
        ) else {
            return false
        }

        guard let bookmarksData = bookmarksJSON.data(using: .utf8) else {
            Swift.print("❌ Could not decode bookmark JSON as UTF-8")
            return false
        }

        do {
            bookmarks = try JSONDecoder().decode([Bookmark].self, from: bookmarksData)
            Swift.print("🔖 Loaded \(bookmarks.count) bookmark(s)")
            return true
        } catch {
            Swift.print("❌ Could not decode bookmark JSON: \(error)")
            return false
        }
    }

    /// Persists a bookmark through the helper, then reloads the complete
    /// catalog-backed list. The helper owns case-insensitive upsert semantics,
    /// including the authoritative display casing and ordering after an update.
    ///
    /// - Parameters:
    ///   - name: Bookmark display name.
    ///   - page: fitz-native 0-based page index.
    ///   - filePath: Absolute path of the open PDF.
    /// - Returns: true only if persistence and the subsequent reload succeed.
    @discardableResult
    func setBookmark(name: String, page: Int, filePath: String) -> Bool {
        guard FitzBridge.setBookmark(
            helperPath: helperPath,
            filePath: filePath,
            name: name,
            page: page
        ) else {
            return false
        }

        return loadBookmarks(filePath: filePath)
    }

    /// Removes a bookmark through the helper, then reloads the complete
    /// catalog-backed list. Name matching is case-insensitive in the helper.
    ///
    /// - Parameters:
    ///   - name: Bookmark name to remove.
    ///   - filePath: Absolute path of the open PDF.
    /// - Returns: true only if deletion and the subsequent reload succeed.
    @discardableResult
    func deleteBookmark(name: String, filePath: String) -> Bool {
        guard FitzBridge.deleteBookmark(
            helperPath: helperPath,
            filePath: filePath,
            name: name
        ) else {
            return false
        }

        return loadBookmarks(filePath: filePath)
    }
}
