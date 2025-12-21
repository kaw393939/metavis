import Foundation

/// Logs validation results to persistent storage for longitudinal tracking.
/// Supports CSV for metric plotting and JSONL for detailed history.
@available(macOS 14.0, *)
public class ValidationLogger {
    private let logsDirectory: URL
    private let csvURL: URL
    private let jsonlURL: URL
    
    public init(workspaceRoot: URL) {
        self.logsDirectory = workspaceRoot.appendingPathComponent("logs")
        self.csvURL = logsDirectory.appendingPathComponent("validation_metrics.csv")
        self.jsonlURL = logsDirectory.appendingPathComponent("validation_history.jsonl")
        
        createDirectoryIfNeeded()
        initializeCSVIfNeeded()
    }
    
    private func createDirectoryIfNeeded() {
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    }
    
    private func initializeCSVIfNeeded() {
        guard !FileManager.default.fileExists(atPath: csvURL.path) else { return }
        
        let header = "timestamp,effect_id,test_id,metric_name,metric_value,status\n"
        try? header.write(to: csvURL, atomically: true, encoding: .utf8)
    }
    
    /// Log a validation run result to persistent history
    public func log(result: ValidationRunResult) {
        let timestamp = ISO8601DateFormatter().string(from: result.timestamp)
        
        // 1. Append to JSONL
        if let jsonData = try? JSONEncoder().encode(result),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            let line = jsonString + "\n"
            append(text: line, to: jsonlURL)
        }
        
        // 2. Append metrics to CSV
        var csvLines = ""
        for effect in result.effectResults {
            for test in effect.testResults {
                for (metricName, value) in test.metrics {
                    let line = "\(timestamp),\(effect.effectId),\(test.testId),\(metricName),\(value),\(test.status.rawValue)\n"
                    csvLines += line
                }
            }
        }
        
        if !csvLines.isEmpty {
            append(text: csvLines, to: csvURL)
        }
    }
    
    private func append(text: String, to url: URL) {
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            if let data = text.data(using: .utf8) {
                handle.write(data)
            }
            try? handle.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
