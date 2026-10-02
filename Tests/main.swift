// Vérifie la conversion de la touche décimale sans installer d'intercepteur, sur
// toutes les dispositions de clavier installées sur le Mac.
// Compilé avec Sources/KeyRemapper.swift et Sources/KeyboardLayout.swift par build.sh.
import Cocoa
import Carbon.HIToolbox

var checks = 0
var failures = 0

/// N'affiche que les échecs : il y a des milliers de vérifications.
func check(_ condition: Bool, _ message: @autoclosure () -> String) {
    checks += 1
    if !condition {
        failures += 1
        print("  ÉCHEC  \(message())")
    }
}

func makeEvent(keyCode: Int, keyDown: Bool, flags: CGEventFlags = [], character: Character? = nil) -> CGEvent {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: keyDown)!
    event.flags = flags
    if let character {
        var chars = Array(String(character).utf16)
        event.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
    }
    return event
}

func text(of event: CGEvent) -> String {
    var length = 0
    var chars = [UniChar](repeating: 0, count: 4)
    event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
    return String(utf16CodeUnits: chars, count: length)
}

func keyCode(of event: CGEvent) -> Int {
    Int(event.getIntegerValueField(.keyboardEventKeycode))
}

func identifier(of source: TISInputSource) -> String {
    Unmanaged<CFString>.fromOpaque(TISGetInputSourceProperty(source, kTISPropertyInputSourceID)).takeUnretainedValue() as String
}

/// Traduction indépendante du code testé : ce que la disposition tape pour une
/// touche et des modificateurs donnés, Verr. Maj compris.
func translate(_ source: TISInputSource, keyCode: Int, flags: CGEventFlags) -> String {
    let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)!
    let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
    var modifiers = 0
    if flags.contains(.maskShift) { modifiers |= shiftKey }
    if flags.contains(.maskAlphaShift) { modifiers |= alphaLock }
    if flags.contains(.maskAlternate) { modifiers |= optionKey }
    return data.withUnsafeBytes { raw in
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        UCKeyTranslate(
            raw.bindMemory(to: UCKeyboardLayout.self).baseAddress!, UInt16(keyCode),
            UInt16(kUCKeyActionDown), UInt32(modifiers >> 8) & 0xFF, UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState, 4, &length, &chars
        )
        return String(utf16CodeUnits: chars, count: length)
    }
}

/// Vrai si une touche du clavier principal tape ce caractère avec l'un de ces jeux de modificateurs.
func mainKeyboardCanType(_ character: String, in source: TISInputSource, with flagSets: [CGEventFlags] = [[], .maskShift]) -> Bool {
    for keyCode in 0..<128 where !(65...92).contains(keyCode) {
        for flags in flagSets where translate(source, keyCode: keyCode, flags: flags) == character {
            return true
        }
    }
    return false
}

func pressDecimal(_ remapper: KeyRemapper, flags: CGEventFlags, keyDown: Bool = true, isRepeat: Bool = false) -> CGEvent {
    let event = makeEvent(keyCode: kVK_ANSI_KeypadDecimal, keyDown: keyDown, flags: flags.union(.maskNumericPad))
    event.setIntegerValueField(.keyboardEventAutorepeat, value: isRepeat ? 1 : 0)
    remapper.transform(event, type: keyDown ? .keyDown : .keyUp)
    return event
}

let baseCases: [(name: String, flags: CGEventFlags)] = [
    ("sans modificateur", []),
    ("Majuscule", .maskShift),
    ("Option", .maskAlternate),
    ("Option + Majuscule", [.maskAlternate, .maskShift]),
    ("Commande", .maskCommand),
    ("Contrôle", .maskControl),
]
let unchanged = "inchangée"

