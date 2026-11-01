import Foundation
import SopranoDesktopCore

/// One value outside Soprano Desktop that applying changes and restoring puts back: a
/// global default, a line in a config file, a key in a JSONC settings file, the wallpaper.
@MainActor
protocol ManagedSetting: AnyObject {
    /// Key in `DesktopState.originals`, stable across launches.
    var id: String { get }
    /// What the menu and `status` call it: "Accent colour", "Ghostty theme".
    var label: String { get }
    func read() throws -> OriginalValue
    /// `.absent` removes the value.
    func write(_ value: OriginalValue) throws
}

/// A key of the global preferences domain.
final class GlobalDefaultSetting: ManagedSetting {
    let id: String
    let label: String
    private let key: String
    private let preferences: GlobalPreferences

    init(id: String, label: String, key: String, preferences: GlobalPreferences) {
        self.id = id
        self.label = label
        self.key = key
        self.preferences = preferences
    }

    func read() throws -> OriginalValue {
        guard let value = preferences.value(forKey: key), let json = JSONValue(any: value) else { return .absent }
        return .value(json)
    }

    func write(_ value: OriginalValue) throws {
        switch value {
        case .absent: preferences.setValue(nil, forKey: key)
        case let .value(json): preferences.setValue(json.any, forKey: key)
        }
        preferences.postColorChange()
    }
}

/// A `key = value` or `--key=value` line in a config file (Ghostty, bat).
final class LineFileSetting: ManagedSetting {
    let id: String
    let label: String
    let file: URL
    private let setting: LineSetting

    init(id: String, label: String, file: URL, setting: LineSetting) {
        self.id = id
        self.label = label
        self.file = file
        self.setting = setting
    }

    func read() throws -> OriginalValue {
        guard let text = try TextFile.read(file), let value = setting.value(in: text) else { return .absent }
        return .value(.string(value))
    }

    func write(_ value: OriginalValue) throws {
        let text = try TextFile.read(file) ?? ""
        let raw: String? = switch value {
        case .absent: nil
        case let .value(json): json.stringValue
        }
        let edited = setting.setting(raw, in: text)
        if edited != text {
            try TextFile.write(edited, to: file)
        }
    }
}

/// A top-level key of a JSONC settings file (VS Code, Cursor).
final class JSONCFileSetting: ManagedSetting {
    let id: String
    let label: String
    let file: URL
    private let setting: JSONCSetting

    init(id: String, label: String, file: URL, key: String) {
        self.id = id
        self.label = label
        self.file = file
        self.setting = JSONCSetting(key: key)
    }

    func read() throws -> OriginalValue {
        guard let text = try TextFile.read(file), let value = try setting.value(in: text) else { return .absent }
        return .value(value)
    }

    func write(_ value: OriginalValue) throws {
        let text = try TextFile.read(file) ?? ""
        let json: JSONValue? = switch value {
        case .absent: nil
        case let .value(json): json
        }
        let edited = try setting.setting(json, in: text)
        if edited != text {
            try TextFile.write(edited, to: file)
        }
    }
}

/// Every screen's desktop picture, as one value: `{ "<display id>": { "url", "scaling",
/// "allowClipping" } }`. Screens missing when restoring are skipped.
final class WallpaperSetting: ManagedSetting {
    let id = "system.wallpaper"
    let label = SystemSetting.wallpaper.displayName
    private let desktop: DesktopPictures
    /// The colour macOS fills around a picture that does not cover the screen.
    var fillColor: RGB?

    init(desktop: DesktopPictures) {
        self.desktop = desktop
    }

    func read() throws -> OriginalValue {
        var screens: [String: JSONValue] = [:]
        for screen in desktop.screens() {
            screens[screen.id] = desktop.picture(forScreen: screen.id).map(Self.json) ?? .null
        }
        return .value(.object(screens))
    }

    func write(_ value: OriginalValue) throws {
        guard case let .value(.object(screens)) = value else { return }
        let present = Set(desktop.screens().map(\.id))
        for (id, entry) in screens.sorted(by: { $0.key < $1.key }) where present.contains(id) {
            guard let picture = Self.picture(entry) else { continue }
            try desktop.setPicture(picture, fillColor: fillColor, forScreen: id)
        }
    }

    static func json(_ picture: DesktopPicture) -> JSONValue {
        var object: [String: JSONValue] = ["url": .string(picture.url.path)]
        if let scaling = picture.scaling { object["scaling"] = .number(Double(scaling)) }
        if let allowClipping = picture.allowClipping { object["allowClipping"] = .bool(allowClipping) }
        return .object(object)
    }

    static func picture(_ json: JSONValue) -> DesktopPicture? {
        guard case let .object(object) = json, let path = object["url"]?.stringValue else { return nil }
        var picture = DesktopPicture(url: URL(fileURLWithPath: path), scaling: nil, allowClipping: nil)
        if case let .number(scaling) = object["scaling"] { picture.scaling = Int(scaling) }
        if case let .bool(allowClipping) = object["allowClipping"] { picture.allowClipping = allowClipping }
        return picture
    }
}

/// UTF-8 files read and written through symlinks (dotfiles links survive), atomically.
enum TextFile {
    /// nil when the file does not exist.
    static func read(_ url: URL) throws -> String? {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    static func write(_ text: String, to url: URL) throws {
        try SettingsFile.write(text, to: url)
    }

    /// Writes `text` unless the file already holds exactly it; true when it wrote.
    @discardableResult
    static func update(_ text: String, at url: URL) throws -> Bool {
        if try read(url) == text { return false }
        try write(text, to: url)
        return true
    }
}
