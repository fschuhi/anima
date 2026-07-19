//
//  JumpStackTests.swift
//  AnimaTests
//
//  Pure in-memory tests for JumpStack, transcribed from the traces in
//  docs/JUMPSTACK_DESIGN.md section 4. Each trace covers at least one rule no
//  other trace covers; the coverage note on each test says which.
//
//  No PDFView, no fixture PDF, no Python helper -- unlike AnimaTests.swift,
//  which exercises the Swift -> Python -> fitz boundary. JumpStack decides
//  where to go and nothing else, which is what keeps these tests this cheap.
//
//  Page numbers below are written as the design document writes them, as the
//  reader sees them. JumpStack stores 0-based indices; the tests do not
//  convert, because the type never interprets the numbers it is given.
//

import XCTest
@testable import Anima

final class JumpStackTests: XCTestCase {

    // MARK: - Helpers

    /// Builds the canonical [5, 40, 50, 60] stack of trace 1, pointer at the
    /// end, using nothing but the public recording operation. Several traces
    /// start from this state, and constructing it through real transitions
    /// keeps them honest: no test asserts against a state the type could not
    /// actually reach.
    private func canonicalChain() -> JumpStack {
        var stack = JumpStack()
        stack.recordFarJump(from: 5, to: 40)
        stack.recordFarJump(from: 40, to: 50)
        stack.recordFarJump(from: 50, to: 60)
        return stack
    }

    /// Asserts the whole observable state in one call, so a failure reports
    /// both halves rather than only whichever assertion ran first.
    private func assertState(
        _ stack: JumpStack,
        entries: [Int],
        pointer: Int?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(stack.entries, entries, "entries", file: file, line: line)
        XCTAssertEqual(stack.pointer, pointer, "pointer", file: file, line: line)
    }

    // MARK: - Trace 1: canonical chain from empty

    /// Covers: seeding an empty stack, the double push, the origin decline in
    /// the steady state.
    func testTrace1CanonicalChainFromEmpty() {
        var stack = JumpStack()
        assertState(stack, entries: [], pointer: nil)
        XCTAssertTrue(stack.isEmpty)

        // goto 40 from page 5: push 5, push 40.
        stack.recordFarJump(from: 5, to: 40)
        assertState(stack, entries: [5, 40], pointer: 1)

        // find 50 from page 40: decline 40, push 50.
        stack.recordFarJump(from: 40, to: 50)
        assertState(stack, entries: [5, 40, 50], pointer: 2)

        // F3 to 60 from page 50: decline 50, push 60.
        stack.recordFarJump(from: 50, to: 60)
        assertState(stack, entries: [5, 40, 50, 60], pointer: 3)
        XCTAssertFalse(stack.isEmpty)
    }

    // MARK: - Trace 2: walk to both ends

    /// Covers: move-then-jump in both directions, both beeps, and the fact
    /// that the most recent jump target (60) is reachable going forward.
    func testTrace2WalkToBothEnds() {
        var stack = canonicalChain()

        XCTAssertEqual(stack.back(), 50)
        assertState(stack, entries: [5, 40, 50, 60], pointer: 2)

        XCTAssertEqual(stack.back(), 40)
        assertState(stack, entries: [5, 40, 50, 60], pointer: 1)

        XCTAssertEqual(stack.back(), 5)
        assertState(stack, entries: [5, 40, 50, 60], pointer: 0)

        // Bottom of the stack: beep, and nothing moves.
        XCTAssertNil(stack.back())
        assertState(stack, entries: [5, 40, 50, 60], pointer: 0)

        XCTAssertEqual(stack.forward(), 40)
        XCTAssertEqual(stack.forward(), 50)
        XCTAssertEqual(stack.forward(), 60)
        assertState(stack, entries: [5, 40, 50, 60], pointer: 3)

        // Top of the stack: beep, and nothing moves.
        XCTAssertNil(stack.forward())
        assertState(stack, entries: [5, 40, 50, 60], pointer: 3)
    }

