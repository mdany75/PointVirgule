import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum Keys {
        static let enabled = "enabled"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let hasLaunchedBefore = "hasLaunchedBefore"
        static let skipHideIconWarning = "skipHideIconWarning"
    }

    private let defaults = UserDefaults.standard
    private let remapper = KeyRemapper()
    private var statusItem: NSStatusItem?
    private var settingsWindow: SettingsWindowController?
    private var permissionTimer: Timer?

    private let permissionMenuItem = NSMenuItem()
    private let enabledMenuItem = NSMenuItem()
    private let loginMenuItem = NSMenuItem()

    private(set) var hasPermission = false

    // MARK: - Réglages

    var isEnabled: Bool {
        get { defaults.bool(forKey: Keys.enabled) }
        set {
            defaults.set(newValue, forKey: Keys.enabled)
            remapper.isEnabled = newValue
            refreshUI()
        }
    }

    var showsMenuBarIcon: Bool {
        get { defaults.bool(forKey: Keys.showMenuBarIcon) }
        set {
            defaults.set(newValue, forKey: Keys.showMenuBarIcon)
            statusItem?.isVisible = newValue
            refreshUI()
        }
    }

    var opensAtLogin: Bool {
        get { LoginItem.isEnabled }
        set {
            do {
                try LoginItem.setEnabled(newValue)
                if newValue, LoginItem.needsApproval {
                    askLoginItemApproval()
                }
            } catch {
                showAlert(
                    title: "Impossible de modifier l'ouverture automatique",
                    message: "\(error.localizedDescription)\n\nVérifiez que PointVirgule est bien dans le dossier Applications."
                )
            }
            refreshUI()
        }
    }

    // MARK: - Cycle de vie

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: [Keys.enabled: true, Keys.showMenuBarIcon: true])

        if isRunningFromTemporaryLocation(), !confirmRunningFromTemporaryLocation() {
            NSApp.terminate(nil)
            return
        }

        setUpStatusItem()
        remapper.isEnabled = isEnabled
        checkPermission()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.checkPermission()
        }

        let isFirstLaunch = !defaults.bool(forKey: Keys.hasLaunchedBefore)
        defaults.set(true, forKey: Keys.hasLaunchedBefore)
        if isFirstLaunch || !hasPermission {
            showSettings()
            if !hasPermission {
                Permissions.prompt()
            }
        }
    }

    /// Rouvrir l'app (double-clic dans Applications) affiche les réglages :
    /// c'est le moyen de retrouver l'app quand l'icône est masquée.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        remapper.stop()
    }

    // MARK: - Autorisation

    private func checkPermission() {
        let granted = Permissions.isGranted
        if granted {
            if !remapper.isRunning {
                remapper.stop()
                remapper.start()
            }
        } else {
            // Un intercepteur actif sans autorisation peut bloquer le clavier.
            remapper.stop()
        }
        if granted != hasPermission {
            hasPermission = granted
            refreshUI()
        }
    }

    func requestPermission() {
        Permissions.prompt()
        Permissions.openSystemSettings()
    }

    func resetPermission() {
        remapper.stop()
        if Permissions.reset() {
            checkPermission()
            Permissions.prompt()
        } else {
            showAlert(
                title: "Réinitialisation impossible",
                message: "Retirez PointVirgule manuellement dans Réglages Système > Confidentialité et sécurité > Accessibilité, puis ajoutez-la de nouveau."
            )
        }
    }

    // MARK: - Barre des menus

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "PointVirgule"
        item.button?.image = MenuBarIcon.make()
        item.menu = makeMenu()
        item.isVisible = showsMenuBarIcon
        statusItem = item
        refreshUI()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        configure(permissionMenuItem, title: "⚠️ Autorisation requise…", action: #selector(showSettings))
        configure(enabledMenuItem, title: "Inverser virgule ⇄ point", action: #selector(toggleEnabled))
        configure(loginMenuItem, title: "Ouvrir à l'ouverture de session", action: #selector(toggleOpensAtLogin))

        menu.addItem(permissionMenuItem)
        menu.addItem(enabledMenuItem)
        menu.addItem(.separator())
        menu.addItem(loginMenuItem)
        menu.addItem(makeItem(title: "Masquer l'icône de la barre des menus", action: #selector(hideMenuBarIcon)))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Réglages et autorisations…", action: #selector(showSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Quitter PointVirgule", action: #selector(quit), key: "q"))
        return menu
    }

    private func configure(_ item: NSMenuItem, title: String, action: Selector) {
        item.title = title
        item.action = action
        item.target = self
    }

    private func makeItem(title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        permissionMenuItem.isHidden = hasPermission
        enabledMenuItem.state = isEnabled ? .on : .off
        loginMenuItem.state = opensAtLogin ? .on : .off
    }

    private func refreshUI() {
        if let button = statusItem?.button {
            let isActive = isEnabled && hasPermission
            button.appearsDisabled = !isActive
            if !hasPermission {
                button.toolTip = "PointVirgule — autorisation requise"
            } else if isEnabled {
                button.toolTip = "PointVirgule — inversion active"
            } else {
                button.toolTip = "PointVirgule — en pause"
            }
        }
        settingsWindow?.refresh()
    }

    // MARK: - Actions

    @objc func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(app: self)
        }
        settingsWindow?.refresh()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleEnabled() {
        isEnabled.toggle()
    }

    @objc private func toggleOpensAtLogin() {
        opensAtLogin.toggle()
    }

    @objc private func hideMenuBarIcon() {
        if !defaults.bool(forKey: Keys.skipHideIconWarning) {
            let alert = NSAlert()
            alert.messageText = "Masquer l'icône de la barre des menus ?"
            alert.informativeText = "PointVirgule continuera de fonctionner. Pour réafficher l'icône ou changer les réglages, ouvrez de nouveau PointVirgule depuis le dossier Applications."
            alert.addButton(withTitle: "Masquer")
            alert.addButton(withTitle: "Annuler")
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Ne plus afficher ce message"
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            if alert.suppressionButton?.state == .on {
                defaults.set(true, forKey: Keys.skipHideIconWarning)
            }
        }
        showsMenuBarIcon = false
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Alertes

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func askLoginItemApproval() {
        let alert = NSAlert()
        alert.messageText = "Approbation requise"
        alert.informativeText = "macOS demande d'approuver PointVirgule dans Réglages Système > Général > Ouverture."
        alert.addButton(withTitle: "Ouvrir les Réglages Système")
        alert.addButton(withTitle: "Plus tard")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            LoginItem.openSystemSettings()
        }
    }

    /// Lancée depuis l'image disque ou un emplacement temporaire de macOS, l'app
    /// ne peut conserver ni son autorisation ni son ouverture automatique.
    private func isRunningFromTemporaryLocation() -> Bool {
        let path = Bundle.main.bundlePath
        return path.contains("/AppTranslocation/") || path.hasPrefix("/Volumes/")
    }

    private func confirmRunningFromTemporaryLocation() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Installez d'abord PointVirgule"
        alert.informativeText = "Glissez PointVirgule dans le dossier Applications, puis ouvrez-la à partir de là. Sinon, l'autorisation et l'ouverture automatique ne seront pas conservées."
        alert.addButton(withTitle: "Quitter")
        alert.addButton(withTitle: "Continuer quand même")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertSecondButtonReturn
    }
}
