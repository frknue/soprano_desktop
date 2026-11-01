import AppKit
import SopranoDesktopCore

/// Runs the engine whenever anything it depends on changes: settings.json, Soprano's theme,
/// the macOS appearance, the screens, the active Space (macOS sets a wallpaper per Space,
/// so each Space gets it when you first visit it), and Apply/Restore from the CLI.
///
/// One operation at a time. Triggers during a run coalesce into one more; a pending Apply
/// or Restore is never replaced by a plain sync (the latest Apply/Restore wins).
@MainActor
final class SyncCoordinator {
    enum Operation {
        case sync
        case apply
        case restore
    }

    /// Posted by the CLI after `apply`/`restore`, so the running app re-reads state.json.
    static let stateChangedNotification = Notification.Name("com.soprano.desktop.state-changed")

    let engine: DesktopEngine
    private let settings: SettingsCenter
    private let theme: ThemeCenter
    private(set) var lastReport: [DesktopEngine.ReportItem] = []
    private(set) var isRunning = false
    private var pending: Operation?
    private let observers = ObserverList<Void>()
    private var tokens: [NSObjectProtocol] = []

    init(engine: DesktopEngine, settings: SettingsCenter = .shared, theme: ThemeCenter = .shared) {
        self.engine = engine
        self.settings = settings
        self.theme = theme
    }

    var isActive: Bool { engine.state.active }

    func start() {
        settings.addObserver(self) { [weak self] in self?.request(.sync) }
        theme.addObserver(self) { [weak self] in self?.request(.sync) }
        let workspace = NSWorkspace.shared.notificationCenter
        tokens.append(workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.request(.sync) }
        })
        tokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.request(.sync) }
        })
        tokens.append(DistributedNotificationCenter.default().addObserver(forName: Self.stateChangedNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.engine.reloadState()
                self.observers.notify(())
                self.request(.sync)
            }
        })
        request(.sync)
    }

    func request(_ operation: Operation) {
        guard !isRunning else {
            if operation != .sync || pending == nil {
                pending = operation
            }
            return
        }
        isRunning = true
        observers.notify(())
        Task { @MainActor in
            let settings = settings.settings
            let pair = theme.pair
            let appearance = theme.appearance
            switch operation {
            case .sync: lastReport = await engine.sync(settings: settings, pair: pair, appearance: appearance)
            case .apply: lastReport = await engine.apply(settings: settings, pair: pair, appearance: appearance)
            case .restore: lastReport = await engine.restore(settings: settings, pair: pair, appearance: appearance)
            }
            isRunning = false
            observers.notify(())
            if let next = pending {
                pending = nil
                request(next)
            }
        }
    }

    /// Handlers fire when a run starts or ends and when another process changed the state,
    /// until `owner` is deallocated.
    func addObserver(_ owner: AnyObject, _ handler: @escaping @MainActor () -> Void) {
        observers.add(owner) { _ in handler() }
    }
}
