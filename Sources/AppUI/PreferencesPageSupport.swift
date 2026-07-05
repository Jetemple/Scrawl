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
    required init?(coder _: NSCoder) {
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
                layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.28).cgColor
                layer?.borderWidth = 0.5
                layer?.cornerRadius = 8
            }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

final class PreferencesPinnedActionBarView: NSView {}

/// Table row view that draws Scrawl's coral selection pill — a soft, inset, rounded
/// highlight instead of the default full-bleed macOS selection band. Pair with
/// `tableView.selectionHighlightStyle = .regular` and return this from the row-view delegate.
final class PreferencesSelectionRowView: NSTableRowView {
    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        .normal
    }

    override func drawSelection(in _: NSRect) {
        guard isSelected else { return }
        let rect = bounds.insetBy(
            dx: PreferencesPageSupport.selectionPillHorizontalInset,
            dy: PreferencesPageSupport.selectionPillVerticalInset
        )
        let path = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            PreferencesPageSupport.selectionTint.setFill()
            path.fill()
        }
    }
}

enum PreferencesPageSupport {
    static let pageHorizontalInset: CGFloat = 28
    static let pageVerticalInset: CGFloat = 24
    static let pageSectionSpacing: CGFloat = 18

    /// The single leading/trailing content inset every row on every page shares, so the
    /// primary column lines up down the tabs. The page title outdents to the stack edge;
    /// row content (and section headers) sit one `rowInset` in.
    static let rowInset: CGFloat = 14
    /// Fixed width of the label column on key/value rows, so titles align across pages.
    static let labelColumnWidth: CGFloat = 132
    static let selectionPillHorizontalInset: CGFloat = 8
    static let selectionPillVerticalInset: CGFloat = 3

    /// Scrawl's brand accent — the coral-red of the app icon's waveform, not orange.
    static let accentColor = NSColor(srgbRed: 0.95, green: 0.36, blue: 0.30, alpha: 1)

    /// Shared coral wash behind a selected row. Kept in one place so the History, Dictionary,
    /// and Models selection pills read identically. The saturated accent needs only a whisper
    /// of alpha in light mode to read as a highlight without shouting; dark mode needs more
    /// for the wash to stay visible at all.
    static var selectionTint: NSColor {
        NSColor(name: nil) { appearance in
            let alpha: CGFloat = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 0.14 : 0.09
            return accentColor.withAlphaComponent(alpha)
        }
    }

    /// Hairline color shared by every workbench rule (group frames, row dividers, list frames).
    static var hairlineColor: NSColor { .separatorColor.withAlphaComponent(0.5) }

