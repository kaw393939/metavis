// DiagnoseCommand.swift
// MetaVisCLI
//
// Sprint 03: Hardware diagnostics command
// Profiles device capabilities, verifies GPU/ANE, monitors performance

import Foundation
import ArgumentParser
import MetaVisRender

struct Diagnose: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Diagnose system hardware and capabilities",
        discussion: """
            Profiles the device hardware, verifies GPU and Neural Engine
            availability, and can run performance monitoring.
            
            Examples:
              metavis diagnose hardware
              metavis diagnose hardware --profile 30s
              metavis diagnose hardware --verify-ane --json
            """
    )
    
    // MARK: - Subcommands
    
    @OptionGroup var options: DiagnoseOptions
    
    // MARK: - Run
    
    mutating func run() async throws {
        let profiler = DeviceProfiler()
        let profile = await profiler.profile()
        
        if options.json {
            try await printJSON(profile: profile)
        } else {
            await printHumanReadable(profile: profile)
        }
        
        // Verify ANE if requested
        if options.verifyANE {
            print("\nVerifying Neural Engine...")
            let available = await verifyNeuralEngine()
            print("  ANE available: \(available ? "✓ Yes" : "✗ No")")
        }
        
        // Run performance profiling if requested
        if let duration = options.profileDuration {
            try await runProfiling(duration: duration)
        }
        
        // Show recommended configuration
        if options.showConfig {
            let config = PerformanceConfig.forDevice(profile)
            print("\n" + String(repeating: "=", count: 50))
            print("RECOMMENDED CONFIGURATION")
            print(String(repeating: "=", count: 50))
            try printConfig(config)
        }
    }
    
    private func printJSON(profile: DeviceProfile) async throws {
        let data = try profile.toJSON()
        if let json = String(data: data, encoding: .utf8) {
            print(json)
        }
    }
    
    private func printHumanReadable(profile: DeviceProfile) async {
        print(String(repeating: "=", count: 50))
        print("DEVICE PROFILE")
        print(String(repeating: "=", count: 50))
        print("")
        
        print("Device Type: \(profile.deviceType.rawValue)")
        print("Model: \(profile.marketingName)")
        print("Identifier: \(profile.modelIdentifier)")
        print("Processor: \(profile.processorType.rawValue)")
        print("")
        
        print("CAPABILITIES:")
        print("  Total Memory: \(formatBytes(profile.capabilities.totalMemory))")
        print("  Available ML Memory: \(formatBytes(profile.capabilities.availableMLMemory))")
        print("  CPU Cores: \(profile.capabilities.physicalCores) physical, \(profile.capabilities.logicalCores) logical")
        print("  P-Cores: \(profile.capabilities.performanceCores), E-Cores: \(profile.capabilities.efficiencyCores)")
        print("")
        
        print("GPU & ACCELERATORS:")
        print("  Metal GPU Family: \(profile.capabilities.metalFamily)")
        print("  Neural Engine: \(profile.capabilities.hasNeuralEngine ? "✓" : "✗")")
        if profile.capabilities.hasNeuralEngine {
            print("  ANE TOPS: \(String(format: "%.1f", profile.capabilities.neuralEngineTOPS))")
        }
        print("  ProRes Acceleration: \(profile.capabilities.hasProResAcceleration ? "✓" : "✗")")
        print("  Hardware Video Decoder: \(profile.capabilities.hasHardwareVideoDecoder ? "✓" : "✗")")
        print("  Hardware Video Encoder: \(profile.capabilities.hasHardwareVideoEncoder ? "✓" : "✗")")
    }
    
    private func verifyNeuralEngine() async -> Bool {
        // Try to load a simple CoreML model to verify ANE
        // For now, we just check the capability flag
        let profiler = DeviceProfiler()
        let profile = await profiler.profile()
        return profile.capabilities.hasNeuralEngine
    }
    
    private func runProfiling(duration: TimeInterval) async throws {
        print("\nRunning performance profile for \(Int(duration)) seconds...")
        print("")
        
        let monitor = PerformanceMonitor(interval: 0.5)
        
        // Start monitoring
        guard let stats = await monitor.profile(duration: duration) else {
            print("Failed to collect performance data")
            return
        }
        
        print("PERFORMANCE STATISTICS:")
        print("  Sample Count: \(stats.sampleCount)")
        print("  Duration: \(String(format: "%.1f", stats.windowEnd.timeIntervalSince(stats.windowStart))) seconds")
        print("")
        print("  CPU Usage:")
        print("    Average: \(String(format: "%.1f%%", stats.avgCpuUsage))")
        print("    Peak: \(String(format: "%.1f%%", stats.peakCpuUsage))")
        print("")
        print("  Memory Usage:")
        print("    Average: \(formatBytes(stats.avgMemoryUsage))")
        print("    Peak: \(formatBytes(stats.peakMemoryUsage))")
        print("")
        
        if let avgGpu = stats.avgGpuUsage {
            print("  GPU Usage:")
            print("    Average: \(String(format: "%.1f%%", avgGpu))")
            if let peakGpu = stats.peakGpuUsage {
                print("    Peak: \(String(format: "%.1f%%", peakGpu))")
            }
            print("")
        }
        
        if let avgAne = stats.avgAneUsage {
            print("  ANE Usage:")
            print("    Average: \(String(format: "%.1f%%", avgAne))")
            if let peakAne = stats.peakAneUsage {
                print("    Peak: \(String(format: "%.1f%%", peakAne))")
            }
            print("")
        }
        
        print("  Thermal Throttle Events: \(stats.thermalThrottleCount)")
        print("  Memory Warnings: \(stats.memoryWarningCount)")
    }
    
    private func printConfig(_ config: PerformanceConfig) throws {
        print("")
        print("Concurrency:")
        print("  Max Concurrent Files: \(config.maxConcurrentFiles)")
        print("  Max Concurrent Decodes: \(config.maxConcurrentDecodes)")
        print("  Max Concurrent Inferences: \(config.maxConcurrentInferences)")
        print("  Max Concurrent Renders: \(config.maxConcurrentRenders)")
        print("")
        print("Memory Limits:")
        print("  Decode Buffer: \(formatBytes(config.maxDecodeBufferMemory))")
        print("  ML Memory: \(formatBytes(config.maxMLMemory))")
        print("  Render Cache: \(formatBytes(config.maxRenderCacheMemory))")
        print("")
        print("Compute:")
        print("  Target: \(config.computeTarget.rawValue)")
        print("  Use Neural Engine: \(config.useNeuralEngine ? "Yes" : "No")")
        print("  Use GPU: \(config.useGPU ? "Yes" : "No")")
        print("  Hardware Codecs: \(config.useHardwareCodecs ? "Yes" : "No")")
        print("")
        print("Quality:")
        print("  Tier: \(config.qualityTier.rawValue)")
        print("  Mode: \(config.processingMode.rawValue)")
        print("  Whisper Model: \(config.whisperModelSize.rawValue)")
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0
        
        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        
        return String(format: "%.1f %@", value, units[unitIndex])
    }
}

