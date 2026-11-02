import CoreGraphics
import Foundation

/// Coordinate conversion between the two global spaces macOS uses for windows.
///
/// The Accessibility API and Quartz window lists (`CGWindowListCopyWindowInfo`) use the
/// *global* space: origin at the top-left of the primary display (the one with the menu
/// bar in System Settings → Displays), y growing downwards. AppKit (`NSScreen`, `NSWindow`)
/// uses origin at the bottom-left of the same primary display, y growing upwards. Both are
/// anchored to the primary display, so one flip over its height converts every rect on
/// every display, whatever the arrangement.
public enum SurfaceGeometry {
    /// A global (top-left origin) rect in AppKit's bottom-left-origin screen space.
    public static func appKitRect(fromGlobal rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// An AppKit screen-space rect in the global (top-left origin) space.
    public static func globalRect(fromAppKit rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The menu bar of a screen (AppKit `frame`) as a global rect: the top `menuBarHeight`
    /// points of the screen.
    public static func menuBarRect(
        screenFrame: CGRect,
        menuBarHeight: CGFloat,
        primaryScreenHeight: CGFloat
    ) -> CGRect {
        let appKit = CGRect(
            x: screenFrame.minX,
            y: screenFrame.maxY - menuBarHeight,
            width: screenFrame.width,
            height: menuBarHeight
        )
        return globalRect(fromAppKit: appKit, primaryScreenHeight: primaryScreenHeight)
    }
}

/// Layout of the Folio menu bar strip: how far it reaches on each screen, and where each
/// of the frontmost app's menu titles goes so it sits exactly over the native one.
public enum FolioMenuBarLayout {
    /// Space between the strip's right edge and the leftmost status item.
    public static let statusItemGap: CGFloat = 12
    /// The strip's share of the menu bar when no status item can be found.
    public static let fallbackFraction: CGFloat = 0.55

    /// One `AXMenuBarItem` of the frontmost app: its `AXTitle` and global frame
    /// (`AXPosition` + `AXSize`).
    public struct Item: Equatable, Sendable {
        public var title: String
        public var frame: CGRect

        public init(title: String, frame: CGRect) {
            self.title = title
            self.frame = frame
        }
    }

    public enum Role: Equatable, Sendable {
        /// The first item: drawn as the Apple logo.
        case apple
        /// The second item, named after the app: drawn stronger, with the focus mark.
        case application
        /// Every other menu.
        case menu
    }

    /// Where one title goes in a strip, in the strip's own coordinates (x from its left
    /// edge). `index` is the item's position in the app's menu bar, for pressing it.
    public struct Placement: Equatable, Sendable {
        public var index: Int
        public var title: String
        public var role: Role
        public var x: CGFloat
        public var width: CGFloat

        public init(index: Int, title: String, role: Role, x: CGFloat, width: CGFloat) {
            self.index = index
            self.title = title
            self.role = role
            self.x = x
            self.width = width
        }

        public var maxX: CGFloat { x + width }
    }

    /// The strip width for each menu bar (global rects): up to the leftmost status item on
    /// that menu bar, less `gap`. Status items are only reported for some menu bars (the
    /// Accessibility API reports them on the active one), and they are right-aligned on
    /// every menu bar, so a menu bar without its own keeps the same distance from its right
    /// edge as the nearest-reaching one that has them. With no status item anywhere the
    /// strip covers `fallbackFraction` of the menu bar. Frames that span half a menu bar or
    /// more (a whole-bar host window, not an item) are ignored.
    public static func stripWidths(
        menuBars: [CGRect],
        statusItems: [CGRect],
        gap: CGFloat = statusItemGap,
        fallbackFraction: CGFloat = fallbackFraction
    ) -> [CGFloat] {
        let leftmost: [CGFloat?] = menuBars.map { bar in
            statusItems
                .filter { item in
                    item.width > 0 && item.width < bar.width / 2
                        && bar.minX <= item.midX && item.midX < bar.maxX
                        && bar.minY <= item.midY && item.midY < bar.maxY
                }
                .map(\.minX)
                .min()
        }
        let rightDistance = zip(menuBars, leftmost)
            .compactMap { bar, edge in edge.map { bar.maxX - $0 } }
            .max()
        return zip(menuBars, leftmost).map { bar, edge in
            let width: CGFloat
            if let edge {
                width = edge - gap - bar.minX
            } else if let rightDistance {
                width = bar.width - rightDistance - gap
            } else {
                width = (bar.width * fallbackFraction).rounded(.down)
            }
            return min(max(width, 0), bar.width)
        }
    }

    /// The titles to draw in a strip `stripWidth` wide, each at its native item's x
    /// relative to the app's menu bar (`menuBarOriginX`, the menu bar element's
    /// `AXPosition.x`), so the same layout lines up on every screen. Items starting at or
    /// past the strip's right edge stay native (they are not covered); one that starts
    /// inside is kept and clipped by the strip. Items without a title (other than the
    /// Apple menu) or without width are left out.
    public static func placements(
        items: [Item],
        menuBarOriginX: CGFloat,
        stripWidth: CGFloat
    ) -> [Placement] {
        items.enumerated().compactMap { index, item in
            let role: Role = switch index {
            case 0: .apple
            case 1: .application
            default: .menu
            }
            let x = item.frame.minX - menuBarOriginX
            guard item.frame.width > 0, x >= 0, x < stripWidth else { return nil }
            guard role == .apple || !item.title.isEmpty else { return nil }
            return Placement(index: index, title: item.title, role: role, x: x, width: item.frame.width)
        }
    }

    /// The placement under strip-local `x`, if any.
    public static func placement(at x: CGFloat, in placements: [Placement]) -> Placement? {
        placements.first { $0.x <= x && x < $0.maxX }
    }
}

/// Geometry and visibility of the focus border: a rule drawn just outside the focused
/// window, hugging its corners.
public enum FocusBorderGeometry {
    public static let defaultWidth: CGFloat = 2
    public static let defaultCornerRadius: CGFloat = 12
    public static let standardWindowSubrole = "AXStandardWindow"

    /// The border's own window: the focused window's frame grown by the rule width on
    /// every side, so the rule sits outside the window and never covers its content.
    public static func panelFrame(window: CGRect, width: CGFloat) -> CGRect {
        window.insetBy(dx: -width, dy: -width)
    }

    /// The path the rule is stroked along inside a border panel's bounds: the middle of
    /// the rule, half its width in from the panel edge.
    public static func strokeRect(panelBounds: CGRect, width: CGFloat) -> CGRect {
        panelBounds.insetBy(dx: width / 2, dy: width / 2)
    }

    /// The radius of that path: the window's corner radius plus half the rule, so the
    /// rule's inner edge follows the window's rounded corner.
    public static func strokeRadius(windowCornerRadius: CGFloat, width: CGFloat) -> CGFloat {
        max(windowCornerRadius, 0) + width / 2
    }

    /// What the Accessibility API reports about the frontmost app's focused window.
    public struct Window: Equatable, Sendable {
        public var pid: Int32
        public var bundleID: String?
        public var subrole: String?
        public var isFullScreen: Bool
        public var isMinimized: Bool
        /// Global (top-left origin) frame.
        public var frame: CGRect

        public init(
            pid: Int32,
            bundleID: String?,
            subrole: String?,
            isFullScreen: Bool,
            isMinimized: Bool,
            frame: CGRect
        ) {
            self.pid = pid
            self.bundleID = bundleID
            self.subrole = subrole
            self.isFullScreen = isFullScreen
            self.isMinimized = isMinimized
            self.frame = frame
        }
    }

    /// Whether the border shows around `window`: only a visible standard window of another
    /// app that is not blocked, not minimized and not fullscreen (by the `AXFullScreen`
    /// flag, or a frame exactly covering a screen, `screenFrames` in global coordinates).
    public static func showsBorder(
        around window: Window?,
        ownPID: Int32,
        blockedBundleIDs: Set<String>,
        screenFrames: [CGRect]
    ) -> Bool {
        guard let window else { return false }
        if window.pid == ownPID { return false }
        if let bundleID = window.bundleID, blockedBundleIDs.contains(bundleID) { return false }
        guard window.subrole == standardWindowSubrole else { return false }
        if window.isMinimized || window.isFullScreen { return false }
        guard window.frame.width > 0, window.frame.height > 0 else { return false }
        return !screenFrames.contains(window.frame)
    }
}
