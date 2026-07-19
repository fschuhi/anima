//
//  JumpStack.swift
//  Anima
//
//  Far-jump history for Cmd+E (back) and Cmd+R (forward).
//  Specified in docs/JUMPSTACK_DESIGN.md; this file implements its
//  sections 2 and 3, and its section 4 traces are the unit tests in
//  JumpStackTests.swift.
//
//  Deliberately knows nothing about PDFView, PDFPage, or NSSound. It stores
//  0-based page indices and decides where the reader should go; the caller
//  performs the navigation and beeps when there is nowhere to go. That is
//  what makes the design document's traces directly transcribable into unit
//  tests without a fixture PDF.
//
//  In-memory only, and cleared on document change (see clear()), so every
//  stored entry addresses a page in the currently loaded document and no
//  range validation is needed at navigation time.
//

import Foundation

struct JumpStack {

    /// Page indices, oldest first, 0-based. Unbounded: each entry is one Int,
    /// and the earlier cap of five was bookkeeping for an abandoned
    /// persistence design.
    private(set) var entries: [Int] = []

    /// Index into `entries` identifying the entry the reader currently
    /// occupies. nil exactly when `entries` is empty.
    ///
    /// Optional rather than a -1 sentinel so the empty case is enforced by
    /// the compiler instead of by convention: `entries[pointer]` cannot be
    /// written without first opening the optional.
    private(set) var pointer: Int?

    /// Invariant: `entries[pointer]` is the page the reader arrived at
    /// through the most recent recorded event. The reader may have scrolled
    /// away since -- ordinary scrolling is never recorded -- and that
    /// divergence is handled in recordFarJump, which reads the origin from
    /// the reader rather than from this invariant.

    /// True when there is nothing recorded yet. Both keys beep in this state.
    var isEmpty: Bool {
        entries.isEmpty
    }

    /// Records one far jump: where it departed from and where it arrives.
    ///
    /// - Parameters:
    ///   - origin: the page the reader is on right now, read from the reader
    ///             rather than from the pointer.
    ///   - target: the page the jump lands on.
    ///
    /// Four steps, per the design document's section 3:
    ///   1. Drop every entry above the pointer -- a new jump invalidates the
    ///      forward history.
    ///   2. Push the origin, unless it already equals the last entry.
    ///   3. Push the target, unless it already equals the last entry.
    ///   4. Point at the last entry.
    ///
    /// Because step 1 runs first, the entry under the pointer is always the
    /// last entry by the time steps 2 and 3 run. The decline rule is
    /// therefore a plain comparison against the last entry and needs no
    /// pointer arithmetic.
    ///
    /// In the steady state the origin equals the last entry -- the reader is
    /// standing where the previous jump left it -- so step 2 declines and the
    /// pointer advances by exactly one. The two diverge precisely when the
    /// reader scrolled away after arriving, which is precisely when that
    /// position deserves its own stop. Pushing the target is what makes the
    /// most recent jump reachable by Cmd+R; recording origins alone would
    /// leave it permanently out of reach.
    mutating func recordFarJump(from origin: Int, to target: Int) {
        if let pointer = pointer, pointer + 1 < entries.count {
            entries.removeSubrange((pointer + 1)...)
        }

        append(declineIfLast: origin)
        append(declineIfLast: target)

        pointer = entries.count - 1
    }

    /// Cmd+E. Moves the pointer back one entry and returns the page to
    /// navigate to, or nil when there is nothing behind the reader.
    ///
    /// Move-then-jump, in that order: the alternative -- peek, jump, then
    /// decrement -- leaves the pointer one behind the reader, and the first
    /// press in the opposite direction then navigates to the page the reader
    /// is already standing on. That convention was traced and rejected.
    ///
    /// Never modifies `entries`.
    mutating func back() -> Int? {
        guard let pointer = pointer, pointer > 0 else {
            return nil
        }

        let newPointer = pointer - 1
        self.pointer = newPointer
        return entries[newPointer]
    }

    /// Cmd+R. Moves the pointer forward one entry and returns the page to
    /// navigate to, or nil when there is nothing ahead of the reader.
    ///
    /// Move-then-jump, identically to back(). Never modifies `entries`.
    mutating func forward() -> Int? {
        guard let pointer = pointer, pointer + 1 < entries.count else {
            return nil
        }

        let newPointer = pointer + 1
        self.pointer = newPointer
        return entries[newPointer]
    }

    /// Empties the history on document change. Both keys beep afterwards
    /// until the first far jump in the new document.
    mutating func clear() {
        entries.removeAll()
        pointer = nil
    }

    /// The one push rule, applied twice by recordFarJump: decline if the page
    /// already equals the last entry. Several find hits on one page collapse
    /// to a single stop, which is the intended behavior rather than a
    /// tolerated artifact.
    private mutating func append(declineIfLast page: Int) {
        guard entries.last != page else {
            return
        }

        entries.append(page)
    }
}
