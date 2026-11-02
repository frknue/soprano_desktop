import AppKit
import ApplicationServices
import SopranoDesktopCore

/// An opaque Folio strip over the left part of the system menu bar on every screen that
/// shows one: the frontmost app's menus redrawn in Folio at their native positions, the
/// status-item area on the right left native.
///
/// The menus come from the frontmost app's Accessibility menu bar (`AXMenuBar` →
/// `AXMenuBarItem` title, position, size); clicking a title presses the real item, so the
/// native menu opens in place under it. The strip ends a gap before the leftmost status
/// item: Quartz status windows (`kCGStatusWindowLevel`, bounds only, no Screen Recording)
/// where macOS still has them, else the apps' `AXExtrasMenuBar` items (macOS 26 hosts
/// status items in full-width windows), else 55 % of the screen. Refreshed on app
/// activation, the frontmost app's window focus changes, screen changes and a 1 s timer.
/// The panels sit one level above the main menu, on every Space, and never in a
/// fullscreen Space. Nothing runs until Accessibility is granted; `needsAccessibility`
/// says so.
@MainActor
final class FolioMenuBarController {
    static let refreshInterval: TimeInterval = 1
    /// How often the (slower) Accessibility status-item scan may run.
    static let statusScanInterval: TimeInterval = 5

    /// True while the controller is started but waits for Accessibility permission.
    private(set) var needsAccessibility = false {
        didSet {
            if needsAccessibility != oldValue { onNeedsAccessibilityChange?(needsAccessibility) }
        }
    }

    var onNeedsAccessibilityChange: (@MainActor (Bool) -> Void)?

    /// The frontmost app's menu bar as last read.
    struct MenuSnapshot: Sendable {
        var pid: pid_t
        var originX: CGFloat
        var items: [FolioMenuBarLayout.Item]
        var elements: [SendableElement]
    }

    private struct Strip {
        let panel: SurfacePanel
        let view: FolioMenuBarView
    }

    private let palette: @MainActor () -> ThemeColors
    private var strips: [CGDirectDisplayID: Strip] = [:]
    private var menu: MenuSnapshot?
    private var accessibilityStatusItems: [CGRect] = []
    private var lastStatusScan = Date.distantPast
    private var isScanningStatusItems = false
    private var isReadingMenu = false
    private var session: AXObserverSession?
    private var timer: Timer?
    private var tokens = ObserverTokens()
    private lazy var trustWatcher = AccessibilityTrustWatcher { [weak self] in self?.begin() }
    private var isStarted = false
    private var isRunning = false
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private let readQueue = DispatchQueue(label: "com.soprano.desktop.folio-menu-bar", qos: .userInitiated)

    init(palette: @escaping @MainActor () -> ThemeColors) {
        self.palette = palette
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        if AccessibilityPermission.isTrusted {
            begin()
        } else {
            needsAccessibility = true
            trustWatcher.start()
        }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        isRunning = false
        trustWatcher.stop()
        needsAccessibility = false
        tokens.removeAll()
        timer?.invalidate()
        timer = nil
        endSession()
        menu = nil
        for strip in strips.values {
            strip.panel.orderOut(nil)
            strip.panel.close()
        }
        strips.removeAll()
    }

    func themeDidChange() {
        let colors = palette()
        for strip in strips.values {
            strip.panel.backgroundColor = colors.bgBase
            strip.view.colors = colors
        }
    }

    // MARK: Refresh

