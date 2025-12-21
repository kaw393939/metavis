// DeviceProfile.swift
// MetaVisRender
//
// Created for Sprint 03: Device detection and capability profiling
// Supports iPhone, Mac desktop, and server deployments

import Foundation
#if canImport(IOKit)
import IOKit
#endif
#if canImport(Metal)
import Metal
#endif

// MARK: - Device Type

/// Categorization of device types for performance optimization
public enum DeviceType: String, Codable, Sendable {
    case iphone = "iPhone"
    case ipad = "iPad"
    case macbook = "MacBook"
    case macDesktop = "Mac Desktop"
    case macStudio = "Mac Studio"
    case macPro = "Mac Pro"
    case server = "Server"
    case unknown = "Unknown"
    
    /// Whether this device is mobile (battery-powered)
    public var isMobile: Bool {
        switch self {
        case .iphone, .ipad, .macbook:
            return true
        default:
            return false
        }
    }
    
    /// Whether this device supports ANE (Apple Neural Engine)
    public var supportsANE: Bool {
        switch self {
        case .iphone, .ipad, .macbook, .macDesktop, .macStudio, .macPro:
            return true
        case .server, .unknown:
            return false
        }
    }
}

// MARK: - Processor Type

/// CPU architecture information
public enum ProcessorType: String, Codable, Sendable {
    case appleM1 = "Apple M1"
    case appleM1Pro = "Apple M1 Pro"
    case appleM1Max = "Apple M1 Max"
    case appleM1Ultra = "Apple M1 Ultra"
    case appleM2 = "Apple M2"
    case appleM2Pro = "Apple M2 Pro"
    case appleM2Max = "Apple M2 Max"
    case appleM2Ultra = "Apple M2 Ultra"
    case appleM3 = "Apple M3"
    case appleM3Pro = "Apple M3 Pro"
    case appleM3Max = "Apple M3 Max"
    case appleM4 = "Apple M4"
    case appleM4Pro = "Apple M4 Pro"
    case appleM4Max = "Apple M4 Max"
    case appleA14 = "Apple A14"
    case appleA15 = "Apple A15"
    case appleA16 = "Apple A16"
    case appleA17Pro = "Apple A17 Pro"
    case appleA18 = "Apple A18"
    case appleA18Pro = "Apple A18 Pro"
    case intelXeon = "Intel Xeon"
    case unknown = "Unknown"
    
    /// Number of Neural Engine cores (approximate)
    public var neuralEngineCores: Int {
        switch self {
        case .appleM1, .appleM2, .appleM3:
            return 16
        case .appleM1Pro, .appleM2Pro, .appleM3Pro:
            return 16
        case .appleM1Max, .appleM2Max, .appleM3Max:
            return 16
        case .appleM1Ultra, .appleM2Ultra:
            return 32
        case .appleM4, .appleM4Pro, .appleM4Max:
            return 16 // M4 has improved ANE
        case .appleA14, .appleA15:
            return 16
        case .appleA16, .appleA17Pro:
            return 16
        case .appleA18, .appleA18Pro:
            return 16
        default:
            return 0
        }
    }
    
    /// GPU core count (approximate base)
    public var gpuCores: Int {
        switch self {
        case .appleM1:
            return 8
        case .appleM1Pro:
            return 16
        case .appleM1Max:
            return 32
        case .appleM1Ultra:
            return 64
        case .appleM2:
            return 10
        case .appleM2Pro:
            return 19
        case .appleM2Max:
            return 38
        case .appleM2Ultra:
            return 76
        case .appleM3:
            return 10
        case .appleM3Pro:
            return 18
        case .appleM3Max:
            return 40
        case .appleM4:
            return 10
        case .appleM4Pro:
            return 20
        case .appleM4Max:
            return 40
        case .appleA14, .appleA15:
            return 4
        case .appleA16:
            return 5
        case .appleA17Pro, .appleA18Pro:
            return 6
        case .appleA18:
            return 5
        default:
            return 0
        }
    }
}

// MARK: - Hardware Capabilities

/// Detailed hardware capability information
public struct HardwareCapabilities: Codable, Sendable, Equatable {
    /// Total physical memory in bytes
    public let totalMemory: UInt64
    
    /// Number of physical CPU cores
    public let physicalCores: Int
    
    /// Number of logical CPU cores (including hyperthreading)
    public let logicalCores: Int
    
    /// Number of performance cores
    public let performanceCores: Int
    
