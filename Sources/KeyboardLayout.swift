import Cocoa
import Carbon.HIToolbox

/// Disposition de clavier : indique quel caractère tape une touche, et quelle touche tape un caractère.
struct KeyboardLayout {
    struct KeyStroke: Equatable {
        let keyCode: CGKeyCode
        let shift: Bool
    }

    private static let keypadKeyCodes: ClosedRange<UInt16> = 65...92

    private let data: Data
    private let keyboardType: UInt32

    /// Disposition active au moment de l'appel.
    static func current() -> KeyboardLayout? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
        return KeyboardLayout(source: source)
    }

    init?(source: TISInputSource) {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        keyboardType = UInt32(LMGetKbdType())
    }

    /// Caractère tapé par une touche, ou `nil` si elle ne tape pas exactement un caractère.
    func character(keyCode: CGKeyCode, shift: Bool = false, option: Bool = false) -> UniChar? {
        var modifiers = 0
        if shift { modifiers |= shiftKey }
        if option { modifiers |= optionKey }
        let modifierState = UInt32(modifiers >> 8) & 0xFF

        return data.withUnsafeBytes { raw -> UniChar? in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
            var deadKeyState: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDown), modifierState, keyboardType,
                OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState, chars.count, &length, &chars
            )
            return status == noErr && length == 1 ? chars[0] : nil
        }
    }

    /// Touche du clavier principal qui tape ce caractère, en préférant celle qui n'exige pas Majuscule.
    func keyStroke(for char: UniChar) -> KeyStroke? {
        for shift in [false, true] {
            for keyCode in UInt16(0)..<128 where !Self.keypadKeyCodes.contains(keyCode) {
                if character(keyCode: keyCode, shift: shift) == char {
                    return KeyStroke(keyCode: keyCode, shift: shift)
                }
            }
        }
        return nil
    }
}
