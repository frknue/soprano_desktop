import AppKit
import SopranoDesktopCore

/// The global preferences domain (`defaults -g`). Tests inject a dictionary.
protocol GlobalPreferences: AnyObject {
    func value(forKey key: String) -> Any?
    /// nil removes the key.
    func setValue(_ value: Any?, forKey key: String)
    /// Tells running apps that the accent or highlight colour changed.
    func postColorChange()
}

/// One screen as the wallpaper code needs it.
struct ScreenInfo: Equatable, Sendable {
    /// `CGDirectDisplayID`, as a string key for state.json.
    var id: String
    /// Backing pixels.
    var pixelWidth: Int
    var pixelHeight: Int
    /// Pixels per point.
    var scale: Double
}

/// What a screen shows: the picture and how it is scaled.
struct DesktopPicture: Equatable, Sendable {
    var url: URL
    /// `NSImageScaling.rawValue`; nil when macOS did not report it.
    var scaling: Int?
    var allowClipping: Bool?
}

/// The screens and their desktop pictures (NSWorkspace). Tests inject a fake.
@MainActor
protocol DesktopPictures: AnyObject {
    func screens() -> [ScreenInfo]
    func picture(forScreen id: String) -> DesktopPicture?
    func setPicture(_ picture: DesktopPicture, fillColor: RGB?, forScreen id: String) throws
}

/// Runs a command-line tool. Tests inject a recorder.
protocol ProcessRunning: Sendable {
    func run(_ executable: URL, _ arguments: [String]) async -> ProcessResult
}

struct ProcessResult: Equatable, Sendable {
    var status: Int32
    var output: String

    var succeeded: Bool { status == 0 }
}

/// Where the apps Soprano Desktop themes are installed. Tests inject fixed answers.
protocol AppLocating: Sendable {
    /// The app bundle for a bundle identifier, nil when it is not installed.
    func application(bundleIdentifier: String) -> URL?
    /// The first executable called `name` in the usual install locations.
    func executable(named name: String) -> URL?
}
