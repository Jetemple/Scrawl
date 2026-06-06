import AppKit

final class PreferencesAboutView: NSView {
    private let projectAction: ClosureAction

    init(openProjectPage: @escaping () -> Void) {
        projectAction = ClosureAction(openProjectPage)
        super.init(frame: .zero)

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
        let versionLabel = NSTextField(labelWithString: "Version \(version)")
        versionLabel.textColor = .secondaryLabelColor

        let privacyLabel = NSTextField(wrappingLabelWithString: "Audio and transcription are processed locally on this Mac.")
        privacyLabel.textColor = .secondaryLabelColor

        let projectButton = NSButton(title: "Open Project Page", target: nil, action: nil)
        PreferencesPageSupport.configureSecondaryButton(projectButton)
        projectButton.target = projectAction
        projectButton.action = #selector(ClosureAction.perform(_:))

        let page = PreferencesPageSupport.makePage(
            title: "About Scrawl",
            description: "Private, local-first speech transcription.",
            content: [
                PreferencesPageSupport.makeGroup(rows: [
                    PreferencesPageSupport.makeSettingRow(title: "Application", detail: versionLabel),
                    PreferencesPageSupport.makeSettingRow(title: "Privacy", detail: privacyLabel)
                ]),
                PreferencesPageSupport.makeButtonRow(projectButton)
            ]
        )
        PreferencesPageSupport.fill(self, with: page)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
