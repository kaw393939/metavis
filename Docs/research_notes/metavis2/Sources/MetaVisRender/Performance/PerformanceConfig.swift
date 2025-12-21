// PerformanceConfig.swift
// MetaVisRender
//
// Created for Sprint 03: Adaptive performance configuration
// Auto-tunes based on device profile and current system state

import Foundation

// MARK: - Quality Tier

/// Quality tier for output generation
public enum QualityTier: String, Codable, Sendable, CaseIterable {
    case draft = "draft"           // Fastest, lowest quality
    case preview = "preview"       // Fast preview quality
    case standard = "standard"     // Balanced quality/speed
    case high = "high"             // High quality, slower
    case production = "production" // Maximum quality
    
    /// Recommended for mobile devices
    public static var mobile: QualityTier { .preview }
    
    /// Recommended for desktop
    public static var desktop: QualityTier { .high }
    
    /// Recommended for servers
    public static var server: QualityTier { .production }
}

// MARK: - Processing Mode

/// How to prioritize resources
public enum ProcessingMode: String, Codable, Sendable {
    case speed = "speed"           // Maximize throughput
    case balanced = "balanced"     // Balance speed/efficiency
    case efficiency = "efficiency" // Minimize power/thermals
    case quality = "quality"       // Maximize quality, ignore speed
}

// MARK: - Compute Target

/// Preferred compute target for ML/GPU workloads
public enum ComputeTarget: String, Codable, Sendable {
    case auto = "auto"       // Let system decide
    case cpu = "cpu"         // Force CPU
    case gpu = "gpu"         // Force GPU
    case ane = "ane"         // Force Neural Engine
    case cpuAndGpu = "cpu+gpu"
    case cpuAndANE = "cpu+ane"
    case all = "all"         // Use all available
}

// MARK: - Whisper Model Size

/// Whisper model size for transcription
public enum WhisperModelSize: String, Codable, Sendable, CaseIterable {
    case tiny = "tiny"         // 39M params, fastest
    case base = "base"         // 74M params
    case small = "small"       // 244M params
    case medium = "medium"     // 769M params
    case large = "large"       // 1.5B params
    case turbo = "turbo"       // Optimized large
    
    /// Memory required in bytes (approximate)
    public var memoryRequired: UInt64 {
        switch self {
        case .tiny: return 150 * 1024 * 1024      // 150 MB
        case .base: return 300 * 1024 * 1024      // 300 MB
        case .small: return 1024 * 1024 * 1024    // 1 GB
        case .medium: return 3 * 1024 * 1024 * 1024 // 3 GB
        case .large: return 6 * 1024 * 1024 * 1024  // 6 GB
        case .turbo: return 4 * 1024 * 1024 * 1024  // 4 GB
        }
    }
    
    /// Recommended based on available memory
    public static func recommended(forMemory memory: UInt64) -> WhisperModelSize {
        if memory >= 12 * 1024 * 1024 * 1024 { return .large }
        if memory >= 6 * 1024 * 1024 * 1024 { return .medium }
        if memory >= 3 * 1024 * 1024 * 1024 { return .small }
        if memory >= 1 * 1024 * 1024 * 1024 { return .base }
        return .tiny
    }
}

// MARK: - Performance Config

/// Configuration for system performance tuning
public struct PerformanceConfig: Codable, Sendable, Equatable {
    
    // MARK: - Concurrency
    
    /// Maximum concurrent file operations
    public var maxConcurrentFiles: Int
    
    /// Maximum concurrent video decode operations
    public var maxConcurrentDecodes: Int
    
    /// Maximum concurrent ML inference operations
    public var maxConcurrentInferences: Int
    
    /// Maximum concurrent render operations
    public var maxConcurrentRenders: Int
    
    // MARK: - Memory
    
    /// Maximum memory for decode buffers (bytes)
    public var maxDecodeBufferMemory: UInt64
    
    /// Maximum memory for ML models (bytes)
    public var maxMLMemory: UInt64
    
    /// Maximum memory for render cache (bytes)
    public var maxRenderCacheMemory: UInt64
    
    /// Whether to use memory-mapped files
    public var useMemoryMappedFiles: Bool
    
    // MARK: - Compute
    
    /// Preferred compute target
    public var computeTarget: ComputeTarget
    
    /// Whether to use ANE for supported workloads
    public var useNeuralEngine: Bool
    
    /// Whether to use GPU for render operations
    public var useGPU: Bool
    
    /// Whether to use hardware video encoder/decoder
    public var useHardwareCodecs: Bool
    
    // MARK: - Quality
    
    /// Default quality tier
    public var qualityTier: QualityTier
    
