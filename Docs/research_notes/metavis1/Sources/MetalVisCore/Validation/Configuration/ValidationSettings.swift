// Sources/MetalVisCore/Validation/Configuration/ValidationSettings.swift
// MetaVis Studio - Autonomous Development Infrastructure

import Foundation

/// Global validation settings loaded from validation_settings.yaml
public struct ValidationSettings: Codable, Sendable {
    public let version: String
    public let output: OutputSettings
    public let branding: BrandingSettings
    public let frameExtraction: FrameExtractionSettings
    public let validation: ValidationBehavior
    public let thresholdOverrides: [String: [String: Double]]?
    public let development: DevelopmentSettings?
    
    public init(
        version: String = "1.0.0",
        output: OutputSettings = OutputSettings(),
        branding: BrandingSettings = BrandingSettings(),
        frameExtraction: FrameExtractionSettings = FrameExtractionSettings(),
        validation: ValidationBehavior = ValidationBehavior(),
        thresholdOverrides: [String: [String: Double]]? = nil,
        development: DevelopmentSettings? = nil
    ) {
        self.version = version
        self.output = output
        self.branding = branding
        self.frameExtraction = frameExtraction
        self.validation = validation
        self.thresholdOverrides = thresholdOverrides
        self.development = development
    }
    
    enum CodingKeys: String, CodingKey {
        case version, output, branding, validation, development
        case frameExtraction = "frame_extraction"
        case thresholdOverrides = "threshold_overrides"
    }
}

// MARK: - Output Settings

public struct OutputSettings: Codable, Sendable {
    public let directory: String
    public let formats: [OutputFormat]
    public let timestampFormat: String
    public let symlinks: SymlinkSettings
    
    public init(
        directory: String = "output/lab",
        formats: [OutputFormat] = [.json, .html, .pdf],
        timestampFormat: String = "%Y_%m_%d_%H%M%S",
        symlinks: SymlinkSettings = SymlinkSettings()
    ) {
        self.directory = directory
        self.formats = formats
        self.timestampFormat = timestampFormat
        self.symlinks = symlinks
    }
    
    enum CodingKeys: String, CodingKey {
        case directory, formats, symlinks
        case timestampFormat = "timestamp_format"
    }
}

public enum OutputFormat: String, Codable, Sendable {
    case json
    case html
    case pdf
    case yaml
}

public struct SymlinkSettings: Codable, Sendable {
    public let latest: Bool
    public let baseline: Bool
    
    public init(latest: Bool = true, baseline: Bool = true) {
        self.latest = latest
        self.baseline = baseline
    }
}

// MARK: - Branding Settings

public struct BrandingSettings: Codable, Sendable {
    public let title: String
    public let subtitle: String
    public let logo: String
    public let colors: ColorPalette
    public let typography: Typography
    public let includeSystemInfo: Bool
    public let includeGitInfo: Bool
    public let includeTimestamps: Bool
    
    public init(
        title: String = "MetaVis Studio",
        subtitle: String = "Rendering Engine Validation Report",
        logo: String = "assets/metavisstudioslogo_transparent.png",
        colors: ColorPalette = ColorPalette(),
        typography: Typography = Typography(),
        includeSystemInfo: Bool = true,
        includeGitInfo: Bool = true,
        includeTimestamps: Bool = true
    ) {
        self.title = title
        self.subtitle = subtitle
        self.logo = logo
        self.colors = colors
        self.typography = typography
        self.includeSystemInfo = includeSystemInfo
        self.includeGitInfo = includeGitInfo
        self.includeTimestamps = includeTimestamps
    }
    
    enum CodingKeys: String, CodingKey {
        case title, subtitle, logo, colors, typography
        case includeSystemInfo = "include_system_info"
        case includeGitInfo = "include_git_info"
        case includeTimestamps = "include_timestamps"
    }
}

public struct ColorPalette: Codable, Sendable {
    public let primary: String
    public let secondary: String
    public let accent: String
    public let success: String
    public let warning: String
    public let error: String
    
    public init(
        primary: String = "#000000",
        secondary: String = "#FFFFFF",
        accent: String = "#FF0000",
        success: String = "#00AA00",
        warning: String = "#FFAA00",
        error: String = "#FF0000"
    ) {
        self.primary = primary
        self.secondary = secondary
        self.accent = accent
        self.success = success
        self.warning = warning
        self.error = error
    }
}

