import AppKit
import SopranoDesktopCore

/// `SopranoDesktop snapshot-surfaces --out <dir>`: renders the Folio menu bar strip (Finder's
/// menus) in Folio Paper and Folio Ink to PNGs at 2× — offscreen, with the same view the
/// live strip uses. Needs no permission and changes nothing.
@MainActor
enum SurfaceSnapshotCommand {
    static let usage = "Usage: SopranoDesktop snapshot-surfaces --out <dir>"

    /// The menu bar height on a current Mac without a notch.
    static let menuBarHeight: CGFloat = 30
    static let stripWidth: CGFloat = 560

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

    /// Writes `folio-menu-bar-<paper|ink>.png`.
    static func render(to directory: URL, scale: CGFloat = 2) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [URL] = []
        for (name, theme) in [("paper", AppTheme.folioPaper), ("ink", AppTheme.folioInk)] {
            let bar = directory.appendingPathComponent("folio-menu-bar-\(name).png")
            try png(of: menuBarView(colors: theme.colors), scale: scale).write(to: bar, options: .atomic)
            written.append(bar)
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
