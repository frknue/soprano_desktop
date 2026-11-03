import Foundation
import SopranoDesktopCore

/// One thing outside Soprano Desktop that applying changes and restoring puts back: a
/// global default, Soprano's keys in one config file, one screen's wallpaper on one Space.
@MainActor
protocol ManagedSetting: AnyObject {
    /// Key in `DesktopState.originals`, stable across launches and processes.
    var id: String { get }
    /// What the menu and `status` call it: "Accent colour", "Ghostty config".
    var label: String { get }
    /// The record of the user's own state before the first change. Throws when it cannot
    /// be read back reliably; nothing is changed then.
    func capture(for desired: JSONValue) throws -> JSONValue
    func matches(_ desired: JSONValue) throws -> Bool
    /// Writes `desired`; returns what was written to a file (stored in `state.written`) or nil.
    func apply(_ desired: JSONValue) throws -> String?
    /// Puts the captured record back. `written` is what `apply` last wrote, if anything.
    func restore(_ original: JSONValue, written: String?) throws
    /// The file's current text, for settings that live in a file; nil otherwise.
    func contents() throws -> String?
}

extension ManagedSetting {
    func contents() throws -> String? { nil }
}

/// One key of a preferences domain. The record is the value, or `null` when the key was
/// absent (restoring removes it). Every write is followed by `notifications`, so the
/// process that reads the key picks it up without a relaunch.
final class DefaultsSetting: ManagedSetting {
    let id: String
    let label: String
    private let key: String
    private let domain: String
    private let notifications: [PreferenceNotification]
    private let preferences: PreferencesStore

    init(
        id: String,
        label: String,
        key: String,
        domain: String = PreferencesDomain.global,
        notifications: [PreferenceNotification],
        preferences: PreferencesStore
    ) {
        self.id = id
        self.label = label
        self.key = key
        self.domain = domain
        self.notifications = notifications
        self.preferences = preferences
    }

    func capture(for desired: JSONValue) throws -> JSONValue {
        current() ?? .null
    }

    func matches(_ desired: JSONValue) throws -> Bool {
        current() == desired
    }

    func apply(_ desired: JSONValue) throws -> String? {
        try preferences.setValue(desired.any, forKey: key, domain: domain)
        notifications.forEach(preferences.post)
        return nil
    }

    func restore(_ original: JSONValue, written: String?) throws {
        try preferences.setValue(original == .null ? nil : original.any, forKey: key, domain: domain)
        notifications.forEach(preferences.post)
    }

    private func current() -> JSONValue? {
        preferences.value(forKey: key, domain: domain).flatMap(JSONValue.init(any:))
    }
}

/// Soprano's keys in one config file: Ghostty (`key = value` lines), bat (`--key=value`
/// lines) or VS Code/Cursor (top-level JSONC keys). The desired value is an object of
/// key → value (line formats: the raw text after the separator, as a string).
///
/// The id embeds the file's path, so a process that resolves a different file (another
/// `XDG_CONFIG_HOME`, a new `config.ghostty`) never restores one file's original into
/// another. The record is self-describing (`path`, `format`, `text`, `keys`), so a file no
/// longer targeted is still restored from it.
///
/// Restore puts the original text back byte-for-byte when the file is exactly what Soprano
/// Desktop last wrote (deleting it if it did not exist); after the user edited it, only
/// Soprano's keys are reverted.
final class ConfigFileSetting: ManagedSetting {
    enum Format: String {
        case ghostty
        case argument
        case jsonc
    }

    static let idSeparator = ":"

    let id: String
    let label: String
    let file: URL
    let format: Format

    init(owner: String, label: String, file: URL, format: Format) {
        self.id = "\(owner)\(Self.idSeparator)\(file.path)"
        self.label = label
        self.file = file
        self.format = format
    }

    /// The setting a record describes, for files no longer targeted.
    convenience init?(id: String, record: JSONValue) {
        guard case let .object(object) = record,
              let path = object["path"]?.stringValue,
              let format = object["format"]?.stringValue.flatMap(Format.init(rawValue:)),
              id.hasSuffix(Self.idSeparator + path)
        else { return nil }
        let owner = String(id.dropLast(Self.idSeparator.count + path.count))
        self.init(owner: owner, label: "\(owner) config", file: URL(fileURLWithPath: path), format: format)
    }

    func capture(for desired: JSONValue) throws -> JSONValue {
        let text = try TextFile.read(file)
        var keys: [String: JSONValue] = [:]
        for key in Self.keys(of: desired) {
            keys[key] = try text.flatMap { try value(of: key, in: Self.body($0)) } ?? .null
        }
        return .object([
            "path": .string(file.path),
            "format": .string(format.rawValue),
            "text": text.map(JSONValue.string) ?? .null,
            "keys": .object(keys),
        ])
    }

    func contents() throws -> String? {
        try TextFile.read(file)
    }