/// Vérifie une disposition; retourne le résultat de chaque combinaison (caractère tapé ou « inchangée »).
func verify(_ source: TISInputSource, _ layout: KeyboardLayout) -> [String: String] {
    let id = identifier(of: source)
    let remapper = KeyRemapper()
    remapper.layoutProvider = { layout }
    var results: [String: String] = [:]

    for base in baseCases {
        for capsLock in [false, true] {
            let name = capsLock ? "Verr. Maj + \(base.name)" : base.name
            let flags = capsLock ? base.flags.union(.maskAlphaShift) : base.flags
            let label = "\(id), \(name)"
            let sentFlags = flags.union(.maskNumericPad)

            // Ce que la touche tape nativement, Verr. Maj mis de côté.
            let native = translate(source, keyCode: kVK_ANSI_KeypadDecimal, flags: base.flags)
            let expected = native == "," ? "." : native == "." ? "," : nil

            let event = pressDecimal(remapper, flags: flags)
            let release = pressDecimal(remapper, flags: [], keyDown: false)

            guard let expected else {
                // La touche ne tape ni virgule ni point : PointVirgule n'y touche pas.
                results[name] = unchanged
                check(keyCode(of: event) == kVK_ANSI_KeypadDecimal && event.flags == sentFlags, "\(label) : la touche devrait rester intacte")
                check(keyCode(of: release) == kVK_ANSI_KeypadDecimal, "\(label) : le relâchement devrait rester intact")
                continue
            }

            results[name] = text(of: event)
            check(text(of: event) == expected, "\(label) : natif « \(native) », attendu « \(expected) », obtenu « \(text(of: event)) »")
            check(keyCode(of: release) == keyCode(of: event) && text(of: release) == expected, "\(label) : le relâchement ne correspond pas à l'appui")

            if mainKeyboardCanType(expected, in: source) {
                check(release.flags.intersection([.maskNumericPad, .maskShift]) == event.flags.intersection(.maskShift), "\(label) : le relâchement devrait porter la même Majuscule que l'appui, sans l'indicateur de pavé numérique")
                if mainKeyboardCanType(expected, in: source, with: [[]]) {
                    check(!event.flags.contains(.maskShift), "\(label) : la touche sans Majuscule devrait être préférée")
                }
                check(!(65...92).contains(keyCode(of: event)), "\(label) : la touche envoyée (\(keyCode(of: event))) devrait être celle du clavier principal")
                check(event.flags.isDisjoint(with: [.maskNumericPad, .maskAlphaShift, .maskAlternate]), "\(label) : pavé numérique, Verr. Maj et Option devraient être retirés")
                check(event.flags.intersection([.maskCommand, .maskControl]) == flags.intersection([.maskCommand, .maskControl]), "\(label) : Commande et Contrôle devraient être conservées")
                let retranslated = translate(source, keyCode: keyCode(of: event), flags: event.flags)
                check(retranslated == expected, "\(label) : une app qui retraduit la touche obtient « \(retranslated) » au lieu de « \(expected) »")
            } else {
                // Aucune touche du clavier principal ne tape ce caractère : seul le caractère est remplacé.
                check(keyCode(of: event) == kVK_ANSI_KeypadDecimal && event.flags == sentFlags, "\(label) : la touche devrait garder son code et ses modificateurs")
            }
        }

        // La demande : Verr. Maj n'influence jamais la touche.
        let withCapsLock = results["Verr. Maj + \(base.name)"] ?? "?"
        check(withCapsLock == results[base.name], "\(id) : « Verr. Maj + \(base.name) » donne « \(withCapsLock) », mais « \(base.name) » donne « \(results[base.name] ?? "?") »")
    }
    return results
}

print("Dispositions de clavier installées")
let filter = [kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String] as CFDictionary
let sources = TISCreateInputSourceList(filter, true).takeRetainedValue() as! [TISInputSource]
var resultsByLayout: [String: [String: String]] = [:]
for source in sources {
    guard let layout = KeyboardLayout(source: source) else { continue }
    resultsByLayout[identifier(of: source)] = verify(source, layout)
}
print("  \(resultsByLayout.count) dispositions vérifiées")
check(resultsByLayout.count >= 3, "trop peu de dispositions vérifiées : \(resultsByLayout.count)")

