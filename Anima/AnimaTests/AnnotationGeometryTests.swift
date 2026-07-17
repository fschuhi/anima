//
//  AnnotationGeometryTests.swift
//  AnimaTests
//
//  Pure geometry tests for AnnotationManager coordinate conversion and
//  QuadPoints construction. No PDF fixtures required.
//

import XCTest
@testable import Anima

final class AnnotationGeometryTests: XCTestCase {

    // MARK: - Coordinate Conversion: fitzQuad y-flip

    /// Pins AnnotationManager.fitzQuad(from:pageHeight:) -- the PDFKit-space
    /// (origin bottom-left) -> fitz-space (origin top-left) conversion used
    /// when persisting highlight quads via anima_helper.py.
    ///
    /// Contract under test (must match anima_helper.py's docstring):
    ///     y_fitz = page_height - y_pdfkit
    ///
    /// Pure arithmetic -- no PDF fixture needed. This documents the coordinate
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
        // different fitz y -- guards against any hardcoded page-height assumption.
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

    /// Pins AnnotationManager.quadPoints(for:) -- the PDFKit-space rect ->
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
}