    /// Processing mode
    public var processingMode: ProcessingMode
    
    /// Whisper model size for transcription
    public var whisperModelSize: WhisperModelSize
    
    // MARK: - Throttling
    
    /// Thermal throttle threshold (celsius, where available)
    public var thermalThrottleTemp: Double
    
    /// Enable thermal-aware throttling
    public var enableThermalThrottling: Bool
    
    /// Enable memory pressure throttling
    public var enableMemoryThrottling: Bool
    
    /// Enable battery-aware throttling (mobile only)
    public var enableBatteryThrottling: Bool
    
    /// Battery level below which to throttle (percentage)
    public var batteryThrottleLevel: Int
    
    // MARK: - Initialization
    
    public init(
        maxConcurrentFiles: Int = 4,
        maxConcurrentDecodes: Int = 2,
        maxConcurrentInferences: Int = 2,
        maxConcurrentRenders: Int = 2,
        maxDecodeBufferMemory: UInt64 = 512 * 1024 * 1024,
        maxMLMemory: UInt64 = 2 * 1024 * 1024 * 1024,
        maxRenderCacheMemory: UInt64 = 1024 * 1024 * 1024,
        useMemoryMappedFiles: Bool = true,
        computeTarget: ComputeTarget = .auto,
        useNeuralEngine: Bool = true,
        useGPU: Bool = true,
        useHardwareCodecs: Bool = true,
        qualityTier: QualityTier = .standard,
        processingMode: ProcessingMode = .balanced,
        whisperModelSize: WhisperModelSize = .base,
        thermalThrottleTemp: Double = 85.0,
        enableThermalThrottling: Bool = true,
        enableMemoryThrottling: Bool = true,
        enableBatteryThrottling: Bool = true,
        batteryThrottleLevel: Int = 20
    ) {
        self.maxConcurrentFiles = maxConcurrentFiles
        self.maxConcurrentDecodes = maxConcurrentDecodes
        self.maxConcurrentInferences = maxConcurrentInferences
        self.maxConcurrentRenders = maxConcurrentRenders
        self.maxDecodeBufferMemory = maxDecodeBufferMemory
        self.maxMLMemory = maxMLMemory
        self.maxRenderCacheMemory = maxRenderCacheMemory
        self.useMemoryMappedFiles = useMemoryMappedFiles
        self.computeTarget = computeTarget
        self.useNeuralEngine = useNeuralEngine
        self.useGPU = useGPU
        self.useHardwareCodecs = useHardwareCodecs
        self.qualityTier = qualityTier
        self.processingMode = processingMode
        self.whisperModelSize = whisperModelSize
        self.thermalThrottleTemp = thermalThrottleTemp
        self.enableThermalThrottling = enableThermalThrottling
        self.enableMemoryThrottling = enableMemoryThrottling
        self.enableBatteryThrottling = enableBatteryThrottling
        self.batteryThrottleLevel = batteryThrottleLevel
    }
}

// MARK: - Preset Configurations

extension PerformanceConfig {
    
    /// iPhone optimized configuration
    public static var iphone: PerformanceConfig {
        PerformanceConfig(
            maxConcurrentFiles: 2,
            maxConcurrentDecodes: 1,
            maxConcurrentInferences: 1,
            maxConcurrentRenders: 1,
            maxDecodeBufferMemory: 128 * 1024 * 1024,
            maxMLMemory: 512 * 1024 * 1024,
            maxRenderCacheMemory: 256 * 1024 * 1024,
            useMemoryMappedFiles: false, // Limited on iOS
            computeTarget: .ane,
            useNeuralEngine: true,
            useGPU: true,
            useHardwareCodecs: true,
            qualityTier: .preview,
            processingMode: .efficiency,
            whisperModelSize: .tiny,
            thermalThrottleTemp: 80.0,
            enableThermalThrottling: true,
            enableMemoryThrottling: true,
            enableBatteryThrottling: true,
            batteryThrottleLevel: 30
        )
    }
    
    /// iPad optimized configuration
    public static var ipad: PerformanceConfig {
        PerformanceConfig(
            maxConcurrentFiles: 3,
            maxConcurrentDecodes: 2,
            maxConcurrentInferences: 2,
            maxConcurrentRenders: 2,
            maxDecodeBufferMemory: 256 * 1024 * 1024,
            maxMLMemory: 1024 * 1024 * 1024,
            maxRenderCacheMemory: 512 * 1024 * 1024,
            useMemoryMappedFiles: false,
            computeTarget: .ane,
            useNeuralEngine: true,
            useGPU: true,
            useHardwareCodecs: true,
            qualityTier: .standard,
            processingMode: .balanced,
            whisperModelSize: .base,
            thermalThrottleTemp: 80.0,
            enableThermalThrottling: true,
            enableMemoryThrottling: true,
            enableBatteryThrottling: true,
            batteryThrottleLevel: 25
        )
    }
    
