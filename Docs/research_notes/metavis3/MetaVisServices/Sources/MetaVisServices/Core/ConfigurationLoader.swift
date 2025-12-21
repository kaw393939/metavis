import Foundation

/// Responsible for loading configuration from the environment.
/// It looks for a .env file in the project root or uses ProcessInfo.
public struct ConfigurationLoader {
    
    private var envCache: [String: String] = [:]
    
    public init() {
        loadEnvFile()
    }
    
    /// Loads the .env file from the project root if it exists.
    private mutating func loadEnvFile() {
        // Attempt to find the project root.
        // In a real app bundle, this logic might differ, but for this workspace:
        let fileManager = FileManager.default
        let currentPath = fileManager.currentDirectoryPath
        
        // Look up to 3 levels up for .env
        var searchPath = URL(fileURLWithPath: currentPath)
        for _ in 0..<3 {
            let envPath = searchPath.appendingPathComponent(".env")
            if fileManager.fileExists(atPath: envPath.path) {
                parseEnvFile(at: envPath)
                return
            }
            searchPath = searchPath.deletingLastPathComponent()
        }
    }
    
    private mutating func parseEnvFile(at url: URL) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            
            let parts = trimmed.split(separator: "=", maxSplits: 1).map { String($0) }
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                // Remove quotes if present
                let cleanValue = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                envCache[key] = cleanValue
            }
        }
    }
    
    /// Retrieves a value from the loaded .env or ProcessInfo environment.
    public func get(_ key: String) -> String? {
        // 1. Check cache (.env)
        if let value = envCache[key] {
            return value
        }
        // 2. Check ProcessInfo (System Env)
        return ProcessInfo.processInfo.environment[key]
    }
    
    /// Throws if the key is missing.
    public func require(_ key: String) throws -> String {
        guard let value = get(key) else {
            throw ServiceError.configurationError("Missing required environment variable: \(key)")
        }
        return value
    }
}
