import AppKit
import ScreenSaver

/// The Folio screen saver: a large New York clock and the date on Folio paper (Paper in
/// light mode, Ink in dark), with the family's one sienna pencil tick beside the time. The
/// block drifts a step every minute against burn-in.
///
/// Low CPU by construction: the host ticks once a second (`animationTimeInterval`), each
/// tick only compares the current face with the one on screen, and the view redraws only
/// when the minute, the text (time zone, locale) or the appearance changed.
///
/// Built by `scripts/build-saver.sh` together with Soprano's vendored `Theme.swift`,
/// `NSColor+Hex.swift` and `Chrome.swift` (colours and fonts from the single source) and
/// Core's `SaverClock.swift`. The Objective-C name is the bundle's `NSPrincipalClass`.
@objc(SopranoSaverView)
final class SopranoSaverView: ScreenSaverView {
    private let clock = SaverClock()
    /// The face last drawn; nil until the first draw.
    private var shownFace: SaverFace?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        animationTimeInterval = 1
    }

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }
    override var isOpaque: Bool { true }

    override func animateOneFrame() {
        if clock.face(at: Date()) != shownFace {
            needsDisplay = true
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let face = clock.face(at: Date())
        shownFace = face
        let colors = AppTheme.theme(
            for: AppTheme.folioId,
            appearance: AppTheme.Appearance(effectiveAppearance)
        ).colors

        colors.bgBase.setFill()
        bounds.fill()

        let layout = SaverLayout(canvas: bounds.size, metaSize: ChromeFont.meta.pointSize)
        let timeFont = ChromeFont.serif(size: layout.timeSize, weight: .light, tabular: true)
        let dateFont = ChromeFont.sans(size: layout.dateSize)
        let time = NSAttributedString(string: face.time, attributes: [
            .font: timeFont,
            .foregroundColor: colors.textPrimary,
        ])
        let date = NSAttributedString(string: face.date, attributes: [
            .font: dateFont,
            .foregroundColor: colors.textMuted,
        ])

        // The block runs from the date's descender up to the time's capitals; the tick
        // and the text share its left edge.
        let textLeft = SaverLayout.tickWidth + layout.tickGap
        let dateDescent = -dateFont.descender
        let height = timeFont.capHeight + layout.lineGap + dateFont.capHeight + dateDescent
        let width = textLeft + max(time.size().width, date.size().width)
        let origin = layout.blockOrigin(block: CGSize(width: width, height: height), minute: face.minute)

        let dateBaseline = origin.y + dateDescent
        let timeBaseline = dateBaseline + dateFont.capHeight + layout.lineGap
        // `draw(at:)` places the line's lower-left corner, which sits a descender below
        // the baseline.
        date.draw(at: NSPoint(x: origin.x + textLeft, y: dateBaseline + dateFont.descender))
        time.draw(at: NSPoint(x: origin.x + textLeft, y: timeBaseline + timeFont.descender))

        colors.pencilTick.setFill()
        NSRect(
            x: origin.x,
            y: timeBaseline,
            width: SaverLayout.tickWidth,
            height: timeFont.capHeight.rounded()
        ).fill()
    }
}
