import AppKit
import SopranoDesktopCore

/// `SopranoDesktop snapshot-surfaces --out <dir>`: renders the Folio menu bar strip (Finder's
/// menus) and the focus border around a window, in Folio Paper and Folio Ink, to PNGs at
/// 2× — offscreen, with the same views the live surfaces use. Needs no permission and
/// changes nothing.
@MainActor
enum SurfaceSnapshotCommand {
    static let usage = "Usage: SopranoDesktop snapshot-surfaces --out <dir>"

    /// The menu bar height on a current Mac without a notch.
    static let menuBarHeight: CGFloat = 30
    static let stripWidth: CGFloat = 560
    static let borderCanvas = NSSize(width: 560, height: 360)
    static let fixtureWindow = NSRect(x: 80, y: 60, width: 400, height: 240)

    /// Runs the command with the arguments after its name; returns the exit status.
    static func run(arguments: [String]) -> Int32 {
        guard arguments.count == 2, arguments[0] == "--out" else {
            FileHandle.standardError.write(Data((usage + "\n").utf8))
            return 2
        }
        let directory = URL(fileURLWithPath: NSString(string: arguments[1]).expandingTildeInPath, isDirectory: true)
        do {
            try render(to: directory).forEach { print($0.path) }
            return 0
        } catch {
            FileHandle.standardError.write(Data("snapshot-surfaces: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    /// Writes `folio-menu-bar-<paper|ink>.png` and `focus-border-<paper|ink>.png`.
    static func render(to directory: URL, scale: CGFloat = 2) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [URL] = []
        for (name, theme) in [("paper", AppTheme.folioPaper), ("ink", AppTheme.folioInk)] {
            let bar = directory.appendingPathComponent("folio-menu-bar-\(name).png")
            try png(of: menuBarView(colors: theme.colors), scale: scale).write(to: bar, options: .atomic)
            let border = directory.appendingPathComponent("focus-border-\(name).png")
            try png(of: focusBorderScene(colors: theme.colors), scale: scale).write(to: border, options: .atomic)
            written += [bar, border]
        }
        return written
    }

    /// Finder's menu bar as the Accessibility API reports it: the Apple menu 34 pt wide at
    /// x 10, then each title 20 pt wider than its text, neighbours overlapping by 1 pt.
    static func finderItems() -> [FolioMenuBarLayout.Item] {
        let titles = ["Apple", "Finder", "File", "Edit", "View", "Go", "Window", "Help"]
        var x: CGFloat = 10
        return titles.enumerated().map { index, title in
            let width: CGFloat = switch index {
            case 0: 34
            case 1: textWidth(title, font: FolioMenuBarView.applicationFont) + 20
            default: textWidth(title, font: FolioMenuBarView.titleFont) + 20
            }
            defer { x += width - 1 }
            return FolioMenuBarLayout.Item(title: title, frame: CGRect(x: x, y: 0, width: width, height: menuBarHeight))
        }
    }

    static func menuBarView(colors: ThemeColors) -> FolioMenuBarView {
        let view = FolioMenuBarView(frame: NSRect(x: 0, y: 0, width: stripWidth, height: menuBarHeight), colors: colors)
        view.placements = FolioMenuBarLayout.placements(items: finderItems(), menuBarOriginX: 0, stripWidth: stripWidth)
        return view
    }

    /// A desktop (`bgPanel`) with one window card (`bgBase`, hairline edge, panel radius)
    /// and the focus border view at the frame the live border panel would take.
    static func focusBorderScene(colors: ThemeColors) -> NSView {
        let scene = SnapshotDesktopView(frame: NSRect(origin: .zero, size: borderCanvas), colors: colors, windowFrame: fixtureWindow)
        let border = FocusBorderView(frame: .zero, colors: colors)
        border.frame = FocusBorderGeometry.panelFrame(window: fixtureWindow, width: border.ruleWidth)
        scene.addSubview(border)
        return scene
    }

    private static func textWidth(_ title: String, font: NSFont) -> CGFloat {
        ceil(NSAttributedString(string: title, attributes: [.font: font]).size().width)
    }

    /// `view` drawn offscreen at `scale` pixels per point.
    static func bitmap(of view: NSView, scale: CGFloat) throws -> NSBitmapImageRep {
        let size = view.bounds.size
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { throw SnapshotError.renderFailed }
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    private static func png(of view: NSView, scale: CGFloat) throws -> Data {
        guard let data = try bitmap(of: view, scale: scale).representation(using: .png, properties: [:]) else {
            throw SnapshotError.renderFailed
        }
        return data
    }

    enum SnapshotError: LocalizedError {
        case renderFailed
        var errorDescription: String? { "could not render the surface" }
    }
}

/// The backdrop of the focus-border snapshot: desktop and one window, from tokens only.
private final class SnapshotDesktopView: NSView {
    private let colors: ThemeColors
    private let windowFrame: NSRect

    init(frame: NSRect, colors: ThemeColors, windowFrame: NSRect) {
        self.colors = colors
        self.windowFrame = windowFrame
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        colors.bgPanel.setFill()
        bounds.fill()
        let radius = FocusBorderGeometry.defaultCornerRadius
        let card = NSBezierPath(roundedRect: windowFrame.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        colors.bgBase.setFill()
        card.fill()
        colors.borderSubtle.setStroke()
        card.lineWidth = Chrome.hairline
        card.stroke()
    }
}