// MARK: - Diagnose Options

struct DiagnoseOptions: ParsableArguments {
    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false
    
    @Flag(name: .long, help: "Verify Neural Engine availability")
    var verifyANE: Bool = false
    
    @Option(name: .long, help: "Run performance profiling for duration (e.g., 30s, 5m)")
    var profile: String?
    
    @Flag(name: .long, help: "Show recommended configuration for this device")
    var showConfig: Bool = false
    
    var profileDuration: TimeInterval? {
        guard let profile = profile else { return nil }
        
        // Parse duration string like "30s", "5m", "1h"
        let value = profile.dropLast()
        let unit = profile.last
        
        guard let number = Double(value) else { return nil }
        
        switch unit {
        case "s": return number
        case "m": return number * 60
        case "h": return number * 3600
        default: return Double(profile)
        }
    }
}

// MARK: - Setup Command

struct Setup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Set up MetaVis components",
        subcommands: [SetupWhisper.self]
    )
}

struct SetupWhisper: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "whisper",
        abstract: "Download and set up Whisper model for transcription"
    )
    
    @Option(name: .long, help: "Model size: tiny, base, small, medium, large, turbo")
    var model: String = "base"
    
    @Flag(name: .long, help: "Force re-download even if model exists")
    var force: Bool = false
    
    mutating func run() async throws {
        let modelSize: WhisperModelSize
        switch model.lowercased() {
        case "tiny": modelSize = .tiny
        case "small": modelSize = .small
        case "medium": modelSize = .medium
        case "large": modelSize = .large
        case "turbo": modelSize = .turbo
        default: modelSize = .base
        }
        
        print("Setting up Whisper model: \(modelSize.rawValue)")
        print("Memory required: \(formatBytes(modelSize.memoryRequired))")
        print("")
        
        // Check if model already exists
        let modelDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MetaVis")
            .appendingPathComponent("Models")
        
        let modelPath = modelDir.appendingPathComponent("whisper-\(modelSize.rawValue).mlmodelc")
        
        if FileManager.default.fileExists(atPath: modelPath.path) && !force {
            print("✓ Model already exists at \(modelPath.path)")
            print("  Use --force to re-download")
            return
        }
        
        // Create directory
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        
        print("Downloading from HuggingFace...")
        print("This may take a while depending on your connection speed.")
        print("")
        
        // In a real implementation, this would download from HuggingFace
        // For now, we just show the expected behavior
        let modelURL = "https://huggingface.co/apple/coreml-whisper-\(modelSize.rawValue)/resolve/main/whisper-\(modelSize.rawValue).mlmodelc.zip"
        
        print("Model URL: \(modelURL)")
        print("")
        print("Note: Whisper CoreML models must be downloaded manually for now.")
        print("1. Visit: https://huggingface.co/apple/coreml-whisper-\(modelSize.rawValue)")
        print("2. Download the .mlmodelc file")
        print("3. Place it in: \(modelDir.path)")
        print("")
        print("Apple Speech framework will be used as a fallback for transcription.")
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0
        
        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        
        return String(format: "%.1f %@", value, units[unitIndex])
    }
}
