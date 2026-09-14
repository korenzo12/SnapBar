import AppKit
import Carbon.HIToolbox
import XCTest
@testable import SnapBar

final class KeyComboTests: XCTestCase {
    private func event(_ code: Int, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                         context: nil, characters: "s", charactersIgnoringModifiers: "s", isARepeat: false,
                         keyCode: UInt16(code))!
    }

    func testDefaultCaptureShortcutIsShiftCommandS() {
        XCTAssertEqual(KeyCombo.defaultCaptureArea.displayString, "⇧⌘S")
        XCTAssertFalse(KeyCombo.defaultCaptureArea.isReserved)
        XCTAssertEqual(KeyCombo.defaultLibrary.displayString, "⌃⇧V")
    }

    func testSystemCombosAreRejected() {
        XCTAssertTrue(KeyCombo(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(cmdKey | shiftKey)).isReserved)
        XCTAssertTrue(KeyCombo(keyCode: UInt32(kVK_ANSI_3), modifiers: UInt32(cmdKey | shiftKey)).isReserved)
        XCTAssertTrue(KeyCombo(keyCode: UInt32(kVK_ANSI_Q), modifiers: UInt32(cmdKey)).isReserved)
        XCTAssertTrue(KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey)).isReserved)
    }

    func testPlainLetterIsNotAShortcut() {
        XCTAssertNil(KeyCombo(event: event(kVK_ANSI_S, [])))
        XCTAssertNil(KeyCombo(event: event(kVK_ANSI_S, [.shift])))
    }

    func testModifiedLetterBecomesCombo() {
        XCTAssertEqual(KeyCombo(event: event(kVK_ANSI_S, [.command, .shift])), KeyCombo.defaultCaptureArea)
    }

    func testFunctionKeyAloneIsAllowed() {
        let combo = KeyCombo(event: event(kVK_F5, []))
        XCTAssertNotNil(combo)
        XCTAssertEqual(combo?.displayString, "F5")
    }

    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(KeyCombo.defaultCaptureArea)
        XCTAssertEqual(try JSONDecoder().decode(KeyCombo.self, from: data), .defaultCaptureArea)
    }
}