    /// MacBook (laptop) optimized configuration
    public static var macbook: PerformanceConfig {
        PerformanceConfig(
            maxConcurrentFiles: 4,
            maxConcurrentDecodes: 2,
            maxConcurrentInferences: 2,
            maxConcurrentRenders: 2,
            maxDecodeBufferMemory: 512 * 1024 * 1024,
            maxMLMemory: 2 * 1024 * 1024 * 1024,
            maxRenderCacheMemory: 1024 * 1024 * 1024,
            useMemoryMappedFiles: true,
            computeTarget: .auto,
            useNeuralEngine: true,
            useGPU: true,
            useHardwareCodecs: true,
            qualityTier: .high,
            processingMode: .balanced,
            whisperModelSize: .small,
            thermalThrottleTemp: 90.0,
            enableThermalThrottling: true,
            enableMemoryThrottling: true,
            enableBatteryThrottling: true,
            batteryThrottleLevel: 20
        )
    }
    
    /// Mac desktop (iMac, Mac mini, Mac Studio) configuration
    public static var macDesktop: PerformanceConfig {
        PerformanceConfig(
            maxConcurrentFiles: 8,
            maxConcurrentDecodes: 4,
            maxConcurrentInferences: 4,
            maxConcurrentRenders: 4,
            maxDecodeBufferMemory: 1024 * 1024 * 1024,
            maxMLMemory: 4 * 1024 * 1024 * 1024,
            maxRenderCacheMemory: 2 * 1024 * 1024 * 1024,
            useMemoryMappedFiles: true,
            computeTarget: .all,
            useNeuralEngine: true,
            useGPU: true,
            useHardwareCodecs: true,
            qualityTier: .high,
            processingMode: .balanced,
            whisperModelSize: .medium,
            thermalThrottleTemp: 95.0,
            enableThermalThrottling: true,
            enableMemoryThrottling: true,
            enableBatteryThrottling: false,
            batteryThrottleLevel: 0
        )
    }
    
    /// Mac Pro / Studio (workstation) configuration
    public static var workstation: PerformanceConfig {
        PerformanceConfig(
            maxConcurrentFiles: 16,
            maxConcurrentDecodes: 8,
            maxConcurrentInferences: 8,
            maxConcurrentRenders: 8,
            maxDecodeBufferMemory: 2 * 1024 * 1024 * 1024,
            maxMLMemory: 16 * 1024 * 1024 * 1024,
            maxRenderCacheMemory: 8 * 1024 * 1024 * 1024,
            useMemoryMappedFiles: true,
            computeTarget: .all,
            useNeuralEngine: true,
            useGPU: true,
            useHardwareCodecs: true,
            qualityTier: .production,
            processingMode: .quality,
            whisperModelSize: .large,
            thermalThrottleTemp: 100.0,
            enableThermalThrottling: false,
            enableMemoryThrottling: true,
            enableBatteryThrottling: false,
            batteryThrottleLevel: 0
        )
    }
    
    /// Server (headless) configuration
    public static var server: PerformanceConfig {
        PerformanceConfig(
            maxConcurrentFiles: 32,
            maxConcurrentDecodes: 16,
            maxConcurrentInferences: 8,
            maxConcurrentRenders: 16,
            maxDecodeBufferMemory: 4 * 1024 * 1024 * 1024,
            maxMLMemory: 32 * 1024 * 1024 * 1024,
            maxRenderCacheMemory: 16 * 1024 * 1024 * 1024,
            useMemoryMappedFiles: true,
            computeTarget: .gpu, // Servers may not have ANE
            useNeuralEngine: false,
            useGPU: true,
            useHardwareCodecs: true,
            qualityTier: .production,
            processingMode: .speed,
            whisperModelSize: .large,
            thermalThrottleTemp: 100.0,
            enableThermalThrottling: false,
            enableMemoryThrottling: false,
            enableBatteryThrottling: false,
            batteryThrottleLevel: 0
        )
    }
}

// MARK: - Auto Configuration

extension PerformanceConfig {
    
