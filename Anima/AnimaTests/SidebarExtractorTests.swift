//
//  SidebarExtractorTests.swift
//  AnimaTests
//
//  Tests for SidebarExtractor mechanics: reading highlight annotations from
//  PDFKit-backed fixtures, producing CommentCard data, and verifying that
//  in-memory annotations round-trip through the extractor.
//

import XCTest
import Quartz
@testable import Anima

final class SidebarExtractorTests: XCTestCase {

    // MARK: - Fixture loaders

    /// Helper: loads the single-page fixture and its expected golden JSON.
    private func loadBasicFixture() throws -> (PDFDocument, [CommentCard]) {
        let bundle = Bundle(for: type(of: self))
        guard let pdfURL = bundle.url(forResource: "sidebar_basic", withExtension: "pdf"),
              let jsonURL = bundle.url(forResource: "sidebar_basic_expected", withExtension: "json") else {
            XCTFail("Missing test fixtures. Did you check Target Membership for the Fixtures?")
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

    /// Helper: loads the multi-page fixture and its expected golden JSON.
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

    /// Helper: loads only the multi-page fixture PDF (no golden JSON).
    /// Used by tests that derive their assertions directly from the PDF.
    private func loadMultiPagePDFOnly() throws -> PDFDocument {
        let bundle = Bundle(for: type(of: self))
        guard let pdfURL = bundle.url(forResource: "sidebar_page_extract", withExtension: "pdf") else {
            XCTFail("Missing multi-page test fixture. Did you check Target Membership?")
            return PDFDocument()
        }

        guard let document = PDFDocument(url: pdfURL) else {
            XCTFail("Failed to load PDF from URL: \(pdfURL)")
            return PDFDocument()
        }

        return document
    }

    // MARK: - Single-page extraction (sidebar_basic.pdf)

    func testSidebarExtraction() throws {
        // 1. Locate test fixtures in the test bundle
        guard let pdfURL = Bundle(for: type(of: self)).url(forResource: "sidebar_basic", withExtension: "pdf"),
              let jsonURL = Bundle(for: type(of: self)).url(forResource: "sidebar_basic_expected", withExtension: "json") else {
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

    // MARK: - Multi-page extraction

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

    // MARK: - Per-page extraction

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

    // MARK: - In-Memory Annotation Round-Trip

    /// Verifies that an annotation built in-memory using the same pattern as
    /// AnimaPDFView.addInMemoryHighlight produces a CommentCard that is
    /// indistinguishable from the original fitz-written annotation.
    ///
    /// This test catches dual-write field omissions -- like the /NM and /T
    /// bugs we discovered during Phase 3 development. If addInMemoryHighlight
    /// changes how it sets annotation fields, this test should be updated to
    /// mirror those changes.
    ///
    /// Flow:
    ///   1. Extract cards from page 0 (fitz-written annotations = ground truth)
    ///   2. Pick the last card and find its PDFAnnotation on the page
    ///   3. Read the annotation's key fields (bounds, UUID, author, comment)
    ///   4. Remove the annotation from the page
    ///   5. Verify the card count dropped by one
    ///   6. Recreate the annotation in-memory (mirrors addInMemoryHighlight)
    ///   7. Extract cards again
    ///   8. Assert the recreated card matches the original
    func testInMemoryAnnotationRoundTrip() throws {
        let document = try loadMultiPagePDFOnly()

        let pageIndex = 0
        guard let page = document.page(at: pageIndex) else {
            XCTFail("Could not get page \(pageIndex)")
            return
        }

        // --- Step 1: Extract ground-truth cards ---
        let originalCards = SidebarExtractor.extractCards(from: page, at: pageIndex)
        XCTAssertTrue(originalCards.count >= 1, "Need at least one card on page \(pageIndex)")
        guard let targetCard = originalCards.last else { return }

        print("🎯 Round-trip target: '\(targetCard.text)' (uuid: \(targetCard.uuid))")

        // --- Step 2: Find the corresponding PDFAnnotation ---
        var targetAnnot: PDFAnnotation?
        for annot in page.annotations {
            // Check /NM first (same logic as annotationUUID)
            if let nm = annot.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/NM")) as? String,
               nm == targetCard.uuid {
                targetAnnot = annot
                break
            }
            // Fallback: userName
            if let name = annot.userName, name == targetCard.uuid {
                targetAnnot = annot
                break
            }
        }

        guard let annot = targetAnnot else {
            XCTFail("Could not find annotation with UUID \(targetCard.uuid) on page \(pageIndex)")
            return
        }

        // --- Step 3: Read the annotation's fields ---
        let originalBounds = annot.bounds
        let originalContents = annot.contents ?? ""
        let originalUUID = targetCard.uuid
        let originalAuthor = targetCard.author

        print("📋 Original annotation: bounds=\(originalBounds), author=\(originalAuthor), text=\(originalContents)")

        // --- Step 4: Remove the annotation ---
        page.removeAnnotation(annot)

        // --- Step 5: Verify count dropped ---
        let afterRemovalCards = SidebarExtractor.extractCards(from: page, at: pageIndex)
        XCTAssertEqual(afterRemovalCards.count, originalCards.count - 1,
                       "Removing annotation should reduce card count by 1")

        // Verify the removed card is actually gone
        let removedStillPresent = afterRemovalCards.contains { $0.uuid == originalUUID }
        XCTAssertFalse(removedStillPresent,
                       "Removed annotation's card should not appear in extraction")

        // --- Step 6: Recreate in-memory (mirrors addInMemoryHighlight) ---
        // This must stay in sync with AnimaPDFView.addInMemoryHighlight.
        // If that method changes, update this block accordingly.

        let recreated = PDFAnnotation(
            bounds: originalBounds,
            forType: .highlight,
            withProperties: nil
        )

        // Appearance -- matches anima_helper.py constants
        recreated.color = AnnotationManager.highlightColor
        recreated.setValue(AnnotationManager.highlightOpacity,
                          forAnnotationKey: PDFAnnotationKey(rawValue: "/CA"))

        // Comment
        if !originalContents.isEmpty {
            recreated.contents = originalContents
        }

        // UUID -- /NM is primary, userName is backup
        recreated.setValue(originalUUID,
                          forAnnotationKey: PDFAnnotationKey(rawValue: "/NM"))
        recreated.userName = originalUUID

        // Author -- must be set AFTER userName (PDFKit maps userName -> /T)
        recreated.setValue(originalAuthor,
                          forAnnotationKey: PDFAnnotationKey(rawValue: "/T"))

        // QuadPoints from bounds (one quad from the bounding rect corners) --
        // now calls the same AnnotationManager.quadPoints(for:) that
        // addInMemoryHighlight uses, instead of a hand-copied duplicate.
        let quadPoints = AnnotationManager.quadPoints(for: originalBounds)
        recreated.setValue(quadPoints,
                          forAnnotationKey: PDFAnnotationKey(rawValue: "/QuadPoints"))

        // Add to page
        page.addAnnotation(recreated)

        // --- Step 7: Extract cards again ---
        let afterRecreationCards = SidebarExtractor.extractCards(from: page, at: pageIndex)

        // --- Step 8: Assert the recreated card matches the original ---
        XCTAssertEqual(afterRecreationCards.count, originalCards.count,
                       "Card count should be restored after recreation")

        guard let recreatedCard = afterRecreationCards.first(where: { $0.uuid == originalUUID }) else {
            XCTFail("Recreated annotation not found in extracted cards. " +
                    "This likely means /NM or userName is not set correctly.")
            return
        }

        // Core identity
        XCTAssertEqual(recreatedCard.uuid, targetCard.uuid,
                       "UUID mismatch -- /NM not set correctly on in-memory annotation")
        XCTAssertEqual(recreatedCard.text, targetCard.text,
                       "Comment text mismatch -- .contents not set correctly")
        XCTAssertEqual(recreatedCard.pageIndex, targetCard.pageIndex,
                       "Page index mismatch")

        // Author -- this is the field that broke when /T wasn't set explicitly
        XCTAssertEqual(recreatedCard.author, targetCard.author,
                       "Author mismatch -- /T not set correctly on in-memory annotation. " +
                       "Got '\(recreatedCard.author)', expected '\(targetCard.author)'. " +
                       "If the author looks like a UUID, /T is picking up userName instead.")

        // Anchor position -- may differ slightly because the original annotation
        // might have multi-line quads (larger bounds) while our recreation uses
        // the overall bounding rect. We use a generous tolerance.
        XCTAssertEqual(recreatedCard.anchorY, targetCard.anchorY, accuracy: 1.0,
                       "Anchor Y mismatch -- bounds may differ between original and recreated")

        print("✅ Round-trip passed: '\(recreatedCard.text)' matches original")
    }
}
