import AppKit

final class PreferencesAboutView: NSView {
    private let openProjectPage: () -> Void

    init(openProjectPage: @escaping () -> Void) {
        self.openProjectPage = openProjectPage
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

        let taglineLabel = NSTextField(labelWithString: "Private, local-first speech transcription.")
        taglineLabel.font = .systemFont(ofSize: 13)

        let privacyLabel = NSTextField(labelWithString: "Audio never leaves this Mac.")
        privacyLabel.font = .systemFont(ofSize: 13)
        privacyLabel.textColor = .secondaryLabelColor

        let projectButton = NSButton(title: "Open Project Page", target: nil, action: nil)
        projectButton.bezelStyle = .rounded
        projectButton.target = self
        projectButton.action = #selector(openProjectPageAction(_:))

        let stack = NSStackView(views: [
            iconView, nameLabel, versionLabel, taglineLabel, privacyLabel, projectButton,
        ])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        stack.setCustomSpacing(10, after: iconView)
        stack.setCustomSpacing(2, after: nameLabel)
        stack.setCustomSpacing(16, after: versionLabel)
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

    @objc private func openProjectPageAction(_: NSButton) {
        openProjectPage()
    }

    /// Outside the installed app, Bundle.main belongs to the host process (swift run,
    /// the test runner), so its version string describes the wrong bundle.
    private static func appVersion() -> String? {
        guard Bundle.main.bundleIdentifier == "com.jetemple.scrawl" else { return nil }
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// The bundled copy (derived from Config/AppIcon.png) keeps the page from showing
    /// the generic system icon when there is no .app bundle, e.g. `swift run` or tests.
    private static func appIcon() -> NSImage {
        if let url = Bundle.module.url(forResource: "AboutAppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url)
        {
            return image
        }
        return NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }
}
