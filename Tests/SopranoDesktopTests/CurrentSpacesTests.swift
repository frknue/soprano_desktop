import AppKit
import Testing
@testable import SopranoDesktopCore

struct CurrentSpacesTests {
    @Test func eachDisplayMapsToItsCurrentDesktopSpaceAndFullscreenAppsAreLeftOut() {
        let displays: [[String: Any]] = [
            ["Display Identifier": "UUID-1", "Current Space": ["id64": NSNumber(value: 3), "type": NSNumber(value: 0)]],
            ["Display Identifier": "UUID-2", "Current Space": ["ManagedSpaceID": NSNumber(value: 9), "type": NSNumber(value: 4)]],
            ["Current Space": ["id64": NSNumber(value: 5)]],
        ]
        #expect(CurrentSpaces.parse(displays) == ["UUID-1": "3"])
    }

    @Test func displaysWithoutSeparateSpacesShareTheMainEntry() {
        let spaces = CurrentSpaces.parse([
            ["Display Identifier": "Main", "Current Space": ["id64": NSNumber(value: 12)]],
        ])
        #expect(CurrentSpaces.space(forDisplay: "UUID-1", in: spaces) == "12")
        #expect(CurrentSpaces.space(forDisplay: "UUID-1", in: [:]) == nil)
    }
}
