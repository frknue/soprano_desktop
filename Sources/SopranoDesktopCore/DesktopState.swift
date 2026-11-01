import Foundation

/// A JSON value that round-trips through `Codable` and `JSONSerialization`.
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// From a `JSONSerialization` value; nil for anything else.
    public init?(any value: Any) {
        switch value {
        case is NSNull:
            self = .null
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case let string as String:
            self = .string(string)
        case let array as [Any]:
            var values: [JSONValue] = []
            for element in array {
                guard let value = JSONValue(any: element) else { return nil }
                values.append(value)
            }
            self = .array(values)
        case let object as [String: Any]:
            var values: [String: JSONValue] = [:]
            for (key, element) in object {
                guard let value = JSONValue(any: element) else { return nil }
                values[key] = value
            }
            self = .object(values)
        default:
            return nil
        }
    }

    /// The `JSONSerialization` / `JSONCText` value.
    public var any: Any {
        switch self {
        case .null: NSNull()
        case let .bool(value): value
        case let .number(value):
            value == value.rounded() && abs(value) < 1e15 ? Int(value) as Any : value as Any
        case let .string(value): value
        case let .array(values): values.map(\.any)
        case let .object(values): values.mapValues(\.any)
        }
    }

    public var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(values): try container.encode(values)
        case let .object(values): try container.encode(values)
        }
    }
}

/// Soprano Desktop's persisted state (`~/Library/Application Support/Soprano Desktop/state.json`).
///
/// While `active`, every enabled setting is kept on the Soprano theme. `originals` holds, per
/// setting id, what the setting held before the first change (its record: the value, or
/// for a config file the whole text plus each key's value); it is written once per setting
/// and survives re-applies, so Restore always returns to the user's own values, never to
/// an earlier Soprano value. `written` holds the text Soprano Desktop last wrote to each
/// config file, so Restore can tell an untouched file (put the original text back
/// byte-for-byte) from one the user edited since (revert only Soprano's keys).
public struct DesktopState: Equatable, Sendable, Codable {
    public var active: Bool
    public var originals: [String: JSONValue]
    public var written: [String: String]
    /// Content hash of the editor extension last installed per app (`vscode`, `cursor`), so
    /// it is rebuilt and reinstalled only when the theme changed.
    public var packages: [String: String]

    public init(
        active: Bool = false,
        originals: [String: JSONValue] = [:],
        written: [String: String] = [:],
        packages: [String: String] = [:]
    ) {
        self.active = active
        self.originals = originals
        self.written = written
        self.packages = packages
    }

    private enum CodingKeys: String, CodingKey {
        case active, originals, written, packages
    }

    /// Keys added in later versions are optional, so an older state.json still loads.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        active = try container.decode(Bool.self, forKey: .active)
        originals = try container.decode([String: JSONValue].self, forKey: .originals)
        written = try container.decodeIfPresent([String: String].self, forKey: .written) ?? [:]
        packages = try container.decodeIfPresent([String: String].self, forKey: .packages) ?? [:]
    }

    public static func decode(_ data: Data) throws -> DesktopState {
        try JSONDecoder().decode(DesktopState.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