// Résultats connus (sans modificateur, avec Majuscule), en plus des vérifications génériques.
let knownResults: [(id: String, plain: String, shifted: String)] = [
    ("com.apple.keylayout.Canadian-CSA", ".", ","),  // natif : « , », et « . » avec Majuscule ou Verr. Maj
    ("com.apple.keylayout.US", ",", ","),            // natif : toujours « . »
    ("com.apple.keylayout.French", ".", ","),        // natif : « , », et « . » avec Majuscule
]
for known in knownResults {
    guard let results = resultsByLayout[known.id] else {
        print("  \(known.id) : absente de ce Mac, ignorée")
        continue
    }
    for (name, expected) in [("sans modificateur", known.plain), ("Majuscule", known.shifted)] {
        check(results[name] == expected, "\(known.id), \(name) : attendu « \(expected) », obtenu « \(results[name] ?? "?") »")
        check(results["Verr. Maj + \(name)"] == expected, "\(known.id), Verr. Maj + \(name) : attendu « \(expected) », obtenu « \(results["Verr. Maj + \(name)"] ?? "?") »")
    }
}

print("Disposition active de ce Mac")
let remapper = KeyRemapper()
let plain = text(of: pressDecimal(remapper, flags: []))
let capsLock = text(of: pressDecimal(remapper, flags: .maskAlphaShift))
let shifted = text(of: pressDecimal(remapper, flags: .maskShift))
let capsLockShifted = text(of: pressDecimal(remapper, flags: [.maskAlphaShift, .maskShift]))
print("  touche décimale : « \(plain) »   avec Verr. Maj : « \(capsLock) »")
print("  avec Majuscule  : « \(shifted) »   avec Verr. Maj + Majuscule : « \(capsLockShifted) »")
check(plain == "," || plain == ".", "la touche décimale devrait être convertie")
check(plain == capsLock, "Verr. Maj ne devrait pas changer le résultat")
check(shifted == capsLockShifted, "Verr. Maj ne devrait pas changer le résultat avec Majuscule")

// La disposition lue par défaut doit être la bonne : mêmes résultats que ceux
// vérifiés plus haut pour cette disposition, et touche réellement remplacée.
let activeSource = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
let activeID = identifier(of: activeSource)
if let activeResults = resultsByLayout[activeID] {
    for (name, flags) in [("sans modificateur", CGEventFlags()), ("Majuscule", .maskShift), ("Verr. Maj + sans modificateur", .maskAlphaShift), ("Verr. Maj + Majuscule", [.maskAlphaShift, .maskShift])] {
        let event = pressDecimal(remapper, flags: flags)
        let expected = activeResults[name] ?? "?"
        check(text(of: event) == expected, "\(activeID), \(name) : attendu « \(expected) », obtenu « \(text(of: event)) »")
        if mainKeyboardCanType(expected, in: activeSource) {
            check(keyCode(of: event) != kVK_ANSI_KeypadDecimal, "\(activeID), \(name) : la touche devrait être remplacée par celle du clavier principal")
        }
    }
} else {
    check(false, "la disposition active (\(activeID)) devrait faire partie des dispositions vérifiées")
}

print("Disposition illisible (repli sur le caractère de l'événement)")
let fallbackRemapper = KeyRemapper()
fallbackRemapper.layoutProvider = { nil }
for (sent, expected) in [(Character(","), "."), (Character("."), ","), (Character("5"), "5")] {
    let event = makeEvent(keyCode: kVK_ANSI_KeypadDecimal, keyDown: true, flags: .maskNumericPad, character: sent)
    fallbackRemapper.transform(event, type: .keyDown)
    check(text(of: event) == expected, "« \(sent) » devrait donner « \(expected) », obtenu « \(text(of: event)) »")
    check(keyCode(of: event) == kVK_ANSI_KeypadDecimal && event.flags == .maskNumericPad, "« \(sent) » : la touche et ses modificateurs devraient rester tels quels")
}

