import AppKit
import SopranoDesktopCore

/// The live theme pair and macOS appearance.
///
/// `pair` comes from settings.json `theme` (default `soprano`: Soprano's `theme` and
/// `appearance`, watched live) through `ThemePairResolver`; `appearance` is macOS's
/// effective appearance. Observers fire when either changes.
@MainActor
final class ThemeCenter {
    static let shared = ThemeCenter()

    let sopranoSettingsURL: URL
    private(set) var pair: ThemePair
    private(set) var appearance: Appearance

    /// The palette macOS shows right now.
    var current: Palette { pair.palette(for: appearance) }

    private let settingsCenter: SettingsCenter
    private let systemAppearance: @MainActor () -> Appearance
    private var sopranoWatcher: ConfigFileWatcher?
    private var appearanceObservation: NSKeyValueObservation?
    private let observers = ObserverList<Void>()
    private var isStarted = false

    init(
        sopranoSettingsURL: URL = SettingsFile.sopranoURL(),
        settings: SettingsCenter = .shared,
        systemAppearance: @escaping @MainActor () -> Appearance = ThemeCenter.macOSAppearance
    ) {
        self.sopranoSettingsURL = sopranoSettingsURL
        self.settingsCenter = settings
        self.systemAppearance = systemAppearance
        appearance = systemAppearance()
        pair = PaletteBridge.pair(theme: ThemePairResolver.followSopranoID, soprano: SopranoThemeFile())
    }

    /// macOS's effective appearance as AppKit reports it.
    static func macOSAppearance() -> Appearance {
        let match = NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
        return match == .darkAqua ? .dark : .light
    }

    /// Resolves once; with `watching`, follows settings.json, Soprano's settings.json and
    /// the macOS appearance.
    func start(watching: Bool = true) {
        guard !isStarted else { return }
        isStarted = true
        refresh()
        guard watching else { return }
        settingsCenter.addObserver(self) { [weak self] in
            self?.refresh()
        }
        let watcher = ConfigFileWatcher(url: sopranoSettingsURL) { [weak self] in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        watcher.start()
        sopranoWatcher = watcher
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    /// Handlers fire after the pair or the appearance changed, until `owner` is deallocated.
    func addObserver(_ owner: AnyObject, _ handler: @escaping @MainActor () -> Void) {
        observers.add(owner) { _ in handler() }
    }

    func refresh() {
        let previous = (pair, appearance)
        pair = PaletteBridge.pair(theme: settingsCenter.settings.theme, soprano: readSoprano())
        appearance = systemAppearance()
        if previous != (pair, appearance) {
            observers.notify(())
        }
    }

    private func readSoprano() -> SopranoThemeFile {
        guard let text = try? SettingsFile.read(at: sopranoSettingsURL) else { return SopranoThemeFile() }
        return SopranoThemeFile.parse(text: text, knownThemeIDs: PaletteBridge.knownThemeIDs)
    }
}
