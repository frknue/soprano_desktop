import AppKit
import ApplicationServices

/// Typed reads of Accessibility attributes. Every call is an IPC round trip to the target
/// app, bounded by the element's messaging timeout.
extension AXUIElement {
    /// An application element whose calls give up after `timeout` seconds, so a hung app
    /// cannot stall a surface for the default six.
    static func application(pid: pid_t, timeout: Float = 0.25) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, timeout)
        return element
    }

    func value(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    func element(_ attribute: String) -> AXUIElement? {
        guard let value = value(attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    func elements(_ attribute: String) -> [AXUIElement] {
        (value(attribute) as? [AnyObject])?.compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? (item as! AXUIElement) : nil
        } ?? []
    }

    func string(_ attribute: String) -> String? {
        value(attribute) as? String
    }

    func bool(_ attribute: String) -> Bool {
        (value(attribute) as? Bool) ?? false
    }

    /// `AXPosition` + `AXSize` in global (top-left origin) coordinates.
    var frame: CGRect? {
        guard let position = value(kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = value(kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent)
        else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    var position: CGPoint? {
        guard let position = value(kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        return AXValueGetValue(position as! AXValue, .cgPoint, &origin) ? origin : nil
    }
}

/// An `AXUIElement` handed to a background queue. AX elements are immutable CF references
/// and the Accessibility API is callable from any thread.
struct SendableElement: @unchecked Sendable {
    let element: AXUIElement
}

/// One `AXObserver` for one process, delivering its notifications on the main run loop.
/// Call `invalidate()` before dropping it.
@MainActor
final class AXObserverSession {
    typealias Handler = @MainActor (_ notification: String, _ element: AXUIElement) -> Void

    let pid: pid_t
    let application: AXUIElement
    private let observer: AXObserver
    private let handler: Handler
    private var registrations: [(element: AXUIElement, notification: String)] = []
    private var isValid = true

    /// Nil when the process cannot be observed (it quit, or Accessibility is not granted).
    init?(pid: pid_t, handler: @escaping Handler) {
        var created: AXObserver?
        let status = AXObserverCreate(pid, { _, element, notification, refcon in
            guard let refcon else { return }
            let session = Unmanaged<AXObserverSession>.fromOpaque(refcon).takeUnretainedValue()
            let name = notification as String
            MainActor.assumeIsolated {
                session.deliver(name, element)
            }
        }, &created)
        guard status == .success, let created else { return nil }
        self.pid = pid
        application = .application(pid: pid)
        observer = created
        self.handler = handler
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    /// Subscribes to `notification` on `element`; false when the app refuses it.
    @discardableResult
    func add(_ notification: String, to element: AXUIElement) -> Bool {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let status = AXObserverAddNotification(observer, element, notification as CFString, refcon)
        guard status == .success || status == .notificationAlreadyRegistered else { return false }
        registrations.append((element, notification))
        return true
    }

    /// Unsubscribes everything registered on `element`.
    func removeAll(from element: AXUIElement) {
        registrations.removeAll { registration in
            guard CFEqual(registration.element, element) else { return false }
            AXObserverRemoveNotification(observer, element, registration.notification as CFString)
            return true
        }
    }

    func invalidate() {
        guard isValid else { return }
        isValid = false
        for registration in registrations {
            AXObserverRemoveNotification(observer, registration.element, registration.notification as CFString)
        }
        registrations.removeAll()
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    private func deliver(_ notification: String, _ element: AXUIElement) {
        guard isValid else { return }
        handler(notification, element)
    }
}

/// Block-based notification observers delivered on the main queue, removed together.
@MainActor
struct ObserverTokens {
    private var tokens: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    mutating func observe(
        _ name: Notification.Name,
        in center: NotificationCenter = .default,
        _ handler: @escaping @MainActor () -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
        tokens.append((center, token))
    }

    mutating func removeAll() {
        tokens.forEach { $0.center.removeObserver($0.token) }
        tokens.removeAll()
    }
}

/// A borderless, transparent panel that never becomes key or main and never activates
/// Soprano Desktop, so drawing over other apps leaves their focus alone.
final class SurfacePanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        isMovable = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

extension NSScreen {
    /// The Quartz display id, stable while the display stays attached.
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Height of the menu bar macOS reserves on this screen; zero when it has none (a
    /// secondary display without separate Spaces, or an auto-hiding menu bar).
    var menuBarHeight: CGFloat {
        max(frame.maxY - visibleFrame.maxY, 0)
    }

    /// The display with the global origin: AppKit's and the Accessibility API's
    /// coordinate spaces are both anchored to it.
    static var primaryHeight: CGFloat {
        screens.first { $0.frame.origin == .zero }?.frame.height ?? screens.first?.frame.height ?? 0
    }
}
