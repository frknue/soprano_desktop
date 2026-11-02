import AppKit
import ApplicationServices
import SopranoDesktopCore

/// Draws Folio's keyboard-focus mark — a 2-pt accent rule — around the focused window of
/// the frontmost app, like JankyBorders.
///
/// The window is tracked through the Accessibility API: an `AXObserver` on the frontmost
/// app for focused/main-window changes, and on the focused window for move, resize,
/// minimize and destroy; `NSWorkspace` activation and Space changes re-target it. The rule
/// lives in one click-through, non-activating panel at `.floating` level, faded in and out
/// in 120 ms (opacity only, none under Reduce Motion). Nothing runs until Accessibility is
/// granted; `needsAccessibility` says so.
@MainActor
final class FocusBorderController {
    static let fadeDuration: TimeInterval = 0.12

    /// Bundle ids whose windows never get a border.
    var blockedBundleIDs: Set<String> {
        didSet { update() }
    }

    /// The corner radius of the windows the rule hugs.
    var cornerRadius: CGFloat {
        didSet { view.cornerRadius = cornerRadius }
    }

    /// True while the controller is started but waits for Accessibility permission.
    private(set) var needsAccessibility = false {
        didSet {
            if needsAccessibility != oldValue { onNeedsAccessibilityChange?(needsAccessibility) }
        }
    }

    var onNeedsAccessibilityChange: (@MainActor (Bool) -> Void)?

    private let palette: @MainActor () -> ThemeColors
    private let panel: SurfacePanel
    private let view: FocusBorderView
    private lazy var trustWatcher = AccessibilityTrustWatcher { [weak self] in self?.begin() }
    private var session: AXObserverSession?
    private var observedWindow: AXUIElement?
    private var sessionBundleID: String?
    private var tokens = ObserverTokens()
    private var isStarted = false
    private var isRunning = false
    /// Whether the border is meant to be on screen (the panel may still be fading).
    private var isShown = false
    /// Bumped per fade, so a finished fade-out never hides a border shown since.
    private var fadeGeneration = 0
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    private static let appNotifications = [
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification,
        kAXApplicationHiddenNotification,
        kAXApplicationShownNotification,
        kAXWindowCreatedNotification,
    ]
    private static let windowNotifications = [
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXUIElementDestroyedNotification,
    ]

    init(
        palette: @escaping @MainActor () -> ThemeColors,
        blockedBundleIDs: Set<String> = [],
        cornerRadius: CGFloat = FocusBorderGeometry.defaultCornerRadius
    ) {
        self.palette = palette
        self.blockedBundleIDs = blockedBundleIDs
        self.cornerRadius = cornerRadius
        view = FocusBorderView(frame: .zero, colors: palette(), cornerRadius: cornerRadius)
        panel = SurfacePanel(contentRect: .zero)
        panel.contentView = view
        panel.ignoresMouseEvents = true
        panel.level = .floating
        // `.moveToActiveSpace`, not `.canJoinAllSpaces`: the border belongs with the
        // focused window, which is always on the active Space. Joining all Spaces would
        // leave the rule floating on screen while a Space switch slides the window away;
        // this way it slides with its Space and the next re-target orders it onto the new
        // one. `.transient` keeps it out of Mission Control; no `.fullScreenAuxiliary`, so it
        // never appears in a fullscreen Space.
        panel.collectionBehavior = [.moveToActiveSpace, .transient, .ignoresCycle, .fullScreenNone]
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
        endSession()
        isShown = false
        fadeGeneration += 1
        panel.orderOut(nil)
    }

    func themeDidChange() {
        view.colors = palette()
    }

    // MARK: Tracking

