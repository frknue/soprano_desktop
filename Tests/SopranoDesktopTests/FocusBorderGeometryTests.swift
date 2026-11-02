import AppKit
import Testing
@testable import SopranoDesktop
@testable import SopranoDesktopCore

struct FocusBorderGeometryTests {
    /// A 1440×900 primary display (global origin) as AppKit reports it.
    let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func aWindowOnADisplayStackedAboveThePrimaryLandsOnThatDisplayInAppKit() {
        // A 1920×1080 display above the primary: AppKit puts it at y 900, the
        // Accessibility API (top-left origin) at y -1080.
        let upper = CGRect(x: 0, y: 900, width: 1920, height: 1080)
        #expect(SurfaceGeometry.globalRect(fromAppKit: upper, primaryScreenHeight: primary.height)
            == CGRect(x: 0, y: -1080, width: 1920, height: 1080))

        let window = CGRect(x: 100, y: -1000, width: 400, height: 300)
        let appKit = SurfaceGeometry.appKitRect(fromGlobal: window, primaryScreenHeight: primary.height)
        #expect(appKit == CGRect(x: 100, y: 1600, width: 400, height: 300))
        #expect(upper.contains(appKit))
        #expect(SurfaceGeometry.globalRect(fromAppKit: appKit, primaryScreenHeight: primary.height) == window)
    }

    @Test func aWindowOnADisplayBesideThePrimaryKeepsItsXAndFlipsOverThePrimaryHeight() {
        // A taller 1920×1080 display to the right, bottoms aligned: its top sits 180 pt
        // above the primary's, so global y starts at -180.
        let right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        #expect(SurfaceGeometry.globalRect(fromAppKit: right, primaryScreenHeight: primary.height)
            == CGRect(x: 1440, y: -180, width: 1920, height: 1080))

        let window = CGRect(x: 1500, y: -100, width: 800, height: 600)
        let appKit = SurfaceGeometry.appKitRect(fromGlobal: window, primaryScreenHeight: primary.height)
        #expect(appKit == CGRect(x: 1500, y: 400, width: 800, height: 600))
        #expect(right.contains(appKit))

        // A window at the very top of the primary sits under its top edge in AppKit.
        let top = SurfaceGeometry.appKitRect(fromGlobal: CGRect(x: 0, y: 0, width: 200, height: 100), primaryScreenHeight: 900)
        #expect(top.maxY == 900)
    }

    @Test func theRuleSitsOutsideTheWindowAndFollowsItsRoundedCorners() {
        let window = CGRect(x: 100, y: 200, width: 800, height: 600)
        let panel = FocusBorderGeometry.panelFrame(window: window, width: 2)
        #expect(panel == CGRect(x: 98, y: 198, width: 804, height: 604))

        let bounds = CGRect(origin: .zero, size: panel.size)
        let stroke = FocusBorderGeometry.strokeRect(panelBounds: bounds, width: 2)
        // The rule's inner edge (stroke path minus half the width) is the window's edge.
        #expect(stroke.insetBy(dx: 1, dy: 1).size == window.size)
        #expect(FocusBorderGeometry.strokeRadius(windowCornerRadius: 12, width: 2) == 13)
    }

    @Test func onlyAVisibleStandardWindowOfAnotherUnblockedAppGetsABorder() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        let window = FocusBorderGeometry.Window(
            pid: 42, bundleID: "com.apple.finder", subrole: "AXStandardWindow",
            isFullScreen: false, isMinimized: false, frame: CGRect(x: 100, y: 100, width: 600, height: 400)
        )
        func shows(_ window: FocusBorderGeometry.Window?, blocked: Set<String> = []) -> Bool {
            FocusBorderGeometry.showsBorder(around: window, ownPID: 7, blockedBundleIDs: blocked, screenFrames: screens)
        }

        #expect(shows(window))
        #expect(!shows(nil))
        #expect(!shows(window, blocked: ["com.apple.finder"]))
        var own = window
        own.pid = 7
        #expect(!shows(own))
        var dialog = window
        dialog.subrole = "AXDialog"
        #expect(!shows(dialog))
        var minimized = window
        minimized.isMinimized = true
        #expect(!shows(minimized))
        var fullscreen = window
        fullscreen.isFullScreen = true
        #expect(!shows(fullscreen))
        var coveringScreen = window
        coveringScreen.frame = screens[0]
        #expect(!shows(coveringScreen))
    }

    @MainActor
    @Test func theBorderIsDrawnInTheAccentJustOutsideTheWindowAndNowhereElse() throws {
        for theme in [AppTheme.folioPaper, AppTheme.folioInk] {
            let colors = theme.colors
            let scene = SurfaceSnapshotCommand.focusBorderScene(colors: colors)
            let bitmap = try SurfaceSnapshotCommand.bitmap(of: scene, scale: 1)
            let window = SurfaceSnapshotCommand.fixtureWindow
            let height = scene.bounds.height
            // Bitmap rows run top-down.
            func pixel(_ x: CGFloat, _ y: CGFloat) -> NSColor {
                bitmap.colorAt(x: Int(x), y: Int(height - 1 - y))!
            }
            #expect(matches(pixel(window.minX - 1, window.midY), colors.focusMark))
            #expect(matches(pixel(window.maxX, window.midY), colors.focusMark))
            #expect(matches(pixel(window.midX, window.maxY), colors.focusMark))
            #expect(matches(pixel(window.midX, window.midY), colors.bgBase))
            #expect(matches(pixel(window.minX - 6, window.midY), colors.bgPanel))
        }
    }
}

/// Whether two colours match to within rounding, compared in sRGB.
func matches(_ lhs: NSColor, _ rhs: NSColor, tolerance: CGFloat = 0.03) -> Bool {
    guard let a = lhs.usingColorSpace(.sRGB), let b = rhs.usingColorSpace(.sRGB) else { return false }
    return abs(a.redComponent - b.redComponent) <= tolerance
        && abs(a.greenComponent - b.greenComponent) <= tolerance
        && abs(a.blueComponent - b.blueComponent) <= tolerance
}
