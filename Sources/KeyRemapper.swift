import Cocoa
import Carbon.HIToolbox

/// Intercepte la touche décimale du pavé numérique et inverse virgule ⇄ point.
final class KeyRemapper {
    private struct Conversion {
        let target: UniChar
        let stroke: KeyboardLayout.KeyStroke?
    }

    /// Ce qui a été décidé à l'appui, pour traiter le relâchement de la même façon.
    private enum Decision {
        case convert(Conversion)
        case leave

        var conversion: Conversion? {
            if case .convert(let conversion) = self { return conversion }
            return nil
        }
    }

    private static let comma = UniChar(0x2C)
    private static let period = UniChar(0x2E)
    private static let keypadDecimal = CGKeyCode(kVK_ANSI_KeypadDecimal)

    var isEnabled = true

    /// Remplaçable dans les tests pour vérifier d'autres dispositions que celle du Mac.
    var layoutProvider: () -> KeyboardLayout? = KeyboardLayout.current

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyDownDecision: Decision?

    var isRunning: Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    deinit {
        stop()
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
        guard type == .keyDown || type == .keyUp else { return }
        guard event.getIntegerValueField(.keyboardEventKeycode) == Int64(Self.keypadDecimal) else { return }

        let isRepeat = type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let decision: Decision
        if type == .keyUp || isRepeat, let keyDownDecision {
            // Les répétitions et le relâchement suivent l'appui, même si un modificateur
            // a changé entre-temps : sinon l'app verrait une touche jamais relâchée.
            decision = keyDownDecision
        } else if isEnabled, let conversion = makeConversion(for: event) {
            decision = .convert(conversion)
        } else {
            decision = .leave
        }
        keyDownDecision = type == .keyDown ? decision : nil
        guard let conversion = decision.conversion else { return }

        // Certaines apps (Excel, entre autres) ignorent le caractère et se fient au
        // code de touche : on envoie donc la vraie touche « . » ou « , » du clavier.
        if let stroke = conversion.stroke {
            event.setIntegerValueField(.keyboardEventKeycode, value: Int64(stroke.keyCode))
            var flags = event.flags
            flags.remove([.maskNumericPad, .maskShift, .maskAlternate, .maskAlphaShift])
            if stroke.shift {
                flags.insert(.maskShift)
            }
            event.flags = flags
        }
        var char = conversion.target
        event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &char)
    }

    private func makeConversion(for event: CGEvent) -> Conversion? {
        let layout = layoutProvider()
        let target: UniChar
        switch nativeCharacter(of: event, in: layout) {
        case Self.comma: target = Self.period
        case Self.period: target = Self.comma
        default: return nil
        }
        return Conversion(target: target, stroke: layout?.keyStroke(for: target))
    }

    /// Caractère que la touche taperait sans PointVirgule. Verr. Maj est ignoré exprès :
    /// certaines dispositions (Canadien – CSA) y changent la virgule en point, ce qui
    /// inverserait le résultat selon l'état de Verr. Maj.
    private func nativeCharacter(of event: CGEvent, in layout: KeyboardLayout?) -> UniChar? {
        if let layout {
            let flags = event.flags
            return layout.character(
                keyCode: Self.keypadDecimal,
                shift: flags.contains(.maskShift),
                option: flags.contains(.maskAlternate)
            )
        }
        // Disposition illisible : on se fie au caractère porté par l'événement.
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: chars.count, actualStringLength: &length, unicodeString: &chars)
        return length == 1 ? chars[0] : nil
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