    static func fill(_ container: NSView, with view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
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
        for item in content {
            item.setContentHuggingPriority(.defaultLow, for: .horizontal)
            stack.addArrangedSubview(item)
            item.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let container = makeContentBackground()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: pageHorizontalInset),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -pageHorizontalInset),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: pageVerticalInset),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -pageVerticalInset),
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
            descriptionLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    /// A flat "workbench" group: an optional section header over a hairline-framed run of
    /// rows on the plain window background — no white card. Full-width top and bottom rules
    /// plus inter-row dividers make it read as a table section that matches the Models page.
    static func makeGroup(header: String? = nil, rows: [NSView]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        // A single flat stack so `.width` alignment stretches every row to full width.
        // (Nesting the rows one level deeper broke the width propagation and shoved
        // content to the right.)
        if let header {
            stack.addArrangedSubview(makeSectionHeaderRow(header))
        }
        stack.addArrangedSubview(makeSeparator())
        for (index, row) in rows.enumerated() {
            stack.addArrangedSubview(row)
            if index < rows.count - 1 {
                stack.addArrangedSubview(makeSeparator())
            }
        }
        stack.addArrangedSubview(makeSeparator())
        return stack
    }

    /// A workbench section header: a semibold label indented to the shared row grid, with a
    /// little breathing room before the framed rows below it.
    static func makeSectionHeaderRow(_ title: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail

        let row = NSStackView(views: [label, NSView()])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 0
        row.edgeInsets = NSEdgeInsets(top: 0, left: rowInset, bottom: 7, right: rowInset)
        return row
    }

    static func makeSettingRow(title: String, detail: NSTextField, action: NSView? = nil) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth).isActive = true

        detail.font = .systemFont(ofSize: 13)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // Keep the value snug against its title; the trailing spacer, not the value,
        // absorbs the row's slack.
        detail.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        // Greedy spacer keeps sparse rows from centering and gives action controls a
        // stable trailing column.
        let trailingSpacer = NSView()
        trailingSpacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        trailingSpacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 11, left: rowInset, bottom: 11, right: rowInset)
        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(detail)
        row.addArrangedSubview(trailingSpacer)
        if let action {
            row.addArrangedSubview(action)
        }
        return row
    }

    static func makeSettingControlRow(title: String, control: NSView) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.widthAnchor.constraint(equalToConstant: labelColumnWidth).isActive = true

        let trailingSpacer = NSView()
        trailingSpacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        trailingSpacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 11, left: rowInset, bottom: 11, right: rowInset)
        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(control)
        row.addArrangedSubview(trailingSpacer)
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

    static func makeSectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    static func makeActionRow(buttons: [NSButton]) -> NSView {
        let stack = NSStackView(views: buttons + [NSView()])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 0, left: rowInset, bottom: 0, right: rowInset)

        let row = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            stack.topAnchor.constraint(equalTo: row.topAnchor),
            stack.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])
        return row
    }

    static func makePinnedActionBar(
        leading: [NSButton],
        trailing: [NSButton],
        leadingInset: CGFloat? = nil,
        trailingInset: CGFloat? = nil
    ) -> NSView {
        let leadingStack = NSStackView(views: leading)
        leadingStack.orientation = .horizontal
        leadingStack.alignment = .centerY
        leadingStack.spacing = 8

        let trailingStack = NSStackView(views: trailing)
        trailingStack.orientation = .horizontal
        trailingStack.alignment = .centerY
        trailingStack.spacing = 8

        let stack = NSStackView(views: [leadingStack, NSView(), trailingStack])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(
            top: 10,
            left: leadingInset ?? rowInset,
            bottom: 0,
            right: trailingInset ?? rowInset
        )

        let row = PreferencesPinnedActionBarView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            stack.topAnchor.constraint(equalTo: row.topAnchor),
            stack.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])
        return row
    }

    /// Minimum and maximum height of a flat list workspace. The view drives the exact height
    /// (via the returned constraint) to hug its content, clamped to this range.
    static let listMinHeight: CGFloat = 96
    static let listMaxHeight: CGFloat = 300

    /// A flat, hairline-framed list area on the plain window background — no white well.
    /// Top and bottom rules frame the scrolling list (or its empty-state message) so it reads
    /// as the same kind of table section as the key/value groups and the Models page.
    ///
    /// Returns the group plus its height constraint: the owning view sets `.constant` to the
    /// list's content height after each reload so the bottom rule hugs the last row instead of
    /// leaving a mostly-empty framed region. The constraint sits just below required, so a tight
    /// window can still compress it without breaking layout.
    static func makeListWorkspace(scrollView: NSScrollView, stateView: NSView) -> (view: NSView, heightConstraint: NSLayoutConstraint) {
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.verticalScrollElasticity = .none

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
            stateView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        // Flat (window-background) surface — invisible against the pane — kept as a
        // PreferencesBackgroundView so shared "grouped workspace" checks still hold.
        let group = makeContentBackground()
        let topRule = makeSeparator()
        let bottomRule = makeSeparator()
        content.translatesAutoresizingMaskIntoConstraints = false
        group.addSubview(topRule)
        group.addSubview(content)
        group.addSubview(bottomRule)
        // Hug the list's content height (set by the owner after each reload), clamped to
        // [listMinHeight, listMaxHeight]. The hug is just under required so a tight window can
        // still compress it; the bounds stay required so a short list never leaves a big
        // empty framed region and a long one scrolls.
        let contentHeight = group.heightAnchor.constraint(equalToConstant: listMinHeight)
        contentHeight.priority = NSLayoutConstraint.Priority(999)
        NSLayoutConstraint.activate([
            contentHeight,
            group.heightAnchor.constraint(lessThanOrEqualToConstant: listMaxHeight),
            group.heightAnchor.constraint(greaterThanOrEqualToConstant: listMinHeight),
            topRule.leadingAnchor.constraint(equalTo: group.leadingAnchor),
            topRule.trailingAnchor.constraint(equalTo: group.trailingAnchor),
            topRule.topAnchor.constraint(equalTo: group.topAnchor),
            content.leadingAnchor.constraint(equalTo: group.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: group.trailingAnchor),
            content.topAnchor.constraint(equalTo: topRule.bottomAnchor),
            content.bottomAnchor.constraint(equalTo: bottomRule.topAnchor),
            bottomRule.leadingAnchor.constraint(equalTo: group.leadingAnchor),
            bottomRule.trailingAnchor.constraint(equalTo: group.trailingAnchor),
            bottomRule.bottomAnchor.constraint(equalTo: group.bottomAnchor),
        ])
        return (group, contentHeight)
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
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -28),
        ])
        return view
    }
}
