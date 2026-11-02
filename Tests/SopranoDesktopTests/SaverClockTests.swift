import AppKit
import Testing
@testable import SopranoDesktopCore

struct SaverClockTests {
    private let berlin = TimeZone(identifier: "Europe/Berlin")!

    /// 2026-11-02 at `hour:minute:second` in Berlin (a Monday).
    private func moment(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        return calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 2, hour: hour, minute: minute, second: second
        ))!
    }

    private func clock(_ locale: String) -> SaverClock {
        SaverClock(
            locale: Locale(identifier: locale),
            timeZone: berlin,
            calendar: Calendar(identifier: .gregorian)
        )
    }

    @Test func aTwentyFourHourLocaleShowsPaddedHoursAndATwelveHourOneLeavesOutTheDayPeriod() {
        #expect(clock("de_DE").face(at: moment(14, 7)).time == "14:07")
        #expect(clock("de_DE").face(at: moment(7, 4)).time == "07:04")
        #expect(clock("en_US").face(at: moment(14, 7)).time == "2:07")
        #expect(clock("en_US").face(at: moment(7, 4)).time == "7:04")
    }

    @Test func theDateNamesWeekdayDayAndMonthInTheLocalesOwnOrder() {
        #expect(clock("de_DE").face(at: moment(14, 7)).date == "Montag, 2. November")
        #expect(clock("en_US").face(at: moment(14, 7)).date == "Monday, November 2")
    }

    @Test func theFaceStaysTheSameWithinAMinuteAndChangesWithTheNextOne() {
        let clock = clock("de_DE")
        let start = clock.face(at: moment(14, 7, 0))
        #expect(clock.face(at: moment(14, 7, 59)) == start)
        let next = clock.face(at: moment(14, 8, 0))
        #expect(next != start)
        #expect(next.minute == start.minute + 1)
    }

    @Test func typeScalesWithTheScreenButNeverDropsBelowTheFloors() {
        let preview = SaverLayout(canvas: CGSize(width: 296, height: 184), metaSize: 11)
        #expect(preview.dateSize == 11)
        #expect(preview.timeSize >= 15)

        let laptop = SaverLayout(canvas: CGSize(width: 1512, height: 982), metaSize: 11)
        let studio = SaverLayout(canvas: CGSize(width: 2560, height: 1440), metaSize: 11)
        #expect(laptop.timeSize > preview.timeSize)
        #expect(studio.timeSize > laptop.timeSize)
        #expect(studio.dateSize > laptop.dateSize)
        #expect(laptop.timeSize > laptop.dateSize * 4)
    }

    @Test func theBlockDriftsAFewPointsEachMinuteAndNeverLeavesTheMargin() {
        let layout = SaverLayout(canvas: CGSize(width: 1512, height: 982), metaSize: 11)
        let block = CGSize(width: 420, height: 230)
        var previous = layout.blockOrigin(block: block, minute: 29_000_000)
        var visited = Set<String>()
        for minute in 29_000_001...29_006_000 {
            let origin = layout.blockOrigin(block: block, minute: minute)
            #expect(origin.x >= layout.margin && origin.x + block.width <= 1512 - layout.margin)
            #expect(origin.y >= layout.margin && origin.y + block.height <= 982 - layout.margin)
            let step = hypot(origin.x - previous.x, origin.y - previous.y)
            #expect(step <= 40)
            visited.insert("\(origin.x),\(origin.y)")
            previous = origin
        }
        // Over a few days the block covers a wide spread of positions instead of a few spots.
        #expect(visited.count > 1000)
    }

    @Test func aBlockLargerThanTheScreenIsCentredInsteadOfDrifting() {
        let layout = SaverLayout(canvas: CGSize(width: 296, height: 184), metaSize: 11)
        let origin = layout.blockOrigin(block: CGSize(width: 400, height: 300), minute: 12_345)
        #expect(origin == CGPoint(x: -52, y: -58))
    }
}
