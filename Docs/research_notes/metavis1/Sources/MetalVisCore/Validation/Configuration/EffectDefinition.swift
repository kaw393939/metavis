// Sources/MetalVisCore/Validation/Configuration/EffectDefinition.swift
// MetaVis Studio - Autonomous Development Infrastructure

import Foundation

/// Complete definition of an effect including documentation, parameters, and validation tests.
/// Loaded from YAML files in assets/config/effects/
public struct EffectDefinition: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let category: EffectCategory
    
    public let documentation: Documentation
    public let parameters: [String: ParameterDefinition]
    public let validation: ValidationSpec
    public let fixtures: [Fixture]?
    public let report: ReportStyle?
    
    public enum EffectCategory: String, Codable, Sendable {
        case postProcessing = "post_processing"
        case lens
        case film
        case color
        case typography
        case geometry
        case camera
        case generation
    }
}

// MARK: - Documentation

public struct Documentation: Codable, Sendable {
    public let summary: String
    public let physics: String?
    public let cinematicReference: String?
    public let whenToUse: String?
    public let orientationBehavior: String?
    
    enum CodingKeys: String, CodingKey {
        case summary, physics
        case cinematicReference = "cinematic_reference"
        case whenToUse = "when_to_use"
        case orientationBehavior = "orientation_behavior"
    }
}

// MARK: - Parameter Definition

public struct ParameterDefinition: Codable, Sendable {
    public let type: ParameterType
    public let range: [Double]?
    public let options: [String]?
    public let defaultValue: AnyCodableValue
    public let unit: String?
    public let description: String
    public let tuningNotes: String?
    public let affectsTests: [String]?
    public let tuningGuidance: String?
    
    enum CodingKeys: String, CodingKey {
        case type, range, options, unit, description
        case defaultValue = "default"
        case tuningNotes = "tuning_notes"
        case affectsTests = "affects_tests"
        case tuningGuidance = "tuning_guidance"
    }
}

public enum ParameterType: String, Codable, Sendable {
    case float
    case int
    case bool
    case color
    case string
    case `enum`
}

// MARK: - Validation Specification

public struct ValidationSpec: Codable, Sendable {
    public let requiredProfiles: [String]?
    public let tests: [ValidationTestDefinition]
    
    enum CodingKeys: String, CodingKey {
        case requiredProfiles = "required_profiles"
        case tests
    }
}

public struct ValidationTestDefinition: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let severity: Severity
    public let description: String
    public let methodology: String
    public let threshold: ThresholdSpec?
    public let thresholdsPerProfile: [String: [String: Double]]?
    public let profileIndependent: Bool?
    public let requiredProfiles: [String]?
    /// Parameters specific to this test (overrides global effect parameters)
    public let parameters: [String: AnyCodableValue]?
    /// Fix patterns to suggest when this test fails
    public let fixPatterns: [FixPattern]?
    
    enum CodingKeys: String, CodingKey {
        case id, name, severity, description, methodology, threshold
        case thresholdsPerProfile = "thresholds_per_profile"
        case profileIndependent = "profile_independent"
        case requiredProfiles = "required_profiles"
        case parameters
        case fixPatterns = "fix_patterns"
    }
}

/// A fix pattern defines where and how to fix a validation failure
public struct FixPattern: Codable, Sendable {
    public enum FixType: String, Codable, Sendable {
        case codeChange = "code_change"
        case parameterTune = "parameter_tune"
        case configUpdate = "config_update"
        case shaderFix = "shader_fix"
        case testUpdate = "test_update"
    }
    
    public enum Priority: String, Codable, Sendable {
        case critical
        case high
        case medium
        case low
    }
    
    /// Relative path to the file to modify
    public let file: String
    /// Function or method name to locate
    public let function: String?
    /// Line number hint (approximate)
    public let lineHint: Int?
    /// What action to take
    public let action: String
    /// Type of fix
    public let type: FixType
    /// Priority of this fix
    public let priority: Priority
    /// Code snippet showing the fix (optional)
    public let codeSnippet: String?
    /// When this fix applies (condition description)
    public let condition: String?
    
    enum CodingKeys: String, CodingKey {
        case file, function
        case lineHint = "line_hint"
        case action, type, priority
        case codeSnippet = "code_snippet"
        case condition
    }
}

public struct ThresholdSpec: Codable, Sendable {
    public let key: String?
    public let value: Double
    public let tolerance: Double?
    public let comparison: Comparison
    public let unit: String
    public let rationale: String
    public let overrides: [String: ThresholdOverride]?
    
    enum CodingKeys: String, CodingKey {
        case key, value, tolerance, comparison, unit, rationale, overrides
    }
}

public struct ThresholdOverride: Codable, Sendable {
    public let value: Double
    public let rationale: String?
}

public enum Comparison: String, Codable, Sendable {
    case lessThan = "less_than"
    case greaterThan = "greater_than"
    case lessOrEqual = "less_or_equal"
    case greaterOrEqual = "greater_or_equal"
    case equals
    case approxEquals = "approx_equals"
    case between
}

// MARK: - Fixtures

public struct Fixture: Codable, Identifiable, Sendable {
    public let id: String
    public let description: String
    public let generator: FixtureGenerator
    public let spec: [String: AnyCodableValue]?
    public let manifest: String?
}

public enum FixtureGenerator: String, Codable, Sendable {
    case synthetic
    case render
    case file
    case procedural
}

// MARK: - Report Styling

public struct ReportStyle: Codable, Sendable {
    public let icon: String?
    public let accentColor: String?
    public let heroImage: String?
    
    enum CodingKeys: String, CodingKey {
        case icon
        case accentColor = "accent_color"
        case heroImage = "hero_image"
    }
}

// MARK: - AnyCodableValue (for mixed-type fields)

/// A type-erasing wrapper for Codable values of any type
public enum AnyCodableValue: Codable, Sendable, CustomStringConvertible {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case null
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([AnyCodableValue].self) {
            self = .array(array)
        } else if let dict = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(dict)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode AnyCodableValue")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .dictionary(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
    
    public var description: String {
        switch self {
        case .string(let v): return v
        case .int(let v): return "\(v)"
        case .double(let v): return "\(v)"
        case .bool(let v): return "\(v)"
        case .array(let v): return "\(v)"
        case .dictionary(let v): return "\(v)"
        case .null: return "null"
        }
    }
    
    public var doubleValue: Double? {
        switch self {
        case .double(let v): return v
        case .int(let v): return Double(v)
        case .string(let v): return Double(v)
        default: return nil
        }
    }
    
    public var floatValue: Float? {
        switch self {
        case .double(let v): return Float(v)
        case .int(let v): return Float(v)
        case .string(let v): return Float(v) ?? nil
        default: return nil
        }
    }
    
    public var stringValue: String? {
        switch self {
        case .string(let v): return v
        default: return nil
        }
    }
    
    public var boolValue: Bool? {
        switch self {
        case .bool(let v): return v
        default: return nil
        }
    }
}
