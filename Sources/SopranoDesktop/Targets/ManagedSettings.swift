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

/// One screen's desktop picture on one Space: `{ "url", "scaling", "allowClipping" }`.
///
/// macOS keeps a picture per display and Space and only exposes the current one, so the id
/// names both (`system.wallpaper:<display uuid>:<space id>`). An original is read on, and
/// only ever written back to, the Space it came from: writes check that the screen still
/// shows that Space. Originals of Spaces not visible at Restore stay in `state.originals`
/// and are put back the next time their Space is visible.
final class WallpaperSetting: ManagedSetting {
    static let idPrefix = "system.wallpaper:"

    let id: String
    let label: String
    private let screen: ScreenInfo
    private let spaceID: String
    private let desktop: DesktopPictures
    /// The colour macOS fills around a picture that does not cover the screen.
    private let fillColor: RGB?

    /// nil when the screen's Space is unknown: such a screen is never touched.
    init?(screen: ScreenInfo, desktop: DesktopPictures, fillColor: RGB?) {
        guard let spaceID = screen.spaceID else { return nil }
        self.id = "\(Self.idPrefix)\(screen.id):\(spaceID)"
        self.label = "\(SystemSetting.wallpaper.displayName) (\(screen.name))"
        self.screen = screen
        self.spaceID = spaceID
        self.desktop = desktop
        self.fillColor = fillColor
    }

    func read() throws -> OriginalValue {
        try ensureOnSpace()
        return desktop.picture(forScreen: screen.id).map { .value(Self.json($0)) } ?? .absent
    }

    /// `.absent` (macOS reported no picture URL) cannot be put back and is a no-op.
    func write(_ value: OriginalValue) throws {
        guard case let .value(json) = value, let picture = Self.picture(json) else { return }
        try ensureOnSpace()
        try desktop.setPicture(picture, fillColor: fillColor, forScreen: screen.id)
    }

    private func ensureOnSpace() throws {
        guard desktop.screens().contains(where: { $0.id == screen.id && $0.spaceID == spaceID }) else {
            throw WallpaperError.spaceChanged
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
