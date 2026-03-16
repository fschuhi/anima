//
//  AnimaTests.swift
//  AnimaTests
//

import XCTest
import Quartz
@testable import Anima

final class AnimaTests: XCTestCase {

    // MARK: - Existing Test (sidebar_basic.pdf)

    func testSidebarExtraction() throws {
        // 1. Locate test fixtures in the test bundle
        let bundle = Bundle(for: type(of: self))
        guard let pdfURL = bundle.url(forResource: "sidebar_basic", withExtension: "pdf"),
              let jsonURL = bundle.url(forResource: "sidebar_basic_expected", withExtension: "json") else {
            XCTFail("Missing test fixtures. Did you check Target Membership for the Fixtures?")
            return
        }

        // 2. Load Expected Data (The Golden JSON)
        let jsonData = try Data(contentsOf: jsonURL)
        let expectedCards = try JSONDecoder().decode([CommentCard].self, from: jsonData)

        // 3. Load the PDF
        guard let document = PDFDocument(url: pdfURL) else {
            XCTFail("Failed to load PDF from URL: \(pdfURL)")
            return
        }

        // 4. Run the Extractor
        let actualCards = SidebarExtractor.extractCards(from: document)

        // 5. Assertions
        XCTAssertEqual(actualCards.count, expectedCards.count, "Extractor should find exactly \(expectedCards.count) cards.")

        // If counts match, verify the contents
        if actualCards.count == expectedCards.count {
            for (expected, actual) in zip(expectedCards, actualCards) {
                XCTAssertEqual(actual.uuid, expected.uuid, "UUID mismatch")
                XCTAssertEqual(actual.text, expected.text, "Text mismatch")
                XCTAssertEqual(actual.pageIndex, expected.pageIndex, "Page index mismatch")

                // For the first run, this will print the actual anchorY so we can update our JSON
                print("💡 Extracted Anchor Y for '\(actual.text)': \(actual.anchorY)")

                // We use an accuracy tolerance because floating point math between systems can drift
                XCTAssertEqual(actual.anchorY, expected.anchorY, accuracy: 0.1, "Anchor Y mismatch for \(actual.text)")
            }
        }
    }

    // MARK: - Multi-Page Test (sidebar_page_extract.pdf)

    /// Helper: loads the multi-page fixture and its expected JSON.
    private func loadMultiPageFixture() throws -> (PDFDocument, [CommentCard]) {
        let bundle = Bundle(for: type(of: self))
        guard let pdfURL = bundle.url(forResource: "sidebar_page_extract", withExtension: "pdf"),
              let jsonURL = bundle.url(forResource: "sidebar_page_extract_expected", withExtension: "json") else {
            XCTFail("Missing multi-page test fixtures. Did you check Target Membership?")
            return (PDFDocument(), [])
        }

        let jsonData = try Data(contentsOf: jsonURL)
        let expectedCards = try JSONDecoder().decode([CommentCard].self, from: jsonData)

        guard let document = PDFDocument(url: pdfURL) else {
            XCTFail("Failed to load PDF from URL: \(pdfURL)")
            return (PDFDocument(), [])
        }

        return (document, expectedCards)
    }

    func testMultiPageExtraction() throws {
        let (document, expectedCards) = try loadMultiPageFixture()
        guard !expectedCards.isEmpty else { return } // loadMultiPageFixture already failed

        let actualCards = SidebarExtractor.extractCards(from: document)

        // We expect 4 cards total: 2 on page 0, 2 on page 1
        XCTAssertEqual(actualCards.count, expectedCards.count,
                       "Expected \(expectedCards.count) cards, got \(actualCards.count)")

        guard actualCards.count == expectedCards.count else { return }

        for (expected, actual) in zip(expectedCards, actualCards) {
            XCTAssertEqual(actual.uuid, expected.uuid, "UUID mismatch")
            XCTAssertEqual(actual.text, expected.text, "Text mismatch")
            XCTAssertEqual(actual.pageIndex, expected.pageIndex, "Page index mismatch")
            XCTAssertEqual(actual.author, expected.author, "Author mismatch for \(actual.text)")

            print("💡 Multi-page — Extracted Anchor Y for '\(actual.text)' (page \(actual.pageIndex)): \(actual.anchorY)")

            XCTAssertEqual(actual.anchorY, expected.anchorY, accuracy: 0.1,
                           "Anchor Y mismatch for \(actual.text)")
        }
    }

