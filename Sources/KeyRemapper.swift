import Cocoa
import Carbon.HIToolbox

/// Intercepte la touche décimale du pavé numérique et inverse virgule ⇄ point.
final class KeyRemapper {
    private struct KeyStroke {
        let keyCode: CGKeyCode
        let shift: Bool
    }

    private static let comma = UniChar(0x2C)
    private static let period = UniChar(0x2E)
    private static let keypadDecimal = Int64(kVK_ANSI_KeypadDecimal)
    private static let keypadKeyCodes: ClosedRange<UInt16> = 65...92

    var isEnabled = true

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var strokes: [UniChar: KeyStroke]?
    private var lastTarget: UniChar?
    private var layoutObserver: NSObjectProtocol?

    var isRunning: Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    init() {
        // La touche qui produit « , » ou « . » dépend de la disposition du clavier.
        layoutObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.strokes = nil
        }
    }

    deinit {
        stop()
        if let layoutObserver {
            DistributedNotificationCenter.default().removeObserver(layoutObserver)
        }
    }

    /// Retourne `false` si macOS refuse la création de l'intercepteur (autorisation manquante).
    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }

        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: keyRemapperCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        tap = newTap
        runLoopSource = source
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CFMachPortInvalidate(tap)
        self.tap = nil
        runLoopSource = nil
    }

    fileprivate func reenable() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    /// Modifie l'événement sur place si c'est la touche décimale du pavé numérique.
    func transform(_ event: CGEvent, type: CGEventType) {
        guard isEnabled, type == .keyDown || type == .keyUp else { return }
        guard event.getIntegerValueField(.keyboardEventKeycode) == Self.keypadDecimal else { return }

        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)

        let target: UniChar
        if length == 1, chars[0] == Self.comma {
            target = Self.period
        } else if length == 1, chars[0] == Self.period {
            target = Self.comma
        } else if type == .keyUp, length == 0, let lastTarget {
            // Relâchement sans caractère : on reprend la conversion de l'appui.
            target = lastTarget
        } else {
            return
        }
        lastTarget = type == .keyDown ? target : nil

        // Certaines apps (Excel, entre autres) ignorent le caractère et se fient au
        // code de touche : on envoie donc la vraie touche « . » ou « , » du clavier.
        if let stroke = keyStroke(for: target) {
            event.setIntegerValueField(.keyboardEventKeycode, value: Int64(stroke.keyCode))
            var flags = event.flags
            flags.remove([.maskNumericPad, .maskShift, .maskAlternate])
            if stroke.shift {
                flags.insert(.maskShift)
            }
            event.flags = flags
        }
        var char = target
        event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &char)
    }

    private func keyStroke(for char: UniChar) -> KeyStroke? {
        if strokes == nil {
            strokes = Self.findStrokes()
        }
        return strokes?[char]
    }

    /// Cherche, dans la disposition de clavier active, les touches qui tapent « , » et « . ».
    private static func findStrokes() -> [UniChar: KeyStroke] {
        var found: [UniChar: KeyStroke] = [:]
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return found
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        let keyboardType = UInt32(LMGetKbdType())

        layoutData.withUnsafeBytes { raw in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return }
            // Sans majuscule d'abord, pour préférer la touche directe.
            for shift in [false, true] {
                let modifiers = shift ? UInt32(shiftKey >> 8) & 0xFF : 0
                for keyCode in UInt16(0)..<128 where !keypadKeyCodes.contains(keyCode) {
                    var deadKeyState: UInt32 = 0
                    var length = 0
                    var chars = [UniChar](repeating: 0, count: 4)
                    let status = UCKeyTranslate(
                        layout, keyCode, UInt16(kUCKeyActionDown), modifiers, keyboardType,
                        OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState, 4, &length, &chars
                    )
                    guard status == noErr, length == 1 else { continue }
                    let char = chars[0]
                    if (char == comma || char == period), found[char] == nil {
                        found[char] = KeyStroke(keyCode: keyCode, shift: shift)
                    }
                }
            }
        }
        return found
    }
}

private func keyRemapperCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let remapper = Unmanaged<KeyRemapper>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        remapper.reenable()
    } else {
        remapper.transform(event, type: type)
    }
    return Unmanaged.passUnretained(event)
}
