//
//  OpenDialogKeyTranslator.swift
//  Anima
//
//  Translates a raw NSEvent into an OpenDialogKey, or nil if the event is
//  not the open dialog's to handle. The one rule: an event counts as ours
//  only when no Command, Control, or Option modifier is held (Shift is
//  fine -- it's how uppercase letters and shifted punctuation arrive).
//  Anything carrying one of those three falls through untouched, so
//  Cmd+W, Cmd+Q, and similar app-level shortcuts keep working normally
//  while the dialog is open.
//

import Cocoa

enum OpenDialogKeyTranslator {

    private static let blockingModifiers: NSEvent.ModifierFlags = [.command, .control, .option]

    /// Unicode values AppKit uses for function keys (arrows, F-keys, Home,
    /// Page Up/Down, etc.) when they arrive via charactersIgnoringModifiers.
    /// Arrow keys are already handled by keyCode below; this range excludes
    /// the rest so they don't fall through into ".character".
    private static let functionKeyRange: ClosedRange<UInt32> = 0xF700...0xF8FF

    static func translate(_ event: NSEvent) -> OpenDialogKey? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.isDisjoint(with: blockingModifiers) else {
            return nil
        }

        switch event.keyCode {
        case 51:
            return .backspace
        case 126:
            return .up
        case 125:
            return .down
        case 36, 76:
            return .enter
        case 53:
            return .escape
        default:
            guard let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first,
                  !CharacterSet.controlCharacters.contains(scalar),
                  !functionKeyRange.contains(scalar.value) else {
                return nil
            }
            return .character(Character(scalar))
        }
    }
}