    // MARK: - Per-Page Extraction Test

    func testPerPageExtraction() throws {
        let (document, expectedCards) = try loadMultiPageFixture()
        guard !expectedCards.isEmpty else { return }

        let expectedPage0 = expectedCards.filter { $0.pageIndex == 0 }
        let expectedPage1 = expectedCards.filter { $0.pageIndex == 1 }

        // --- Page 0 ---
        guard let page0 = document.page(at: 0) else {
            XCTFail("Could not get page 0")
            return
        }

        let actualPage0 = SidebarExtractor.extractCards(from: page0, at: 0)

        XCTAssertEqual(actualPage0.count, expectedPage0.count,
                       "Page 0: expected \(expectedPage0.count) cards, got \(actualPage0.count)")

        if actualPage0.count == expectedPage0.count {
            for (expected, actual) in zip(expectedPage0, actualPage0) {
                XCTAssertEqual(actual.uuid, expected.uuid, "Page 0: UUID mismatch")
                XCTAssertEqual(actual.text, expected.text, "Page 0: Text mismatch")
                XCTAssertEqual(actual.pageIndex, 0, "Page 0: pageIndex should be 0")

                print("💡 Per-page — Page 0 Anchor Y for '\(actual.text)': \(actual.anchorY)")

                XCTAssertEqual(actual.anchorY, expected.anchorY, accuracy: 0.1,
                               "Page 0: Anchor Y mismatch for \(actual.text)")
            }
        }

        // --- Page 1 ---
        guard let page1 = document.page(at: 1) else {
            XCTFail("Could not get page 1")
            return
        }

        let actualPage1 = SidebarExtractor.extractCards(from: page1, at: 1)

        XCTAssertEqual(actualPage1.count, expectedPage1.count,
                       "Page 1: expected \(expectedPage1.count) cards, got \(actualPage1.count)")

        if actualPage1.count == expectedPage1.count {
            for (expected, actual) in zip(expectedPage1, actualPage1) {
                XCTAssertEqual(actual.uuid, expected.uuid, "Page 1: UUID mismatch")
                XCTAssertEqual(actual.text, expected.text, "Page 1: Text mismatch")
                XCTAssertEqual(actual.pageIndex, 1, "Page 1: pageIndex should be 1")

                print("💡 Per-page — Page 1 Anchor Y for '\(actual.text)': \(actual.anchorY)")

                XCTAssertEqual(actual.anchorY, expected.anchorY, accuracy: 0.1,
                               "Page 1: Anchor Y mismatch for \(actual.text)")
            }
        }

        // --- Page 2 (should have no cards) ---
        guard let page2 = document.page(at: 2) else {
            XCTFail("Could not get page 2")
            return
        }

        let actualPage2 = SidebarExtractor.extractCards(from: page2, at: 2)
        XCTAssertEqual(actualPage2.count, 0, "Page 2 should have no cards")
    }

    // MARK: - Consistency: per-page results == document-level results

    func testPerPageConsistencyWithDocumentLevel() throws {
        let (document, _) = try loadMultiPageFixture()

        // Get the document-level result
        let documentCards = SidebarExtractor.extractCards(from: document)

        // Reassemble from per-page calls
        var reassembledCards: [CommentCard] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            reassembledCards.append(contentsOf: SidebarExtractor.extractCards(from: page, at: pageIndex))
        }

        // They must be identical
        XCTAssertEqual(documentCards.count, reassembledCards.count,
                       "Document-level and reassembled per-page counts must match")

        for (docCard, pageCard) in zip(documentCards, reassembledCards) {
            XCTAssertEqual(docCard, pageCard,
                           "Document-level card \(docCard.uuid) differs from per-page card")
        }
    }
}
