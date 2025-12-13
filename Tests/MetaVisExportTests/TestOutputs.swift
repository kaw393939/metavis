import Foundation

/// Test helpers for consistent video export output locations
public enum TestOutputs {
    /// Base directory for all test video outputs (project_root/test_outputs/)
    public static var baseDirectory: URL = {
        // Find project root by looking for Package.swift
        var currentURL = URL(fileURLWithPath: #filePath)
        while currentURL.path != "/" {
            currentURL.deleteLastPathComponent()
            let packageURL = currentURL.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: packageURL.path) {
                return currentURL.appendingPathComponent("test_outputs")
            }
        }
        // Fallback to /tmp if project root not found
        return URL(fileURLWithPath: "/tmp/metavis_test_outputs")
    }()
    
    /// Create a test output URL with consistent naming
    /// - Parameters:
    ///   - testName: Name of the test (e.g., "multi_clip_crossfade")
    ///   - quality: Quality suffix (e.g., "4K_10bit")
    ///   - extension: File extension (default: "mov")
    /// - Returns: Full URL for the test output file
    public static func url(for testName: String, quality: String = "4K_10bit", ext: String = "mov") -> URL {
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        
        // Clean up old file if exists
        let filename = "\(testName)_\(quality).\(ext)"
        let url = baseDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
        
        return url
    }
    
    /// Get URL for extracted frames from a test
    public static func framesURL(for testName: String) -> URL {
        let framesDir = baseDirectory.appendingPathComponent("\(testName)_frames")
        try? FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)
        return framesDir
    }
    
    /// Clean all test outputs (useful for maintenance)
    public static func cleanAll() throws {
        if FileManager.default.fileExists(atPath: baseDirectory.path) {
            try FileManager.default.removeItem(at: baseDirectory)
        }
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }
}
