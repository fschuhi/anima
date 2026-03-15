//
//  AnimaTests.swift
//  AnimaTests
//

import XCTest
import Quartz
@testable import Anima

final class AnimaTests: XCTestCase {

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
}