print("Touches à ne pas modifier")
for flags in [CGEventFlags(), .maskAlphaShift, .maskShift] {
    let sentFlags = flags.union(.maskNumericPad)
    let digit = makeEvent(keyCode: kVK_ANSI_Keypad5, keyDown: true, flags: sentFlags)
    remapper.transform(digit, type: .keyDown)
    check(keyCode(of: digit) == kVK_ANSI_Keypad5 && text(of: digit) == "5" && digit.flags == sentFlags, "le 5 du pavé numérique devrait rester intact (modificateurs \(flags.rawValue))")
}
let mainPeriod = makeEvent(keyCode: kVK_ANSI_Period, keyDown: true, flags: .maskAlphaShift, character: ".")
remapper.transform(mainPeriod, type: .keyDown)
check(keyCode(of: mainPeriod) == kVK_ANSI_Period && text(of: mainPeriod) == "." && mainPeriod.flags == .maskAlphaShift, "le point du clavier principal devrait rester intact, Verr. Maj compris")
let mainComma = makeEvent(keyCode: kVK_ANSI_Comma, keyDown: true, character: ",")
remapper.transform(mainComma, type: .keyDown)
check(keyCode(of: mainComma) == kVK_ANSI_Comma && text(of: mainComma) == ",", "la virgule du clavier principal devrait rester intacte")

print("Inversion en pause")
remapper.isEnabled = false
let pausedFlags: CGEventFlags = [.maskNumericPad, .maskAlphaShift]
let paused = makeEvent(keyCode: kVK_ANSI_KeypadDecimal, keyDown: true, flags: pausedFlags, character: ",")
remapper.transform(paused, type: .keyDown)
check(keyCode(of: paused) == kVK_ANSI_KeypadDecimal && text(of: paused) == "," && paused.flags == pausedFlags, "aucune modification attendue quand l'inversion est désactivée")
let pausedRelease = makeEvent(keyCode: kVK_ANSI_KeypadDecimal, keyDown: false, flags: .maskNumericPad, character: ",")
remapper.transform(pausedRelease, type: .keyUp)
check(keyCode(of: pausedRelease) == kVK_ANSI_KeypadDecimal, "le relâchement ne devrait pas être modifié non plus")

print("Changements entre l'appui et le relâchement")
remapper.isEnabled = true
let shiftedDown = pressDecimal(remapper, flags: .maskShift)
let unshiftedUp = pressDecimal(remapper, flags: [], keyDown: false)
check(keyCode(of: unshiftedUp) == keyCode(of: shiftedDown) && text(of: unshiftedUp) == text(of: shiftedDown), "Majuscule relâchée avant la touche : le relâchement devrait suivre l'appui")
// Majuscule enfoncée pendant que la touche se répète : la touche envoyée ne doit pas changer.
let heldDown = pressDecimal(remapper, flags: [])
let heldRepeat = pressDecimal(remapper, flags: .maskShift, isRepeat: true)
let heldUp = pressDecimal(remapper, flags: .maskShift, keyDown: false)
check(keyCode(of: heldRepeat) == keyCode(of: heldDown) && text(of: heldRepeat) == text(of: heldDown), "Majuscule enfoncée pendant la répétition : la répétition devrait suivre l'appui")
check(keyCode(of: heldUp) == keyCode(of: heldDown), "Majuscule enfoncée pendant la répétition : le relâchement devrait suivre l'appui")
let freshDown = pressDecimal(remapper, flags: .maskShift)
check(text(of: freshDown) == shifted, "un nouvel appui avec Majuscule devrait être recalculé : attendu « \(shifted) », obtenu « \(text(of: freshDown)) »")
_ = pressDecimal(remapper, flags: [], keyDown: false)

let down = pressDecimal(remapper, flags: [])
remapper.isEnabled = false
let up = pressDecimal(remapper, flags: [], keyDown: false)
check(keyCode(of: up) == keyCode(of: down), "mise en pause avant le relâchement : le relâchement devrait suivre l'appui")
let strayUp = pressDecimal(remapper, flags: [], keyDown: false)
check(keyCode(of: strayUp) == kVK_ANSI_KeypadDecimal, "un relâchement isolé ne devrait plus être converti ensuite")

print(failures == 0 ? "\n\(checks) vérifications réussies." : "\n\(failures) échec(s) sur \(checks) vérifications.")
exit(failures == 0 ? 0 : 1)
