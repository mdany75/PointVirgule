import Cocoa

final class SettingsWindowController: NSWindowController {
    private unowned let app: AppDelegate

    private static let contentWidth: CGFloat = 440
    private static let margin: CGFloat = 24

    private lazy var enabledCheckbox = NSButton(
        checkboxWithTitle: "Inverser la virgule et le point du pavé numérique",
        target: self, action: #selector(toggleEnabled)
    )
    private lazy var iconCheckbox = NSButton(
        checkboxWithTitle: "Afficher l'icône dans la barre des menus",
        target: self, action: #selector(toggleIcon)
    )
    private lazy var loginCheckbox = NSButton(
        checkboxWithTitle: "Ouvrir automatiquement à l'ouverture de session",
        target: self, action: #selector(toggleLogin)
    )
    private let permissionIcon = NSImageView()
    private let permissionLabel = NSTextField(labelWithString: "")
    private lazy var grantButton = NSButton(
        title: "Ouvrir les Réglages Système…",
        target: self, action: #selector(requestPermission)
    )
    private lazy var resetButton = NSButton(
        title: "Réinitialiser l'autorisation",
        target: self, action: #selector(resetPermission)
    )

    init(app: AppDelegate) {
        self.app = app
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth + Self.margin * 2, height: 100),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "PointVirgule"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildContent()
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) n'est pas pris en charge")
    }

    // MARK: - Mise en page

    private func buildContent() {
        let fullWidthViews: [NSView] = [
            makeHeader(),
            makeSeparator(),
            makeSectionTitle("Général"),
            enabledCheckbox,
            iconCheckbox,
            makeNote("Si l'icône est masquée, ouvrez de nouveau PointVirgule depuis le dossier Applications pour revenir à cette fenêtre.", indent: 20),
            loginCheckbox,
            makeSeparator(),
            makeSectionTitle("Autorisation du Mac"),
            makePermissionRow(),
            makeNote("macOS exige l'autorisation « Accessibilité » pour qu'une app puisse modifier une touche. PointVirgule ne regarde que la touche décimale du pavé numérique : rien n'est enregistré ni transmis.\n\nSi l'autorisation est cochée dans les Réglages Système mais reste « non accordée » ici, cliquez sur Réinitialiser, puis accordez-la de nouveau."),
            makeButtonRow([grantButton, resetButton]),
            makeSeparator(),
            makeFooter(),
        ]

        let stack = NSStackView(views: fullWidthViews)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: Self.margin, bottom: 20, right: Self.margin)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(16, after: fullWidthViews[0])
        stack.setCustomSpacing(4, after: iconCheckbox)

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.widthAnchor.constraint(equalToConstant: Self.contentWidth + Self.margin * 2),
        ])
        for view in fullWidthViews where view is NSBox || view is NSStackView {
            view.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
        }
        window?.contentView = container
    }

    private func makeHeader() -> NSView {
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 56).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 56).isActive = true

        let title = NSTextField(labelWithString: "PointVirgule")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "Le pavé numérique tape un point au lieu d'une virgule, et l'inverse.")
        subtitle.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        subtitle.textColor = .secondaryLabelColor

        let texts = NSStackView(views: [title, subtitle])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 3

        let header = NSStackView(views: [icon, texts])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 14
        return header
    }

    private func makeSeparator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func makeSectionTitle(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        return label
    }

    private func makeNote(_ text: String, indent: CGFloat = 0) -> NSView {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.isSelectable = false
        label.preferredMaxLayoutWidth = Self.contentWidth - indent

        let row = NSStackView(views: [label])
        row.orientation = .horizontal
        row.edgeInsets = NSEdgeInsets(top: 0, left: indent, bottom: 0, right: 0)
        return row
    }

    private func makePermissionRow() -> NSView {
        permissionIcon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        permissionIcon.heightAnchor.constraint(equalToConstant: 18).isActive = true
        let row = NSStackView(views: [permissionIcon, permissionLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        return row
    }

    private func makeButtonRow(_ buttons: [NSButton]) -> NSView {
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    private func makeFooter() -> NSView {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let versionLabel = NSTextField(labelWithString: "Version \(version)")
        versionLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        versionLabel.textColor = .tertiaryLabelColor

        let quitButton = NSButton(title: "Quitter PointVirgule", target: self, action: #selector(quit))

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let footer = NSStackView(views: [versionLabel, spacer, quitButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.distribution = .fill
        return footer
    }

    // MARK: - État

    func refresh() {
        enabledCheckbox.state = app.isEnabled ? .on : .off
        iconCheckbox.state = app.showsMenuBarIcon ? .on : .off
        loginCheckbox.state = app.opensAtLogin ? .on : .off

        let granted = app.hasPermission
        let symbol = granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        permissionIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        permissionIcon.contentTintColor = granted ? .systemGreen : .systemOrange
        permissionLabel.stringValue = granted
            ? "Accessibilité : autorisation accordée"
            : "Accessibilité : autorisation non accordée (inversion inactive)"
        grantButton.keyEquivalent = granted ? "" : "\r"
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        app.isEnabled = enabledCheckbox.state == .on
    }

    @objc private func toggleIcon() {
        app.showsMenuBarIcon = iconCheckbox.state == .on
    }

    @objc private func toggleLogin() {
        app.opensAtLogin = loginCheckbox.state == .on
    }

    @objc private func requestPermission() {
        app.requestPermission()
    }

    @objc private func resetPermission() {
        app.resetPermission()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
