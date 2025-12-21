import Foundation
import Metal

/// Represents the complete context of a test run, including environment,
/// performance metrics, and analysis results.
public struct TestRunContext: Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let mode: String
    public let environment: EnvironmentInfo
    public let performance: PerformanceMetrics
    public let quantitative: QuantitativeData
    public let qualitative: QualitativeData
    
    public init(
        mode: String,
        environment: EnvironmentInfo,
        performance: PerformanceMetrics,
        quantitative: QuantitativeData,
        qualitative: QualitativeData
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.mode = mode
        self.environment = environment
        self.performance = performance
        self.quantitative = quantitative
        self.qualitative = qualitative
    }
}

public struct EnvironmentInfo: Codable, Sendable {
    public let osVersion: String
    public let deviceName: String
    public let processorCount: Int
    public let physicalMemory: UInt64
    public let gpuName: String
    
    public init(device: MTLDevice?) {
        let processInfo = ProcessInfo.processInfo
        self.osVersion = processInfo.operatingSystemVersionString
        self.deviceName = Host.current().localizedName ?? "Unknown"
        self.processorCount = processInfo.activeProcessorCount
        self.physicalMemory = processInfo.physicalMemory
        self.gpuName = device?.name ?? "Unknown/Headless"
    }
}

public struct PerformanceMetrics: Codable, Sendable {
    public let generationTime: TimeInterval
    public let ioTime: TimeInterval
    public let analysisTime: TimeInterval
    public let totalTime: TimeInterval
    
    public init(generation: TimeInterval, io: TimeInterval, analysis: TimeInterval, total: TimeInterval) {
        self.generationTime = generation
        self.ioTime = io
        self.analysisTime = analysis
        self.totalTime = total
    }
}

public struct QuantitativeData: Codable, Sendable {
    public let meanLuminance: Double
    public let stdDev: Double
    // Future: DeltaE, SNR, etc.
    
    public init(meanLuminance: Double, stdDev: Double) {
        self.meanLuminance = meanLuminance
        self.stdDev = stdDev
    }
}

public struct QualitativeData: Codable, Sendable {
    public let observerNotes: String
    public let rawGeminiResponse: String?
    
    public init(observerNotes: String, rawGeminiResponse: String? = nil) {
        self.observerNotes = observerNotes
        self.rawGeminiResponse = rawGeminiResponse
    }
}
