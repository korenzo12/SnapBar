import AppKit

/// One thumbnail card in the grid, with a selection ring and hover state.
final class ShotItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ShotItem")

    private(set) var shotID: UUID?
    private let card = NSView()
    private let thumb = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let star = NSImageView()
    private var hovering = false
    private var trackingArea: NSTrackingArea?

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("HH:mm")
        return f
    }()

    static func itemSize(for size: Double) -> NSSize {
        NSSize(width: size, height: (size * 0.64).rounded() + 44)
    }

    override func loadView() {
        let root = HoverView()
        root.onHover = { [weak self] inside in
            self?.hovering = inside
            self?.updateAppearance()
        }
        view = root

        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.cornerCurve = .continuous
        card.translatesAutoresizingMaskIntoConstraints = false

        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 6
        thumb.layer?.masksToBounds = true
        thumb.translatesAutoresizingMaskIntoConstraints = false
        for axis in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
            thumb.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: axis)
            thumb.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: axis)
        }

        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        star.image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: String(localized: "Favorite"))
        star.contentTintColor = .systemYellow
        star.translatesAutoresizingMaskIntoConstraints = false
        star.isHidden = true

        root.addSubview(card)
        card.addSubview(thumb)
        card.addSubview(titleLabel)
        card.addSubview(subtitleLabel)
        card.addSubview(star)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            card.topAnchor.constraint(equalTo: root.topAnchor),
            card.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            thumb.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 6),
            thumb.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -6),
            thumb.topAnchor.constraint(equalTo: card.topAnchor, constant: 6),
            thumb.bottomAnchor.constraint(equalTo: titleLabel.topAnchor, constant: -6),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -6),
            star.topAnchor.constraint(equalTo: thumb.topAnchor, constant: 5),
            star.trailingAnchor.constraint(equalTo: thumb.trailingAnchor, constant: -5),
            star.widthAnchor.constraint(equalToConstant: 15),
            star.heightAnchor.constraint(equalToConstant: 15),
        ])
        updateAppearance()
    }

    #if DEBUG
    var debugHasImage: Bool { thumb.image != nil }
    #endif

    override var isSelected: Bool {
        didSet { updateAppearance() }
    }

    override var highlightState: NSCollectionViewItem.HighlightState {
        didSet { updateAppearance() }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateAppearance()
    }

    func configure(shot: Shot, size: Double) {
        let sameShot = shotID == shot.id
        shotID = shot.id
        titleLabel.stringValue = shot.appName ?? shot.fileName
        var parts = [ShotItem.timeFormatter.string(from: shot.createdAt)]
        if shot.pixelWidth > 0 { parts.append("\(shot.pixelWidth)×\(shot.pixelHeight)") }
        subtitleLabel.stringValue = parts.joined(separator: "  ·  ")
        star.isHidden = !shot.favorite
        view.toolTip = shot.fileName
        view.setAccessibilityLabel(shot.appName ?? shot.fileName)
        let bucket = ThumbnailCache.bucket(forPoints: CGFloat(size))
        if let cached = ThumbnailCache.shared.cached(shot.id, size: bucket) {
            thumb.image = cached
            return
        }
        if !sameShot { thumb.image = nil }
        let id = shot.id
        ThumbnailCache.shared.thumbnail(for: shot, size: bucket) { [weak self] image in
            guard let self, self.shotID == id else { return }
            self.thumb.image = image
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        shotID = nil
        thumb.image = nil
        hovering = false
    }

    private func updateAppearance() {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            let selected = isSelected || highlightState == .forSelection
            let accent = NSColor.controlAccentColor
            if selected {
                card.layer?.backgroundColor = accent.withAlphaComponent(0.16).cgColor
                card.layer?.borderColor = accent.cgColor
                card.layer?.borderWidth = 2
            } else {
                card.layer?.backgroundColor = hovering ? NSColor.labelColor.withAlphaComponent(0.06).cgColor : NSColor.clear.cgColor
                card.layer?.borderColor = NSColor.clear.cgColor
                card.layer?.borderWidth = 0
            }
            thumb.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
        }
    }
}

/// Root view of a grid card that reports hover.
final class HoverView: NSView {
    var onHover: ((Bool) -> Void)?
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let new = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                 owner: self, userInfo: nil)
        addTrackingArea(new)
        area = new
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

/// Pinned day header: "Today", "Yesterday", or the full date, with a count.
final class SectionHeader: NSVisualEffectView, NSCollectionViewElement {
    static let identifier = NSUserInterfaceItemIdentifier("SectionHeader")

    private let title = NSTextField(labelWithString: "")
    private let count = NSTextField(labelWithString: "")
    private var sectionID: String?

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        // The user's region may prefer the Hebrew calendar; screenshots are filed by ordinary dates.
        f.calendar = Calendar(identifier: .gregorian)
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMMy")
        return f
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .headerView
        blendingMode = .withinWindow
        state = .followsWindowActiveState
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        count.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        count.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, count])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 26),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(section: ShotSection?) {
        sectionID = section?.id
        title.stringValue = SectionHeader.title(for: section?.day)
        count.stringValue = "\(section?.shots.count ?? 0)"
    }

    func refreshCount(_ sections: [String: ShotSection]) {
        guard let id = sectionID, let section = sections[id] else { return }
        count.stringValue = "\(section.shots.count)"
    }

    static func title(for day: Date?, now: Date = Date(), calendar: Calendar = .snapbar) -> String {
        guard let day else { return String(localized: "All Screenshots") }
        if calendar.isDate(day, inSameDayAs: now) { return String(localized: "Today") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return String(localized: "Yesterday")
        }
        return dayFormatter.string(from: day)
    }
}
