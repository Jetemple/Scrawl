import AppKit

final class PreferencesAboutView: NSView {
    private let openProjectPage: () -> Void
    private let checkForUpdates: () -> Void

    private let updateButton = NSButton()
    private var availableUpdate: UpdateRelease?

    init(openProjectPage: @escaping () -> Void, checkForUpdates: @escaping () -> Void) {
        self.openProjectPage = openProjectPage
        self.checkForUpdates = checkForUpdates
        super.init(frame: .zero)

        let iconView = NSImageView(image: Self.appIcon())
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 96),
            iconView.heightAnchor.constraint(equalToConstant: 96),
        ])

        let nameLabel = NSTextField(labelWithString: "Scrawl")
        nameLabel.font = .systemFont(ofSize: 26, weight: .semibold)

        let versionText = Self.appVersion().map { "Version \($0)" } ?? "Development build"
        let versionLabel = NSTextField(labelWithString: versionText)
        versionLabel.font = .systemFont(ofSize: 13)
        versionLabel.textColor = .secondaryLabelColor

        configureUpdateButton()

        let taglineLabel = NSTextField(labelWithString: "Private, local-first speech transcription.")
        taglineLabel.font = .systemFont(ofSize: 13)

        let privacyLabel = NSTextField(labelWithString: "Audio never leaves this Mac.")
        privacyLabel.font = .systemFont(ofSize: 13)
        privacyLabel.textColor = .secondaryLabelColor

        let projectButton = NSButton(title: "Open Project Page", target: self, action: #selector(openProjectPageAction(_:)))
        projectButton.bezelStyle = .rounded

        let updatesButton = NSButton(title: "Check for Updates…", target: self, action: #selector(checkForUpdatesAction(_:)))
        updatesButton.bezelStyle = .rounded

        let buttonRow = NSStackView(views: [projectButton, updatesButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        let stack = NSStackView(views: [
            iconView, nameLabel, versionLabel, updateButton, taglineLabel, privacyLabel, buttonRow,
        ])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        stack.setCustomSpacing(10, after: iconView)
        stack.setCustomSpacing(2, after: nameLabel)
        stack.setCustomSpacing(6, after: versionLabel)
        stack.setCustomSpacing(16, after: updateButton)
        stack.setCustomSpacing(18, after: privacyLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = PreferencesPageSupport.makeContentBackground()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 36),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -36),
            stack.leadingAnchor.constraint(
                greaterThanOrEqualTo: container.leadingAnchor,
                constant: PreferencesPageSupport.pageHorizontalInset
            ),
            stack.trailingAnchor.constraint(
                lessThanOrEqualTo: container.trailingAnchor,
                constant: -PreferencesPageSupport.pageHorizontalInset
            ),
        ])
        PreferencesPageSupport.fill(self, with: container)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows or hides the coral "Update available" link under the version line.
    /// The row collapses out of the stack when the build is current.
    func update(availableUpdate release: UpdateRelease?) {
        availableUpdate = release
        if let release {
            updateButton.attributedTitle = Self.updateTitle(for: release)
            updateButton.isHidden = false
        } else {
            updateButton.isHidden = true
        }
    }

    private func configureUpdateButton() {
        updateButton.isBordered = false
        updateButton.bezelStyle = .inline
        updateButton.setButtonType(.momentaryChange)
        updateButton.target = self
        updateButton.action = #selector(openAvailableUpdateAction(_:))
        updateButton.isHidden = true
    }

    private static func updateTitle(for release: UpdateRelease) -> NSAttributedString {
        NSAttributedString(
            string: "Update available: \(release.version) — View Release",
            attributes: [
                .foregroundColor: PreferencesPageSupport.accentColor,
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            ]
        )
    }

    @objc private func openProjectPageAction(_: NSButton) {
        openProjectPage()
    }

    @objc private func checkForUpdatesAction(_: NSButton) {
        checkForUpdates()
    }

    @objc private func openAvailableUpdateAction(_: NSButton) {
        guard let availableUpdate else { return }
        NSWorkspace.shared.open(availableUpdate.pageURL)
    }

    /// Outside the installed app, Bundle.main belongs to the host process (swift run,
    /// the test runner), so its version string describes the wrong bundle.
    private static func appVersion() -> String? {
        guard Bundle.main.bundleIdentifier == "com.jetemple.scrawl" else { return nil }
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    private static func appIcon() -> NSImage {
        ScrawlBrandIcon.image()
    }
}
