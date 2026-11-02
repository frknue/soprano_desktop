import AppKit
import ApplicationServices

/// Accessibility permission (System Settings → Privacy & Security → Accessibility), which
/// the focus border and the Folio menu bar need to read window frames and menu bars.
enum AccessibilityPermission {
    /// Whether this process may use the Accessibility API.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Asks macOS to show its Accessibility prompt (once per app; afterwards it only lists
    /// the app in System Settings). Returns whether the process is trusted already.
    @discardableResult
    static func request() -> Bool {
        // `kAXTrustedCheckOptionPrompt` is a mutable C global; its value is this string.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
}

/// Polls `AccessibilityPermission.isTrusted` every two seconds while a surface waits for
/// permission and calls `onTrusted` once it is granted. macOS sends no notification for it.
@MainActor
final class AccessibilityTrustWatcher {
    private var timer: Timer?
    private let onTrusted: @MainActor () -> Void

    init(onTrusted: @escaping @MainActor () -> Void) {
        self.onTrusted = onTrusted
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, AccessibilityPermission.isTrusted else { return }
                self.stop()
                self.onTrusted()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
