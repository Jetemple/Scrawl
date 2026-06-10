import AppKit

final class PreferencesBackgroundView: NSView {
    enum Style {
        case content
        case group
    }

    private let style: Style

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            switch style {
            case .content:
                layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
                layer?.borderWidth = 0
            case .group:
                layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
                layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
                layer?.borderWidth = 1
                layer?.cornerRadius = 8
            }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

enum PreferencesPageSupport {
    static let pageHorizontalInset: CGFloat = 28
    static let pageVerticalInset: CGFloat = 24
    static let pageSectionSpacing: CGFloat = 16

    static func fill(_ container: NSView, with view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    static func makePage(title: String, description: String, content: [NSView]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = pageSectionSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        let header = makePageHeader(title: title, description: description)
        stack.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        content.forEach {
            $0.setContentHuggingPriority(.defaultLow, for: .horizontal)
            stack.addArrangedSubview($0)
            $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: pageHorizontalInset),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -pageHorizontalInset),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: pageVerticalInset),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -pageVerticalInset)
        ])
        return container
    }

    static func makePageHeader(title: String, description: String) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.alignment = .left

        let descriptionLabel = NSTextField(wrappingLabelWithString: description)
        descriptionLabel.font = .systemFont(ofSize: 12)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.alignment = .left

        let container = NSView()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)
        container.addSubview(descriptionLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
            descriptionLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            descriptionLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    static func makeGroup(rows: [NSView]) -> NSView {
        let group = makeRoundedBackground()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        group.addSubview(stack)

        for (index, row) in rows.enumerated() {
            stack.addArrangedSubview(row)
            if index < rows.count - 1 {
                stack.addArrangedSubview(makeSeparator())
            }
        }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: group.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: group.trailingAnchor),
            stack.topAnchor.constraint(equalTo: group.topAnchor),
            stack.bottomAnchor.constraint(equalTo: group.bottomAnchor)
        ])
        return group
    }

    static func makeSettingRow(title: String, detail: NSTextField, action: NSView? = nil) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.widthAnchor.constraint(equalToConstant: 112).isActive = true

        detail.font = .systemFont(ofSize: 13)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(detail)
        if let action {
            row.addArrangedSubview(action)
        }
        return row
    }

    static func makeSeparator() -> NSView {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return separator
    }

    static func makeRoundedBackground() -> NSView {
        PreferencesBackgroundView(style: .group)
    }

    static func makeContentBackground() -> NSView {
        PreferencesBackgroundView(style: .content)
    }

    static func configureSecondaryButton(_ button: NSButton) {
        button.bezelStyle = .rounded
        button.controlSize = .small
    }

    static func makeButtonRow(_ button: NSButton) -> NSView {
        makeActionRow(buttons: [button])
    }

    static func makeActionRow(buttons: [NSButton]) -> NSView {
        let stack = NSStackView(views: buttons + [NSView()])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6

        let row = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            stack.topAnchor.constraint(equalTo: row.topAnchor),
            stack.bottomAnchor.constraint(equalTo: row.bottomAnchor)
        ])
        return row
    }

    static func makeListWorkspace(scrollView: NSScrollView, stateView: NSView) -> NSView {
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let content = NSView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stateView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scrollView)
        content.addSubview(stateView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: content.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stateView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stateView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stateView.topAnchor.constraint(equalTo: content.topAnchor),
            stateView.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])

        let group = makeRoundedBackground()
        content.translatesAutoresizingMaskIntoConstraints = false
        group.addSubview(content)
        NSLayoutConstraint.activate([
            group.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
            content.leadingAnchor.constraint(equalTo: group.leadingAnchor, constant: 1),
            content.trailingAnchor.constraint(equalTo: group.trailingAnchor, constant: -1),
            content.topAnchor.constraint(equalTo: group.topAnchor, constant: 1),
            content.bottomAnchor.constraint(equalTo: group.bottomAnchor, constant: -1)
        ])
        return group
    }

    static func makeEmptyState(title: String, detail: String) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.alignment = .center

        let detailLabel = NSTextField(wrappingLabelWithString: detail)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .center

        let stack = NSStackView(views: [titleLabel, detailLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        let view = NSView()
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -28)
        ])
        return view
    }
}
