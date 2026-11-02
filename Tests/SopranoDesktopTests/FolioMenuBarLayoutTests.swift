import AppKit
import Testing
@testable import SopranoDesktop
@testable import SopranoDesktopCore

struct FolioMenuBarLayoutTests {
    /// Menu bars (global rects) of a 1440-wide primary and a 1920-wide display to its right.
    let primaryBar = CGRect(x: 0, y: 0, width: 1440, height: 24)
    let rightBar = CGRect(x: 1440, y: -180, width: 1920, height: 24)

    @Test func theStripEndsAGapBeforeTheLeftmostStatusItemOnItsMenuBar() {
        let statusItems = [
            CGRect(x: 1300, y: 0, width: 30, height: 24),
            CGRect(x: 1180, y: 0, width: 24, height: 24),
            CGRect(x: 1380, y: 0, width: 60, height: 24),
            // A whole-bar status host window (macOS 26) is not an item.
            CGRect(x: 0, y: 0, width: 1440, height: 24),
            // An item parked off the menu bar (hidden by its app).
            CGRect(x: -1, y: 876, width: 34, height: 24),
        ]
        let widths = FolioMenuBarLayout.stripWidths(menuBars: [primaryBar], statusItems: statusItems, gap: 12)
        #expect(widths == [1168])
    }

    @Test func aMenuBarWithoutReportedStatusItemsKeepsTheSameDistanceFromItsRightEdge() {
        // Status items are reported on the primary only; they sit 260 pt from its right edge.
        let statusItems = [CGRect(x: 1180, y: 0, width: 24, height: 24)]
        let widths = FolioMenuBarLayout.stripWidths(menuBars: [primaryBar, rightBar], statusItems: statusItems, gap: 12)
        #expect(widths == [1168, 1648])
    }

    @Test func withoutAnyStatusItemTheStripCoversFiftyFivePercentOfTheMenuBar() {
        let widths = FolioMenuBarLayout.stripWidths(menuBars: [primaryBar, rightBar], statusItems: [])
        #expect(widths == [792, 1056])
    }

    @Test func titlesSitAtTheirNativeItemsXOnEveryScreen() {
        // The app's menu bar element starts at x 0 on the primary; items are where the
        // native menu bar draws them.
        let items = [
            FolioMenuBarLayout.Item(title: "Apple", frame: CGRect(x: 10, y: 0, width: 34, height: 24)),
            FolioMenuBarLayout.Item(title: "Finder", frame: CGRect(x: 43, y: 0, width: 62, height: 24)),
            FolioMenuBarLayout.Item(title: "File", frame: CGRect(x: 104, y: 0, width: 42, height: 24)),
            FolioMenuBarLayout.Item(title: "", frame: CGRect(x: 145, y: 0, width: 20, height: 24)),
            FolioMenuBarLayout.Item(title: "Edit", frame: CGRect(x: 164, y: 0, width: 44, height: 24)),
            FolioMenuBarLayout.Item(title: "Help", frame: CGRect(x: 207, y: 0, width: 49, height: 24)),
        ]
        let placements = FolioMenuBarLayout.placements(items: items, menuBarOriginX: 0, stripWidth: 200)
        #expect(placements.map(\.title) == ["Apple", "Finder", "File", "Edit"])
        #expect(placements.map(\.role) == [.apple, .application, .menu, .menu])
        #expect(placements.map(\.x) == [10, 43, 104, 164])
        #expect(placements.map(\.index) == [0, 1, 2, 4])
        // Edit starts inside the strip and runs past it: kept (clipped); Help starts past
        // the strip edge and stays native.
        #expect(placements.last!.maxX > 200)

        // The same menus reported on a display that starts at x 1440 land at the same
        // strip-local positions.
        let shifted = items.map { item in
            FolioMenuBarLayout.Item(title: item.title, frame: item.frame.offsetBy(dx: 1440, dy: -180))
        }
        #expect(FolioMenuBarLayout.placements(items: shifted, menuBarOriginX: 1440, stripWidth: 200) == placements)
    }

    @Test func aClickPicksTheTitleUnderThePointer() {
        let placements = FolioMenuBarLayout.placements(
            items: [
                FolioMenuBarLayout.Item(title: "Apple", frame: CGRect(x: 10, y: 0, width: 34, height: 24)),
                FolioMenuBarLayout.Item(title: "Finder", frame: CGRect(x: 44, y: 0, width: 62, height: 24)),
            ],
            menuBarOriginX: 0,
            stripWidth: 500
        )
        #expect(FolioMenuBarLayout.placement(at: 20, in: placements)?.index == 0)
        #expect(FolioMenuBarLayout.placement(at: 44, in: placements)?.index == 1)
        #expect(FolioMenuBarLayout.placement(at: 5, in: placements) == nil)
        #expect(FolioMenuBarLayout.placement(at: 300, in: placements) == nil)
    }

    @MainActor
    @Test func onlyTheAppNameCarriesTheAccentFocusMarkOnPaperWithAHairlineBelow() throws {
        for theme in [AppTheme.folioPaper, AppTheme.folioInk] {
            let colors = theme.colors
            let view = SurfaceSnapshotCommand.menuBarView(colors: colors)
            let bitmap = try SurfaceSnapshotCommand.bitmap(of: view, scale: 1)
            let height = view.bounds.height
            func pixel(_ x: CGFloat, _ y: CGFloat) -> NSColor {
                bitmap.colorAt(x: Int(x), y: Int(height - 1 - y))!
            }
            let app = try #require(view.placements.first { $0.role == .application })
            let file = try #require(view.placements.first { $0.title == "File" })
            #expect(matches(pixel(app.x + app.width / 2, 0), colors.focusMark))
            #expect(matches(pixel(file.x + file.width / 2, 0), colors.borderSubtle))
            #expect(matches(pixel(view.bounds.maxX - 4, height / 2), colors.bgBase))
            #expect(matches(pixel(app.x + 2, height / 2), colors.bgBase))
        }
    }
}
