#if canImport(UIKit)
import UIKit

enum Palette {
    static let background = UIColor(hex: 0xF8F9F6)
    static let sidebar = UIColor(hex: 0xF0F2EC)
    static let ink = UIColor(hex: 0x202C25)
    static let secondary = UIColor(hex: 0x758076)
    static let accent = UIColor(hex: 0x446B4F)
    static let line = UIColor(hex: 0xE1E6DF)
    static func color(_ name: String) -> UIColor {
        switch name {
        case "blue": UIColor(hex: 0x438FE6)
        case "orange": UIColor(hex: 0xD99052)
        case "purple": UIColor(hex: 0x8D7AB6)
        case "ink": ink
        case "gray": secondary
        default: accent
        }
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

func label(_ text: String, _ size: CGFloat = 14, _ weight: UIFont.Weight = .regular,
           _ color: UIColor = Palette.ink) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: size, weight: weight))
    label.adjustsFontForContentSizeCategory = true
    label.textColor = color
    label.numberOfLines = 0
    return label
}

func stack(_ views: [UIView] = [], axis: NSLayoutConstraint.Axis = .vertical, spacing: CGFloat = 12) -> UIStackView {
    let stack = UIStackView(arrangedSubviews: views)
    stack.axis = axis
    stack.spacing = spacing
    return stack
}

func symbol(_ name: String, size: CGFloat = 18, color: UIColor = Palette.accent) -> UIImageView {
    let image = UIImageView(image: UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .medium)))
    image.tintColor = color
    image.contentMode = .scaleAspectFit
    image.setContentHuggingPriority(.required, for: .horizontal)
    return image
}

func button(_ title: String, symbol name: String? = nil, filled: Bool = false, action: @escaping () -> Void) -> UIButton {
    var configuration = filled ? UIButton.Configuration.filled() : UIButton.Configuration.plain()
    configuration.title = title
    configuration.image = name.flatMap { UIImage(systemName: $0) }
    configuration.imagePadding = 8
    configuration.baseBackgroundColor = Palette.accent
    configuration.baseForegroundColor = filled ? .white : Palette.ink
    configuration.cornerStyle = .medium
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
        var result = incoming
        result.font = .systemFont(ofSize: 13, weight: .semibold)
        return result
    }
    let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
    button.isPointerInteractionEnabled = true
    return button
}

extension UIView {
    func pin(to parent: UIView, inset: CGFloat = 0) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
            trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
            topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
            bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)
        ])
    }

    func rounded(_ radius: CGFloat = 16, color: UIColor = .white, border: Bool = true) {
        backgroundColor = color
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
        layer.borderWidth = border ? 1 : 0
        layer.borderColor = Palette.line.cgColor
    }

    func padded(_ inset: CGFloat = 18) -> UIView {
        let container = UIView()
        container.addSubview(self)
        pin(to: container, inset: inset)
        return container
    }
}

final class AppIconView: UIView {
    init(item: DockItem, size: CGFloat = 48) {
        super.init(frame: .zero)
        rounded(size * 0.24, color: Palette.color(item.color), border: false)
        let icon = symbol(item.symbol, size: size * 0.48, color: .white)
        addSubview(icon)
        icon.pin(to: self, inset: size * 0.22)
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: size), heightAnchor.constraint(equalToConstant: size)])
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowOffset = CGSize(width: 0, height: 3)
        layer.shadowRadius = 5
        isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Original vector wallpaper, drawn locally without bundled third-party artwork.
final class WallpaperView: UIView {
    var theme = "Meadow" { didSet { setNeedsDisplay() } }
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let colors: [UIColor]
        switch theme {
        case "Dusk": colors = [UIColor(hex: 0xECD9CC), UIColor(hex: 0xBCA5BD), UIColor(hex: 0x7E89A3)]
        case "Ocean": colors = [UIColor(hex: 0xE0EBF0), UIColor(hex: 0x9DBECA), UIColor(hex: 0x618596)]
        default: colors = [UIColor(hex: 0xEDF0DF), UIColor(hex: 0xC5D5B8), UIColor(hex: 0x88A593)]
        }
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: [0, 0.5, 1])!
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: rect.width * 0.8, y: rect.height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        for index in 0..<5 {
            let y = rect.height * (0.32 + CGFloat(index) * 0.13)
            let path = UIBezierPath()
            path.move(to: CGPoint(x: -40, y: y + 70))
            path.addCurve(to: CGPoint(x: rect.width + 60, y: y - 50), controlPoint1: CGPoint(x: rect.width * 0.38, y: y - 180), controlPoint2: CGPoint(x: rect.width * 0.62, y: y + 190))
            path.addLine(to: CGPoint(x: rect.width + 60, y: rect.height + 40))
            path.addLine(to: CGPoint(x: -40, y: rect.height + 40))
            path.close()
            colors[index % colors.count].withAlphaComponent(0.16 + CGFloat(index) * 0.06).setFill()
            path.fill()
        }
        let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [UIColor.white.withAlphaComponent(0.55).cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
        context.drawRadialGradient(glow, startCenter: CGPoint(x: rect.width * 0.75, y: 20), startRadius: 0, endCenter: CGPoint(x: rect.width * 0.75, y: 20), endRadius: rect.width * 0.7, options: [])
    }
}

