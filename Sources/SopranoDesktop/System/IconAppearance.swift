import CoreGraphics
import Foundation
import ObjectiveC
import SopranoDesktopCore

/// Appearance → Icon & widget style and Folder colour, as SkyLight stores them
/// (`SLSIconAppearanceConfiguration`; persisted as `AppleIconAppearanceTheme`,
/// `AppleIconAppearanceTintColor` and `AppleIconAppearanceCustomTintColor` in the global
/// domain). Values observed on macOS 27 by flipping the settings in System Settings.
struct IconAppearance: Equatable, Sendable {
    /// `iconAppearanceTheme`: RegularDark 2, TintedAutomatic 6, TintedLight 7, TintedDark 8.
    var theme: UInt32
    /// `iconTintColorName`: Automatic 0, Orange 3, Other 10 (uses `color`).
    var tint: UInt32
    /// The custom tint while `tint` is `other`.
    var color: RGB?

    static let tintAutomatic: UInt32 = 0
    static let tintOther: UInt32 = 10

    var json: JSONValue {
        .object([
            "theme": .number(Double(theme)),
            "tint": .number(Double(tint)),
            "color": color.map { .string($0.hex) } ?? .null,
        ])
    }

    init(theme: UInt32, tint: UInt32, color: RGB?) {
        self.theme = theme
        self.tint = tint
        self.color = color
    }

    init?(json: JSONValue) {
        guard case let .object(object) = json,
              case let .number(theme) = object["theme"],
              case let .number(tint) = object["tint"]
        else { return nil }
        self.init(theme: UInt32(theme), tint: UInt32(tint), color: object["color"]?.stringValue.flatMap(RGB.init(hex:)))
    }
}

/// Reads and saves the icon appearance. Tests inject a fake.
@MainActor
protocol IconAppearanceStore: AnyObject {
    /// nil when macOS has no such configuration (older than macOS 26).
    func read() -> IconAppearance?
    func write(_ appearance: IconAppearance) throws
}

/// SkyLight's `SLSIconAppearanceConfiguration`, resolved at runtime: `fetchCurrent…`, the
/// setters, then `save`, which applies it system-wide and persists it (what System Settings
/// does).
@MainActor
final class LiveIconAppearance: IconAppearanceStore {
    private typealias U32Getter = @convention(c) (AnyObject, Selector) -> UInt32
    private typealias U32Setter = @convention(c) (AnyObject, Selector, UInt32) -> Void
    private typealias ColorGetter = @convention(c) (AnyObject, Selector) -> Unmanaged<CGColor>?
    private typealias ColorSetter = @convention(c) (AnyObject, Selector, CGColor?) -> Void
    private typealias Action = @convention(c) (AnyObject, Selector) -> Void

    private let configurationClass: NSObject.Type? = {
        _ = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        return NSClassFromString("SLSIconAppearanceConfiguration") as? NSObject.Type
    }()

    func read() -> IconAppearance? {
        guard let configuration = fetch() else { return nil }
        let unmanaged = call(configuration, "otherIconTintColor", as: ColorGetter.self) { $0(configuration, $1) } ?? nil
        let color = unmanaged?.takeUnretainedValue()
        return IconAppearance(
            theme: call(configuration, "iconAppearanceTheme", as: U32Getter.self) { $0(configuration, $1) } ?? 0,
            tint: call(configuration, "iconTintColorName", as: U32Getter.self) { $0(configuration, $1) } ?? 0,
            color: color.flatMap(Self.rgb)
        )
    }

    func write(_ appearance: IconAppearance) throws {
        guard let configuration = fetch() else { throw IconAppearanceError.unavailable }
        let color = appearance.color.map { CGColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: 1) }
        let done = [
            call(configuration, "setIconAppearanceTheme:", as: U32Setter.self) { $0(configuration, $1, appearance.theme) },
            call(configuration, "setIconTintColorName:", as: U32Setter.self) { $0(configuration, $1, appearance.tint) },
            call(configuration, "setOtherIconTintColor:", as: ColorSetter.self) { $0(configuration, $1, color) },
            call(configuration, "save", as: Action.self) { $0(configuration, $1) },
        ]
        guard done.allSatisfy({ $0 != nil }) else { throw IconAppearanceError.unavailable }
    }

    private func fetch() -> NSObject? {
        guard let configurationClass else { return nil }
        let selector = NSSelectorFromString("fetchCurrentIconAppearanceConfiguration")
        guard configurationClass.responds(to: selector) else { return nil }
        return configurationClass.perform(selector)?.takeUnretainedValue() as? NSObject
    }

    /// Calls `name` through its IMP when the object responds to it; nil otherwise.
    private func call<F, R>(_ object: NSObject, _ name: String, as type: F.Type, _ body: (F, Selector) -> R) -> R? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return nil }
        return body(unsafeBitCast(object.method(for: selector), to: type), selector)
    }

    private static func rgb(_ color: CGColor) -> RGB? {
        guard let srgb = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let components = srgb.components, components.count >= 3
        else { return nil }
        return RGB(red: Double(components[0]), green: Double(components[1]), blue: Double(components[2]))
    }
}

enum IconAppearanceError: Error, LocalizedError {
    case unavailable

    var errorDescription: String? {
        "This macOS has no icon & folder colour settings Soprano Desktop can change."
    }
}
