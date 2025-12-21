import Foundation
import ArgumentParser
import MetalVisCore
import Metal
import Logging

@main
@available(macOS 14.0, *)
struct Metavis: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            abstract: "MetalVis CLI - Scientific Visualization Engine",
            version: "1.0.0",
            subcommands: [Render.self, Validate.self, Baseline.self, Check.self]
        )
    }
}

// MARK: - Render Subcommand

@available(macOS 14.0, *)
struct Render: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            abstract: "Render a visualization from a manifest",
            discussion: "Generates video output based on a JSON/YAML manifest file."
        )
    }
    
    @Option(name: .shortAndLong, help: "Path to the JSON manifest file.")
    var manifest: String
    
    @Option(name: .shortAndLong, help: "Output file path (e.g. output.png).")
    var output: String
    
    @Flag(name: .long, help: "Run validation after render.")
    var validate: Bool = false
    
    @Option(name: .long, help: "Render only a specific frame index.")
    var frame: Int?
    
    @Flag(name: .long, help: "Export frames as PNG sequence.")
    var exportPng: Bool = false
    
    mutating func run() async throws {
        let logger = Logger(label: "com.metalvis.cli")
        
        logger.info("Running Lab Mode with manifest: \(manifest)")
        let runner = try LabRunner()
        try await runner.runManifest(
            path: manifest, 
            output: output, 
            validate: validate,
            frameIndex: frame,
            exportPNG: exportPng
        )
    }
}

// MARK: - Check Subcommand

@available(macOS 14.0, *)
struct Check: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            abstract: "Validate an existing video file",
            discussion: "Runs the validation suite on a pre-rendered video file against a manifest."
        )
    }
    
    @Option(name: .long, help: "Path to the rendered video file.")
    var video: String
    
    @Option(name: .long, help: "Path to the manifest file.")
    var manifest: String
    
    mutating func run() async throws {
        let logger = Logger(label: "com.metalvis.check")
        
        guard let device = MTLCreateSystemDefaultDevice() else {
            logger.error("Metal device not found")
            throw ExitCode.failure
        }
        
        let service = try EffectValidationService(device: device)
        
        // Register validators
        await service.registerValidators([
            BloomValidator(device: device),
            VignetteValidator(device: device),
            HalationValidator(device: device),
            ChromaticAberrationValidator(device: device),
            FilmGrainValidator(device: device),
            AnamorphicValidator(device: device),
            TextLayoutValidator(device: device),
            ACESValidator(device: device)
        ])
        
        let videoURL = URL(fileURLWithPath: video)
        let manifestURL = URL(fileURLWithPath: manifest)
        
        logger.info("Checking video: \(video)")
        logger.info("Against manifest: \(manifest)")
        
        let report = try await service.validate(videoURL: videoURL, manifestURL: manifestURL)
        
        // Save report
        let reportPath = video.replacingOccurrences(of: ".mov", with: "_validation.json")
                               .replacingOccurrences(of: ".mp4", with: "_validation.json")
        let reportURL = URL(fileURLWithPath: reportPath)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let reportData = try encoder.encode(report)
        try reportData.write(to: reportURL)
        
        logger.info("📝 Validation report saved: \(reportPath)")
        
        if report.summary.failed > 0 {
            logger.warning("⚠️ Validation FAILED: \(report.summary.failed) effects failed")
            throw ExitCode.failure
        } else {
            logger.info("✅ Validation PASSED")
        }
    }
}

// MARK: - Validate Subcommand

@available(macOS 14.0, *)
struct Validate: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            abstract: "Run effect validation tests",
            discussion: """
            Loads YAML effect definitions and runs validation tests.
            Outputs structured JSON results for agent consumption.
            """
        )
    }
    
    @Option(name: .shortAndLong, help: "Specific effect ID to validate (e.g. 'bloom')")
    var effect: String?
    
    @Option(name: .shortAndLong, help: "Output JSON file path")
    var output: String?
    
    @Flag(name: .long, help: "Output JSON to stdout")
    var json: Bool = false
    
    mutating func run() async throws {
        let logger = Logger(label: "com.metalvis.validation")
        
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ValidationRunnerError.noDevice
        }
        
        let runner = try ValidationRunner(device: device)
        
        print("🔍 MetalVis Validation Runner")
        print("==============================\n")
        
        let result: ValidationRunResult
        
        if let effectId = effect {
            logger.info("Validating single effect: \(effectId)")
            let effectResult = await runner.runEffectValidation(effectId: effectId)
            result = ValidationRunResult(
                success: effectResult.status == .passed,
                timestamp: Date(),
                effectResults: [effectResult],
                summary: ValidationSummary(
                    total: 1,
                    passed: effectResult.status == .passed ? 1 : 0,
                    failed: effectResult.status == .failed ? 1 : 0,
                    skipped: effectResult.status == .skipped ? 1 : 0
                ),
                errors: []
            )
        } else {
            logger.info("Running all validations...")
            result = await runner.runAllValidations()
        }
        
        // Output results
        if json {
            let jsonString = try result.toJSON()
            print(jsonString)
        } else {
            printHumanReadable(result)
        }
        
        // Log to persistent history
        let workspaceRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let validationLogger = ValidationLogger(workspaceRoot: workspaceRoot)
        validationLogger.log(result: result)
        print("📊 Metrics logged to logs/validation_metrics.csv")
        
        // Write to file if specified
        if let outputPath = output {
            let jsonString = try result.toJSON()
            try jsonString.write(toFile: outputPath, atomically: true, encoding: .utf8)
            print("\n📄 Results written to: \(outputPath)")
        }
        
        // Exit with appropriate code
        if !result.success {
            throw ExitCode.failure
        }
    }
    
    private func printHumanReadable(_ result: ValidationRunResult) {
        print("Summary:")
        print("  Total:   \(result.summary.total)")
        print("  Passed:  \(result.summary.passed) ✅")
        print("  Failed:  \(result.summary.failed) ❌")
        print("  Skipped: \(result.summary.skipped) ⏭️")
        print("")
        
        for effectResult in result.effectResults {
            let statusIcon = switch effectResult.status {
            case .passed: "✅"
            case .failed: "❌"
            case .skipped: "⏭️"
            case .error: "⚠️"
            }
            
            print("\(statusIcon) \(effectResult.effectName) (\(effectResult.effectId))")
            
            if let error = effectResult.error {
                print("   └─ \(error)")
            }
            
            for test in effectResult.testResults {
                let testIcon = switch test.status {
                case .passed: "  ✓"
                case .failed: "  ✗"
                case .skipped: "  ○"
                case .error: "  !"
                }
                print("\(testIcon) \(test.testName)")
                if let message = test.message {
                    print("      └─ \(message)")
                }
            }
        }
        
        print("")
        if result.success {
            print("✅ All validations passed!")
        } else {
            print("❌ Some validations failed.")
        }
    }
}

