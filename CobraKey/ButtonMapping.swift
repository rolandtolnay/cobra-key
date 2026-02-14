import Cocoa

struct ButtonMapping: Codable, Equatable {
    let id: UUID
    var mouseButton: Int        // CGEvent button number
    var keyCode: UInt16         // Virtual key code (CGKeyCode)
    var modifierFlags: UInt64   // CGEventFlags.rawValue

    var displayTitle: String {
        let mouseLabel = "Button \(mouseButton)"
        let keyName = Self.keyName(for: keyCode)
        let modString = Self.modifierString(for: CGEventFlags(rawValue: modifierFlags))
        let shortcut = modString.isEmpty ? keyName : "\(modString)+\(keyName)"
        return "\(mouseLabel) \u{2192} \(shortcut)"
    }

    // MARK: - Modifier String

    static func modifierString(for flags: CGEventFlags) -> String {
        var parts: [String] = []
        if flags.contains(.maskControl) { parts.append("Ctrl") }
        if flags.contains(.maskAlternate) { parts.append("Opt") }
        if flags.contains(.maskShift) { parts.append("Shift") }
        if flags.contains(.maskCommand) { parts.append("Cmd") }
        return parts.joined(separator: "+")
    }

    // MARK: - Key Name Lookup

    static func keyName(for keyCode: UInt16) -> String {
        keyNames[keyCode] ?? "Key\(keyCode)"
    }

    private static let keyNames: [UInt16: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F",
        0x04: "H", 0x05: "G", 0x06: "Z", 0x07: "X",
        0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q",
        0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y",
        0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
        0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=",
        0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8",
        0x1D: "0", 0x1E: "]", 0x1F: "O", 0x20: "U",
        0x21: "[", 0x22: "I", 0x23: "P", 0x25: "L",
        0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";",
        0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N",
        0x2E: "M", 0x2F: ".",
        // Function keys
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4",
        0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
        0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
        0x69: "F13", 0x6B: "F14", 0x71: "F15",
        // Special keys
        0x24: "Return", 0x30: "Tab", 0x31: "Space",
        0x33: "Delete", 0x35: "Escape", 0x75: "ForwardDelete",
        0x7E: "Up", 0x7D: "Down", 0x7B: "Left", 0x7C: "Right",
        0x73: "Home", 0x77: "End", 0x74: "PageUp", 0x79: "PageDown",
        0x32: "`",
    ]
}

// MARK: - CGEventFlags from NSEvent.ModifierFlags

extension CGEventFlags {
    init(cocoaFlags: NSEvent.ModifierFlags) {
        var flags = CGEventFlags()
        if cocoaFlags.contains(.control) { flags.insert(.maskControl) }
        if cocoaFlags.contains(.option) { flags.insert(.maskAlternate) }
        if cocoaFlags.contains(.shift) { flags.insert(.maskShift) }
        if cocoaFlags.contains(.command) { flags.insert(.maskCommand) }
        self = flags
    }
}