    private func begin() {
        guard isStarted, !isRunning else { return }
        isRunning = true
        needsAccessibility = false
        let workspace = NSWorkspace.shared.notificationCenter
        tokens.observe(NSWorkspace.didActivateApplicationNotification, in: workspace) { [weak self] in
            self?.retarget(spaceChanged: false)
        }
        tokens.observe(NSWorkspace.activeSpaceDidChangeNotification, in: workspace) { [weak self] in
            self?.retarget(spaceChanged: true)
        }
        tokens.observe(NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.update()
        }
        retarget(spaceChanged: false)
    }

    /// Observes the frontmost app afresh.
    private func retarget(spaceChanged: Bool) {
        guard isRunning else { return }
        if spaceChanged {
            // Re-ordering moves the panel onto the new Space (`.moveToActiveSpace`).
            isShown = false
            fadeGeneration += 1
            panel.orderOut(nil)
        }
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if session?.pid != pid {
            endSession()
            if let pid, pid != ownPID {
                session = AXObserverSession(pid: pid) { [weak self] notification, element in
                    self?.handle(notification, element: element)
                }
                sessionBundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
                if let session {
                    for notification in Self.appNotifications {
                        session.add(notification, to: session.application)
                    }
                }
            }
        }
        update()
    }

    private func endSession() {
        session?.invalidate()
        session = nil
        observedWindow = nil
    }

    private func handle(_ notification: String, element: AXUIElement) {
        if notification == kAXUIElementDestroyedNotification, let observedWindow, CFEqual(observedWindow, element) {
            session?.removeAll(from: observedWindow)
            self.observedWindow = nil
        }
        update()
    }

    /// Reads the focused window and shows, moves or hides the border.
    private func update() {
        guard isRunning else { return }
        guard let session else { return hide() }
        let windowElement = session.application.element(kAXFocusedWindowAttribute)
        observe(windowElement)

        let screens = NSScreen.screens
        let primaryHeight = NSScreen.primaryHeight
        let window = windowElement.flatMap { element -> FocusBorderGeometry.Window? in
            guard let frame = element.frame else { return nil }
            return FocusBorderGeometry.Window(
                pid: session.pid,
                bundleID: sessionBundleID,
                subrole: element.string(kAXSubroleAttribute),
                isFullScreen: element.bool("AXFullScreen"),
                isMinimized: element.bool(kAXMinimizedAttribute),
                frame: frame
            )
        }
        let screenFrames = screens.map { SurfaceGeometry.globalRect(fromAppKit: $0.frame, primaryScreenHeight: primaryHeight) }
        guard let window, FocusBorderGeometry.showsBorder(
            around: window, ownPID: ownPID, blockedBundleIDs: blockedBundleIDs, screenFrames: screenFrames
        ) else { return hide() }

        let frame = SurfaceGeometry.appKitRect(
            fromGlobal: FocusBorderGeometry.panelFrame(window: window.frame, width: view.ruleWidth),
            primaryScreenHeight: primaryHeight
        )
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        show()
    }

    /// Moves the per-window subscriptions to `element` when focus moved to another window.
    private func observe(_ element: AXUIElement?) {
        guard let session else { return }
        if let observedWindow, let element, CFEqual(observedWindow, element) { return }
        if let observedWindow { session.removeAll(from: observedWindow) }
        observedWindow = element
        guard let element else { return }
        for notification in Self.windowNotifications {
            session.add(notification, to: element)
        }
    }

    // MARK: Fades

    private func show() {
        guard !isShown else { return }
        isShown = true
        fadeGeneration += 1
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        fade(to: 1, generation: fadeGeneration)
    }

    private func hide() {
        guard isShown else { return }
        isShown = false
        fadeGeneration += 1
        fade(to: 0, generation: fadeGeneration)
    }

    private func fade(to alpha: CGFloat, generation: Int) {
        let finish: @MainActor () -> Void = { [weak self] in
            guard let self, self.fadeGeneration == generation, alpha == 0 else { return }
            self.panel.orderOut(nil)
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = alpha
            finish()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fadeDuration
            panel.animator().alphaValue = alpha
        }, completionHandler: {
            MainActor.assumeIsolated { finish() }
        })
    }
}
