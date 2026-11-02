import AppKit
import SopranoDesktopCore

/// The folders that get a Folio icon, each with its glyph.
enum FolioFolder: String, CaseIterable, Sendable {
    case home
    case desktop
    case documents
    case downloads

    func url(home: URL) -> URL {
        switch self {
        case .home: home
        case .desktop: home.appendingPathComponent("Desktop", isDirectory: true)
        case .documents: home.appendingPathComponent("Documents", isDirectory: true)
        case .downloads: home.appendingPathComponent("Downloads", isDirectory: true)
        }
    }
}

/// Custom folder icons (`Icon\r` inside the folder). Tests inject a fake.
@MainActor
protocol FolderIconStore: AnyObject {
    func hasCustomIcon(_ folder: URL) -> Bool
    /// nil removes the custom icon.
    func setIcon(_ folder: FolioFolder?, at url: URL) throws
}

@MainActor
final class LiveFolderIcons: FolderIconStore {
    func hasCustomIcon(_ folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent("Icon\r").path)
    }

    func setIcon(_ folder: FolioFolder?, at url: URL) throws {
        let image = folder.map { FolderIconRenderer.image(for: $0) }
        guard NSWorkspace.shared.setIcon(image, forFile: url.path, options: []) else {
            throw FolderIconError.refused(url.path)
        }
    }
}

enum FolderIconError: Error, LocalizedError {
    case refused(String)

    var errorDescription: String? {
        switch self {
        case let .refused(path): "macOS refused to change the icon of \(path)"
        }
    }
}

/// Folio folder icons in the family's icon language (`scripts/render-app-icon.swift`):
/// paper body, ink outline with round joins, an ink glyph, and exactly one sienna element
/// (the folder tab). Paper only, like the app icons: an icon has no dark-appearance slot.
enum FolderIconRenderer {
    /// Bumped when the drawing changes, so applied icons are redrawn.
    static let version = "folio-folder-1"

    private static let ink = NSColor(srgbRed: 0x2b / 255.0, green: 0x26 / 255.0, blue: 0x20 / 255.0, alpha: 1)
    private static let sheet = NSColor(srgbRed: 0xfb / 255.0, green: 0xf8 / 255.0, blue: 0xf2 / 255.0, alpha: 1)
    private static let back = NSColor(srgbRed: 0xe9 / 255.0, green: 0xe2 / 255.0, blue: 0xd4 / 255.0, alpha: 1)
    private static let mark = NSColor(srgbRed: 0xa3 / 255.0, green: 0x4a / 255.0, blue: 0x17 / 255.0, alpha: 1)
    private static let stroke: CGFloat = 40

    static func image(for folder: FolioFolder) -> NSImage {
        let image = NSImage(size: NSSize(width: 1024, height: 1024), flipped: true) { _ in
            draw(folder)
            return true
        }
        return image
    }

    /// PNG data at `pixels`, for previews.
    static func png(for folder: FolioFolder, pixels: Int) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = NSSize(width: 1024, height: 1024)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image(for: folder).draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// Top-left origin, 1024 units.
    private static func draw(_ folder: FolioFolder) {
        // Back sheet with the tab cut into its top-left.
        let backPath = NSBezierPath(roundedRect: NSRect(x: 132, y: 236, width: 760, height: 560), xRadius: 56, yRadius: 56)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        shadow.shadowBlurRadius = 24
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        back.setFill()
        backPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        // The tab: the one sienna element.
        let tab = NSBezierPath(roundedRect: NSRect(x: 172, y: 196, width: 280, height: 92), xRadius: 36, yRadius: 36)
        mark.setFill()
        tab.fill()

        outline(backPath)

        // Front sheet.
        let front = NSBezierPath(roundedRect: NSRect(x: 132, y: 324, width: 760, height: 472), xRadius: 56, yRadius: 56)
        sheet.setFill()
        front.fill()
        outline(front)

        drawGlyph(folder, center: NSPoint(x: 512, y: 560))
    }

    private static func outline(_ path: NSBezierPath, width: CGFloat = stroke) {
        ink.setStroke()
        path.lineWidth = width
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.stroke()
    }

    private static func drawGlyph(_ folder: FolioFolder, center c: NSPoint) {
        let path = NSBezierPath()
        switch folder {
        case .home:
            // Roof and walls with a door.
            path.move(to: NSPoint(x: c.x - 130, y: c.y + 10))
            path.line(to: NSPoint(x: c.x, y: c.y - 110))
            path.line(to: NSPoint(x: c.x + 130, y: c.y + 10))
            path.move(to: NSPoint(x: c.x - 96, y: c.y - 20))
            path.line(to: NSPoint(x: c.x - 96, y: c.y + 120))
            path.line(to: NSPoint(x: c.x + 96, y: c.y + 120))
            path.line(to: NSPoint(x: c.x + 96, y: c.y - 20))
            path.move(to: NSPoint(x: c.x - 30, y: c.y + 120))
            path.line(to: NSPoint(x: c.x - 30, y: c.y + 46))
            path.line(to: NSPoint(x: c.x + 30, y: c.y + 46))
            path.line(to: NSPoint(x: c.x + 30, y: c.y + 120))
        case .desktop:
            // A display on its stand.
            path.appendRoundedRect(NSRect(x: c.x - 150, y: c.y - 110, width: 300, height: 190), xRadius: 24, yRadius: 24)
            path.move(to: NSPoint(x: c.x, y: c.y + 80))
            path.line(to: NSPoint(x: c.x, y: c.y + 124))
            path.move(to: NSPoint(x: c.x - 70, y: c.y + 128))
            path.line(to: NSPoint(x: c.x + 70, y: c.y + 128))
        case .documents:
            // A page with a folded corner and three lines.
            path.move(to: NSPoint(x: c.x - 100, y: c.y - 130))
            path.line(to: NSPoint(x: c.x + 40, y: c.y - 130))
            path.line(to: NSPoint(x: c.x + 100, y: c.y - 70))
            path.line(to: NSPoint(x: c.x + 100, y: c.y + 130))
            path.line(to: NSPoint(x: c.x - 100, y: c.y + 130))
            path.close()
            for y in [c.y - 20, c.y + 30, c.y + 80] {
                path.move(to: NSPoint(x: c.x - 54, y: y))
                path.line(to: NSPoint(x: c.x + 54, y: y))
            }
        case .downloads:
            // An arrow onto a tray.
            path.move(to: NSPoint(x: c.x, y: c.y - 130))
            path.line(to: NSPoint(x: c.x, y: c.y + 50))
            path.move(to: NSPoint(x: c.x - 80, y: c.y - 30))
            path.line(to: NSPoint(x: c.x, y: c.y + 50))
            path.line(to: NSPoint(x: c.x + 80, y: c.y - 30))
            path.move(to: NSPoint(x: c.x - 130, y: c.y + 60))
            path.line(to: NSPoint(x: c.x - 130, y: c.y + 124))
            path.line(to: NSPoint(x: c.x + 130, y: c.y + 124))
            path.line(to: NSPoint(x: c.x + 130, y: c.y + 60))
        }
        outline(path, width: 36)
    }
}
