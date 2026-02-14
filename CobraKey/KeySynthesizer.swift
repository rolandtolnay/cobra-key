import Cocoa
import Carbon.HIToolbox

enum KeySynthesizer {

    private static let fallbackCodeO: CGKeyCode = CGKeyCode(kVK_ANSI_O)
    private static let fallbackCodeE: CGKeyCode = CGKeyCode(kVK_ANSI_E)

    static func postCtrlO() {
        postControlCharacter("o", fallbackKeyCode: fallbackCodeO)
    }

    static func postCtrlE() {
        postControlCharacter("e", fallbackKeyCode: fallbackCodeE)
    }

    static func postKeystroke(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            print("[KeySynthesizer] Failed to create CGEvent")
            return
        }

        keyDown.flags = flags
        keyUp.flags = flags

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private static func postControlCharacter(_ character: String, fallbackKeyCode: CGKeyCode) {
        let keyCode = keyCodeForCurrentLayout(character) ?? fallbackKeyCode
        postKeystroke(keyCode: keyCode, flags: .maskControl)
    }

    private static func keyCodeForCurrentLayout(_ character: String) -> CGKeyCode? {
        guard
            let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let layoutDataPtr = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData)
        else {
            return nil
        }

        let layoutData = unsafeBitCast(layoutDataPtr, to: CFData.self)
        guard let keyboardLayoutBytes = CFDataGetBytePtr(layoutData) else {
            return nil
        }
        let keyboardLayout = UnsafePointer<UCKeyboardLayout>(OpaquePointer(keyboardLayoutBytes))

        let target = character.lowercased()
        for keyCode in 0..<128 {
            var deadKeyState: UInt32 = 0
            let maxLength = 4
            var actualLength = 0
            var chars = [UniChar](repeating: 0, count: maxLength)

            let status = UCKeyTranslate(
                keyboardLayout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDown),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                maxLength,
                &actualLength,
                &chars
            )

            guard status == noErr, actualLength > 0 else {
                continue
            }

            let resolved = String(utf16CodeUnits: chars, count: actualLength).lowercased()
            if resolved == target {
                return CGKeyCode(keyCode)
            }
        }

        return nil
    }
}
