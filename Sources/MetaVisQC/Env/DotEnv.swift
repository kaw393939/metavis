import Foundation

#if canImport(Darwin)
import Darwin
#endif

public enum DotEnv {
    /// Parses a dotenv file into a dictionary. Supports `KEY=VALUE`, quoted values, and `#` comments.
    public static func parse(contents: String) -> [String: String] {
        var out: [String: String] = [:]
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.hasPrefix("#") { continue }

            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)

            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            } else if value.hasPrefix("'") && value.hasSuffix("'") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }

            if key.isEmpty { continue }
            out[key] = value
        }
        return out
    }

    public static func load(from url: URL) throws -> [String: String] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        return parse(contents: contents)
    }

    /// Applies dotenv variables to the current process env using `setenv`.
    /// By default, does not overwrite existing environment variables.
    public static func apply(_ vars: [String: String], overwrite: Bool = false) {
        for (k, v) in vars {
            if !overwrite {
                let existing = ProcessInfo.processInfo.environment[k]
                if let existing, !existing.isEmpty { continue }
            }

            k.withCString { kPtr in
                v.withCString { vPtr in
                    _ = setenv(kPtr, vPtr, overwrite ? 1 : 0)
                }
            }
        }
    }

    /// Loads and applies a dotenv file if it exists. Returns the parsed dictionary.
    @discardableResult
    public static func loadAndApplyIfPresent(from url: URL?, overwrite: Bool = false) -> [String: String] {
        guard let url else { return [:] }
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        do {
            let vars = try load(from: url)
            apply(vars, overwrite: overwrite)
            return vars
        } catch {
            return [:]
        }
    }
}
