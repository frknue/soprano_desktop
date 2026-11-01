import AppKit
import ImageIO
import SopranoDesktopCore
import UniformTypeIdentifiers

/// Renders the Folio wallpaper: the palette's paper (a soft vertical wash from `bgRaised` to
/// `bgBase` to `bgPanel`), a fine deterministic paper grain, and one accent pencil tick in
/// the lower-left corner — Folio's single sienna mark.
enum WallpaperRenderer {
    /// Bumped when the drawing changes, so new files replace cached renders.
    static let version = 1

    /// The file name for a palette at a size: macOS caches a desktop picture by URL, so every
    /// palette and size gets its own file.
    static func fileName(for palette: Palette, pixelWidth: Int, pixelHeight: Int) -> String {
        "soprano-\(palette.id)-\(pixelWidth)x\(pixelHeight)-v\(version).png"
    }

    /// Renders into `directory` unless the file is already there; returns its URL.
    static func render(
        _ palette: Palette,
        pixelWidth: Int,
        pixelHeight: Int,
        scale: Double,
        into directory: URL
    ) throws -> URL {
        let url = directory.appendingPathComponent(fileName(for: palette, pixelWidth: pixelWidth, pixelHeight: pixelHeight))
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let image = image(palette, pixelWidth: pixelWidth, pixelHeight: pixelHeight, scale: scale) else {
            throw WallpaperError.renderFailed
        }
        let staging = directory.appendingPathComponent(".\(UUID().uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(staging as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw WallpaperError.renderFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: staging)
            throw WallpaperError.renderFailed
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: staging)
        return url
    }

    static func image(_ palette: Palette, pixelWidth: Int, pixelHeight: Int, scale: Double) -> CGImage? {
        guard pixelWidth > 0, pixelHeight > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: pixelWidth,
                  height: pixelHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return nil }
        let height = CGFloat(pixelHeight)

        // Paper: lighter at the top, settling into the panel tone at the bottom.
        let top = palette.bgBase.mixed(with: palette.bgRaised, amount: palette.isLight ? 0.6 : 0.5)
        let bottom = palette.bgBase.mixed(with: palette.bgPanel, amount: 0.7)
        let gradient = CGGradient(
            colorsSpace: space,
            colors: [cgColor(top), cgColor(palette.bgBase), cgColor(bottom)] as CFArray,
            locations: [0, 0.55, 1]
        )!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: .zero, options: [])

        drawGrain(in: context, palette: palette)

        // The pencil tick: Folio's 2-pt accent rule, wallpaper-sized, lower left.
        let points = CGFloat(scale)
        let tick = CGRect(x: 72 * points, y: 64 * points, width: 3 * points, height: 28 * points)
        context.setFillColor(cgColor(palette.accent))
        context.addPath(CGPath(roundedRect: tick, cornerWidth: 1.5 * points, cornerHeight: 1.5 * points, transform: nil))
        context.fillPath()

        return context.makeImage()
    }

    /// A 512-pixel tile of monochrome specks, tiled across the image: ink specks on Paper,
    /// light specks on Ink, a few percent opaque so the paper reads as paper, not noise.
    private static func drawGrain(in context: CGContext, palette: Palette) {
        let size = 512
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let speck = palette.textPrimary
        let maxAlpha = palette.isLight ? 0.035 : 0.045
        var seed: UInt64 = 0x5050_7241_6e6f_2026
        for index in 0..<(size * size) {
            // xorshift64*: deterministic, so every render of a palette is identical.
            seed ^= seed >> 12
            seed ^= seed << 25
            seed ^= seed >> 27
            let random = Double((seed &* 0x2545_f491_4f6c_dd1d) >> 11) / Double(1 << 53)
            let alpha = random * random * maxAlpha
            let offset = index * 4
            // Premultiplied RGBA.
            pixels[offset] = UInt8((speck.red * alpha * 255).rounded())
            pixels[offset + 1] = UInt8((speck.green * alpha * 255).rounded())
            pixels[offset + 2] = UInt8((speck.blue * alpha * 255).rounded())
            pixels[offset + 3] = UInt8((alpha * 255).rounded())
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(pixels) as CFData),
              let tile = CGImage(
                  width: size,
                  height: size,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: size * 4,
                  space: space,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              )
        else { return }
        context.saveGState()
        context.interpolationQuality = .none
        context.draw(tile, in: CGRect(x: 0, y: 0, width: size, height: size), byTiling: true)
        context.restoreGState()
    }

    private static func cgColor(_ rgb: RGB) -> CGColor {
        CGColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }
}

enum WallpaperError: Error, LocalizedError {
    case renderFailed
    /// The screen no longer shows the Space the setting belongs to.
    case spaceChanged

    var errorDescription: String? {
        switch self {
        case .renderFailed: "The wallpaper could not be rendered."
        case .spaceChanged: "The screen switched Spaces; the wallpaper is left for the next sync."
        }
    }
}
