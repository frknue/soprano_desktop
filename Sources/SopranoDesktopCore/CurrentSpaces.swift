import Foundation

/// The desktop Space each display shows now, from WindowServer's managed display spaces
/// (`CGSCopyManagedDisplaySpaces`). macOS keeps one desktop picture per Space and display,
/// so a wallpaper original is only restorable on the Space it was read from.
public enum CurrentSpaces {
    /// "Display Identifier" when displays do not have separate Spaces.
    public static let mainDisplayIdentifier = "Main"
    /// `type` of a fullscreen app's Space (0 is a desktop Space).
    static let fullscreenSpaceType = 4

    /// Display identifier (a display UUID, or `Main`) → id of its current desktop Space.
    /// Displays showing a fullscreen app, and entries without an identifier or Space id,
    /// are left out.
    public static func parse(_ displays: [[String: Any]]) -> [String: String] {
        var result: [String: String] = [:]
        for display in displays {
            guard let identifier = display["Display Identifier"] as? String,
                  let current = display["Current Space"] as? [String: Any],
                  let id = spaceID(of: current)
            else { continue }
            if (current["type"] as? NSNumber)?.intValue == fullscreenSpaceType { continue }
            result[identifier] = id
        }
        return result
    }

    /// The current Space of the display with `uuid`: its own entry, else the shared `Main`
    /// entry (displays without separate Spaces).
    public static func space(forDisplay uuid: String, in spaces: [String: String]) -> String? {
        spaces[uuid] ?? spaces[mainDisplayIdentifier]
    }

    private static func spaceID(of space: [String: Any]) -> String? {
        let number = (space["id64"] as? NSNumber) ?? (space["ManagedSpaceID"] as? NSNumber)
        return number.map { String($0.uint64Value) }
    }
}
