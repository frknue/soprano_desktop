import Foundation

/// What the Folio screen saver shows during one minute.
public struct SaverFace: Equatable, Sendable {
    /// Whole minutes since 1970; the face changes when this does.
    public let minute: Int
    /// Hours and minutes in the locale's hour cycle, without a day period (`14:07`, `2:07`).
    public let time: String
    /// Weekday, day and month in the locale's order (`Montag, 2. November`).
    public let date: String
}

/// Turns a moment into the saver's face. Value-typed format styles, so the saver can build
/// a face every second and compare it with the one on screen instead of keeping a timer per
/// minute.
public struct SaverClock: Sendable {
    private let timeStyle: Date.FormatStyle
    private let dateStyle: Date.FormatStyle

    public init(
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        let base = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone)
        // 24-hour locales pad the hour (`07:04`), 12-hour ones do not (`7:04`), as in their
        // own short time format; the day period is left out either way.
        let twelveHour = [.oneToTwelve, .zeroToEleven].contains(locale.hourCycle)
        timeStyle = base
            .hour(twelveHour ? .defaultDigits(amPM: .omitted) : .twoDigits(amPM: .omitted))
            .minute(.twoDigits)
        dateStyle = base.weekday(.wide).day(.defaultDigits).month(.wide)
    }

    public func face(at moment: Date) -> SaverFace {
        SaverFace(
            minute: Int((moment.timeIntervalSince1970 / 60).rounded(.down)),
            time: moment.formatted(timeStyle),
            date: moment.formatted(dateStyle)
        )
    }
}

/// Type scales with the canvas's short side against a 360-pt reference: the date is the
/// chrome meta size scaled and never drops below it (Folio's 11-pt floor; it only bites in
/// the small System Settings preview), the time is New York display type at 5.8 times the
/// scaled meta size. The block drifts on a slow Lissajous path, one step per minute, so no
/// pixel holds the same ink for long (burn-in) yet the clock never jumps across the screen.
public struct SaverLayout: Sendable {
    public let canvas: CGSize
    /// Canvas short side over the 360-pt reference.
    public let scale: CGFloat
    /// Point size of the time (New York, light, tabular figures).
    public let timeSize: CGFloat
    /// Point size of the date (SF Pro): the meta size scaled.
    public let dateSize: CGFloat
    /// From the time's baseline to the top of the date's capitals.
    public let lineGap: CGFloat
    /// From the pencil tick to the text.
    public let tickGap: CGFloat
    /// Width of the pencil tick, the family's single accent mark. Never scaled.
    public static let tickWidth: CGFloat = 2

    /// Kept clear on every side, whatever the drift.
    public var margin: CGFloat { (min(canvas.width, canvas.height) * 0.08).rounded() }

    /// How far the block's centre may move from the canvas centre, as a share of the canvas
    /// on each axis: enough to keep moving ink off every pixel, little enough that the clock
    /// stays a centred composition rather than wandering into the corners.
    public static let driftReach: CGFloat = 0.15

    public init(canvas: CGSize, metaSize: CGFloat) {
        self.canvas = canvas
        scale = min(canvas.width, canvas.height) / 360
        let unit = metaSize * scale
        dateSize = max(metaSize, unit.rounded())
        timeSize = max(15, (unit * 5.8).rounded())
        lineGap = max(4, (unit * 1.1).rounded())
        tickGap = max(4, (unit * 0.9).rounded())
    }

    /// The drift position for `minute`, each component in -1...1. Two sines with coprime
    /// periods (97 and 61 minutes) trace a Lissajous figure: neighbouring minutes sit a few
    /// percent of the range apart, and the path repeats only every 97 × 61 minutes.
    public static func drift(minute: Int) -> CGPoint {
        let m = Double(minute)
        return CGPoint(
            x: sin(2 * .pi * m / 97),
            y: sin(2 * .pi * m / 61 + 1)
        )
    }

    /// Lower-left corner of a `block`-sized box for `minute`, on whole points, inside the
    /// margin. A block wider or taller than the free space is centred on that axis.
    public func blockOrigin(block: CGSize, minute: Int) -> CGPoint {
        let drift = Self.drift(minute: minute)
        func place(_ length: CGFloat, in extent: CGFloat, by amount: CGFloat) -> CGFloat {
            let reach = max(0, min((extent - length) / 2 - margin, extent * Self.driftReach))
            return ((extent - length) / 2 + amount * reach).rounded()
        }
        return CGPoint(
            x: place(block.width, in: canvas.width, by: drift.x),
            y: place(block.height, in: canvas.height, by: drift.y)
        )
    }
}