    func matches(_ desired: JSONValue) throws -> Bool {
        guard case let .object(values) = desired, let text = try TextFile.read(file) else { return false }
        let body = Self.body(text)
        return try values.allSatisfy { key, value in try self.value(of: key, in: body) == value }
    }

    func apply(_ desired: JSONValue) throws -> String? {
        guard case let .object(values) = desired else { return nil }
        let text = try TextFile.read(file) ?? ""
        var body = Self.body(text)
        for (key, value) in values.sorted(by: { $0.key < $1.key }) {
            body = try setting(key, to: value, in: body)
        }
        let edited = Self.bom(of: text) + body
        if edited != text {
            try TextFile.write(edited, to: file)
        }
        return edited
    }

    func restore(_ original: JSONValue, written: String?) throws {
        guard case let .object(record) = original else { return }
        let current = try TextFile.read(file)
        let originalText = record["text"]?.stringValue
        if let current, current == written {
            if let originalText {
                try TextFile.write(originalText, to: file)
            } else {
                try FileManager.default.removeItem(at: file)
            }
            return
        }
        // Edited (or removed) since Soprano Desktop wrote it: revert only Soprano's keys.
        guard let current, case let .object(keys) = record["keys"] else { return }
        var body = Self.body(current)
        for (key, value) in keys.sorted(by: { $0.key < $1.key }) {
            body = try setting(key, to: value == .null ? nil : value, in: body)
        }
        let edited = Self.bom(of: current) + body
        if edited != current {
            try TextFile.write(edited, to: file)
        }
    }

    private func value(of key: String, in text: String) throws -> JSONValue? {
        switch format {
        case .ghostty: LineSetting(key: key, syntax: .ghostty).value(in: text).map(JSONValue.string)
        case .argument: LineSetting(key: key, syntax: .argument).value(in: text).map(JSONValue.string)
        case .jsonc: try JSONCSetting(key: key).value(in: text)
        }
    }

    private func setting(_ key: String, to value: JSONValue?, in text: String) throws -> String {
        switch format {
        case .ghostty: LineSetting(key: key, syntax: .ghostty).setting(value?.stringValue, in: text)
        case .argument: LineSetting(key: key, syntax: .argument).setting(value?.stringValue, in: text)
        case .jsonc: try JSONCSetting(key: key).setting(value, in: text)
        }
    }

    private static func keys(of desired: JSONValue) -> [String] {
        guard case let .object(values) = desired else { return [] }
        return values.keys.sorted()
    }

    /// The text without a leading byte-order mark, which the parsers do not expect.
    private static func body(_ text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }

    private static func bom(of text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? "\u{FEFF}" : ""
    }
}

/// One screen's desktop picture on one Space: `{ "url", "scaling", "allowClipping",
/// "fillColor" }`.
///
/// macOS keeps a picture per display and Space and only exposes the current one, so the id
/// names both (`system.wallpaper:<display uuid>:<space id>`). An original is read on, and
/// only ever written back to, the Space it came from: every read and write checks that the
/// screen still shows that Space. Originals of Spaces not visible at Restore stay in
/// `state.originals` and are put back the next time their Space is visible. A screen whose
/// current picture cannot be read is never changed.
final class WallpaperSetting: ManagedSetting {
    static let idPrefix = "system.wallpaper:"

    let id: String
    let label: String
    private let screen: ScreenInfo
    private let spaceID: String
    private let desktop: DesktopPictures

    /// nil when the screen's Space is unknown: such a screen is never touched.
    init?(screen: ScreenInfo, desktop: DesktopPictures) {
        guard let spaceID = screen.spaceID else { return nil }
        self.id = "\(Self.idPrefix)\(screen.id):\(spaceID)"
        self.label = "\(SystemSetting.wallpaper.displayName) (\(screen.name))"
        self.screen = screen
        self.spaceID = spaceID
        self.desktop = desktop
    }

    func capture(for desired: JSONValue) throws -> JSONValue {
        try ensureOnSpace()
        guard let picture = desktop.picture(forScreen: screen.id) else { throw WallpaperError.unreadable }
        return Self.json(picture)
    }

    func matches(_ desired: JSONValue) throws -> Bool {
        try ensureOnSpace()
        return desktop.picture(forScreen: screen.id)?.url == Self.picture(desired)?.url
    }

    func apply(_ desired: JSONValue) throws -> String? {
        guard let picture = Self.picture(desired) else { return nil }
        try ensureOnSpace()
        try desktop.setPicture(picture, forScreen: screen.id)
        return nil
    }

    func restore(_ original: JSONValue, written: String?) throws {
        guard let picture = Self.picture(original) else { return }
        try ensureOnSpace()
        try desktop.setPicture(picture, forScreen: screen.id)
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
        if let fillColor = picture.fillColor { object["fillColor"] = .string(fillColor.hex) }
        return .object(object)
    }