    /// Create a configuration optimized for the given device profile
    public static func forDevice(_ profile: DeviceProfile) -> PerformanceConfig {
        var config: PerformanceConfig
        
        // Start with preset based on device type
        switch profile.deviceType {
        case .iphone:
            config = .iphone
        case .ipad:
            config = .ipad
        case .macbook:
            config = .macbook
        case .macDesktop:
            config = .macDesktop
        case .macStudio, .macPro:
            config = .workstation
        case .server:
            config = .server
        case .unknown:
            config = .macDesktop // Safe default
        }
        
        // Tune based on actual capabilities
        let caps = profile.capabilities
        
        // Adjust concurrency based on core count
        config.maxConcurrentFiles = min(caps.logicalCores, config.maxConcurrentFiles)
        config.maxConcurrentDecodes = min(caps.performanceCores / 2, config.maxConcurrentDecodes)
        config.maxConcurrentInferences = min(4, config.maxConcurrentInferences)
        config.maxConcurrentRenders = min(caps.performanceCores / 2, config.maxConcurrentRenders)
        
        // Adjust memory based on available RAM
        let availableML = caps.availableMLMemory
        config.maxMLMemory = min(availableML, config.maxMLMemory)
        config.maxDecodeBufferMemory = min(availableML / 4, config.maxDecodeBufferMemory)
        config.maxRenderCacheMemory = min(availableML / 2, config.maxRenderCacheMemory)
        
        // Adjust Whisper model based on available memory
        config.whisperModelSize = .recommended(forMemory: availableML)
        
        // Enable/disable features based on hardware
        config.useNeuralEngine = caps.hasNeuralEngine
        config.useHardwareCodecs = caps.hasHardwareVideoDecoder
        
        // Set compute target based on capabilities
        if caps.hasNeuralEngine && caps.metalFamily >= 7 {
            config.computeTarget = .all
        } else if caps.hasNeuralEngine {
            config.computeTarget = .cpuAndANE
        } else if caps.metalFamily >= 5 {
            config.computeTarget = .cpuAndGpu
        } else {
            config.computeTarget = .cpu
        }
        
        return config
    }
    
    /// Create a configuration for current device
    public static func autoDetect() async -> PerformanceConfig {
        let profiler = DeviceProfiler()
        let profile = await profiler.profile()
        return forDevice(profile)
    }
    
    /// Adjust configuration based on current performance state
    public func adjusted(for snapshot: PerformanceSnapshot) -> PerformanceConfig {
        var config = self
        
        // Apply thermal throttling
        if enableThermalThrottling && snapshot.thermalState.shouldThrottle {
            let multiplier = snapshot.thermalState.concurrencyMultiplier
            config.maxConcurrentFiles = max(1, Int(Double(maxConcurrentFiles) * multiplier))
            config.maxConcurrentDecodes = max(1, Int(Double(maxConcurrentDecodes) * multiplier))
            config.maxConcurrentInferences = max(1, Int(Double(maxConcurrentInferences) * multiplier))
            config.maxConcurrentRenders = max(1, Int(Double(maxConcurrentRenders) * multiplier))
        }
        
        // Apply memory throttling
        if enableMemoryThrottling && snapshot.memoryPressure != .normal {
            let multiplier = snapshot.memoryPressure.memoryMultiplier
            config.maxDecodeBufferMemory = UInt64(Double(maxDecodeBufferMemory) * multiplier)
            config.maxMLMemory = UInt64(Double(maxMLMemory) * multiplier)
            config.maxRenderCacheMemory = UInt64(Double(maxRenderCacheMemory) * multiplier)
        }
        
        // Apply battery throttling
        if enableBatteryThrottling,
           let level = snapshot.batteryLevel,
           snapshot.isPluggedIn == false,
           level <= batteryThrottleLevel {
            config.processingMode = .efficiency
            config.maxConcurrentFiles = max(1, maxConcurrentFiles / 2)
            config.maxConcurrentDecodes = max(1, maxConcurrentDecodes / 2)
            config.maxConcurrentInferences = max(1, maxConcurrentInferences / 2)
            config.maxConcurrentRenders = max(1, maxConcurrentRenders / 2)
        }
        
        // Apply low power mode
        if snapshot.isLowPowerMode {
            config.processingMode = .efficiency
            config.maxConcurrentFiles = max(1, maxConcurrentFiles / 2)
            config.qualityTier = min(qualityTier, .preview)
        }
        
        return config
    }
}

// MARK: - Comparable Quality

extension QualityTier: Comparable {
    public static func < (lhs: QualityTier, rhs: QualityTier) -> Bool {
        let order: [QualityTier] = [.draft, .preview, .standard, .high, .production]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }
}

// MARK: - JSON Export

extension PerformanceConfig {
    /// Export configuration as JSON
    public func toJSON(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        return try encoder.encode(self)
    }
    
    /// Create configuration from JSON
    public static func fromJSON(_ data: Data) throws -> PerformanceConfig {
        let decoder = JSONDecoder()
        return try decoder.decode(PerformanceConfig.self, from: data)
    }
}
