import AppKit
import SopranoDesktopCore

/// `SopranoDesktop <command>`: runs in-process (no running app needed) and exits. After
/// `apply` and `restore` it tells a running Soprano Desktop to re-read its state.
@MainActor
enum CLI {
    static let commands: Set<String> = ["apply", "restore", "status", "export", "snapshot-surfaces", "help", "--help", "-h", "version", "--version"]

    static let usage = """
    Usage: SopranoDesktop <command>

      apply           Apply the Soprano theme to macOS and your apps, and keep it current
                      while Soprano Desktop runs.
      restore         Put back every macOS and app setting Soprano Desktop changed.
      status          The theme, whether it is applied, and every app's state.
      export <dir>    Write every theme file, the editor extension and the wallpapers into
                      <dir>, without changing anything else.
      snapshot-surfaces --out <dir>
                      Render the Folio menu bar and focus border offscreen to PNGs.
      version         Print the version.

    Settings: ~/.config/soprano-desktop/settings.json (SOPRANO_DESKTOP_CONFIG overrides).
    """

    static func run(arguments: [String]) -> Never {
        _ = NSApplication.shared
        Task { @MainActor in
            exit(await execute(arguments))
        }
        RunLoop.main.run()
        exit(0)
    }

    static func execute(_ arguments: [String]) async -> Int32 {
        guard let command = arguments.first else {
            print(usage)
            return 2
        }
        switch command {
        case "help", "--help", "-h":
            print(usage)
            return 0
        case "version", "--version":
            print(AppVersion.current)
            return 0
        default:
            break
        }

        if command == "snapshot-surfaces" {
            return SurfaceSnapshotCommand.run(arguments: Array(arguments.dropFirst()))
        }

        let settings = SettingsCenter.shared
        settings.start(watching: false)
        let theme = ThemeCenter.shared
        theme.start(watching: false)
        let engine = DesktopEngine(dependencies: .live())

        switch command {
        case "apply", "restore":
            guard arguments.count == 1 else { return usageError() }
            let report = command == "apply"
                ? await engine.apply(settings: settings.settings, pair: theme.pair, appearance: theme.appearance)
                : await engine.restore(settings: settings.settings, pair: theme.pair, appearance: theme.appearance)
            DistributedNotificationCenter.default().postNotificationName(
                SyncCoordinator.stateChangedNotification, object: nil, userInfo: nil, deliverImmediately: true
            )
            printThemeLine(theme)
            print(render(report))
            return report.contains { if case .failed = $0.status { true } else { false } } ? 1 : 0
        case "status":
            guard arguments.count == 1 else { return usageError() }
            printStatus(engine: engine, settings: settings.settings, theme: theme)
            return 0
        case "export":
            guard arguments.count == 2 else { return usageError() }
            let directory = URL(fileURLWithPath: NSString(string: arguments[1]).expandingTildeInPath, isDirectory: true)
            do {
                let written = try export(pair: theme.pair, engine: engine, to: directory)
                written.forEach { print($0) }
                return 0
            } catch {
                FileHandle.standardError.write(Data("export: \(error.localizedDescription)\n".utf8))
                return 1
            }
        default:
            return usageError()
        }
    }

    private static func usageError() -> Int32 {
        FileHandle.standardError.write(Data((usage + "\n").utf8))
        return 2
    }

    private static func printThemeLine(_ theme: ThemeCenter) {
        let pair = theme.pair
        let names = pair.light == pair.dark ? pair.light.name : "\(pair.light.name) (light) · \(pair.dark.name) (dark)"
        print("Theme: \(names); macOS is \(theme.appearance.rawValue)")
    }

    static func render(_ report: [DesktopEngine.ReportItem]) -> String {
        let width = report.map(\.name.count).max() ?? 0
        return report.map { item in
            let name = item.name.padding(toLength: width, withPad: " ", startingAt: 0)
            let status: String = switch item.status {
            case .applied: "applied"
            case .unchanged: "on theme"
            case .restored: "restored"
            case let .skipped(reason): "– \(reason)"
            case let .needsSetup(hint): "theme files written; add once: \(hint)"
            case let .failed(message): "FAILED: \(message)"
            }
            return "  \(name)  \(status)"
        }.joined(separator: "\n")
    }

    private static func printStatus(engine: DesktopEngine, settings: DesktopSettings, theme: ThemeCenter) {
        printThemeLine(theme)
        print("Applied: \(engine.state.active ? "yes" : "no")")
        if let error = engine.stateError {
            print("Problem: \(error). Nothing is changed until it is fixed.")
        }
        let recorded = engine.state.originals.keys.sorted()
        print("Settings with a saved original: \(recorded.isEmpty ? "none" : recorded.joined(separator: ", "))")
        print("macOS:")
        for setting in SystemSetting.allCases {
            var line = "  \(setting.displayName): \(settings.system.contains(setting) ? "on" : "off")"
            if setting == .screenSaver {
                line += "; select \"Soprano\" once in System Settings → Screen Saver"
            }
            print(line)
        }
        print("Desktop:")
        for behavior in DesktopBehavior.allCases {
            print("  \(behavior.displayName): \(settings.desktop.contains(behavior) ? "on" : "off")")
        }
        print("Surfaces (Accessibility \(AccessibilityPermission.isTrusted ? "allowed" : "not allowed yet")):")
        for surface in Surface.allCases {
            print("  \(surface.displayName): \(settings.surfaces.contains(surface) ? "on" : "off")")
        }
        print("Screens (the wallpaper is set per screen and Space):")
        for screen in engine.dependencies.desktop.screens() {
            print("  \(screen.name): Space \(screen.spaceID ?? "unknown — wallpaper left alone")")
        }
        print("Apps:")
        for target in DesktopTarget.allCases {
            var line = "  \(target.displayName): \(settings.apps.contains(target) ? "on" : "off")"
            line += engine.isInstalled(target) ? ", installed" : ", not installed"
            if let hint = target.setupHint, let place = target.setupHintPlace {
                line += "; setup: \(hint) (\(place))"
            }
            print(line)
        }
    }

    /// Every target's files under `<dir>/<target>/`, the .vsix under `<dir>/vscode/`, and
    /// wallpapers for both palettes at every connected screen's size under `<dir>/wallpapers/`.
    static func export(pair: ThemePair, engine: DesktopEngine, to directory: URL) throws -> [String] {
        var written: [String] = []
        for target in DesktopTarget.allCases where target != .cursor {
            let root = directory.appendingPathComponent(target.rawValue, isDirectory: true)
            if target == .vscode {
                let vsix = try engine.buildPackage(VSCodeTheme.packageFiles(for: pair, version: "1.0.0"), into: root)
                written.append(vsix.path)
                continue
            }
            for file in DesktopEngine.files(for: target, pair: pair) {
                let url = root.appendingPathComponent(file.path)
                try TextFile.write(file.contents, to: url)
                written.append(url.path)
            }
        }
        let wallpapers = directory.appendingPathComponent("wallpapers", isDirectory: true)
        let screens = LiveDesktopPictures().screens()
        let fallback = ScreenInfo(id: "0", name: "Built-in", spaceID: nil, pixelWidth: 3024, pixelHeight: 1964, scale: 2)
        let sizes = screens.isEmpty ? [fallback] : screens
        for palette in [pair.light, pair.dark] {
            for screen in sizes {
                let url = try WallpaperRenderer.render(
                    palette,
                    pixelWidth: screen.pixelWidth,
                    pixelHeight: screen.pixelHeight,
                    scale: screen.scale,
                    into: wallpapers
                )
                written.append(url.path)
            }
        }
        return written
    }
}
