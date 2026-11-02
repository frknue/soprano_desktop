import AppKit
import SopranoDesktopCore

/// Folio's keyboard-focus mark around a window: one `ruleWidth` rule in `focusMark`,
/// drawn inside a border panel that is `ruleWidth` larger than the window on every side.
final class FocusBorderView: NSView {
    var colors: ThemeColors {
        didSet { needsDisplay = true }
    }

    /// The corner radius of the window the rule hugs.
    var cornerRadius: CGFloat {
        didSet { needsDisplay = true }
    }

    let ruleWidth: CGFloat

    init(
        frame: NSRect,
        colors: ThemeColors,
        cornerRadius: CGFloat = FocusBorderGeometry.defaultCornerRadius,
        ruleWidth: CGFloat = Chrome.focusMarkWidth
    ) {
        self.colors = colors
        self.cornerRadius = cornerRadius
        self.ruleWidth = ruleWidth
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let radius = FocusBorderGeometry.strokeRadius(windowCornerRadius: cornerRadius, width: ruleWidth)
        let path = NSBezierPath(
            roundedRect: FocusBorderGeometry.strokeRect(panelBounds: bounds, width: ruleWidth),
            xRadius: radius,
            yRadius: radius
        )
        path.lineWidth = ruleWidth
        colors.focusMark.setStroke()
        path.stroke()
    }
}