    /// Number of efficiency cores
    public let efficiencyCores: Int
    
    /// Whether the device has a dedicated GPU
    public let hasDiscreteGPU: Bool
    
    /// Metal GPU family support level
    public let metalFamily: Int
    
    /// Whether ANE is available
    public let hasNeuralEngine: Bool
    
    /// ANE TOPS (trillion operations per second)
    public let neuralEngineTOPS: Double
    
    /// Whether ProRes hardware acceleration is available
    public let hasProResAcceleration: Bool
    
    /// Whether hardware video decoder is available
    public let hasHardwareVideoDecoder: Bool
    
    /// Whether hardware video encoder is available
    public let hasHardwareVideoEncoder: Bool
    
    public init(
        totalMemory: UInt64,
        physicalCores: Int,
        logicalCores: Int,
        performanceCores: Int,
        efficiencyCores: Int,
        hasDiscreteGPU: Bool,
        metalFamily: Int,
        hasNeuralEngine: Bool,
        neuralEngineTOPS: Double,
        hasProResAcceleration: Bool,
        hasHardwareVideoDecoder: Bool,
        hasHardwareVideoEncoder: Bool
    ) {
        self.totalMemory = totalMemory
        self.physicalCores = physicalCores
        self.logicalCores = logicalCores
        self.performanceCores = performanceCores
        self.efficiencyCores = efficiencyCores
        self.hasDiscreteGPU = hasDiscreteGPU
        self.metalFamily = metalFamily
        self.hasNeuralEngine = hasNeuralEngine
        self.neuralEngineTOPS = neuralEngineTOPS
        self.hasProResAcceleration = hasProResAcceleration
        self.hasHardwareVideoDecoder = hasHardwareVideoDecoder
        self.hasHardwareVideoEncoder = hasHardwareVideoEncoder
    }
    
    /// Memory available for ML workloads (conservative estimate)
    public var availableMLMemory: UInt64 {
        // Reserve 2GB for system, use up to 70% of remaining for ML
        let reserved: UInt64 = 2 * 1024 * 1024 * 1024
        let available = totalMemory > reserved ? totalMemory - reserved : totalMemory / 2
        return UInt64(Double(available) * 0.7)
    }
}

// MARK: - Device Profile

/// Complete device profile for performance optimization
public struct DeviceProfile: Codable, Sendable, Equatable {
    /// Unique identifier for this profile
    public let id: UUID
    
    /// Device type classification
    public let deviceType: DeviceType
    
    /// Processor type
    public let processorType: ProcessorType
    
    /// Hardware model identifier (e.g., "MacBookPro18,3")
    public let modelIdentifier: String
    
    /// Marketing name (e.g., "MacBook Pro (16-inch, 2021)")
    public let marketingName: String
    
    /// Hardware capabilities
    public let capabilities: HardwareCapabilities
    
    /// Profile creation timestamp
    public let createdAt: Date
    
    public init(
        id: UUID = UUID(),
        deviceType: DeviceType,
        processorType: ProcessorType,
        modelIdentifier: String,
        marketingName: String,
        capabilities: HardwareCapabilities,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.deviceType = deviceType
        self.processorType = processorType
        self.modelIdentifier = modelIdentifier
        self.marketingName = marketingName
        self.capabilities = capabilities
        self.createdAt = createdAt
    }
}

// MARK: - Device Profiler

