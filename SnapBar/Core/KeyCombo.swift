import AppKit
import Carbon.HIToolbox

/// A global shortcut in Carbon terms: virtual key code plus Carbon modifier mask.
struct KeyCombo: Codable, Equatable, Hashable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Builds a combo from a key-down event. Needs ⌘, ⌃ or ⌥ unless it is a function key.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let combo = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: KeyCombo.carbonModifiers(from: flags))
        guard combo.isValidShortcut else { return nil }
        self = combo
    }

    static let defaultCaptureArea = KeyCombo(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey | shiftKey))
    static let defaultLibrary = KeyCombo(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | shiftKey))

    var hasCommand: Bool { modifiers & UInt32(cmdKey) != 0 }
    var hasShift: Bool { modifiers & UInt32(shiftKey) != 0 }
    var hasOption: Bool { modifiers & UInt32(optionKey) != 0 }
    var hasControl: Bool { modifiers & UInt32(controlKey) != 0 }

    var isFunctionKey: Bool { KeyCombo.functionKeys.contains(keyCode) }
    var isValidShortcut: Bool { isFunctionKey || hasCommand || hasControl || hasOption }
    var isReserved: Bool { KeyCombo.reserved.contains(self) }

    /// Apple's glyph order: ⌃ ⌥ ⇧ ⌘, then the key.
    var displayString: String {
        var s = ""
        if hasControl { s += "⌃" }
        if hasOption { s += "⌥" }
        if hasShift { s += "⇧" }
        if hasCommand { s += "⌘" }
        return s + KeyCombo.keyName(for: keyCode)
    }

    var eventModifierFlags: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if hasCommand { f.insert(.command) }
        if hasShift { f.insert(.shift) }
        if hasOption { f.insert(.option) }
        if hasControl { f.insert(.control) }
        return f
    }

    /// Key equivalent for NSMenuItem display. Empty for keys a menu cannot show.
    var menuKeyEquivalent: String {
        let name = KeyCombo.keyName(for: keyCode)
        return name.count == 1 ? name.lowercased() : ""
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    static func keyName(for code: UInt32) -> String {
        names[Int(code)] ?? "#\(code)"
    }

    private static func k(_ code: Int, _ mods: Int) -> KeyCombo {
        KeyCombo(keyCode: UInt32(code), modifiers: UInt32(mods))
    }

    /// Combos macOS or nearly every app already owns. Registering one would break something.
    static let reserved: Set<KeyCombo> = [
        k(kVK_ANSI_3, cmdKey | shiftKey), k(kVK_ANSI_4, cmdKey | shiftKey),
        k(kVK_ANSI_5, cmdKey | shiftKey), k(kVK_ANSI_6, cmdKey | shiftKey),
        k(kVK_ANSI_3, cmdKey | shiftKey | controlKey), k(kVK_ANSI_4, cmdKey | shiftKey | controlKey),
        k(kVK_Space, cmdKey), k(kVK_Space, controlKey), k(kVK_Tab, cmdKey), k(kVK_ANSI_Grave, cmdKey),
        k(kVK_ANSI_Q, cmdKey), k(kVK_ANSI_W, cmdKey), k(kVK_ANSI_H, cmdKey), k(kVK_ANSI_M, cmdKey),
        k(kVK_ANSI_C, cmdKey), k(kVK_ANSI_V, cmdKey), k(kVK_ANSI_X, cmdKey), k(kVK_ANSI_Z, cmdKey),
        k(kVK_ANSI_A, cmdKey), k(kVK_ANSI_S, cmdKey), k(kVK_ANSI_N, cmdKey), k(kVK_ANSI_O, cmdKey),
        k(kVK_ANSI_P, cmdKey), k(kVK_ANSI_F, cmdKey), k(kVK_ANSI_T, cmdKey), k(kVK_ANSI_Comma, cmdKey),
        k(kVK_Escape, cmdKey | optionKey), k(kVK_ANSI_Q, cmdKey | controlKey),
        k(kVK_ANSI_Q, cmdKey | shiftKey), k(kVK_ANSI_F, cmdKey | controlKey),
    ]

    static let functionKeys: Set<UInt32> = Set([
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ].map { UInt32($0) })

    private static let names: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
        kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
        kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
        kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
        kVK_ANSI_Z: "Z", kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8",
        kVK_ANSI_9: "9", kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[",
        kVK_ANSI_RightBracket: "]", kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",",
        kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/", kVK_ANSI_Backslash: "\\", kVK_ANSI_Grave: "`",
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]
}