    // MARK: - Trace 3: scroll, then far-jump

    /// Covers: the origin being read from the reader rather than from the
    /// pointer, and the extra stop this produces.
    func testTrace3ScrollThenFarJump() {
        var stack = JumpStack()
        stack.recordFarJump(from: 5, to: 40)
        stack.recordFarJump(from: 40, to: 50)
        assertState(stack, entries: [5, 40, 50], pointer: 2)

        // The reader scrolls from 50 to 55, which records nothing, and then
        // an F3 hit lands on 60. The origin 55 differs from the last entry.
        stack.recordFarJump(from: 55, to: 60)
        assertState(stack, entries: [5, 40, 50, 55, 60], pointer: 4)

        // Walking back stops at both 55, where reading actually happened,
        // and 50, the find target.
        XCTAssertEqual(stack.back(), 55)
        XCTAssertEqual(stack.back(), 50)
    }

    // MARK: - Trace 4: far jump whose target is the current page

    /// Covers: both pushes declining, and page-local movement collapsing to a
    /// single stop.
    func testTrace4JumpToCurrentPage() {
        var stack = JumpStack()
        stack.recordFarJump(from: 5, to: 40)
        stack.recordFarJump(from: 40, to: 50)
        assertState(stack, entries: [5, 40, 50], pointer: 2)

        // Another hit on page 50: decline the origin, decline the target.
        stack.recordFarJump(from: 50, to: 50)
        assertState(stack, entries: [5, 40, 50], pointer: 2)

        XCTAssertEqual(stack.back(), 40)
    }

    // MARK: - Trace 5: back, then a new far jump

    /// Covers: dropping the forward history. This rule fires in no other
    /// trace.
    func testTrace5BackThenNewFarJump() {
        var stack = canonicalChain()

        XCTAssertEqual(stack.back(), 50)
        XCTAssertEqual(stack.back(), 40)
        assertState(stack, entries: [5, 40, 50, 60], pointer: 1)

        // goto 90 from the rewound position: drop 50 and 60, decline the
        // origin 40, push 90.
        stack.recordFarJump(from: 40, to: 90)
        assertState(stack, entries: [5, 40, 90], pointer: 2)

        XCTAssertEqual(stack.back(), 40)
        XCTAssertEqual(stack.back(), 5)
        XCTAssertNil(stack.back())
        assertState(stack, entries: [5, 40, 90], pointer: 0)
    }

    /// Composed with trace 3: had the reader scrolled from 40 to 42 before
    /// the goto, the origin push would not have declined. Same rule, no
    /// special case.
    func testTrace5ComposedWithScrolledOrigin() {
        var stack = canonicalChain()

        _ = stack.back()
        _ = stack.back()
        stack.recordFarJump(from: 42, to: 90)

        assertState(stack, entries: [5, 40, 42, 90], pointer: 3)
    }

    // MARK: - Trace 6: document change

    /// Not a trace in the design document. Loading a different PDF empties
    /// the entries and returns the pointer to its undefined state; both keys
    /// beep until the first far jump in the new document.
    func testTrace6DocumentChangeClearsHistory() {
        var stack = canonicalChain()

        stack.clear()

        assertState(stack, entries: [], pointer: nil)
        XCTAssertTrue(stack.isEmpty)
        XCTAssertNil(stack.back())
        XCTAssertNil(stack.forward())
    }

    // MARK: - Acceptance (d): empty stack

    /// Fresh launch, before any far jump: both keys beep rather than
    /// silently doing nothing. This overrides the earlier acceptance wording
    /// in TARGET_ARCHITECTURE.md, which specified a silent no-op.
    func testEmptyStackBeepsInBothDirections() {
        var stack = JumpStack()

        XCTAssertNil(stack.back())
        XCTAssertNil(stack.forward())
        assertState(stack, entries: [], pointer: nil)
    }
}