// MARK: - Baseline Subcommand

@available(macOS 14.0, *)
struct Baseline: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            abstract: "Run the full baseline validation suite",
            discussion: """
            Executes all demos in the demos/ directory, captures performance metrics,
            and archives validation reports to logs/baseline_YYYY_MM_DD.
            """
        )
    }
    
    mutating func run() async throws {
        let logger = Logger(label: "com.metalvis.baseline")
        let fileManager = FileManager.default
        let workspaceRoot = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        
        // Setup directories
        let demosDir = workspaceRoot.appendingPathComponent("demos")
        let outputDir = workspaceRoot.appendingPathComponent("output")
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy_MM_dd"
        let dateString = dateFormatter.string(from: Date())
        let logsDir = workspaceRoot.appendingPathComponent("logs").appendingPathComponent("baseline_\(dateString)")
        
        try? fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: logsDir, withIntermediateDirectories: true)
        
        // Find manifests
        let resourceKeys: [URLResourceKey] = [.nameKey, .isDirectoryKey]
        
        // Use contentsOfDirectory for flat list, safer in async context
        guard let files = try? fileManager.contentsOfDirectory(at: demosDir, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles]) else {
            logger.error("Could not list demos directory")
            throw ExitCode.failure
        }
        
        var manifests: [URL] = []
        for fileURL in files {
            if fileURL.pathExtension == "json" && !fileURL.path.contains("validation_manifest") {
                manifests.append(fileURL)
            }
        }
        manifests.sort { $0.lastPathComponent < $1.lastPathComponent }
        
        print("🚀 Starting Baseline Run: \(manifests.count) demos")
        print("   Logs: \(logsDir.path)")
        print("==================================================")
        
        var successCount = 0
        var failCount = 0
        
        let runner = try LabRunner()
        
        for manifest in manifests {
            let name = manifest.deletingPathExtension().lastPathComponent
            let outputPath = outputDir.appendingPathComponent("\(name).mov").path
            
            print("▶️  Running \(name)...")
            let startTime = Date()
            
            do {
                try await runner.runManifest(path: manifest.path, output: outputPath, validate: true)
                let duration = Date().timeIntervalSince(startTime)
                print("   ✅ Success (\(String(format: "%.2f", duration))s)")
                successCount += 1
                
                // Archive validation report
                let reportPath = outputPath.replacingOccurrences(of: ".mov", with: "_validation.json")
                let reportURL = URL(fileURLWithPath: reportPath)
                if fileManager.fileExists(atPath: reportPath) {
                    let destURL = logsDir.appendingPathComponent("\(name)_validation.json")
                    try? fileManager.removeItem(at: destURL)
                    try fileManager.copyItem(at: reportURL, to: destURL)
                }
                
            } catch {
                let duration = Date().timeIntervalSince(startTime)
                print("   ❌ Failed (\(String(format: "%.2f", duration))s)")
                print("      Error: \(error)")
                failCount += 1
            }
        }
        
        print("==================================================")
        print("🏁 Baseline Complete")
        print("   Success: \(successCount)")
        print("   Failed:  \(failCount)")
        
        // Archive global logs
        let globalLogs = ["validation_metrics.csv", "validation_history.jsonl", "performance_log.json"]
        for logName in globalLogs {
            let src = workspaceRoot.appendingPathComponent("logs").appendingPathComponent(logName)
            let dst = logsDir.appendingPathComponent(logName)
            if fileManager.fileExists(atPath: src.path) {
                try? fileManager.removeItem(at: dst)
                try? fileManager.copyItem(at: src, to: dst)
                print("   Archived \(logName)")
            }
        }
        
        if failCount > 0 {
            throw ExitCode.failure
        }
    }
}
