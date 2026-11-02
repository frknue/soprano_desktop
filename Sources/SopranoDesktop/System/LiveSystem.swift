import AppKit
import Darwin
import notify
import SopranoDesktopCore

/// `defaults` through CFPreferences (current user, any host: what `defaults write` writes).
/// Only the given key changes; the rest of the domain is kept.
final class LivePreferences: PreferencesStore {
    func value(forKey key: String, domain: String) -> Any? {
        CFPreferencesCopyValue(key as CFString, Self.application(domain), kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    func setValue(_ value: Any?, forKey key: String, domain: String) throws {
        let application = Self.application(domain)
        CFPreferencesSetValue(key as CFString, value.map { $0 as CFPropertyList }, application, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard CFPreferencesSynchronize(application, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            throw PreferencesError.refused(domain: domain)
        }
    }

    func post(_ notification: PreferenceNotification) {
        switch notification {
        case let .distributed(name):
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name(name), object: nil, userInfo: nil, deliverImmediately: true
            )
        case let .darwin(name):
            notify_post(name)
        }
    }

    private static func application(_ domain: String) -> CFString {
        domain == PreferencesDomain.global ? kCFPreferencesAnyApplication : domain as CFString
    }
}

enum PreferencesError: Error, LocalizedError {
    case refused(domain: String)

    var errorDescription: String? {
        switch self {
        case let .refused(domain): "macOS refused to change \(domain)"
        }
    }
}

/// Screens and desktop pictures through NSScreen and NSWorkspace. macOS sets a picture on
/// the current Space of each screen; the current Space comes from the private
/// `CGSCopyManagedDisplaySpaces` (resolved with `dlsym`, so a macOS without it gives nil
/// Spaces and the wallpaper is left alone).
@MainActor
final class LiveDesktopPictures: DesktopPictures {
    func screens() -> [ScreenInfo] {
        let spaces = CurrentSpaces.parse(PrivateSpaces.managedDisplaySpaces())
        return NSScreen.screens.compactMap { screen in
            guard let id = Self.id(of: screen) else { return nil }
            let size = screen.convertRectToBacking(screen.frame).size
            return ScreenInfo(
                id: id,
                name: screen.localizedName,
                spaceID: CurrentSpaces.space(forDisplay: id, in: spaces),
                pixelWidth: Int(size.width.rounded()),
                pixelHeight: Int(size.height.rounded()),
                scale: Double(screen.backingScaleFactor)
            )
        }
    }

    func picture(forScreen id: String) -> DesktopPicture? {
        guard let screen = screen(id), let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
        return DesktopPicture(
            url: url,
            scaling: (options[.imageScaling] as? NSNumber)?.intValue,
            allowClipping: (options[.allowClipping] as? NSNumber)?.boolValue,
            fillColor: (options[.fillColor] as? NSColor).map(PaletteBridge.rgb)
        )
    }

    func setPicture(_ picture: DesktopPicture, forScreen id: String) throws {
        guard let screen = screen(id) else { return }
        var options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
        if let scaling = picture.scaling {
            options[.imageScaling] = NSNumber(value: scaling)
        }
        if let allowClipping = picture.allowClipping {
            options[.allowClipping] = NSNumber(value: allowClipping)
        }
        if let fillColor = picture.fillColor {
            options[.fillColor] = PaletteBridge.color(fillColor)
        }
        try NSWorkspace.shared.setDesktopImageURL(picture.url, for: screen, options: options)
    }

    private func screen(_ id: String) -> NSScreen? {
        NSScreen.screens.first { Self.id(of: $0) == id }
    }

    /// The display's UUID (what CGSCopyManagedDisplaySpaces calls "Display Identifier").
    private static func id(of screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

/// The one private SkyLight call Soprano Desktop makes, resolved at first use.
enum PrivateSpaces {
    private typealias MainConnectionIDFn = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private struct Symbols: @unchecked Sendable {
        let mainConnectionID: MainConnectionIDFn?
        let copyManagedDisplaySpaces: CopyManagedDisplaySpacesFn?
    }

    private static let symbols: Symbols = {
        let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        func load<T>(_ name: String) -> T? {
            dlsym(skyLight, name).map { unsafeBitCast($0, to: T.self) }
        }
        return Symbols(
            mainConnectionID: load("CGSMainConnectionID"),
            copyManagedDisplaySpaces: load("CGSCopyManagedDisplaySpaces")
        )
    }()

    /// [] when the symbols are missing.
    static func managedDisplaySpaces() -> [[String: Any]] {
        guard let connection = symbols.mainConnectionID?(),
              let function = symbols.copyManagedDisplaySpaces,
              let array = function(connection)?.takeRetainedValue() as? [[String: Any]]
        else { return [] }
        return array
    }
}

/// `Process`, awaited without blocking the main thread. The output is drained while the
/// process runs (a full pipe would otherwise block the tool and it would never exit).
struct LiveProcessRunner: ProcessRunning {
    func run(_ executable: URL, _ arguments: [String]) async -> ProcessResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                process.standardInput = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: ProcessResult(status: -1, output: error.localizedDescription))
                    return
                }
                // EOF arrives when the process (and anything it spawned holding the pipe) exits.
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: ProcessResult(
                    status: process.terminationStatus,
                    output: String(decoding: data, as: UTF8.self)
                ))
            }
        }
    }
}

/// Apps through Launch Services; command-line tools in the usual Homebrew and system
/// locations (a menu-bar app does not inherit the login shell's PATH).
struct LiveAppLocator: AppLocating {
    static let searchPath = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]

    func application(bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    func executable(named name: String) -> URL? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path
        let directories = Self.searchPath + ["\(home)/.local/bin", "\(home)/bin"]
        return directories
            .map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}
