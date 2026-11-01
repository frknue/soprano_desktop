import Foundation

/// One setting in a line-based config file, edited in place so every other line, comment and
/// blank line stays as the user wrote it.
///
/// - `.ghostty`: `key = value` (Ghostty's config; `#` starts a comment line). Ghostty lets a
///   later line override an earlier one, so the last active line is the value in force.
/// - `.argument`: `--key=value` or `--key value`, one command-line argument per line
///   (bat's config; `#` comments).
///
/// Values are the raw text after the separator (quotes included), so restoring writes
/// back exactly what was there.
public struct LineSetting: Equatable, Sendable {
    public enum Syntax: Equatable, Sendable {
        case ghostty
        case argument
    }

    public let key: String
    public let syntax: Syntax

    public init(key: String, syntax: Syntax) {
        self.key = key
        self.syntax = syntax
    }

    /// The value of the last active line for `key`, or nil when there is none.
    public func value(in text: String) -> String? {
        lines(of: text).compactMap(parse).last
    }

    /// `value` replaces the value of the last active line for `key` (appending a line when
    /// there is none); nil removes every active line for `key`. Other lines are untouched.
    public func setting(_ value: String?, in text: String) -> String {
        var lines = lines(of: text)
        let indices = lines.indices.filter { parse(lines[$0]) != nil }
        if let value {
            let line = format(value)
            if let last = indices.last {
                lines[last] = line
            } else {
                if let lastLine = lines.last, lastLine.isEmpty {
                    lines.removeLast()
                }
                lines.append(line)
                lines.append("")
            }
        } else {
            for index in indices.reversed() {
                lines.remove(at: index)
            }
        }
        return lines.joined(separator: "\n")
    }

    private func lines(of text: String) -> [String] {
        text.isEmpty ? [""] : text.components(separatedBy: "\n")
    }

    private func format(_ value: String) -> String {
        switch syntax {
        case .ghostty: "\(key) = \(value)"
        case .argument: "--\(key)=\(value)"
        }
    }

    /// The value of `line` when it is an active line for `key`.
    private func parse(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#") else { return nil }
        switch syntax {
        case .ghostty:
            guard let equals = trimmed.firstIndex(of: "=") else { return nil }
            let name = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
            guard name == key else { return nil }
            return trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        case .argument:
            let flag = "--\(key)"
            guard trimmed.hasPrefix(flag) else { return nil }
            let rest = trimmed.dropFirst(flag.count)
            if rest.hasPrefix("=") {
                return String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            if let first = rest.first, first == " " || first == "\t" {
                return rest.trimmingCharacters(in: .whitespaces)
            }
            return nil
        }
    }
}

/// One top-level key of a JSONC settings file (VS Code, Cursor), read and written through
/// the vendored `JSONCText`, so comments, key order and trailing commas survive.
public struct JSONCSetting: Equatable, Sendable {
    /// The whole key, dots included: `workbench.colorTheme` is one key in VS Code.
    public let key: String

    public init(key: String) {
        self.key = key
    }

    /// The key's value; nil when the key is absent. Throws when the document is not a JSONC
    /// object.
    public func value(in text: String) throws -> JSONValue? {
        let root = try Self.root(of: text)
        return root[key].flatMap(JSONValue.init(any:))
    }

    /// Sets the key (nil removes it), keeping everything else. An empty document becomes an
    /// object. Throws when the document is not a JSONC object.
    public func setting(_ value: JSONValue?, in text: String) throws -> String {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "{}\n" : text
        _ = try Self.root(of: source)
        if let value {
            return try JSONCText.setting(value.any, at: [key], in: source)
        }
        guard try Self.root(of: source)[key] != nil else { return source }
        return try JSONCText.removing(at: [key], in: source)
    }

    private static func root(of text: String) throws -> [String: Any] {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [:] }
        let data = try JSONCText.strictJSONData(from: text)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw JSONCSettingError.notAnObject
        }
        return root
    }
}

public enum JSONCSettingError: Error, Equatable, Sendable {
    case notAnObject
}
