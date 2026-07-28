//
//  OpenDialogKeyTranslatorTests.swift
//  AnimaTests
//
//  Synthesizes NSEvent instances directly rather than simulating real
//  keyboard input -- NSEvent's keyEvent(with:...) constructor lets tests
//  set keyCode, characters, and modifierFlags independently, which is all
//  the translator reads.
//

import XCTest
@testable import Anima

final class OpenDialogKeyTranslatorTests: XCTestCase {

    private func keyEvent(
        keyCode: UInt16,
        characters: String = "",
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    // MARK: - Printable characters

    func testPlainLetterTranslatesToCharacter() {
        let event = keyEvent(keyCode: 0, characters: "a")
        XCTAssertEqual(OpenDialogKeyTranslator.translate(event), .character("a"))
    }

    func testShiftedLetterUsesUppercase() {
        let event = keyEvent(keyCode: 0, characters: "A", modifiers: .shift)
        XCTAssertEqual(OpenDialogKeyTranslator.translate(event), .character("A"))
    }

    func testDigitTranslatesToCharacter() {
        let event = keyEvent(keyCode: 18, characters: "1")
        XCTAssertEqual(OpenDialogKeyTranslator.translate(event), .character("1"))
    }

    // MARK: - Blocking modifiers

    func testCommandModifierIsNotConsumed() {
        let event = keyEvent(keyCode: 13, characters: "w", modifiers: .command)
        XCTAssertNil(OpenDialogKeyTranslator.translate(event))
    }

    func testControlModifierIsNotConsumed() {
        let event = keyEvent(keyCode: 0, characters: "a", modifiers: .control)
        XCTAssertNil(OpenDialogKeyTranslator.translate(event))
    }

    func testOptionModifierIsNotConsumed() {
        let event = keyEvent(keyCode: 0, characters: "a", modifiers: .option)
        XCTAssertNil(OpenDialogKeyTranslator.translate(event))
    }

    // MARK: - Named keys

    func testBackspaceKeyCode() {
        let event = keyEvent(keyCode: 51, characters: "\u{7F}")
        XCTAssertEqual(OpenDialogKeyTranslator.translate(event), .backspace)
    }

    func testUpArrowKeyCode() {
        let event = keyEvent(keyCode: 126, characters: "\u{F700}")
        XCTAssertEqual(OpenDialogKeyTranslator.translate(event), .up)
    }

    func testDownArrowKeyCode() {
        let event = keyEvent(keyCode: 125, characters: "\u{F701}")
        XCTAssertEqual(OpenDialogKeyTranslator.translate(event), .down)
    }

    func testEnterKeyCode() {
        let event = keyEvent(keyCode: 36, characters: "\r")
        XCTAssertEqual(OpenDialogKeyTranslator.translate(event), .enter)
    }

    func testNumericKeypadEnterKeyCode() {
        let event = keyEvent(keyCode: 76, characters: "\r")
        XCTAssertEqual(OpenDialogKeyTranslator.translate(event), .enter)
    }

    func testEscapeKeyCode() {
        let event = keyEvent(keyCode: 53, characters: "\u{1B}")
        XCTAssertEqual(OpenDialogKeyTranslator.translate(event), .escape)
    }

    // MARK: - Excluded non-printables

    func testTabIsNotConsumed() {
        let event = keyEvent(keyCode: 48, characters: "\t")
        XCTAssertNil(OpenDialogKeyTranslator.translate(event))
    }

    func testFunctionKeyIsNotConsumed() {
        // F1, unrelated to any keyCode branch above -- carries a private-use
        // Unicode value in charactersIgnoringModifiers.
        let event = keyEvent(keyCode: 122, characters: "\u{F704}")
        XCTAssertNil(OpenDialogKeyTranslator.translate(event))
    }
}
