import Foundation

public enum DotEnvLoader {
    /// Loads a `.env` file into the process environment using `setenv`.
    ///
    /// SwiftPM tests do not automatically source `.env`, so this enables local-only secrets.
    ///
    /// - Important: Does not log or print loaded values.
    public static func loadIfPresent(projectRootHint: URL? = nil, filename: String = ".env") {
        let packageRoot = projectRootHint ?? findPackageRoot()
        let candidates: [URL] = {
            if let root = packageRoot {
                return [root.appendingPathComponent(filename)]
            }
            // Best-effort guesses:
            // - current working directory
            // - walking up from this file
            var urls: [URL] = []
            urls.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(filename))

            var current = URL(fileURLWithPath: #filePath)
            while current.path != "/" {
                current.deleteLastPathComponent()
                urls.append(current.appendingPathComponent(filename))
            }
            return urls
        }()

        guard let envURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            return
        }

        guard let content = try? String(contentsOf: envURL, encoding: .utf8) else { return }

        for rawLine in content.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.hasPrefix("#") { continue }

            // Support `export KEY=VALUE` and `KEY=VALUE`
            let normalized = line.hasPrefix("export ") ? String(line.dropFirst("export ".count)) : line
            guard let eqIndex = normalized.firstIndex(of: "=") else { continue }

            let key = normalized[..<eqIndex].trimmingCharacters(in: .whitespaces)
            var value = normalized[normalized.index(after: eqIndex)...].trimmingCharacters(in: .whitespaces)

            // Strip surrounding quotes
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("\'") && value.hasSuffix("\'")) {
                value = String(value.dropFirst().dropLast())
            }

            guard !key.isEmpty else { continue }
            // do not overwrite existing environment
            if getenv(String(key)) != nil { continue }

            _ = setenv(String(key), value, 0)
        }
    }

    private static func findPackageRoot(startingAt filePath: String = #filePath) -> URL? {
        var current = URL(fileURLWithPath: filePath)
        while current.path != "/" {
            current.deleteLastPathComponent()
            let pkg = current.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: pkg.path) {
                return current
            }
        }
        return nil
    }
}
