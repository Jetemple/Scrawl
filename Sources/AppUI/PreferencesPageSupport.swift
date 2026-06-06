import AppKit

enum PreferencesPageSupport {
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
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(makePageHeader(title: title, description: description))
        content.forEach(stack.addArrangedSubview)
        stack.addArrangedSubview(NSView())

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24)
        ])
        return container
    }

    static func makePageHeader(title: String, description: String) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail

        let descriptionLabel = NSTextField(wrappingLabelWithString: description)
        descriptionLabel.font = .systemFont(ofSize: 12)
        descriptionLabel.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [titleLabel, descriptionLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        return stack
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

    static func makeSettingRow(title: String, detail: NSTextField, action: NSButton? = nil) -> NSView {
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
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        view.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        view.layer?.borderWidth = 1
        return view
    }

    static func configureSecondaryButton(_ button: NSButton) {
        button.bezelStyle = .rounded
        button.controlSize = .small
    }

    static func makeButtonRow(_ button: NSButton) -> NSView {
        let row = NSStackView(views: [button, NSView()])
        row.orientation = .horizontal
        row.alignment = .centerY
        return row
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

final class ClosureAction: NSObject {
    private let closure: () -> Void

    init(_ closure: @escaping () -> Void) {
        self.closure = closure
    }

    @objc func perform(_ sender: Any?) {
        closure()
    }
}
