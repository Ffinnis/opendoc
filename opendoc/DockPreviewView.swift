#if canImport(UIKit)
import UIKit

final class DockPreviewView: UIView {
    var dockOnly = false
    private let wallpaper = WallpaperView()
    private let dock = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialLight))
    private let dockScroll = UIScrollView()
    private let items = UIStackView()
    private var tilePairs: [(UUID, WidgetTile)] = []
    private let title = label("Your space. Your pace.", 29, .light, Palette.ink.withAlphaComponent(0.7))
    private let hint = label("Click a widget or shortcut to open it", 11, .regular, Palette.ink.withAlphaComponent(0.6))
    private var dockConstraints: [NSLayoutConstraint] = []
    var onItem: ((DockItem) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 20
        clipsToBounds = true
        addSubview(wallpaper)
        wallpaper.pin(to: self)
        let live = label("●  LIVE PREVIEW", 9, .semibold, Palette.accent)
        live.translatesAutoresizingMaskIntoConstraints = false
        addSubview(live)
        addSubview(title)
        addSubview(hint)
        title.translatesAutoresizingMaskIntoConstraints = false
        hint.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            live.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22), live.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            title.centerXAnchor.constraint(equalTo: centerXAnchor), title.topAnchor.constraint(equalTo: topAnchor, constant: 82),
            hint.centerXAnchor.constraint(equalTo: centerXAnchor), hint.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 9)
        ])
        dock.layer.cornerRadius = 20
        dock.clipsToBounds = true
        dock.layer.borderWidth = 1
        dock.layer.borderColor = UIColor.white.withAlphaComponent(0.65).cgColor
        addSubview(dock)
        dock.translatesAutoresizingMaskIntoConstraints = false
        dock.contentView.addSubview(dockScroll)
        dockScroll.pin(to: dock.contentView, inset: 10)
        dockScroll.showsHorizontalScrollIndicator = false
        dockScroll.showsVerticalScrollIndicator = false
        items.axis = .horizontal
        items.alignment = .center
        items.spacing = 10
        dockScroll.addSubview(items)
        items.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            items.leadingAnchor.constraint(equalTo: dockScroll.contentLayoutGuide.leadingAnchor),
            items.trailingAnchor.constraint(equalTo: dockScroll.contentLayoutGuide.trailingAnchor),
            items.topAnchor.constraint(equalTo: dockScroll.contentLayoutGuide.topAnchor),
            items.bottomAnchor.constraint(equalTo: dockScroll.contentLayoutGuide.bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ profile: DockProfile) {
        wallpaper.theme = profile.appearance.wallpaper
        dock.effect = UIBlurEffect(style: profile.appearance.material == "Dark" ? .systemMaterialDark : .systemUltraThinMaterialLight)
        dock.contentView.backgroundColor = profile.appearance.material == "Light" ? UIColor.white.withAlphaComponent(0.75) : .clear
        items.arrangedSubviews.forEach { $0.removeFromSuperview() }
        tilePairs.removeAll()
        let vertical = profile.appearance.position != "Bottom"
        items.axis = vertical ? .vertical : .horizontal
        let size = CGFloat(profile.appearance.size)
        for item in profile.items {
            let view: UIView
            if item.kind == .spacer {
                view = UIView()
                let line = UIView()
                line.backgroundColor = Palette.ink.withAlphaComponent(0.15)
                view.addSubview(line)
                line.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([line.widthAnchor.constraint(equalToConstant: vertical ? 30 : 1), line.heightAnchor.constraint(equalToConstant: vertical ? 1 : 30), line.centerXAnchor.constraint(equalTo: view.centerXAnchor), line.centerYAnchor.constraint(equalTo: view.centerYAnchor), view.widthAnchor.constraint(equalToConstant: 15), view.heightAnchor.constraint(equalToConstant: 15)])
            } else if item.kind == .widget {
                let tile = WidgetTile(item: item, compact: true)
                tile.widthAnchor.constraint(equalToConstant: vertical ? 142 : 156).isActive = true
                tile.heightAnchor.constraint(equalToConstant: max(56, size)).isActive = true
                tile.action = { [weak self] in self?.onItem?(item) }
                tilePairs.append((item.id, tile))
                view = tile
            } else {
                let icon = AppIconView(item: item, size: size)
                let control = UIControl()
                let content = stack(profile.appearance.showLabels ? [icon, label(item.title, 9, .medium)] : [icon], spacing: 4)
                content.alignment = .center
                content.isUserInteractionEnabled = false
                control.addSubview(content)
                content.pin(to: control)
                control.addAction(UIAction { [weak self] _ in self?.onItem?(item) }, for: .touchUpInside)
                control.accessibilityLabel = "Open \(item.title)"
                control.isAccessibilityElement = true
                control.accessibilityTraits = .button
                view = control
            }
            items.addArrangedSubview(view)
        }
        if profile.items.isEmpty { items.addArrangedSubview(label("Add your first shortcut or widget", 13, .medium)) }
        NSLayoutConstraint.deactivate(dockConstraints)
        if dockOnly {
            dockConstraints = [dock.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4), dock.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4), dock.topAnchor.constraint(equalTo: topAnchor, constant: 4), dock.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)]
            dockConstraints.append(vertical ? items.widthAnchor.constraint(equalTo: dockScroll.frameLayoutGuide.widthAnchor) : items.heightAnchor.constraint(equalTo: dockScroll.frameLayoutGuide.heightAnchor))
        } else if vertical {
            dockConstraints = [dock.widthAnchor.constraint(equalToConstant: 164), dock.topAnchor.constraint(equalTo: topAnchor, constant: 46), dock.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18), items.widthAnchor.constraint(equalTo: dockScroll.frameLayoutGuide.widthAnchor)]
            dockConstraints.append(profile.appearance.position == "Left" ? dock.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18) : dock.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18))
        } else {
            dockConstraints = [dock.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20), dock.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20), dock.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -22), dock.heightAnchor.constraint(equalToConstant: size + (profile.appearance.showLabels ? 40 : 24)), items.heightAnchor.constraint(equalTo: dockScroll.frameLayoutGuide.heightAnchor)]
        }
        NSLayoutConstraint.activate(dockConstraints)
        title.isHidden = vertical || dockOnly
        hint.isHidden = vertical || dockOnly
        wallpaper.isHidden = dockOnly
        subviews.compactMap { $0 as? UILabel }.forEach { $0.isHidden = dockOnly || ($0 === title && vertical) || ($0 === hint && vertical) }
        dock.alpha = profile.appearance.autoHide ? 0.2 : 1
        accessibilityHint = profile.appearance.autoHide ? "Hover over the preview to reveal the dock" : nil
        autoHide = profile.appearance.autoHide
        if gestureRecognizers?.isEmpty != false {
            addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hover(_:))))
            let tap = UITapGestureRecognizer(target: self, action: #selector(reveal))
            tap.cancelsTouchesInView = false
            addGestureRecognizer(tap)
        }
    }
    private var autoHide = false
    @objc private func hover(_ gesture: UIHoverGestureRecognizer) {
        guard autoHide else { return }
        dock.alpha = gesture.state == .ended ? 0.2 : 1
    }
    @objc private func reveal() { dock.alpha = 1 }

    func refresh(_ profile: DockProfile) {
        for (id, tile) in tilePairs {
            if let item = profile.items.first(where: { $0.id == id }) { tile.refresh(item) }
        }
    }
}

#endif
