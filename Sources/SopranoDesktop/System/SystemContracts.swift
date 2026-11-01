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
    /// The display's UUID: stable across reconnects, unlike its `CGDirectDisplayID`.
    var id: String
    /// `localizedName`, for messages.
    var name: String
    /// The desktop Space the screen shows now; nil when unknown (the private Spaces API is
    /// missing) or when it shows a fullscreen app. The wallpaper is only touched where this
    /// is known, because macOS keeps one picture per Space.
    var spaceID: String?
    /// Backing pixels.
    var pixelWidth: Int
    var pixelHeight: Int
    /// Pixels per point.
    var scale: Double
}

/// What a screen shows: the picture and how it is scaled and padded.
struct DesktopPicture: Equatable, Sendable {
    var url: URL
    /// `NSImageScaling.rawValue`; nil when macOS did not report it.
    var scaling: Int? = nil
    var allowClipping: Bool? = nil
    /// The colour around a picture that does not cover the screen.
    var fillColor: RGB? = nil
}

/// The screens and their desktop pictures (NSWorkspace). Tests inject a fake.
@MainActor
protocol DesktopPictures: AnyObject {
    func screens() -> [ScreenInfo]
    func picture(forScreen id: String) -> DesktopPicture?
    func setPicture(_ picture: DesktopPicture, forScreen id: String) throws
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
