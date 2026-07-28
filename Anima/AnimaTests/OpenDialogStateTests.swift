//
//  OpenDialogStateTests.swift
//  AnimaTests
//
//  Unit tests for OpenDialogState per the test spec in
//  OPEN_DIALOG_DESIGN.md section 7. Pure equality checks throughout --
//  OpenDialogState.applying always returns a fresh outcome, never mutates,
//  so tests need no setup/mutate/inspect choreography.
//

import XCTest
@testable import Anima

final class OpenDialogStateTests: XCTestCase {

    private let files = ["Alpha.pdf", "beta.pdf", "Gamma.pdf", "alphabet.pdf"]

    // MARK: - Character append / Backspace

    func testCharacterAppendsToFilter() {
        let state = OpenDialogState.initial(fullFilenames: files)
        let outcome = OpenDialogState.applying(.character("a"), to: state)
        guard case .updated(let next) = outcome else {
            return XCTFail("expected .updated")
        }
        XCTAssertEqual(next.filterString, "a")
    }

    func testBackspaceRemovesLastCharacter() {
        let typed = OpenDialogState.applying(.character("a"), to: .initial(fullFilenames: files))
        guard case .updated(let afterType) = typed else { return XCTFail("expected .updated") }

        let outcome = OpenDialogState.applying(.backspace, to: afterType)
        guard case .updated(let next) = outcome else {
            return XCTFail("expected .updated")
        }
        XCTAssertEqual(next.filterString, "")
    }

    func testBackspaceOnEmptyFilterStaysEmpty() {
        let state = OpenDialogState.initial(fullFilenames: files)
        let outcome = OpenDialogState.applying(.backspace, to: state)
        guard case .updated(let next) = outcome else {
            return XCTFail("expected .updated")
        }
        XCTAssertEqual(next.filterString, "")
    }

    // MARK: - Case-insensitive substring matching

    func testFilterIsCaseInsensitiveSubstringMatch() {
        var state = OpenDialogState.initial(fullFilenames: files)
        for char in "ALPHA" {
            guard case .updated(let next) = OpenDialogState.applying(.character(char), to: state) else {
                return XCTFail("expected .updated")
            }
            state = next
        }
        // "Alpha.pdf" and "alphabet.pdf" both contain "alpha" case-insensitively.
        XCTAssertEqual(state.visibleFilenames, ["Alpha.pdf", "alphabet.pdf"])
    }

    // MARK: - Snap-to-first after every filter change

    func testSnapToFirstAfterCharacterAppend() {
        // Arrow down first, then type -- the new selection must snap back to
        // row 0 of the newly filtered list, not stay at the pre-type index.
        var state = OpenDialogState.initial(fullFilenames: files)
        guard case .updated(let afterDown) = OpenDialogState.applying(.down, to: state) else {
            return XCTFail("expected .updated")
        }
        state = afterDown
        XCTAssertEqual(state.selectionIndex, 1)

        guard case .updated(let afterType) = OpenDialogState.applying(.character("g"), to: state) else {
            return XCTFail("expected .updated")
        }
        XCTAssertEqual(afterType.selectionIndex, 0)
        XCTAssertEqual(afterType.selectedFilename, "Gamma.pdf")
    }

    func testSnapToFirstAfterBackspace() {
        var state = OpenDialogState.initial(fullFilenames: files)
        for char in "beta" {
            guard case .updated(let next) = OpenDialogState.applying(.character(char), to: state) else {
                return XCTFail("expected .updated")
            }
            state = next
        }
        guard case .updated(let afterBackspace) = OpenDialogState.applying(.backspace, to: state) else {
            return XCTFail("expected .updated")
        }
        XCTAssertEqual(afterBackspace.selectionIndex, 0)
    }

    // MARK: - Two-stage Escape

    func testEscapeWithNonEmptyFilterClearsFilter() {
        guard case .updated(let typed) = OpenDialogState.applying(.character("b"), to: .initial(fullFilenames: files)) else {
            return XCTFail("expected .updated")
        }
        let outcome = OpenDialogState.applying(.escape, to: typed)
        guard case .updated(let next) = outcome else {
            return XCTFail("expected .updated, got \(outcome)")
        }
        XCTAssertEqual(next.filterString, "")
        XCTAssertEqual(next.visibleFilenames, files)
    }

    func testEscapeWithEmptyFilterCloses() {
        let state = OpenDialogState.initial(fullFilenames: files)
        let outcome = OpenDialogState.applying(.escape, to: state)
        XCTAssertEqual(outcome, .close)
    }

    // MARK: - Enter

    func testEnterWithSelectionOpensFile() {
        let state = OpenDialogState.initial(fullFilenames: files)
        let outcome = OpenDialogState.applying(.enter, to: state)
        XCTAssertEqual(outcome, .open("Alpha.pdf"))
    }

    func testEnterWithNoSelectionBeeps() {
        guard case .updated(let typed) = OpenDialogState.applying(.character("z"), to: .initial(fullFilenames: files)) else {
            return XCTFail("expected .updated")
        }
        XCTAssertNil(typed.selectionIndex)
        let outcome = OpenDialogState.applying(.enter, to: typed)
        XCTAssertEqual(outcome, .beep)
    }

    // MARK: - Empty-match entry and recovery

    func testEmptyMatchStateHasNoSelection() {
        guard case .updated(let typed) = OpenDialogState.applying(.character("z"), to: .initial(fullFilenames: files)) else {
            return XCTFail("expected .updated")
        }
        XCTAssertTrue(typed.visibleFilenames.isEmpty)
        XCTAssertNil(typed.selectionIndex)
        XCTAssertNil(typed.selectedFilename)
    }

    func testBackspaceRecoversFromEmptyMatch() {
        var state = OpenDialogState.initial(fullFilenames: files)
        for char in "alphaz" {
            guard case .updated(let next) = OpenDialogState.applying(.character(char), to: state) else {
                return XCTFail("expected .updated")
            }
            state = next
        }
        XCTAssertTrue(state.visibleFilenames.isEmpty)

        guard case .updated(let recovered) = OpenDialogState.applying(.backspace, to: state) else {
            return XCTFail("expected .updated")
        }
        XCTAssertEqual(recovered.filterString, "alpha")
        XCTAssertFalse(recovered.visibleFilenames.isEmpty)
        XCTAssertEqual(recovered.selectionIndex, 0)
    }

    // MARK: - First-occurrence match range

    func testFirstMatchRangeFindsCaseInsensitiveOccurrence() {
        let range = OpenDialogState.firstMatchRange(of: "GAM", in: "Gamma.pdf")
        XCTAssertNotNil(range)
        if let range = range {
            XCTAssertEqual("Gamma.pdf"[range], "Gam")
        }
    }

    func testFirstMatchRangeIsNilForEmptyFilter() {
        XCTAssertNil(OpenDialogState.firstMatchRange(of: "", in: "Gamma.pdf"))
    }

    func testFirstMatchRangeIsNilWhenNoMatch() {
        XCTAssertNil(OpenDialogState.firstMatchRange(of: "zzz", in: "Gamma.pdf"))
    }
}