public struct Typography: Codable, Sendable {
    public let heading: String
    public let body: String
    public let mono: String
    
    public init(
        heading: String = "Helvetica Neue",
        body: String = "Helvetica",
        mono: String = "SF Mono"
    ) {
        self.heading = heading
        self.body = body
        self.mono = mono
    }
}

// MARK: - Frame Extraction Settings

public struct FrameExtractionSettings: Codable, Sendable {
    public let strategy: ExtractionStrategy
    public let intervalSeconds: Double?
    public let customTimestamps: [Double]?
    public let alwaysExtract: [Double]
    
    public init(
        strategy: ExtractionStrategy = .fromManifest,
        intervalSeconds: Double? = 2.0,
        customTimestamps: [Double]? = nil,
        alwaysExtract: [Double] = [0.0, -1.0]
    ) {
        self.strategy = strategy
        self.intervalSeconds = intervalSeconds
        self.customTimestamps = customTimestamps
        self.alwaysExtract = alwaysExtract
    }
    
    enum CodingKeys: String, CodingKey {
        case strategy
        case intervalSeconds = "interval_seconds"
        case customTimestamps = "custom_timestamps"
        case alwaysExtract = "always_extract"
    }
}

public enum ExtractionStrategy: String, Codable, Sendable {
    case fromManifest = "from_manifest"
    case fixedInterval = "fixed_interval"
    case custom
}

// MARK: - Validation Behavior

public struct ValidationBehavior: Codable, Sendable {
    public let enabledEffects: [String]
    public let failOn: [Severity]
    public let warnOn: [Severity]
    public let maxConcurrentValidators: Int
    public let timeoutPerValidatorSeconds: Double
    public let baseline: BaselineSettings
    
    public init(
        enabledEffects: [String] = [],
        failOn: [Severity] = [.critical],
        warnOn: [Severity] = [.warning],
        maxConcurrentValidators: Int = 4,
        timeoutPerValidatorSeconds: Double = 30.0,
        baseline: BaselineSettings = BaselineSettings()
    ) {
        self.enabledEffects = enabledEffects
        self.failOn = failOn
        self.warnOn = warnOn
        self.maxConcurrentValidators = maxConcurrentValidators
        self.timeoutPerValidatorSeconds = timeoutPerValidatorSeconds
        self.baseline = baseline
    }
    
    enum CodingKeys: String, CodingKey {
        case enabledEffects = "enabled_effects"
        case failOn = "fail_on"
        case warnOn = "warn_on"
        case maxConcurrentValidators = "max_concurrent_validators"
        case timeoutPerValidatorSeconds = "timeout_per_validator_seconds"
        case baseline
    }
}

public struct BaselineSettings: Codable, Sendable {
    public let autoCreate: Bool
    public let updateCommand: UpdateStrategy
    
    public init(autoCreate: Bool = true, updateCommand: UpdateStrategy = .manual) {
        self.autoCreate = autoCreate
        self.updateCommand = updateCommand
    }
    
    enum CodingKeys: String, CodingKey {
        case autoCreate = "auto_create"
        case updateCommand = "update_command"
    }
}

public enum UpdateStrategy: String, Codable, Sendable {
    case manual
    case onSuccess = "on_success"
    case always
}

// MARK: - Development Settings

public struct DevelopmentSettings: Codable, Sendable {
    public let verbose: Bool
    public let saveIntermediateFrames: Bool
    public let profileValidators: Bool
    
    public init(
        verbose: Bool = false,
        saveIntermediateFrames: Bool = false,
        profileValidators: Bool = false
    ) {
        self.verbose = verbose
        self.saveIntermediateFrames = saveIntermediateFrames
        self.profileValidators = profileValidators
    }
    
    enum CodingKeys: String, CodingKey {
        case verbose
        case saveIntermediateFrames = "save_intermediate_frames"
        case profileValidators = "profile_validators"
    }
}

// MARK: - Severity (shared with EffectDefinition)

public enum Severity: String, Codable, Sendable {
    case critical
    case warning
    case info
}
