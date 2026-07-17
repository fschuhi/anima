//
//  AnimaTests.swift
//  AnimaTests
//
//  Integration-level tests that exercise the Swift -> Python -> fitz boundary
//  and cross-page reader behavior. Pure extraction mechanics live in
//  SidebarExtractorTests.swift; pure geometry tests live in
//  AnnotationGeometryTests.swift.
//

import XCTest
import Quartz
@testable import Anima

final class AnimaTests: XCTestCase {

    // MARK: - Project self-location

    /// Locates the project root from this source file's own compile-time
    /// path (#filePath), mirroring FitzBridge's own path-derivation logic
    /// instead of relying on an Xcode scheme environment variable.
    ///
    /// #filePath resolves to the absolute path this file had *on the
    /// machine that compiled it* -- unlike the test bundle's runtime
    /// location, which lives in DerivedData:
    ///     <project root>/Anima/AnimaTests/AnimaTests.swift
    /// Three path components up from that gives the project root.
    private static var projectRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // AnimaTests/
            .deletingLastPathComponent()  // Anima/
            .deletingLastPathComponent()  // <project root>/
    }()

    /// Absolute path to tools/anima_helper.py, derived from projectRoot.
    private static var helperPath: String = {
        projectRoot.appendingPathComponent("tools/anima_helper.py").path
    }()

    // MARK: - FitzBridge Integration: add-highlight round-trip

    /// Verifies the real Swift -> Python -> fitz path: FitzBridge.addHighlight
    /// shells out to anima_helper.py (via the project's .venv), which writes
    /// an incremental-save highlight annotation to disk. Reloading the file
    /// and running SidebarExtractor must find the new annotation intact.
    ///
    /// Unlike testInMemoryAnnotationRoundTrip (which recreates a PDFAnnotation
    /// by hand, mirroring addInMemoryHighlight), this test never simulates
    /// the Python side -- it is the actual subprocess boundary under test.
    ///
    /// Requires the project's .venv (see the Makefile's `setup` target) to
    /// be present at <project root>/.venv/bin/python3.
    func testFitzBridgeAddHighlightRoundTrip() throws {
        // --- Step 1: locate anima_helper.py via #filePath self-location ---
        let helperPath = Self.helperPath
        guard FileManager.default.fileExists(atPath: helperPath) else {
            XCTFail("anima_helper.py not found at expected path: \(helperPath). " +
                    "Is the project checkout layout as expected (tools/anima_helper.py " +
                    "two levels above Anima/AnimaTests)? Also run `make setup` if .venv is missing.")
            return
        }

        // --- Step 2: work on a disposable copy of the fixture, never the checked-in file ---
        let bundle = Bundle(for: type(of: self))
        guard let fixtureURL = bundle.url(forResource: "sidebar_basic", withExtension: "pdf") else {
            XCTFail("Missing sidebar_basic.pdf fixture in test bundle.")
            return
        }

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let workingPDF = tempDir.appendingPathComponent("sidebar_basic.pdf")
        try FileManager.default.copyItem(at: fixtureURL, to: workingPDF)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // --- Step 3: baseline card count before the new highlight ---
        guard let beforeDocument = PDFDocument(url: workingPDF) else {
            XCTFail("Failed to load working copy at \(workingPDF.path)")
            return
        }
        let beforeCards = SidebarExtractor.extractCards(from: beforeDocument)

        // --- Step 4: call FitzBridge.addHighlight for real ---
        let newUUID = UUID().uuidString
        let newComment = "Added via FitzBridge integration test"
        let pageIndex = 0

        // A simple one-line quad on the page, in fitz space (origin top-left).
        // Coordinates chosen to land in a plain, uncommented region of the fixture page.
        let quadsJSON = """
        [{"x0": 72, "y0": 660, "x1": 300, "y1": 675}]
        """

        let success = FitzBridge.addHighlight(
            helperPath: helperPath,
            filePath: workingPDF.path,
            page: pageIndex,
            uuid: newUUID,
            quadsJSON: quadsJSON,
            comment: newComment
        )
        XCTAssertTrue(success, "FitzBridge.addHighlight should return true on success")

        // --- Step 5: reload and verify via SidebarExtractor ---
        guard let afterDocument = PDFDocument(url: workingPDF) else {
            XCTFail("Failed to reload working copy after addHighlight at \(workingPDF.path)")
            return
        }
        let afterCards = SidebarExtractor.extractCards(from: afterDocument)

        XCTAssertEqual(afterCards.count, beforeCards.count + 1,
                       "Adding one highlight via FitzBridge should increase the card count by exactly one")

        guard let newCard = afterCards.first(where: { $0.uuid == newUUID }) else {
            XCTFail("New highlight (uuid: \(newUUID)) not found after FitzBridge.addHighlight + reload")
            return
        }

        XCTAssertEqual(newCard.text, newComment,
                       "Comment text mismatch -- anima_helper.py's add-highlight should persist --comment as /Contents")
        XCTAssertEqual(newCard.pageIndex, pageIndex,
                       "Page index mismatch for the newly added highlight")

        print("✅ FitzBridge.addHighlight round-trip passed: uuid \(newUUID) found after reload")
    }

    // MARK: - FitzBridge + BookmarkManager Integration

    /// Verifies the complete Swift bookmark persistence seam against the real
    /// helper: manager mutation -> FitzBridge -> Python -> PDF catalog ->
    /// FitzBridge list -> JSON decode -> refreshed session-local state.
    ///
    /// The test intentionally uses a disposable fixture copy. It checks the
    /// bookmark contract that Swift owns: names, persisted ordering after a
    /// case-insensitive upsert, and fitz-native 0-based page indices.
    func testBookmarkManagerPersistenceRoundTrip() throws {
        // --- Step 1: locate the real helper and a disposable PDF fixture ---
        let helperPath = Self.helperPath
        guard FileManager.default.fileExists(atPath: helperPath) else {
            XCTFail("anima_helper.py not found at expected path: \(helperPath). " +
                    "Run `make setup` if .venv is missing.")
            return
        }

        let bundle = Bundle(for: type(of: self))
        guard let fixtureURL = bundle.url(
            forResource: "sidebar_page_extract",
            withExtension: "pdf"
        ) else {
            XCTFail("Missing sidebar_page_extract.pdf fixture in test bundle.")
            return
        }

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )

        let workingPDF = tempDir.appendingPathComponent("sidebar_page_extract.pdf")
        try FileManager.default.copyItem(at: fixtureURL, to: workingPDF)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // --- Step 2: load an initially bookmark-free document ---
        let bookmarkManager = BookmarkManager(helperPath: helperPath)

        XCTAssertTrue(
            bookmarkManager.loadBookmarks(filePath: workingPDF.path),
            "BookmarkManager should decode the helper's empty JSON array"
        )
        XCTAssertEqual(bookmarkManager.bookmarks, [])

        // --- Step 3: add two bookmarks through the manager ---
        XCTAssertTrue(
            bookmarkManager.setBookmark(
                name: "Endnotes Start",
                page: 1,
                filePath: workingPDF.path
            ),
            "Setting the first bookmark should persist and refresh manager state"
        )

        XCTAssertTrue(
            bookmarkManager.setBookmark(
                name: "Important Figure",
                page: 0,
                filePath: workingPDF.path
            ),
            "Setting the second bookmark should persist and refresh manager state"
        )

        XCTAssertEqual(
            bookmarkManager.bookmarks,
            [
                Bookmark(name: "Endnotes Start", page: 1),
                Bookmark(name: "Important Figure", page: 0),
            ],
            "Bookmark pages remain 0-based inside Swift, matching the helper contract"
        )

        // --- Step 4: case-insensitive upsert changes the helper's order ---
        // The Python helper removes the old matching name and appends the
        // supplied one, so the updated bookmark becomes the final item.
        XCTAssertTrue(
            bookmarkManager.setBookmark(
                name: "ENDNOTES start",
                page: 2,
                filePath: workingPDF.path
            ),
            "Case-insensitive upsert should persist and refresh manager state"
        )

        XCTAssertEqual(
            bookmarkManager.bookmarks,
            [
                Bookmark(name: "Important Figure", page: 0),
                Bookmark(name: "ENDNOTES start", page: 2),
            ],
            "The helper's persisted order and newer display casing must survive the Swift reload"
        )

        // --- Step 5: case-insensitive delete refreshes manager state ---
        XCTAssertTrue(
            bookmarkManager.deleteBookmark(
                name: "important figure",
                filePath: workingPDF.path
            ),
            "Case-insensitive deletion should persist and refresh manager state"
        )

        XCTAssertEqual(
            bookmarkManager.bookmarks,
            [Bookmark(name: "ENDNOTES start", page: 2)]
        )

        // --- Step 6: prove the persisted PDF independently matches Swift ---
        guard let persistedJSON = FitzBridge.listBookmarks(
            helperPath: helperPath,
            filePath: workingPDF.path
        ),
        let persistedData = persistedJSON.data(using: .utf8) else {
            XCTFail("FitzBridge.listBookmarks should return the persisted JSON array")
            return
        }

        let persistedBookmarks = try JSONDecoder().decode(
            [Bookmark].self,
            from: persistedData
        )

        XCTAssertEqual(
            persistedBookmarks,
            bookmarkManager.bookmarks,
            "BookmarkManager's session state must match the PDF catalog after each mutation"
        )
    }

    // MARK: - FitzBridge Integration: last-page round-trip

    /// Verifies the Swift -> Python -> fitz seam for last-page persistence:
    /// FitzBridge.setLastPage writes a 0-based index into the PDF's private
    /// /AnimaLastPage catalog key, and FitzBridge.getLastPage reads the raw
    /// value back. This pins the contract AppDelegate.restoreLastPage depends
    /// on: an unset document reports "-1", a stored index round-trips, and a
    /// second write overwrites the single scalar.
    ///
    /// Clamping a stale index into range is pure view logic in
    /// AnimaPDFView.restore(toPageIndex:) and is intentionally out of scope
    /// here -- this test covers only the persistence seam.
    func testFitzBridgeLastPageRoundTrip() throws {
        // --- Step 1: locate the real helper and a disposable PDF fixture ---
        let helperPath = Self.helperPath
        guard FileManager.default.fileExists(atPath: helperPath) else {
            XCTFail("anima_helper.py not found at expected path: \(helperPath). " +
                    "Run `make setup` if .venv is missing.")
            return
        }

        let bundle = Bundle(for: type(of: self))
        guard let fixtureURL = bundle.url(
            forResource: "sidebar_page_extract",
            withExtension: "pdf"
        ) else {
            XCTFail("Missing sidebar_page_extract.pdf fixture in test bundle.")
            return
        }

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )

        let workingPDF = tempDir.appendingPathComponent("sidebar_page_extract.pdf")
        try FileManager.default.copyItem(at: fixtureURL, to: workingPDF)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // --- Step 2: an untouched fixture reports -1 (no stored position) ---
        let unsetValue = FitzBridge.getLastPage(
            helperPath: helperPath,
            filePath: workingPDF.path
        )
        XCTAssertEqual(
            unsetValue, "-1",
            "A fixture with no /AnimaLastPage key must report -1 through the bridge"
        )

        // --- Step 3: store a page and read the same index back ---
        XCTAssertTrue(
            FitzBridge.setLastPage(
                helperPath: helperPath,
                filePath: workingPDF.path,
                page: 1
            ),
            "setLastPage should persist a valid 0-based index and return true"
        )
        XCTAssertEqual(
            FitzBridge.getLastPage(helperPath: helperPath, filePath: workingPDF.path),
            "1",
            "The stored page index must round-trip through the PDF catalog"
        )

        // --- Step 4: a second write overwrites the single scalar ---
        XCTAssertTrue(
            FitzBridge.setLastPage(
                helperPath: helperPath,
                filePath: workingPDF.path,
                page: 2
            ),
            "Overwriting the last page should persist and return true"
        )
        XCTAssertEqual(
            FitzBridge.getLastPage(helperPath: helperPath, filePath: workingPDF.path),
            "2",
            "The newest write must win -- last page is a single stored value"
        )
    }

    // MARK: - Cross-Page Selection: page-scoped highlight creation

    /// Pins the page-scoped behavior of AnimaPDFView.createHighlightFromSelection()
    /// when the user's text selection spans two pages: only the first-page lines
    /// produce a highlight; the second-page portion is silently dropped.
    ///
    /// This is intentional, not a bug -- Anima's highlight model is deliberately
    /// per-page. Cross-page spans would otherwise pull in inter-page whitespace,
    /// running headers/footers, and footnotes that have nothing to do with the
    /// highlighted content. Stitching a highlight on page N to its continuation
    /// on page N+1 is handled entirely downstream, by pdf-annotations' `link`
    /// comment convention -- Anima's own contract is just to keep producing
    /// clean, single-page highlights and let that convention carry the
    /// relationship.
    ///
    /// Uses PDFDocument.selection(from:atCharacterIndex:to:atCharacterIndex:) to
    /// build a genuine cross-page PDFSelection through PDFKit's own text-selection
    /// machinery, rather than assembling one by hand from two page-local rects.
    ///
    /// Verification reads raw PDFAnnotations directly, not via SidebarExtractor:
    /// highlights created by createHighlightFromSelection() start with an empty
    /// comment (see AnnotationManager.createHighlight's "Highlights are created
    /// without a comment" contract), and SidebarExtractor only surfaces highlights
    /// with a non-empty comment ("cards" and "highlights" are not the same thing
    /// in this codebase). Using SidebarExtractor here would make the test fail
    /// regardless of page-scoping, for an unrelated reason.
    func testCrossPageSelectionOnlyHighlightsFirstPage() throws {
        // --- Step 1: locate anima_helper.py (see testFitzBridgeAddHighlightRoundTrip) ---
        let helperPath = Self.helperPath
        guard FileManager.default.fileExists(atPath: helperPath) else {
            XCTFail("anima_helper.py not found at expected path: \(helperPath). " +
                    "Run `make setup` if .venv is missing.")
            return
        }

        // --- Step 2: work on a disposable copy of the two-page fixture ---
        let bundle = Bundle(for: type(of: self))
        guard let fixtureURL = bundle.url(forResource: "sidebar_page_extract", withExtension: "pdf") else {
            XCTFail("Missing sidebar_page_extract.pdf fixture in test bundle.")
            return
        }

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let workingPDF = tempDir.appendingPathComponent("sidebar_page_extract.pdf")
        try FileManager.default.copyItem(at: fixtureURL, to: workingPDF)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        guard let document = PDFDocument(url: workingPDF) else {
            XCTFail("Failed to load working copy at \(workingPDF.path)")
            return
        }

        guard let page0 = document.page(at: 0), let page1 = document.page(at: 1) else {
            XCTFail("Fixture must have at least two pages")
            return
        }

        // One AnnotationManager instance for the whole test: it's the same
        // toolbox instance the view will use to create the highlight, and we
        // reuse its annotationUUID(_:) helper for verification below rather
        // than duplicating the /NM-then-userName fallback a fourth time
        // (AnnotationManager, SidebarExtractor, and MainViewController each
        // already have their own copy -- see TODO.md's Refactoring section).
        let annotationManager = AnnotationManager(helperPath: helperPath)

        /// Collects UUIDs of all highlight annotations on a page, regardless
        /// of whether they carry a comment.
        func highlightUUIDs(on page: PDFPage) -> Set<String> {
            var uuids: Set<String> = []
            for annot in page.annotations where annot.type == "Highlight" {
                if let uuid = annotationManager.annotationUUID(annot) {
                    uuids.insert(uuid)
                }
            }
            return uuids
        }

        // --- Step 3: baseline highlight UUIDs per page, before the new highlight ---
        let beforePage0UUIDs = highlightUUIDs(on: page0)
        let beforePage1UUIDs = highlightUUIDs(on: page1)

        // --- Step 4: build a genuine cross-page selection ---
        // Character indices are UTF-16-based, matching PDFKit's own indexing.
        let page0Length = (page0.string as NSString?)?.length ?? 0
        let page1Length = (page1.string as NSString?)?.length ?? 0

        guard page0Length > 5, page1Length > 5 else {
            XCTFail("Fixture pages too short to select near their boundary " +
                    "(page0: \(page0Length), page1: \(page1Length) chars)")
            return
        }

        let startCharIndex = page0Length - 5  // near the end of page 0
        let endCharIndex = 5                  // near the start of page 1

        guard let selection = document.selection(
            from: page0, atCharacterIndex: startCharIndex,
            to: page1, atCharacterIndex: endCharIndex
        ) else {
            XCTFail("Could not create cross-page PDFSelection")
            return
        }

        // Sanity-check the selection setup itself spans both pages before we
        // trust what createHighlightFromSelection() does with it.
        XCTAssertTrue(selection.pages.contains(page0),
                      "Test setup: selection should include page 0")
        XCTAssertTrue(selection.pages.contains(page1),
                      "Test setup: selection should include page 1")

        // --- Step 5: drive AnimaPDFView.createHighlightFromSelection() directly ---
        // No window or layout needed -- this method only reads document,
        // currentSelection, isXRayMode, and annotationManager.
        let view = AnimaPDFView()
        view.document = document
        view.annotationManager = annotationManager
        view.isXRayMode = false
        view.currentSelection = selection

        let success = view.createHighlightFromSelection()
        XCTAssertTrue(success, "createHighlightFromSelection should succeed using only the first-page lines")

        // --- Step 6: reload from disk and verify page-scoped behavior ---
        guard let reloadedDocument = PDFDocument(url: workingPDF) else {
            XCTFail("Failed to reload working copy after createHighlightFromSelection at \(workingPDF.path)")
            return
        }
        guard let reloadedPage0 = reloadedDocument.page(at: 0),
              let reloadedPage1 = reloadedDocument.page(at: 1) else {
            XCTFail("Reloaded document must still have at least two pages")
            return
        }

        let afterPage0UUIDs = highlightUUIDs(on: reloadedPage0)
        let afterPage1UUIDs = highlightUUIDs(on: reloadedPage1)

        let newPage0UUIDs = afterPage0UUIDs.subtracting(beforePage0UUIDs)
        let newPage1UUIDs = afterPage1UUIDs.subtracting(beforePage1UUIDs)

        XCTAssertEqual(newPage0UUIDs.count, 1,
                       "The cross-page selection should create exactly one new highlight on page 0 " +
                       "(first-page lines only); found \(newPage0UUIDs.count)")
        XCTAssertEqual(newPage1UUIDs.count, 0,
                       "The cross-page selection's page-1 portion should be silently dropped, not " +
                       "stitched, duplicated, or otherwise turned into a highlight on page 1; " +
                       "found \(newPage1UUIDs.count)")

        print("✅ Cross-page selection round-trip passed: highlight confined to page 0, as intended")
    }
}
