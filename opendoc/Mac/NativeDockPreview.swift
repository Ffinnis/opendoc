#if os(macOS)
import AppKit
import QuartzCore

/// A small, static copy of a dock: the same glass, tint, corners and tiles as
/// the real shelf, drawn over a colourful backdrop so glass settings show.
/// Rebuilt only when settings change, never from pointer movement.
final class NativeDockPreview: NSView {
    private let backdrop = CAGradientLayer()
    private var material: NSView?
    private let row = FlippedNativeView()
    private var tiles: [NativeDockItemView] = []
    private var refreshTimer: Timer?
    private var content: (items: [DockItem], appearance: DockAppearance, iconSize: CGFloat, live: Bool)?
    private var laidOutWidth: CGFloat = 0
    private var colorObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        backdrop.colors = [NSColor(calibratedRed: 0.29, green: 0.52, blue: 0.96, alpha: 1).cgColor,
                           NSColor(calibratedRed: 0.55, green: 0.42, blue: 0.93, alpha: 1).cgColor,
                           NSColor(calibratedRed: 0.96, green: 0.56, blue: 0.62, alpha: 1).cgColor]
        backdrop.startPoint = CGPoint(x: 0, y: 1)
        backdrop.endPoint = CGPoint(x: 1, y: 0)
        layer?.addSublayer(backdrop)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Dock preview")
        colorObserver = NotificationCenter.default.addObserver(forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconfigureGlass() }
        }
    }

    /// Tint and edge colours follow appearance and accent changes, like the dock's.
    private func reconfigureGlass() {
        guard let material, let content else { return }
        DockGlassRoot.configure(material, appearance: content.appearance)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        reconfigureGlass()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit {
        refreshTimer?.invalidate()
        if let colorObserver { NotificationCenter.default.removeObserver(colorObserver) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshTimer?.invalidate(); refreshTimer = nil
        guard window != nil else { return }
        // Widgets in the preview tick like the dock's, at the same low rate.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                // Only while the preview can be seen: Settings keeps its window after closing.
                guard let self, let window = self.window, window.isVisible, window.occlusionState.contains(.visible),
                      !self.isHiddenOrHasHiddenAncestor else { return }
                self.tiles.forEach { $0.refreshIfNeeded(at: Date()) }
            }
        }
    }

    /// Shows `items` at `iconSize`, keeping only as many as fit the width.
    /// `live` lets data widgets fetch and run; use it only for docks already on screen.
    func show(_ items: [DockItem], appearance: DockAppearance, iconSize: CGFloat, live: Bool = true) {
        content = (items, appearance, iconSize, live)
        laidOutWidth = bounds.width
        self.appearance = appearance.material == "Dark" ? NSAppearance(named: .darkAqua) : appearance.material == "Light" ? NSAppearance(named: .aqua) : nil
        tiles.forEach { $0.removeFromSuperview() }
        let thickness = iconSize + 22
        let available = bounds.width - 32
        var shown: [DockItem] = []
        var length: CGFloat = 16
        for item in items {
            let next = NativeDockController.length(of: item, iconSize: iconSize, vertical: false) + 3
            guard length + next <= available || shown.isEmpty else { break }
            shown.append(item); length += next
        }
        let frames = NativeDockController.rowFrames(lengths: shown.map { NativeDockController.length(of: $0, iconSize: iconSize, vertical: false) },
                                                    thickness: thickness, vertical: false)
        let width = (frames.last?.maxX ?? 0) + 8
        tiles = zip(shown, frames).map { item, frame in
            let tile = NativeDockItemView(item: item, iconSize: iconSize, vertical: false, live: live)
            tile.frame = frame
            tile.setAccessibilityElement(false)
            row.addSubview(tile)
            return tile
        }
        material?.removeFromSuperview()
        let glass = DockGlassRoot.makeMaterial(containing: NSView())
        if let effect = glass as? NSVisualEffectView { effect.blendingMode = .withinWindow }
        addSubview(glass)
        material = glass
        // Configure once in the view tree, so colours resolve in the preview's appearance.
        DockGlassRoot.configure(glass, appearance: appearance, cornerRadius: NativeDockStyle.shelfRadius(iconSize: iconSize, thickness: thickness))
        row.removeFromSuperview()
        addSubview(row)
        let origin = NSPoint(x: ((bounds.width - width) / 2).rounded(), y: ((bounds.height - thickness) / 2).rounded())
        glass.frame = NSRect(origin: origin, size: NSSize(width: width, height: thickness))
        row.frame = glass.frame
        glass.shadow = {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
            shadow.shadowBlurRadius = 12
            shadow.shadowOffset = NSSize(width: 0, height: -4)
            return shadow
        }()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.frame = bounds
        CATransaction.commit()
        if let content, bounds.width != laidOutWidth { show(content.items, appearance: content.appearance, iconSize: content.iconSize, live: content.live) }
    }
}
#endif
