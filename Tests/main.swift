// Vérifie la conversion de la touche décimale sans installer d'intercepteur.
// Compilé avec Sources/KeyRemapper.swift par build.sh.
import Cocoa
import Carbon.HIToolbox

var failures = 0

func check(_ condition: Bool, _ message: String) {
    print(condition ? "  ok     \(message)" : "  ÉCHEC  \(message)")
    if !condition { failures += 1 }
}

func makeEvent(keyCode: Int, keyDown: Bool, character: Character? = nil) -> CGEvent {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: keyDown)!
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

let remapper = KeyRemapper()

print("Touche décimale du pavé numérique")
for (input, expected) in [(Character(","), "."), (Character("."), ",")] {
    for keyDown in [true, false] {
        let event = makeEvent(keyCode: kVK_ANSI_KeypadDecimal, keyDown: keyDown, character: input)
        event.flags.insert(.maskNumericPad)
        remapper.transform(event, type: keyDown ? .keyDown : .keyUp)
        let phase = keyDown ? "appui" : "relâchement"
        check(text(of: event) == expected, "« \(input) » devient « \(expected) » (\(phase))")
        check(keyCode(of: event) != kVK_ANSI_KeypadDecimal, "le code de touche devient celui du clavier principal : \(keyCode(of: event)) (\(phase))")
        check(!event.flags.contains(.maskNumericPad), "l'indicateur « pavé numérique » est retiré (\(phase))")

        // La touche envoyée doit vraiment taper le caractère voulu dans la disposition active.
        let replay = makeEvent(keyCode: keyCode(of: event), keyDown: true)
        replay.flags = event.flags
        check(text(of: replay) == expected, "la touche \(keyCode(of: event)) tape bien « \(expected) » dans la disposition active")
    }
}

print("Disposition active")
let native = makeEvent(keyCode: kVK_ANSI_KeypadDecimal, keyDown: true)
let nativeText = text(of: native)
remapper.transform(native, type: .keyDown)
print("  la touche décimale tape « \(nativeText) » → PointVirgule tape « \(text(of: native)) »")
check(text(of: native) != nativeText, "le caractère natif est inversé")

print("Touches à ne pas modifier")
let digit = makeEvent(keyCode: kVK_ANSI_Keypad5, keyDown: true)
remapper.transform(digit, type: .keyDown)
check(keyCode(of: digit) == kVK_ANSI_Keypad5 && text(of: digit) == "5", "le 5 du pavé numérique reste intact")

let mainPeriod = makeEvent(keyCode: kVK_ANSI_Period, keyDown: true, character: ".")
remapper.transform(mainPeriod, type: .keyDown)
check(keyCode(of: mainPeriod) == kVK_ANSI_Period && text(of: mainPeriod) == ".", "le point du clavier principal reste intact")

let mainComma = makeEvent(keyCode: kVK_ANSI_Comma, keyDown: true, character: ",")
remapper.transform(mainComma, type: .keyDown)
check(keyCode(of: mainComma) == kVK_ANSI_Comma && text(of: mainComma) == ",", "la virgule du clavier principal reste intacte")

print("Inversion en pause")
remapper.isEnabled = false
let paused = makeEvent(keyCode: kVK_ANSI_KeypadDecimal, keyDown: true, character: ",")
remapper.transform(paused, type: .keyDown)
check(keyCode(of: paused) == kVK_ANSI_KeypadDecimal && text(of: paused) == ",", "aucune modification quand l'inversion est désactivée")

print(failures == 0 ? "\nTous les tests réussissent." : "\n\(failures) test(s) en échec.")
exit(failures == 0 ? 0 : 1)