    private func begin() {
        guard isStarted, !isRunning else { return }
        isRunning = true
        needsAccessibility = false
        let workspace = NSWorkspace.shared.notificationCenter
        tokens.observe(NSWorkspace.didActivateApplicationNotification, in: workspace) { [weak self] in
            self?.refresh()
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            tokens.observe(name, in: workspace) { [weak self] in
                // Apps bring and take their status items: scan again on the next refresh.
                self?.lastStatusScan = .distantPast
            }
        }
        tokens.observe(NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.lastStatusScan = .distantPast
            self?.layout()
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer?.tolerance = 0.2
        refresh()
    }

    /// Reads the frontmost app's menu bar off the main thread, then lays the strips out.
    private func refresh() {
        guard isRunning else { return }
        scanStatusItemsIfNeeded()
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier, pid != ownPID else {
            // Soprano Desktop's own menus (its settings window) stay native: reading our own
            // process through Accessibility from the main thread would deadlock.
            endSession()
            menu = nil
            layout()
            return
        }
        observeWindowFocus(of: pid)
        guard !isReadingMenu else { return }
        isReadingMenu = true
        readQueue.async { [weak self] in
            let snapshot = Self.readMenuBar(pid: pid)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isReadingMenu = false
                    guard self.isRunning else { return }
                    // A failed read of the same app (busy, timed out) keeps the last menus.
                    if let snapshot {
                        self.menu = snapshot
                    } else if self.menu?.pid != pid {
                        self.menu = nil
                    }
                    self.layout()
                }
            }
        }
    }

    /// Apps often swap menus with the focused window (an inspector, a web inspector): an
    /// observer on the frontmost app refreshes right then rather than on the next tick.
    private func observeWindowFocus(of pid: pid_t) {
        guard session?.pid != pid else { return }
        endSession()
        session = AXObserverSession(pid: pid) { [weak self] _, _ in
            self?.refresh()
        }
        if let session {
            session.add(kAXFocusedWindowChangedNotification, to: session.application)
            session.add(kAXMainWindowChangedNotification, to: session.application)
        }
    }

    private func endSession() {
        session?.invalidate()
        session = nil
    }

    nonisolated private static func readMenuBar(pid: pid_t) -> MenuSnapshot? {
        let application = AXUIElement.application(pid: pid)
        guard let menuBar = application.element(kAXMenuBarAttribute) else { return nil }
        AXUIElementSetMessagingTimeout(menuBar, 0.25)
        let originX = menuBar.position?.x ?? 0
        let children = menuBar.elements(kAXChildrenAttribute)
        guard !children.isEmpty else { return nil }
        var items: [FolioMenuBarLayout.Item] = []
        let attributes = [kAXTitleAttribute, kAXPositionAttribute, kAXSizeAttribute] as CFArray
        for child in children {
            AXUIElementSetMessagingTimeout(child, 0.25)
            var values: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(child, attributes, AXCopyMultipleAttributeOptions(rawValue: 0), &values) == .success,
                  let list = values as? [AnyObject], list.count == 3
            else { return nil }
            let title = list[0] as? String ?? ""
            var origin = CGPoint.zero
            var size = CGSize.zero
            if CFGetTypeID(list[1]) == AXValueGetTypeID() { AXValueGetValue(list[1] as! AXValue, .cgPoint, &origin) }
            if CFGetTypeID(list[2]) == AXValueGetTypeID() { AXValueGetValue(list[2] as! AXValue, .cgSize, &size) }
            items.append(FolioMenuBarLayout.Item(title: title, frame: CGRect(origin: origin, size: size)))
        }
        return MenuSnapshot(pid: pid, originX: originX, items: items, elements: children.map(SendableElement.init))
    }

    // MARK: Status items

    /// Status windows at `kCGStatusWindowLevel`, excluding the strips themselves (one level
    /// above the main menu is the same level). Bounds need no Screen Recording.
    private func quartzStatusItems() -> [CGRect] {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        return windows.compactMap { window in
            guard (window[kCGWindowLayer as String] as? Int) == statusLevel,
                  (window[kCGWindowOwnerPID as String] as? Int).map(pid_t.init) != ownPID,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary
            else { return nil }
            return CGRect(dictionaryRepresentation: bounds as CFDictionary)
        }
    }

    /// Every running app's `AXExtrasMenuBar` items, scanned off the main thread at most every
    /// `statusScanInterval` seconds, and only when Quartz reports no status windows.
    private func scanStatusItemsIfNeeded() {
        guard !isScanningStatusItems,
              Date().timeIntervalSince(lastStatusScan) >= Self.statusScanInterval,
              quartzStatusItems().isEmpty
        else { return }
        isScanningStatusItems = true
        lastStatusScan = Date()
        let pids = NSWorkspace.shared.runningApplications.map(\.processIdentifier).filter { $0 != ownPID }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let frames = Self.accessibilityStatusItems(pids: pids)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isScanningStatusItems = false
                    guard self.isRunning, frames != self.accessibilityStatusItems else { return }
                    self.accessibilityStatusItems = frames
                    self.layout()
                }
            }
        }
    }

    nonisolated private static func accessibilityStatusItems(pids: [pid_t]) -> [CGRect] {
        pids.flatMap { pid -> [CGRect] in
            let application = AXUIElement.application(pid: pid, timeout: 0.1)
            guard let extras = application.element(kAXExtrasMenuBarAttribute) else { return [] }
            AXUIElementSetMessagingTimeout(extras, 0.1)
            return extras.elements(kAXChildrenAttribute).compactMap { item in
                AXUIElementSetMessagingTimeout(item, 0.1)
                return item.frame
            }
        }
    }

    // MARK: Layout

    private func layout() {
        guard isRunning else { return }
        let primaryHeight = NSScreen.primaryHeight
        let screens = NSScreen.screens.filter { $0.menuBarHeight > 0 && $0.displayID != nil }
        let menuBars = screens.map {
            SurfaceGeometry.menuBarRect(screenFrame: $0.frame, menuBarHeight: $0.menuBarHeight, primaryScreenHeight: primaryHeight)
        }
        let quartz = quartzStatusItems()
        let widths = FolioMenuBarLayout.stripWidths(
            menuBars: menuBars,
            statusItems: quartz.isEmpty ? accessibilityStatusItems : quartz
        )

        var seen = Set<CGDirectDisplayID>()
        for (screen, width) in zip(screens, widths) {
            guard let displayID = screen.displayID else { continue }
            seen.insert(displayID)
            let strip = strips[displayID] ?? makeStrip(displayID: displayID)
            guard let menu, width >= 1 else {
                strip.panel.orderOut(nil)
                continue
            }
            let height = screen.menuBarHeight
            let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: width, height: height)
            if strip.panel.frame != frame {
                strip.panel.setFrame(frame, display: false)
            }
            strip.view.placements = FolioMenuBarLayout.placements(
                items: menu.items,
                menuBarOriginX: menu.originX,
                stripWidth: width
            )
            if !strip.panel.isVisible {
                strip.panel.orderFrontRegardless()
            }
        }
        for (displayID, strip) in strips where !seen.contains(displayID) {
            strip.panel.orderOut(nil)
            strip.panel.close()
            strips[displayID] = nil
        }
    }

    private func makeStrip(displayID: CGDirectDisplayID) -> Strip {
        let view = FolioMenuBarView(frame: .zero, colors: palette())
        let panel = SurfacePanel(contentRect: .zero)
        panel.contentView = view
        panel.isOpaque = true
        panel.backgroundColor = palette().bgBase
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        // On every Space like the menu bar, fixed in Mission Control, out of the window
        // cycle; without `.fullScreenAuxiliary` it stays out of fullscreen Spaces.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        view.onPress = { [weak self] index in self?.press(index) }
        let strip = Strip(panel: panel, view: view)
        strips[displayID] = strip
        return strip
    }

    /// Presses the native menu bar item, which opens its menu in place. `AXPress` on a menu
    /// bar item can block until the menu closes, so it runs off the main thread.
    private func press(_ index: Int) {
        guard let menu, menu.elements.indices.contains(index) else { return }
        let item = menu.elements[index]
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            AXUIElementPerformAction(item.element, kAXPressAction as CFString)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    for strip in self.strips.values where strip.view.hoveredIndex == index {
                        strip.view.hoveredIndex = nil
                    }
                }
            }
        }
    }
}
