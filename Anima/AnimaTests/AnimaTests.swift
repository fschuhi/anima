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

    // MARK: - In-Memory Annotation Round-Trip

    /// Verifies that an annotation built in-memory using the same pattern as
    /// AnimaPDFView.addInMemoryHighlight produces a CommentCard that is
    /// indistinguishable from the original fitz-written annotation.
    ///
    /// This test catches dual-write field omissions — like the /NM and /T
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
        let (document, _) = try loadMultiPageFixture()

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

        // Appearance — matches anima_helper.py constants
        recreated.color = AnnotationManager.highlightColor
        recreated.setValue(AnnotationManager.highlightOpacity,
                          forAnnotationKey: PDFAnnotationKey(rawValue: "/CA"))

        // Comment
        if !originalContents.isEmpty {
            recreated.contents = originalContents
        }

        // UUID — /NM is primary, userName is backup
        recreated.setValue(originalUUID,
                          forAnnotationKey: PDFAnnotationKey(rawValue: "/NM"))
        recreated.userName = originalUUID

        // Author — must be set AFTER userName (PDFKit maps userName → /T)
        recreated.setValue(originalAuthor,
                          forAnnotationKey: PDFAnnotationKey(rawValue: "/T"))

        // QuadPoints from bounds (one quad from the bounding rect corners) —
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
                       "UUID mismatch — /NM not set correctly on in-memory annotation")
        XCTAssertEqual(recreatedCard.text, targetCard.text,
                       "Comment text mismatch — .contents not set correctly")
        XCTAssertEqual(recreatedCard.pageIndex, targetCard.pageIndex,
                       "Page index mismatch")

        // Author — this is the field that broke when /T wasn't set explicitly
        XCTAssertEqual(recreatedCard.author, targetCard.author,
                       "Author mismatch — /T not set correctly on in-memory annotation. " +
                       "Got '\(recreatedCard.author)', expected '\(targetCard.author)'. " +
                       "If the author looks like a UUID, /T is picking up userName instead.")

        // Anchor position — may differ slightly because the original annotation
        // might have multi-line quads (larger bounds) while our recreation uses
        // the overall bounding rect. We use a generous tolerance.
        XCTAssertEqual(recreatedCard.anchorY, targetCard.anchorY, accuracy: 1.0,
                       "Anchor Y mismatch — bounds may differ between original and recreated")

        print("✅ Round-trip passed: '\(recreatedCard.text)' matches original")
    }

    // MARK: - Coordinate Conversion: fitzQuad y-flip

    /// Pins AnnotationManager.fitzQuad(from:pageHeight:) — the PDFKit-space
    /// (origin bottom-left) → fitz-space (origin top-left) conversion used
    /// when persisting highlight quads via anima_helper.py.
    ///
    /// Contract under test (must match anima_helper.py's docstring):
    ///     y_fitz = page_height - y_pdfkit
    ///
    /// Pure arithmetic — no PDF fixture needed. This documents the coordinate
    /// specifics in code and guards against regression; there was no known
    /// bug behind it at the time of writing.
    func testFitzQuadYFlip() {
        let letterHeight: CGFloat = 792  // US Letter, points

        // --- Case 1: known page, known rect ---
        // A line near the top of the page should flip to a small y0_fitz;
        // a line near the bottom should flip to a y0_fitz near the page height.
        let topLineRect = NSRect(x: 72, y: 750, width: 400, height: 20)
        let topQuad = AnnotationManager.fitzQuad(from: topLineRect, pageHeight: letterHeight)

        XCTAssertEqual(topQuad["y0"]!, Double(letterHeight) - Double(topLineRect.origin.y + topLineRect.size.height),
                       accuracy: 0.001, "y0_fitz should equal pageHeight - (y + height)")
        XCTAssertEqual(topQuad["y1"]!, Double(letterHeight) - Double(topLineRect.origin.y),
                       accuracy: 0.001, "y1_fitz should equal pageHeight - y")
        XCTAssertLessThan(topQuad["y0"]!, 30,
                          "A line near the top of the page should have a small y0_fitz")

        let bottomLineRect = NSRect(x: 72, y: 40, width: 400, height: 20)
        let bottomQuad = AnnotationManager.fitzQuad(from: bottomLineRect, pageHeight: letterHeight)

        XCTAssertGreaterThan(bottomQuad["y0"]!, Double(letterHeight) - 70,
                             "A line near the bottom of the page should have y0_fitz near the page height")

        // --- Case 2: round-trip identity ---
        // Flipping once and flipping back must recover the original PDFKit y
        // values. Catches an off-by-one-flip or sign error in the conversion.
        let rect = NSRect(x: 100, y: 300, width: 250, height: 15)
        let quad = AnnotationManager.fitzQuad(from: rect, pageHeight: letterHeight)

        let recoveredOriginY = Double(letterHeight) - quad["y1"]!
        let recoveredTopY = Double(letterHeight) - quad["y0"]!

        XCTAssertEqual(recoveredOriginY, Double(rect.origin.y), accuracy: 0.001,
                       "Flipping y1_fitz back should recover the rect's original origin.y")
        XCTAssertEqual(recoveredTopY, Double(rect.origin.y + rect.size.height), accuracy: 0.001,
                       "Flipping y0_fitz back should recover the rect's original top edge")

        // --- Case 3: non-standard page height ---
        // The same PDFKit rect on a differently sized page must produce a
        // different fitz y — guards against any hardcoded page-height assumption.
        let a4Height: CGFloat = 841.89  // A4, points
        let sameRect = NSRect(x: 50, y: 100, width: 300, height: 12)

        let letterQuad = AnnotationManager.fitzQuad(from: sameRect, pageHeight: letterHeight)
        let a4Quad = AnnotationManager.fitzQuad(from: sameRect, pageHeight: a4Height)

        XCTAssertNotEqual(letterQuad["y0"]!, a4Quad["y0"]!,
                          "The same rect on different page heights must produce different fitz y values")
        XCTAssertEqual(a4Quad["y0"]!, Double(a4Height) - Double(sameRect.origin.y + sameRect.size.height),
                       accuracy: 0.001)

        // --- Case 4: x is unaffected by the flip ---
        // Only y inverts; x0/x1 pass through unchanged.
        let wideRect = NSRect(x: 36, y: 500, width: 500, height: 18)
        let wideQuad = AnnotationManager.fitzQuad(from: wideRect, pageHeight: letterHeight)

        XCTAssertEqual(wideQuad["x0"]!, Double(wideRect.origin.x), accuracy: 0.001,
                       "x0 should pass through unchanged")
        XCTAssertEqual(wideQuad["x1"]!, Double(wideRect.origin.x + wideRect.size.width), accuracy: 0.001,
                       "x1 should pass through unchanged")
    }

    // MARK: - QuadPoints Construction

    /// Pins AnnotationManager.quadPoints(for:) — the PDFKit-space rect →
    /// QuadPoints corner-array conversion used both when persisting the
    /// in-memory annotation (addInMemoryHighlight) and, until this change,
    /// duplicated by hand in testInMemoryAnnotationRoundTrip.
    ///
    /// Contract under test: for a given rect, the four corners are emitted
    /// in the order bottom-left, bottom-right, top-left, top-right (the
    /// order the source comments call "PDF spec order" -- this test pins
    /// that claim in code without judging whether it's correct).
    ///
    /// Pure geometry, no PDF fixture needed.
    func testQuadPointsConstruction() {
        // --- Case 1: known rect -> four exact corners, in order ---
        let rect = NSRect(x: 100, y: 50, width: 200, height: 30)
        let quad = AnnotationManager.quadPoints(for: rect)

        XCTAssertEqual(quad.count, 4, "One rect should produce exactly 4 QuadPoints")

        let bottomLeft  = quad[0].pointValue
        let bottomRight = quad[1].pointValue
        let topLeft     = quad[2].pointValue
        let topRight    = quad[3].pointValue

        XCTAssertEqual(bottomLeft,  NSPoint(x: 100, y: 50),  "bottom-left corner")
        XCTAssertEqual(bottomRight, NSPoint(x: 300, y: 50),  "bottom-right corner")
        XCTAssertEqual(topLeft,     NSPoint(x: 100, y: 80),  "top-left corner")
        XCTAssertEqual(topRight,    NSPoint(x: 300, y: 80),  "top-right corner")

        // --- Case 2: multiple rects (multi-line selection) ---
        // Each rect contributes exactly 4 points, flattened in rect order --
        // this is the invariant addInMemoryHighlight's loop depends on.
        let rects = [
            NSRect(x: 0, y: 0, width: 50, height: 10),
            NSRect(x: 0, y: 10, width: 80, height: 10),
            NSRect(x: 0, y: 20, width: 30, height: 10),
        ]

        var flattened: [NSValue] = []
        for r in rects {
            flattened.append(contentsOf: AnnotationManager.quadPoints(for: r))
        }

        XCTAssertEqual(flattened.count, rects.count * 4,
                       "N rects should produce exactly 4*N QuadPoints")

        for (index, r) in rects.enumerated() {
            let base = index * 4
            XCTAssertEqual(flattened[base].pointValue, NSPoint(x: r.minX, y: r.minY),
                           "Rect \(index): bottom-left")
            XCTAssertEqual(flattened[base + 1].pointValue, NSPoint(x: r.maxX, y: r.minY),
                           "Rect \(index): bottom-right")
            XCTAssertEqual(flattened[base + 2].pointValue, NSPoint(x: r.minX, y: r.maxY),
                           "Rect \(index): top-left")
            XCTAssertEqual(flattened[base + 3].pointValue, NSPoint(x: r.maxX, y: r.maxY),
                           "Rect \(index): top-right")
        }

        // --- Case 3: degenerate rects (zero width or height) ---
        // quadPoints(for:) is pure geometry -- it does not filter these out
        // (that's createHighlight's job, upstream). It should still return
        // 4 well-defined, non-crashing points for a zero-area rect.
        let zeroWidthRect = NSRect(x: 50, y: 50, width: 0, height: 20)
        let zeroWidthQuad = AnnotationManager.quadPoints(for: zeroWidthRect)

        XCTAssertEqual(zeroWidthQuad.count, 4, "A zero-width rect should still produce 4 points")
        XCTAssertEqual(zeroWidthQuad[0].pointValue.x, zeroWidthQuad[1].pointValue.x,
                       "Zero-width rect: left and right corners collapse to the same x")
        XCTAssertEqual(zeroWidthQuad[0].pointValue.y, 50, "bottom-left y")
        XCTAssertEqual(zeroWidthQuad[2].pointValue.y, 70, "top-left y")

        let zeroHeightRect = NSRect(x: 50, y: 50, width: 20, height: 0)
        let zeroHeightQuad = AnnotationManager.quadPoints(for: zeroHeightRect)

        XCTAssertEqual(zeroHeightQuad.count, 4, "A zero-height rect should still produce 4 points")
        XCTAssertEqual(zeroHeightQuad[0].pointValue.y, zeroHeightQuad[2].pointValue.y,
                       "Zero-height rect: bottom and top corners collapse to the same y")
        XCTAssertEqual(zeroHeightQuad[0].pointValue.x, 50, "bottom-left x")
        XCTAssertEqual(zeroHeightQuad[1].pointValue.x, 70, "bottom-right x")
    }

    // MARK: - FitzBridge Integration: add-highlight round-trip

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
}
