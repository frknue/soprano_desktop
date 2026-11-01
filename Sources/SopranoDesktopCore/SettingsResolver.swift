import Foundation

/// settings.json → `DesktopSettings`. Every key is optional; a bad value keeps its default and
/// becomes a `.warning` naming its dotted path; unknown keys warn.
public enum SettingsResolver {
    /// JSONC (comments, trailing commas) → settings over the defaults. A document that is
    /// not a JSON object gives `settings == nil` and one `.error` issue with its line.
    public static func resolve(text: String, knownThemeIDs: Set<String>) -> SettingsResolution {
        let root: [String: Any]
        do {
            let data = try JSONCText.strictJSONData(from: text)
            let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            guard let dictionary = object as? [String: Any] else {
                return failure("settings.json must be a JSON object", line: 1)
            }
            root = dictionary
        } catch let error as JSONCText.ParseError {
            return failure(error.message, line: error.line)
        } catch {
            return failure("settings.json could not be read: \(error.localizedDescription)", line: 1)
        }

        var reader = Reader(knownThemeIDs: knownThemeIDs)
        let settings = reader.settings(from: root)
        return SettingsResolution(settings: settings, issues: reader.issues)
    }

    private static func failure(_ message: String, line: Int) -> SettingsResolution {
        SettingsResolution(settings: nil, issues: [ConfigIssue(severity: .error, message: message, line: line)])
    }
}

private struct Reader {
    let knownThemeIDs: Set<String>
    var issues: [ConfigIssue] = []

    static let builtInThemes = [ThemePairResolver.followSopranoID, ThemePairResolver.folioID]

    mutating func settings(from root: [String: Any]) -> DesktopSettings {
        var settings = DesktopSettings()
        warnUnknownKeys(in: root, path: nil, known: ["theme", "system", "apps", "app"])

        if let value = root["theme"] {
            if let id = value as? String, Self.builtInThemes.contains(id) || knownThemeIDs.contains(id) {
                settings.theme = id
            } else {
                let known = (Self.builtInThemes + knownThemeIDs.subtracting(Self.builtInThemes).sorted())
                    .map { "\"\($0)\"" }
                    .joined(separator: ", ")
                warn("theme: \(describe(value)) is not a known theme; kept \"\(settings.theme)\". Known themes: \(known).")
            }
        }
        if let system = section("system", in: root) {
            settings.system = flags(system, path: "system", all: SystemSetting.allCases, current: settings.system)
        }
        if let apps = section("apps", in: root) {
            settings.apps = flags(apps, path: "apps", all: DesktopTarget.allCases, current: settings.apps)
        }
        if let app = section("app", in: root) {
            warnUnknownKeys(in: app, path: "app", known: ["startAtLogin"])
            if let value = app["startAtLogin"] {
                if let flag = boolean(value) {
                    settings.startAtLogin = flag
                } else {
                    warn("app.startAtLogin: \(describe(value)) is not true or false; kept \(settings.startAtLogin).")
                }
            }
        }
        return settings
    }

    /// An object of `"<case>": true | false`; missing keys keep their default.
    private mutating func flags<Value: RawRepresentable & Hashable>(
        _ object: [String: Any],
        path: String,
        all: [Value],
        current: Set<Value>
    ) -> Set<Value> where Value.RawValue == String {
        var result = current
        warnUnknownKeys(in: object, path: path, known: Set(all.map(\.rawValue)))
        for item in all {
            guard let value = object[item.rawValue] else { continue }
            guard let flag = boolean(value) else {
                warn("\(path).\(item.rawValue): \(describe(value)) is not true or false; kept \(current.contains(item)).")
                continue
            }
            if flag {
                result.insert(item)
            } else {
                result.remove(item)
            }
        }
        return result
    }

    private mutating func warn(_ message: String) {
        issues.append(ConfigIssue(severity: .warning, message: message))
    }

    private mutating func warnUnknownKeys(in object: [String: Any], path: String?, known: Set<String>) {
        for key in object.keys.sorted() where !known.contains(key) {
            warn("Unknown setting \"\(path.map { "\($0).\(key)" } ?? key)\".")
        }
    }

    private mutating func section(_ key: String, in object: [String: Any]) -> [String: Any]? {
        guard let value = object[key] else { return nil }
        guard let section = value as? [String: Any] else {
            warn("\(key): \(describe(value)) is not an object; ignored.")
            return nil
        }
        return section
    }

    /// JSON booleans only (JSONSerialization gives NSNumber for both numbers and booleans).
    private func boolean(_ value: Any) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private func describe(_ value: Any) -> String {
        switch value {
        case is NSNull:
            return "null"
        case let string as String:
            return "\"\(string)\""
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            return number.stringValue
        case is [Any]:
            return "an array"
        case is [String: Any]:
            return "an object"
        default:
            return String(describing: value)
        }
    }
}
