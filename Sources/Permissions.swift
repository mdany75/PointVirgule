import Cocoa
import ApplicationServices

/// Autorisation « Accessibilité » de macOS, requise pour modifier une touche.
enum Permissions {
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Affiche la demande de macOS et ajoute l'app à la liste Accessibilité.
    static func prompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Efface l'autorisation enregistrée pour cette app (utile si elle est restée
    /// cochée dans les Réglages Système mais ne fonctionne plus après une mise à jour).
    @discardableResult
    static func reset() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
