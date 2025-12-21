import Foundation
import Metal
import MetalVisCore

/// Standalone validation runner for MetalVis rendering system
/// Executes all 15 validators and generates production readiness report
@main
@available(macOS 14.0, *)
struct ValidationCLI {
    static func main() async {
        print("=== MetalVis Validation Suite ===")
        print("Validating rendering system...")
        print("")
        
        // Initialize Metal device
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("❌ ERROR: No Metal device available")
            exit(1)
        }
        
        print("✅ Metal device: \(device.name)")
        print("")
        
        // Create validation runner
        let runner: ValidationRunner
        do {
            runner = try await ValidationRunner(device: device)
        } catch {
            print("❌ ERROR: Failed to create ValidationRunner: \(error)")
            exit(1)
        }
        
        // Run all validations
        print("🔬 Running all validators...")
        print("")
        
        let startTime = Date()
        let result = await runner.runAllValidations()
        let duration = Date().timeIntervalSince(startTime)
        
        // Print results
        printResults(result, duration: duration)
        
        // Exit with appropriate code
        exit(result.success ? 0 : 1)
    }
    
    static func printResults(_ result: ValidationRunResult, duration: TimeInterval) {
        print("=" * 60)
        print("VALIDATION RESULTS")
        print("=" * 60)
        print("")
        
        // Summary
        let summary = result.summary
        print("📊 Summary:")
        print("   Total Tests:  \(summary.total)")
        print("   ✅ Passed:    \(summary.passed)")
        print("   ❌ Failed:    \(summary.failed)")
        print("   ⏭️  Skipped:   \(summary.skipped)")
        print("   ⏱️  Duration:  \(String(format: "%.2f", duration))s")
        print("")
        
        // Overall status
        if result.success {
            print("🎉 OVERALL STATUS: ✅ ALL VALIDATIONS PASSED")
        } else {
            print("⚠️  OVERALL STATUS: ❌ SOME VALIDATIONS FAILED")
        }
        print("")
        
        // Individual effect results
        print("=" * 60)
        print("EFFECT-BY-EFFECT RESULTS")
        print("=" * 60)
        print("")
        
        for effectResult in result.effectResults {
            let statusIcon = effectResult.status == .passed ? "✅" :
                           effectResult.status == .failed ? "❌" :
                           effectResult.status == .skipped ? "⏭️" : "❓"
            
            print("\(statusIcon) \(effectResult.effectName)")
            print("   ID: \(effectResult.effectId)")
            print("   Status: \(effectResult.status)")
            
            if let error = effectResult.error {
                print("   Error: \(error)")
            }
            
            if !effectResult.testResults.isEmpty {
                print("   Tests:")
                for testResult in effectResult.testResults {
                    let testIcon = testResult.passed ? "  ✓" : "  ✗"
                    print("   \(testIcon) \(testResult.testName)")
                    if !testResult.passed {
                        print("      Reason: \(testResult.failureReason ?? "Unknown")")
                        if let measured = testResult.measuredValue,
                           let expected = testResult.expectedValue {
                            print("      Expected: \(expected), Got: \(measured)")
                        }
                    }
                }
            }
            print("")
        }
        
        // Errors
        if !result.errors.isEmpty {
            print("=" * 60)
            print("ERRORS")
            print("=" * 60)
            print("")
            for error in result.errors {
                print("❌ \(error)")
            }
            print("")
        }
        
        // Production readiness assessment
        print("=" * 60)
        print("PRODUCTION READINESS ASSESSMENT")
        print("=" * 60)
        print("")
        
        if result.success {
            print("✅ System Status: PRODUCTION READY")
            print("")
            print("All critical validators passed. The rendering system is:")
            print("  • Physically accurate (validated against specifications)")
            print("  • Color-correct (ACEScg workflow verified)")
            print("  • Performant (within target parameters)")
            print("  • Stable (no regressions detected)")
            print("")
            print("Recommendation: APPROVED FOR DEPLOYMENT 🚀")
        } else {
            print("⚠️  System Status: NOT READY FOR PRODUCTION")
            print("")
            print("Failed validators indicate issues that must be resolved before deployment.")
            print("Review failed tests above and address root causes.")
            print("")
            print("Recommendation: FIX ISSUES BEFORE DEPLOYMENT ⚠️")
        }
        print("")
        print("=" * 60)
    }
}

// Helper for string repetition
extension String {
    static func *(lhs: String, rhs: Int) -> String {
        return String(repeating: lhs, count: rhs)
    }
}
