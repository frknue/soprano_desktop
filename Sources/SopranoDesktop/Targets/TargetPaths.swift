import Foundation
import SopranoDesktopCore

/// Where every app keeps its themes and settings, from the home directory and the
/// environment (XDG and the apps' own overrides). Tests and `export` use a scratch home.
struct TargetPaths: Sendable {
    let home: URL
    let environment: [String: String]

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.home = home
        self.environment = environment
    }

    var configHome: URL {
        directory(environment["XDG_CONFIG_HOME"]) ?? home.appendingPathComponent(".config", isDirectory: true)
    }

    var dataHome: URL {
        directory(environment["XDG_DATA_HOME"]) ?? home.appendingPathComponent(".local/share", isDirectory: true)
    }

    var applicationSupport: URL {
        home.appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    /// Soprano Desktop's own state and rendered wallpapers.
    var supportDirectory: URL {
        applicationSupport.appendingPathComponent("Soprano Desktop", isDirectory: true)
    }

    var stateFile: URL {
        supportDirectory.appendingPathComponent("state.json")
    }

    /// Held while one process (the app or the CLI) syncs (`StateLock`).
    var stateLockFile: URL {
        supportDirectory.appendingPathComponent("state.lock")
    }

    /// Where the editor keeps installed extensions.
    func editorExtensionsDirectory(for target: DesktopTarget) -> URL {
        home.appendingPathComponent(target == .cursor ? ".cursor/extensions" : ".vscode/extensions", isDirectory: true)
    }

    var wallpaperDirectory: URL {
        supportDirectory.appendingPathComponent("Wallpapers", isDirectory: true)
    }

    /// `~/.config/soprano-desktop`: files the user sources or loads by hand (fzf, Chrome).
    var desktopConfigDirectory: URL {
        configHome.appendingPathComponent("soprano-desktop", isDirectory: true)
    }

    /// The directory a target's generated files are relative to.
    func themeRoot(for target: DesktopTarget) -> URL {
        switch target {
        case .ghostty: configHome.appendingPathComponent("ghostty", isDirectory: true)
        case .neovim: dataHome.appendingPathComponent("nvim/site", isDirectory: true)
        case .bat: batConfigDirectory
        case .fzf, .chrome: desktopConfigDirectory
        case .vscode, .cursor: supportDirectory.appendingPathComponent("Extensions/\(target.rawValue)", isDirectory: true)
        }
    }

    /// Ghostty loads `config.ghostty` and `config` from its XDG directory, then from
    /// Application Support, each later file overriding earlier ones; the last that exists
    /// is edited so its `theme` line wins, else the XDG `config` is created. (Files pulled in
    /// with `config-file` load after all of these and can still override it.)
    var ghosttyConfigFile: URL {
        let xdg = configHome.appendingPathComponent("ghostty", isDirectory: true)
        let support = applicationSupport.appendingPathComponent("com.mitchellh.ghostty", isDirectory: true)
        let candidates = [
            xdg.appendingPathComponent("config.ghostty"),
            xdg.appendingPathComponent("config"),
            support.appendingPathComponent("config.ghostty"),
            support.appendingPathComponent("config"),
        ]
        return candidates.last { FileManager.default.fileExists(atPath: $0.path) }
            ?? xdg.appendingPathComponent("config")
    }

    /// bat's config directory (`BAT_CONFIG_DIR`, else `<config home>/bat`).
    var batConfigDirectory: URL {
        directory(environment["BAT_CONFIG_DIR"]) ?? configHome.appendingPathComponent("bat", isDirectory: true)
    }

    /// bat's config file (`BAT_CONFIG_PATH`, else `config` in its config directory).
    var batConfigFile: URL {
        environment["BAT_CONFIG_PATH"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) }
            ?? batConfigDirectory.appendingPathComponent("config")
    }

    var vscodeSettingsFile: URL {
        applicationSupport.appendingPathComponent("Code/User/settings.json")
    }

    var cursorSettingsFile: URL {
        applicationSupport.appendingPathComponent("Cursor/User/settings.json")
    }

    var neovimConfigDirectory: URL {
        configHome.appendingPathComponent("nvim", isDirectory: true)
    }

    /// `~/…` for messages.
    func display(_ url: URL) -> String {
        let path = url.path
        guard path.hasPrefix(home.path + "/") else { return path }
        return "~" + path.dropFirst(home.path.count)
    }

    private func directory(_ value: String?) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        return URL(fileURLWithPath: NSString(string: value).expandingTildeInPath, isDirectory: true).standardizedFileURL
    }
}
