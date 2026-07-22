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
                // System Settings-style card: lighter than the window in both appearances.
                // `controlBackgroundColor` goes the wrong way in dark mode (darker than the
                // window), so the elevation is spelled out per appearance instead.
                let isDark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                layer?.backgroundColor = isDark
                    ? NSColor.white.withAlphaComponent(0.07).cgColor
                    : NSColor.white.cgColor
                layer?.borderColor = NSColor.separatorColor.withAlphaComponent(isDark ? 0.45 : 0.3).cgColor
                layer?.borderWidth = 0.5
                layer?.cornerRadius = 10
                layer?.cornerCurve = .continuous
                // Square scroll/table content must not poke past the rounded corners.
                layer?.masksToBounds = true
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
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            PreferencesPageSupport.selectionTint.setFill()
            path.fill()
        }
    }
}

enum PreferencesPageSupport {
    static let pageHorizontalInset: CGFloat = 28
    static let pageVerticalInset: CGFloat = 24
    static let pageSectionSpacing: CGFloat = 20

    /// The single leading/trailing content inset every card row shares, so text lines up
    /// down the tabs and the inset row separators start at the same edge.
    static let rowInset: CGFloat = 14
    static let selectionPillHorizontalInset: CGFloat = 8
    static let selectionPillVerticalInset: CGFloat = 3

    /// Scrawl's brand accent — the coral-red of the app icon's waveform, not orange.
    static let accentColor = NSColor(srgbRed: 0.95, green: 0.36, blue: 0.30, alpha: 1)

    /// Shared coral wash behind a selected row. Kept in one place so the History, Dictionary,
    /// and Models selection pills read identically. Strong enough to read as a deliberate
    /// selection, soft enough that black text stays comfortable on top of it.
    static var selectionTint: NSColor {
        NSColor(name: nil) { appearance in
            let alpha: CGFloat = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 0.18 : 0.12
            return accentColor.withAlphaComponent(alpha)
        }
    }

    /// Hairline color shared by every rule (row dividers, table grids).
    static var hairlineColor: NSColor {
        .separatorColor.withAlphaComponent(0.5)
    }

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

