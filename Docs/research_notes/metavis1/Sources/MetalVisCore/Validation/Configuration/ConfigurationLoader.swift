// Sources/MetalVisCore/Validation/Configuration/ConfigurationLoader.swift
// MetaVis Studio - Autonomous Development Infrastructure

import Foundation
import Yams

/// Loads and parses YAML configuration files for the validation system.
/// Provides clear error messages for debugging and autonomous development.
public actor ConfigurationLoader {
    
    /// Base path for configuration files
    private let basePath: String
    
    /// Cached settings
    private var cachedSettings: ValidationSettings?
    
    /// Cached effect definitions
    private var cachedEffects: [String: EffectDefinition] = [:]
    
    public init(basePath: String = "assets/config") {
        self.basePath = basePath
    }
    
    // MARK: - Loading Methods
    
    /// Load global validation settings
    public func loadSettings() throws -> ValidationSettings {
        if let cached = cachedSettings {
            return cached
        }
        
        let path = "\(basePath)/validation_settings.yaml"
        let settings = try loadYAML(ValidationSettings.self, from: path)
        cachedSettings = settings
        return settings
    }
    
    /// Load a specific effect definition
    public func loadEffect(id: String) throws -> EffectDefinition {
        if let cached = cachedEffects[id] {
            return cached
        }
        
        let path = "\(basePath)/effects/\(id).yaml"
        let effect = try loadYAML(EffectDefinition.self, from: path)
        
        // Validate that the ID matches the filename
        guard effect.id == id else {
            throw ConfigurationError.idMismatch(
                expected: id,
                actual: effect.id,
                file: path
            )
        }
        
        cachedEffects[id] = effect
        return effect
    }
    
    /// Load all effect definitions from the effects directory
    public func loadAllEffects() throws -> [EffectDefinition] {
        let effectsPath = "\(basePath)/effects"
        let fileManager = FileManager.default
        
        guard let files = try? fileManager.contentsOfDirectory(atPath: effectsPath) else {
            throw ConfigurationError.directoryNotFound(effectsPath)
        }
        
        var effects: [EffectDefinition] = []
        var errors: [ConfigurationError] = []
        
        for file in files where file.hasSuffix(".yaml") || file.hasSuffix(".yml") {
            let id = file.replacingOccurrences(of: ".yaml", with: "")
                         .replacingOccurrences(of: ".yml", with: "")
            
            do {
                let effect = try loadEffect(id: id)
                effects.append(effect)
            } catch let error as ConfigurationError {
                errors.append(error)
            } catch {
                errors.append(.parsingFailed(file: "\(effectsPath)/\(file)", message: error.localizedDescription))
            }
        }
        
        // If any errors, report them all
        if !errors.isEmpty {
            throw ConfigurationError.multipleErrors(errors)
        }
        
        return effects.sorted { $0.name < $1.name }
    }
    
    /// Reload all configuration (clears cache)
    public func reload() throws -> (settings: ValidationSettings, effects: [EffectDefinition]) {
        cachedSettings = nil
        cachedEffects = [:]
        
        let settings = try loadSettings()
        let effects = try loadAllEffects()
        
        return (settings, effects)
    }
    
    // MARK: - Async Convenience Methods (for ValidationRunner)
    
    /// Async wrapper to load all effect definitions
    public func loadAllEffectDefinitions() throws -> [EffectDefinition] {
        return try loadAllEffects()
    }
    
    /// Async wrapper to load a single effect definition
    public func loadEffectDefinition(named id: String) throws -> EffectDefinition {
        return try loadEffect(id: id)
    }
    
    // MARK: - Private Helpers
    
    private func loadYAML<T: Decodable>(_ type: T.Type, from path: String) throws -> T {
        let fileManager = FileManager.default
        
        // Check if file exists
        guard fileManager.fileExists(atPath: path) else {
            throw ConfigurationError.fileNotFound(path)
        }
        
        // Read file contents
        guard let contents = fileManager.contents(atPath: path),
              let yamlString = String(data: contents, encoding: .utf8) else {
            throw ConfigurationError.readFailed(path)
        }
        
        // Parse YAML
        do {
            let decoder = YAMLDecoder()
            return try decoder.decode(type, from: yamlString)
        } catch let error as DecodingError {
            throw ConfigurationError.decodingFailed(
                file: path,
                detail: formatDecodingError(error)
            )
        } catch {
            throw ConfigurationError.parsingFailed(
                file: path,
                message: error.localizedDescription
            )
        }
    }
    
    private func formatDecodingError(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            return "Missing required key '\(key.stringValue)' at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
            
        case .typeMismatch(let type, let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "Type mismatch at '\(path)': expected \(type)"
            
        case .valueNotFound(let type, let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "Value not found at '\(path)': expected \(type)"
            
        case .dataCorrupted(let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "Data corrupted at '\(path)': \(context.debugDescription)"
            
        @unknown default:
            return "Unknown decoding error"
        }
    }
    
    // MARK: - Validation
    
    /// Validate configuration files and return a report
    public func validate() async -> ConfigurationValidationReport {
        var report = ConfigurationValidationReport()
        
        // Validate settings
        do {
            let settings = try loadSettings()
            report.settingsValid = true
            report.settingsVersion = settings.version
        } catch {
            report.settingsValid = false
            report.settingsError = formatError(error)
        }
        
        // Validate each effect file
        let effectsPath = "\(basePath)/effects"
        let fileManager = FileManager.default
        
        if let files = try? fileManager.contentsOfDirectory(atPath: effectsPath) {
            for file in files where file.hasSuffix(".yaml") || file.hasSuffix(".yml") {
                let id = file.replacingOccurrences(of: ".yaml", with: "")
                             .replacingOccurrences(of: ".yml", with: "")
                
                do {
                    let effect = try loadEffect(id: id)
                    report.effectsStatus[id] = .valid(
                        name: effect.name,
                        version: effect.version,
                        testCount: effect.validation.tests.count
                    )
                } catch {
                    report.effectsStatus[id] = .invalid(error: formatError(error))
                }
            }
        } else {
            report.effectsDirectoryExists = false
        }
        
        return report
    }
    
    private func formatError(_ error: Error) -> String {
        if let configError = error as? ConfigurationError {
            return configError.description
        }
        return error.localizedDescription
    }
}

// MARK: - Errors

public enum ConfigurationError: Error, CustomStringConvertible {
    case fileNotFound(String)
    case directoryNotFound(String)
    case readFailed(String)
    case parsingFailed(file: String, message: String)
    case decodingFailed(file: String, detail: String)
    case idMismatch(expected: String, actual: String, file: String)
    case multipleErrors([ConfigurationError])
    
    public var description: String {
        switch self {
        case .fileNotFound(let path):
            return "Configuration file not found: \(path)"
            
        case .directoryNotFound(let path):
            return "Configuration directory not found: \(path)"
            
        case .readFailed(let path):
            return "Failed to read configuration file: \(path)"
            
        case .parsingFailed(let file, let message):
            return "YAML parsing failed for \(file): \(message)"
            
        case .decodingFailed(let file, let detail):
            return "Configuration decoding failed for \(file): \(detail)"
            
        case .idMismatch(let expected, let actual, let file):
            return "Effect ID mismatch in \(file): filename suggests '\(expected)' but file contains id: '\(actual)'"
            
        case .multipleErrors(let errors):
            return "Multiple configuration errors:\n" + errors.map { "  - \($0.description)" }.joined(separator: "\n")
        }
    }
    
    /// Agent-friendly structured representation
    public var agentReport: [String: Any] {
        switch self {
        case .fileNotFound(let path):
            return [
                "error_type": "file_not_found",
                "path": path,
                "suggestion": "Create the file at the specified path"
            ]
            
        case .directoryNotFound(let path):
            return [
                "error_type": "directory_not_found",
                "path": path,
                "suggestion": "Create the directory: mkdir -p \(path)"
            ]
            
        case .readFailed(let path):
            return [
                "error_type": "read_failed",
                "path": path,
                "suggestion": "Check file permissions"
            ]
            
        case .parsingFailed(let file, let message):
            return [
                "error_type": "parsing_failed",
                "file": file,
                "message": message,
                "suggestion": "Fix YAML syntax errors"
            ]
            
        case .decodingFailed(let file, let detail):
            return [
                "error_type": "decoding_failed",
                "file": file,
                "detail": detail,
                "suggestion": "Check that YAML structure matches expected schema"
            ]
            
        case .idMismatch(let expected, let actual, let file):
            return [
                "error_type": "id_mismatch",
                "file": file,
                "expected_id": expected,
                "actual_id": actual,
                "suggestion": "Change the id field in the YAML to '\(expected)' or rename the file to '\(actual).yaml'"
            ]
            
        case .multipleErrors(let errors):
            return [
                "error_type": "multiple_errors",
                "count": errors.count,
                "errors": errors.map { $0.agentReport }
            ]
        }
    }
}

extension ConfigurationError: LocalizedError {
    public var errorDescription: String? {
        return description
    }
}

// MARK: - Validation Report

public struct ConfigurationValidationReport: Sendable {
    public var settingsValid: Bool = false
    public var settingsVersion: String?
    public var settingsError: String?
    public var effectsDirectoryExists: Bool = true
    public var effectsStatus: [String: EffectStatus] = [:]
    
    public enum EffectStatus: Sendable {
        case valid(name: String, version: String, testCount: Int)
        case invalid(error: String)
    }
    
    public var allValid: Bool {
        guard settingsValid, effectsDirectoryExists else { return false }
        return effectsStatus.values.allSatisfy {
            if case .valid = $0 { return true }
            return false
        }
    }
    
    public var summary: String {
        var lines: [String] = []
        
        lines.append("Configuration Validation Report")
        lines.append("═══════════════════════════════")
        lines.append("")
        
        // Settings
        if settingsValid {
            lines.append("✅ Settings: Valid (v\(settingsVersion ?? "?"))")
        } else {
            lines.append("❌ Settings: Invalid")
            if let error = settingsError {
                lines.append("   Error: \(error)")
            }
        }
        
        lines.append("")
        lines.append("Effects:")
        
        for (id, status) in effectsStatus.sorted(by: { $0.key < $1.key }) {
            switch status {
            case .valid(let name, let version, let testCount):
                lines.append("  ✅ \(id): \(name) v\(version) (\(testCount) tests)")
            case .invalid(let error):
                lines.append("  ❌ \(id): \(error)")
            }
        }
        
        lines.append("")
        lines.append(allValid ? "✅ All configuration valid" : "❌ Configuration has errors")
        
        return lines.joined(separator: "\n")
    }
}