    static func picture(_ json: JSONValue) -> DesktopPicture? {
        guard case let .object(object) = json, let path = object["url"]?.stringValue else { return nil }
        var picture = DesktopPicture(url: URL(fileURLWithPath: path))
        if case let .number(scaling) = object["scaling"] { picture.scaling = Int(scaling) }
        if case let .bool(allowClipping) = object["allowClipping"] { picture.allowClipping = allowClipping }
        picture.fillColor = object["fillColor"]?.stringValue.flatMap(RGB.init(hex:))
        return picture
    }
}

/// Icon & widget style plus folder colour (`IconAppearance`). The record is the whole
/// configuration before the first change.
final class IconAppearanceSetting: ManagedSetting {
    let id = "system.iconAppearance"
    let label = "Folder colour and icons"
    private let store: IconAppearanceStore

    init(store: IconAppearanceStore) {
        self.store = store
    }

    func capture(for desired: JSONValue) throws -> JSONValue {
        guard let current = store.read() else { throw IconAppearanceError.unavailable }
        return current.json
    }

    /// Compared as JSON (`#rrggbb`): SkyLight keeps the tint at six decimals, so a colour
    /// read back never equals the one written component for component.
    func matches(_ desired: JSONValue) throws -> Bool {
        store.read()?.json == IconAppearance(json: desired)?.json
    }

    func apply(_ desired: JSONValue) throws -> String? {
        guard let appearance = IconAppearance(json: desired) else { return nil }
        try store.write(appearance)
        return nil
    }

    func restore(_ original: JSONValue, written: String?) throws {
        guard let appearance = IconAppearance(json: original) else { return }
        try store.write(appearance)
    }
}

/// A Folio icon on one folder. The record is `{ "custom": false }`: the folder had no icon
/// of its own (folders that have one are never registered), so restoring removes ours.
/// `matches` relies on the version Soprano Desktop last wrote, so a redesigned icon is
/// applied again.
final class FolderIconSetting: ManagedSetting {
    static let idPrefix = "system.folderIcon:"

    let id: String
    let label: String
    private let folder: FolioFolder
    private let url: URL
    private let store: FolderIconStore
    private let lastWritten: String?

    init(folder: FolioFolder, url: URL, store: FolderIconStore, lastWritten: String?) {
        self.id = Self.idPrefix + url.path
        self.label = "Folder icon (\(url.lastPathComponent))"
        self.folder = folder
        self.url = url
        self.store = store
        self.lastWritten = lastWritten
    }

    func capture(for desired: JSONValue) throws -> JSONValue {
        .object(["custom": .bool(store.hasCustomIcon(url))])
    }

    func matches(_ desired: JSONValue) throws -> Bool {
        store.hasCustomIcon(url) && lastWritten == desired.stringValue
    }

    func apply(_ desired: JSONValue) throws -> String? {
        try store.setIcon(folder, at: url)
        return desired.stringValue
    }

    func restore(_ original: JSONValue, written: String?) throws {
        guard case let .object(record) = original, record["custom"] == .bool(false) else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try store.setIcon(nil, at: url)
    }
}

/// The Soprano screen saver bundle copied into `~/Library/Screen Savers`. The record says
/// whether a `Soprano.saver` was there before; restoring removes ours when it was not.
final class ScreenSaverSetting: ManagedSetting {
    let id = "system.screenSaver"
    let label = SystemSetting.screenSaver.displayName
    private let source: URL
    private let destination: URL

    init(source: URL, destination: URL) {
        self.source = source
        self.destination = destination
    }

    func capture(for desired: JSONValue) throws -> JSONValue {
        .object(["existed": .bool(FileManager.default.fileExists(atPath: destination.path))])
    }

    func matches(_ desired: JSONValue) throws -> Bool {
        Self.executableHash(of: destination) == desired.stringValue
    }

    func apply(_ desired: JSONValue) throws -> String? {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".Soprano-\(UUID().uuidString).saver")
        try fileManager.copyItem(at: source, to: staging)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: destination)
        }
        return nil
    }

    func restore(_ original: JSONValue, written: String?) throws {
        guard case let .object(record) = original, record["existed"] == .bool(false) else { return }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
    }

    /// SHA-256 of the bundle's executable; identifies the build.
    static func executableHash(of bundle: URL) -> String? {
        let macOS = bundle.appendingPathComponent("Contents/MacOS", isDirectory: true)
        guard let name = try? FileManager.default.contentsOfDirectory(atPath: macOS.path).sorted().first,
              let data = try? Data(contentsOf: macOS.appendingPathComponent(name))
        else { return nil }
        return DesktopEngine.sha256(data)
    }
}

/// UTF-8 files read and written through symlinks (dotfiles links survive), atomically.
enum TextFile {
    /// nil when the file does not exist. A byte-order mark is kept as U+FEFF.
    static func read(_ url: URL) throws -> String? {
        do {
            return String(decoding: try Data(contentsOf: url), as: UTF8.self)
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