final class WidgetTile: UIControl {
    let kind: WidgetKind
    private let value = UILabel()
    private let subtitle = UILabel()
    private let badge = UIImageView()
    private var item: DockItem
    var action: (() -> Void)?
    private let compact: Bool

    init(item: DockItem, compact: Bool = false) {
        self.item = item
        self.kind = item.widget ?? .clock
        self.compact = compact
        super.init(frame: .zero)
        rounded(compact ? 12 : 14, color: kind == .note ? UIColor(hex: 0xF1E6A8) : UIColor.white.withAlphaComponent(0.86), border: false)
        badge.image = UIImage(systemName: kind.symbol)
        badge.tintColor = kind == .focus ? UIColor(hex: 0xC67A3A) : Palette.accent
        badge.contentMode = .scaleAspectFit
        badge.widthAnchor.constraint(equalToConstant: compact ? 22 : 26).isActive = true
        value.font = .monospacedDigitSystemFont(ofSize: compact ? 19 : 27, weight: .medium)
        value.textColor = Palette.ink
        value.adjustsFontSizeToFitWidth = true
        value.minimumScaleFactor = 0.6
        subtitle.font = .systemFont(ofSize: compact ? 10 : 11)
        subtitle.textColor = Palette.secondary
        let text = stack([value, subtitle], spacing: compact ? 3 : 6)
        let row = stack([badge, text], axis: .horizontal, spacing: 12)
        row.isUserInteractionEnabled = false
        addSubview(row)
        row.pin(to: self, inset: compact ? 12 : 18)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        isAccessibilityElement = true
        accessibilityTraits = .button
        refresh(item)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func tapped() { action?() }

    func refresh(_ item: DockItem) {
        self.item = item
        let now = Date()
        switch kind {
        case .clock:
            value.text = now.formatted(date: .omitted, time: .shortened)
            subtitle.text = "Local time"
        case .worldClock:
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            formatter.timeZone = TimeZone(identifier: item.timeZone)
            value.text = formatter.string(from: now)
            subtitle.text = item.timeZone.split(separator: "/").last?.replacingOccurrences(of: "_", with: " ")
        case .calendar:
            value.text = now.formatted(.dateTime.day().month(.abbreviated))
            subtitle.text = now.formatted(.dateTime.weekday(.wide))
        case .focus, .stopwatch:
            let seconds = Int(item.timerValue())
            value.text = String(format: "%02d:%02d", seconds / 60, seconds % 60)
            subtitle.text = item.startedAt == nil ? kind.title : (kind == .focus && seconds == 0 ? "Session complete" : "Running")
        case .note:
            value.font = .systemFont(ofSize: compact ? 12 : 16, weight: .medium)
            value.numberOfLines = 2
            value.text = item.note.isEmpty ? "Write a thought…" : item.note
            subtitle.text = "Sticky note"
        case .reminders:
            value.text = "\(item.checklist.filter { !$0.done }.count) tasks"
            subtitle.text = item.checklist.first(where: { !$0.done })?.text ?? "A clear list"
        case .hydration:
            value.text = "\(item.dailyCount) / 8"
            subtitle.text = "Glasses today"
        case .battery:
            let level = UIDevice.current.batteryLevel
            value.text = level < 0 ? "—" : "\(Int(level * 100))%"
            subtitle.text = level < 0 ? "Unavailable on this device" : "Battery"
        case .countdown:
            let seconds = max(0, Int((item.deadline ?? now).timeIntervalSince(now)))
            value.text = seconds >= 86400 ? "\(seconds / 86400)d \((seconds % 86400) / 3600)h" : String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
            subtitle.text = item.title == kind.title ? "Until your next moment" : item.title
        case .cpu, .memory, .webValue:
            value.text = "Mac widget"
            subtitle.text = "Available in Open Doc for Mac"
        case .custom:
            value.font = .systemFont(ofSize: compact ? 15 : 23, weight: .medium)
            value.text = item.note
            subtitle.text = item.title
        }
        accessibilityLabel = "\(kind.title), \(value.text ?? ""), \(subtitle.text ?? "")"
        accessibilityHint = "Open widget"
    }
}

#endif
