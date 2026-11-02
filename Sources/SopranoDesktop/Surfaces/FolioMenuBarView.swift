import AppKit
import SopranoDesktopCore

/// The Folio menu bar strip: paper (`bgBase`) with a `borderSubtle` hairline along the
/// bottom, the frontmost app's menu titles in ink at their native positions, the Apple
/// menu as the `apple.logo` symbol, and the app's name in medium weight with the 2-pt
/// focus mark under it. Clicking a title reports its menu-bar index.
final class FolioMenuBarView: NSView {
    /// Menu-bar text size, as the native menu bar.
    static let titleSize: CGFloat = 13
    static var titleFont: NSFont { ChromeFont.row }
    static var applicationFont: NSFont { ChromeFont.sans(size: titleSize, weight: .medium) }
    static let appleSymbolSize: CGFloat = 14
    /// Gap between a title and the focus mark under it.
    private static let markGap: CGFloat = 4
    /// Vertical inset of the hover pill from the strip's edges.
    private static let pillInset: CGFloat = 4

    var colors: ThemeColors {
        didSet { needsDisplay = true }
    }

    var placements: [FolioMenuBarLayout.Placement] = [] {
        didSet {
            guard placements != oldValue else { return }
            if let hovered = hoveredIndex, !placements.contains(where: { $0.index == hovered }) {
                hoveredIndex = nil
            }
            needsDisplay = true
        }
    }

    /// Called with the menu-bar index of the clicked title.
    var onPress: ((Int) -> Void)?

    /// The title under the pointer, or the one whose menu was just opened.
    var hoveredIndex: Int? {
        didSet {
            if hoveredIndex != oldValue { needsDisplay = true }
        }
    }

    init(frame: NSRect, colors: ThemeColors) {
        self.colors = colors
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isOpaque: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        colors.bgBase.setFill()
        bounds.fill()
        colors.borderSubtle.setFill()
        NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: Chrome.hairline).fill()

        let band = NSRect(x: bounds.minX, y: bounds.minY + Chrome.hairline, width: bounds.width, height: bounds.height - Chrome.hairline)
        for placement in placements {
            let item = NSRect(x: placement.x, y: band.minY, width: placement.width, height: band.height)
            if placement.index == hoveredIndex {
                ChromeSelectionPill.draw(.hover, in: item.insetBy(dx: 0, dy: Self.pillInset), colors: colors, inset: 0)
            }
            switch placement.role {
            case .apple:
                drawAppleLogo(centeredIn: item)
            case .application:
                let text = drawTitle(placement.title, font: Self.applicationFont, centeredIn: item)
                drawFocusMark(under: text)
            case .menu:
                drawTitle(placement.title, font: Self.titleFont, centeredIn: item)
            }
        }
    }

    @discardableResult
    private func drawTitle(_ title: String, font: NSFont, centeredIn item: NSRect) -> NSRect {
        let string = NSAttributedString(string: title, attributes: [
            .font: font,
            .foregroundColor: colors.textPrimary,
        ])
        let size = string.size()
        // Centre the capitals on the band: draw(at:) puts the baseline `-descender` above
        // the origin.
        let baseline = item.midY - font.capHeight / 2
        let origin = NSPoint(
            x: (item.midX - size.width / 2).rounded(),
            y: (baseline + font.descender).rounded()
        )
        string.draw(at: origin)
        return NSRect(origin: origin, size: size)
    }

    private func drawAppleLogo(centeredIn item: NSRect) {
        let configuration = NSImage.SymbolConfiguration(pointSize: Self.appleSymbolSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [colors.textPrimary]))
        guard let symbol = NSImage(systemSymbolName: "apple.logo", accessibilityDescription: "Apple")?
            .withSymbolConfiguration(configuration)
        else { return }
        let size = symbol.size
        let rect = NSRect(
            x: (item.midX - size.width / 2).rounded(),
            y: (item.midY - size.height / 2).rounded(),
            width: size.width,
            height: size.height
        )
        symbol.draw(in: rect)
    }

    /// The focus mark: a 2-pt accent rule along the bottom of the strip, as wide as the
    /// title above it.
    private func drawFocusMark(under text: NSRect) {
        let rule = NSRect(
            x: text.minX,
            y: bounds.minY,
            width: text.width,
            height: Chrome.focusMarkWidth
        )
        colors.focusMark.setFill()
        NSBezierPath(roundedRect: rule, xRadius: Chrome.focusMarkWidth / 2, yRadius: Chrome.focusMarkWidth / 2).fill()
    }

    // MARK: Input

    override func mouseDown(with event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        guard let placement = FolioMenuBarLayout.placement(at: x, in: placements) else { return }
        hoveredIndex = placement.index
        onPress?(placement.index)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        hoveredIndex = FolioMenuBarLayout.placement(at: x, in: placements)?.index
    }

    override func mouseExited(with event: NSEvent) {
        hoveredIndex = nil
    }
}