    /// A preferences page: sections stacked on the plain window background. The toolbar tab
    /// already names the page, so there is no in-page title.
    static func makePage(content: [NSView]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = pageSectionSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
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

    /// An inset rounded card with an optional section label above and caption below —
    /// the System Settings grouped-form section. Rows are separated by inset hairlines.
    static func makeGroup(header: String? = nil, footer: String? = nil, rows: [NSView]) -> NSView {
        let card = makeCard(rows: rows)
        guard header != nil || footer != nil else { return card }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 6
        if let header {
            stack.addArrangedSubview(makeSectionHeaderRow(header))
        }
        card.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        if let footer {
            stack.addArrangedSubview(makeCaptionRow(footer))
        }
        return stack
    }

    /// The bare card: rows on the elevated surface with inset separators between them.
    /// Use `makeGroup` unless the card needs custom surroundings.
    static func makeCard(rows: [NSView]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        /// `.width` alignment alone leaves a child at its natural width (right-aligned),
        /// so every row is pinned to the stack width explicitly.
        func append(_ row: NSView) {
            row.setContentHuggingPriority(.defaultLow, for: .horizontal)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        for (index, row) in rows.enumerated() {
            append(row)
            if index < rows.count - 1 {
                append(makeInsetSeparator())
            }
        }
        let card = PreferencesBackgroundView(style: .group)
        fill(card, with: stack)
        return card
    }

    /// A section label sitting above its card, indented to the card's text grid.
    static func makeSectionHeaderRow(_ title: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail

        let row = NSStackView(views: [label, NSView()])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 0
        row.edgeInsets = NSEdgeInsets(top: 0, left: rowInset, bottom: 1, right: rowInset)
        return row
    }

    /// A small secondary caption aligned to the card text grid — section footers and
    /// page intros.
    static func makeCaptionRow(_ text: String) -> NSView {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor

        let row = NSStackView(views: [label])
        row.orientation = .vertical
        row.alignment = .leading
        row.edgeInsets = NSEdgeInsets(top: 0, left: rowInset, bottom: 0, right: rowInset)
        return row
    }

    /// A card row: title (with optional help captions) on the leading edge, value and
    /// control on the trailing edge, per the grouped-form convention.
    static func makeSettingRow(
        title: String,
        detail: NSTextField,
        action: NSView? = nil,
        helpLines: [String] = []
    ) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        detail.font = .systemFont(ofSize: 13)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detail.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        // Greedy spacer pushes the value and control to the trailing edge.
        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.distribution = .fill
        header.spacing = 8
        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(spacer)
        header.addArrangedSubview(detail)
        if let action {
            header.addArrangedSubview(action)
        }

        if helpLines.isEmpty {
            header.edgeInsets = NSEdgeInsets(top: 10, left: rowInset, bottom: 10, right: rowInset)
            return header
        }

        // Help captions run full-width beneath the title line so the trailing
        // controls stay aligned with the title instead of a taller text block.
        let row = NSStackView()
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 2
        row.edgeInsets = NSEdgeInsets(top: 10, left: rowInset, bottom: 11, right: rowInset)
        row.addArrangedSubview(header)
        row.setCustomSpacing(5, after: header)
        header.widthAnchor.constraint(equalTo: row.widthAnchor, constant: -2 * rowInset).isActive = true
        for text in helpLines {
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            row.addArrangedSubview(label)
        }
        return row
    }

    /// A card row with just a title and a trailing control (popup, switch, stepper).
    static func makeSettingControlRow(title: String, control: NSView) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 8, left: rowInset, bottom: 8, right: rowInset)
        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(control)
        return row
    }

    static func makeSeparator() -> NSView {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return separator
    }

    /// A row divider that starts at the card's text grid instead of running full-bleed.
    static func makeInsetSeparator() -> NSView {
        let separator = makeSeparator()
        let row = NSView()
        row.addSubview(separator)
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: rowInset),
            separator.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -rowInset),
            separator.topAnchor.constraint(equalTo: row.topAnchor),
            separator.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])
        return row
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

    static func makeSectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        return label
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
            top: 8,
            left: leadingInset ?? rowInset,
            bottom: 8,
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

        // The outer centerY stack compresses to just its edge insets when asked for its
        // fitting height, because the buttons live in a nested stack whose height only
        // propagates as a breakable constraint. Pin the bar to at least the tallest
        // button plus insets so the footer always reserves the button's full height —
        // and stays a constant height whether the "delete" or "cancel" button is shown,
        // avoiding a resize jump when they swap.
        let verticalInset = stack.edgeInsets.top + stack.edgeInsets.bottom
        for button in leading + trailing {
            row.heightAnchor.constraint(
                greaterThanOrEqualTo: button.heightAnchor,
                constant: verticalInset
            ).isActive = true
        }
        return row
    }

    /// Minimum and maximum height of a list card's scrolling region. The view drives the
    /// exact height (via the returned constraint) to hug its content, clamped to this range.
    static let listMinHeight: CGFloat = 96
    static let listMaxHeight: CGFloat = 300

    /// A list inside a card: the scrolling table (or its empty-state message) on the
    /// elevated surface, with the page's action bar as the card's footer.
    ///
    /// Returns the card plus the list region's height constraint: the owning view sets
    /// `.constant` to the list's content height after each reload so the card hugs the last
    /// row instead of leaving a mostly-empty region. The constraint sits just below
    /// required, so a tight window can still compress it without breaking layout.
    static func makeListWorkspace(
        scrollView: NSScrollView,
        stateView: NSView,
        actionBar: NSView? = nil
    ) -> (view: NSView, heightConstraint: NSLayoutConstraint) {
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.verticalScrollElasticity = .none

        let content = NSView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stateView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scrollView)
        content.addSubview(stateView)
        let contentHeight = content.heightAnchor.constraint(equalToConstant: listMinHeight)
        contentHeight.priority = NSLayoutConstraint.Priority(999)
        NSLayoutConstraint.activate([
            contentHeight,
            content.heightAnchor.constraint(lessThanOrEqualToConstant: listMaxHeight),
            content.heightAnchor.constraint(greaterThanOrEqualToConstant: listMinHeight),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: content.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stateView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stateView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stateView.topAnchor.constraint(equalTo: content.topAnchor),
            stateView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        let card = makeCard(rows: actionBar.map { [content, $0] } ?? [content])
        return (card, contentHeight)
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