/// Actor responsible for detecting and profiling device capabilities
public actor DeviceProfiler {
    
    /// Cached device profile
    private var cachedProfile: DeviceProfile?
    
    public init() {}
    
    /// Detect and profile the current device
    public func profile() async -> DeviceProfile {
        // Return cached if available
        if let cached = cachedProfile {
            return cached
        }
        
        let deviceType = detectDeviceType()
        let processorType = detectProcessorType()
        let modelIdentifier = getModelIdentifier()
        let marketingName = getMarketingName(from: modelIdentifier)
        let capabilities = detectCapabilities()
        
        let profile = DeviceProfile(
            deviceType: deviceType,
            processorType: processorType,
            modelIdentifier: modelIdentifier,
            marketingName: marketingName,
            capabilities: capabilities
        )
        
        cachedProfile = profile
        return profile
    }
    
    /// Clear cached profile to force re-detection
    public func clearCache() {
        cachedProfile = nil
    }
    
    // MARK: - Private Detection Methods
    
    private func detectDeviceType() -> DeviceType {
        #if os(iOS)
        let model = UIDevice.current.model
        if model.contains("iPhone") {
            return .iphone
        } else if model.contains("iPad") {
            return .ipad
        }
        return .unknown
        #else
        let modelId = getModelIdentifier()
        
        if modelId.hasPrefix("MacBookPro") || modelId.hasPrefix("MacBookAir") {
            return .macbook
        } else if modelId.hasPrefix("MacPro") {
            return .macPro
        } else if modelId.hasPrefix("Mac14,13") || modelId.hasPrefix("Mac14,14") {
            // Mac Studio identifiers
            return .macStudio
        } else if modelId.hasPrefix("iMac") || modelId.hasPrefix("Macmini") || modelId.hasPrefix("Mac") {
            return .macDesktop
        }
        
        return .unknown
        #endif
    }
    
    private func detectProcessorType() -> ProcessorType {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var brand = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
        let brandString = String(cString: brand)
        
        // Parse Apple Silicon chip name
        if brandString.contains("Apple M4 Max") { return .appleM4Max }
        if brandString.contains("Apple M4 Pro") { return .appleM4Pro }
        if brandString.contains("Apple M4") { return .appleM4 }
        if brandString.contains("Apple M3 Max") { return .appleM3Max }
        if brandString.contains("Apple M3 Pro") { return .appleM3Pro }
        if brandString.contains("Apple M3") { return .appleM3 }
        if brandString.contains("Apple M2 Ultra") { return .appleM2Ultra }
        if brandString.contains("Apple M2 Max") { return .appleM2Max }
        if brandString.contains("Apple M2 Pro") { return .appleM2Pro }
        if brandString.contains("Apple M2") { return .appleM2 }
        if brandString.contains("Apple M1 Ultra") { return .appleM1Ultra }
        if brandString.contains("Apple M1 Max") { return .appleM1Max }
        if brandString.contains("Apple M1 Pro") { return .appleM1Pro }
        if brandString.contains("Apple M1") { return .appleM1 }
        if brandString.contains("Xeon") { return .intelXeon }
        
        return .unknown
    }
    
    private func getModelIdentifier() -> String {
        #if os(iOS)
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
        #else
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
        #endif
    }
    
    private func getMarketingName(from modelIdentifier: String) -> String {
        // Common model identifier to marketing name mappings
        let mappings: [String: String] = [
            "MacBookPro18,3": "MacBook Pro (14-inch, 2021)",
            "MacBookPro18,4": "MacBook Pro (14-inch, 2021)",
            "MacBookPro18,1": "MacBook Pro (16-inch, 2021)",
            "MacBookPro18,2": "MacBook Pro (16-inch, 2021)",
            "Mac14,5": "MacBook Pro (14-inch, 2023)",
            "Mac14,6": "MacBook Pro (16-inch, 2023)",
            "Mac14,9": "MacBook Pro (14-inch, 2023)",
            "Mac14,10": "MacBook Pro (16-inch, 2023)",
            "Mac15,3": "MacBook Pro (14-inch, Nov 2023)",
            "Mac15,6": "MacBook Pro (14-inch, Nov 2023)",
            "Mac15,7": "MacBook Pro (14-inch, Nov 2023)",
            "Mac15,8": "MacBook Pro (16-inch, Nov 2023)",
            "Mac15,9": "MacBook Pro (14-inch, Nov 2023)",
            "Mac15,10": "MacBook Pro (16-inch, Nov 2023)",
            "Mac15,11": "MacBook Pro (16-inch, Nov 2023)",
            "Mac14,13": "Mac Studio (2023)",
            "Mac14,14": "Mac Studio (2023)",
            "Mac14,2": "MacBook Air (M2, 2022)",
            "Mac14,15": "MacBook Air (15-inch, M2, 2023)",
            "Mac15,12": "MacBook Air (13-inch, M3, 2024)",
            "Mac15,13": "MacBook Air (15-inch, M3, 2024)",
        ]
        
        return mappings[modelIdentifier] ?? modelIdentifier
    }
    
    private func detectCapabilities() -> HardwareCapabilities {
        // Get memory
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        
        // Get CPU cores
        let physicalCores = ProcessInfo.processInfo.processorCount
        let logicalCores = ProcessInfo.processInfo.activeProcessorCount
        
        // Estimate P/E core split for Apple Silicon
        let (pCores, eCores) = estimateCoreDistribution(total: physicalCores)
        
        // Detect Metal capabilities
        let metalFamily = detectMetalFamily()
        
        // Detect Neural Engine
        let (hasNE, neTOPS) = detectNeuralEngine()
        
        // Detect video acceleration
        let hasVideoDecoder = detectVideoDecoder()
        let hasVideoEncoder = detectVideoEncoder()
        let hasProRes = detectProResSupport()
        
        return HardwareCapabilities(
            totalMemory: totalMemory,
            physicalCores: physicalCores,
            logicalCores: logicalCores,
            performanceCores: pCores,
            efficiencyCores: eCores,
            hasDiscreteGPU: false, // Apple Silicon uses unified memory
            metalFamily: metalFamily,
            hasNeuralEngine: hasNE,
            neuralEngineTOPS: neTOPS,
            hasProResAcceleration: hasProRes,
            hasHardwareVideoDecoder: hasVideoDecoder,
            hasHardwareVideoEncoder: hasVideoEncoder
        )
    }
    
    private func estimateCoreDistribution(total: Int) -> (performance: Int, efficiency: Int) {
        // Apple Silicon typical P/E distributions
        switch total {
        case 8: return (4, 4)      // M1
        case 10: return (6, 4)    // M1 Pro base
        case 12: return (8, 4)    // M2 Pro
        case 14: return (10, 4)   // M2 Max / M3 Pro
        case 16: return (12, 4)   // M3 Max
        case 20: return (16, 4)   // M1 Ultra
        case 24: return (20, 4)   // M2 Ultra
        default: return (total / 2, total / 2)
        }
    }
    
    private func detectMetalFamily() -> Int {
        #if canImport(Metal)
        guard let device = MTLCreateSystemDefaultDevice() else {
            return 0
        }
        
        // Check Metal GPU family support
        if device.supportsFamily(.apple9) { return 9 }
        if device.supportsFamily(.apple8) { return 8 }
        if device.supportsFamily(.apple7) { return 7 }
        if device.supportsFamily(.apple6) { return 6 }
        if device.supportsFamily(.apple5) { return 5 }
        if device.supportsFamily(.apple4) { return 4 }
        
        return 3
        #else
        return 0
        #endif
    }
    
    private func detectNeuralEngine() -> (available: Bool, tops: Double) {
        // All Apple Silicon Macs have Neural Engine
        let processorType = detectProcessorType()
        
        switch processorType {
        case .appleM1, .appleM1Pro, .appleM1Max:
            return (true, 11.0)
        case .appleM1Ultra:
            return (true, 22.0)
        case .appleM2, .appleM2Pro, .appleM2Max:
            return (true, 15.8)
        case .appleM2Ultra:
            return (true, 31.6)
        case .appleM3, .appleM3Pro, .appleM3Max:
            return (true, 18.0)
        case .appleM4, .appleM4Pro, .appleM4Max:
            return (true, 38.0) // M4 significantly improved ANE
        case .appleA14, .appleA15:
            return (true, 11.0)
        case .appleA16:
            return (true, 17.0)
        case .appleA17Pro:
            return (true, 35.0)
        case .appleA18, .appleA18Pro:
            return (true, 35.0)
        default:
            return (false, 0)
        }
    }
    
    private func detectVideoDecoder() -> Bool {
        // All Apple Silicon devices have hardware video decoder
        let processorType = detectProcessorType()
        return processorType != .unknown && processorType != .intelXeon
    }
    
    private func detectVideoEncoder() -> Bool {
        // All Apple Silicon devices have hardware video encoder
        let processorType = detectProcessorType()
        return processorType != .unknown && processorType != .intelXeon
    }
    
    private func detectProResSupport() -> Bool {
        // Pro chips have dedicated ProRes engines
        let processorType = detectProcessorType()
        switch processorType {
        case .appleM1Pro, .appleM1Max, .appleM1Ultra,
             .appleM2Pro, .appleM2Max, .appleM2Ultra,
             .appleM3Pro, .appleM3Max,
             .appleM4Pro, .appleM4Max,
             .appleA17Pro, .appleA18Pro:
            return true
        default:
            return false
        }
    }
}

// MARK: - Profile JSON Export

extension DeviceProfile {
    /// Export profile as JSON data
    public func toJSON(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        return try encoder.encode(self)
    }
    
    /// Create profile from JSON data
    public static func fromJSON(_ data: Data) throws -> DeviceProfile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DeviceProfile.self, from: data)
    }
}
