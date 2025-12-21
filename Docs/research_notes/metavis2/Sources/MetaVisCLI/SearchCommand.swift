// SearchCommand.swift
// MetaVisCLI
//
// CLI command for semantic search across indexed footage

import ArgumentParser
import Foundation
import MetaVisRender

struct SearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Semantic search across indexed footage"
    )
    
    @Argument(help: "Search query (natural language)")
    var query: String
    
    @Option(name: .shortAndLong, help: "Path to index directory or file")
    var index: String = "./.metavis/index"
    
    @Option(name: .shortAndLong, help: "Maximum number of results")
    var limit: Int = 10
    
    @Option(name: .long, help: "Minimum similarity score (0.0-1.0)")
    var threshold: Float = 0.1
    
    @Option(name: .shortAndLong, help: "Output format: table, json, paths")
    var format: String = "table"
    
    @Flag(name: .long, help: "Search in transcripts only")
    var transcriptsOnly: Bool = false
    
    @Flag(name: .long, help: "Search in tags only")
    var tagsOnly: Bool = false
    
    @Flag(name: .shortAndLong, help: "Show verbose output")
    var verbose: Bool = false
    
    mutating func run() async throws {
        let indexURL = URL(fileURLWithPath: index)
        
        // Load index
        let records = try await loadIndex(from: indexURL)
        
        if records.isEmpty {
            print("No indexed footage found at: \(index)")
            print("Run 'metavis ingest <video>' to index footage first.")
            return
        }
        
        if verbose {
            print("Searching \(records.count) indexed items for: \"\(query)\"")
        }
        
        // Perform search
        let results = searchRecords(records, query: query)
        
        // Apply threshold and limit
        let filteredResults = results
            .filter { $0.score >= threshold }
            .prefix(limit)
        
        // Output results
        switch format.lowercased() {
        case "json":
            printJSON(Array(filteredResults))
        case "paths":
            printPaths(Array(filteredResults))
        default:
            printTable(Array(filteredResults))
        }
    }
    
    private func loadIndex(from url: URL) async throws -> [IndexedFootageRecord] {
        var records: [IndexedFootageRecord] = []
        
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return []
        }
        
        if isDirectory.boolValue {
            // Load all JSON files in directory
            let contents = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil
            )
            
            for fileURL in contents where fileURL.pathExtension == "json" {
                if let record = try? loadRecord(from: fileURL) {
                    records.append(record)
                } else if let ingestionRecords = try? loadIngestionResults(from: fileURL) {
                    records.append(contentsOf: ingestionRecords)
                }
            }
        } else {
            // Single file - try IndexedFootageRecord first, then IngestionResults
            if let record = try? loadRecord(from: url) {
                records.append(record)
            } else if let ingestionRecords = try? loadIngestionResults(from: url) {
                records.append(contentsOf: ingestionRecords)
            }
        }
        
        return records
    }
    
    private func loadRecord(from url: URL) throws -> IndexedFootageRecord {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(IndexedFootageRecord.self, from: data)
    }
    
    /// Load from IngestionResults format and convert to IndexedFootageRecord
    private func loadIngestionResults(from url: URL) throws -> [IndexedFootageRecord] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let results = try decoder.decode(IngestionResults.self, from: data)
        
        return results.profiles.map { profile in
            IndexedFootageRecord(
                id: UUID(),
                sourcePath: profile.path,
                analyzedAt: results.timestamp,
                version: "1.0",
                mediaProfile: profile,
                transcript: results.transcripts[profile.path],
                qualityScore: 1.0,
                issues: [],
                status: .complete,
                processingTime: 0
            )
        }
    }
    
    private func searchRecords(_ records: [IndexedFootageRecord], query: String) -> [SearchResult] {
        let queryTerms = query.lowercased().split(separator: " ").map(String.init)
        
        var results: [SearchResult] = []
        
        for record in records {
            var score: Float = 0.0
            var matchDetails: [String] = []
            
            // Search in issues (similar to tags)
            if !tagsOnly || !transcriptsOnly {
                let issueScore = searchInTags(record.issues, queryTerms: queryTerms)
                if issueScore > 0 {
                    score += issueScore * 0.2
                    matchDetails.append("issues")
                }
            }
            
            // Search in source path
            if !transcriptsOnly {
                let pathScore = searchInText(record.sourcePath, queryTerms: queryTerms)
                if pathScore > 0 {
                    score += pathScore * 0.2
                    matchDetails.append("path")
                }
            }
            
            // Search in transcript
            if !tagsOnly {
                if let transcript = record.transcript {
                    let transcriptScore = searchInText(transcript.text, queryTerms: queryTerms)
                    if transcriptScore > 0 {
                        score += transcriptScore * 0.5
                        matchDetails.append("transcript")
                    }
                }
            }
            
            // Search in error message
            if !tagsOnly && !transcriptsOnly {
                if let error = record.error {
                    let errorScore = searchInText(error, queryTerms: queryTerms)
                    if errorScore > 0 {
                        score += errorScore * 0.1
                        matchDetails.append("error")
                    }
                }
            }
            
            if score > 0 {
                results.append(SearchResult(
                    record: record,
                    score: min(score, 1.0),
                    matchedIn: matchDetails
                ))
            }
        }
        
        return results.sorted { $0.score > $1.score }
    }
    
    private func searchInTags(_ tags: [String], queryTerms: [String]) -> Float {
        var matchCount = 0
        
        for term in queryTerms {
            for tag in tags {
                if tag.lowercased().contains(term) {
                    matchCount += 1
                    break
                }
            }
        }
        
        return Float(matchCount) / Float(max(queryTerms.count, 1))
    }
    
    private func searchInText(_ text: String, queryTerms: [String]) -> Float {
        let lowerText = text.lowercased()
        var matchCount = 0
        
        for term in queryTerms {
            if lowerText.contains(term) {
                matchCount += 1
            }
        }
        
        return Float(matchCount) / Float(max(queryTerms.count, 1))
    }
    
    private func printTable(_ results: [SearchResult]) {
        if results.isEmpty {
            print("No results found for: \"\(query)\"")
            return
        }
        
        print("""
        
        ┌─────────────────────────────────────────────────────────────────────────┐
        │ SEARCH RESULTS                                                          │
        │ Query: \(query.padding(toLength: 64, withPad: " ", startingAt: 0)) │
        ├───────┬──────────────────────────────────────────┬───────┬──────────────┤
        │ Score │ File                                     │ Match │ Status       │
        ├───────┼──────────────────────────────────────────┼───────┼──────────────┤
        """)
        
        for result in results {
            let filename = URL(fileURLWithPath: result.record.sourcePath).lastPathComponent
            let truncatedName = String(filename.prefix(40))
            let matchStr = result.matchedIn.prefix(2).joined(separator: ",")
            let status = result.record.status.rawValue
            
            print("│ \(String(format: "%.0f%%", result.score * 100).padding(toLength: 5, withPad: " ", startingAt: 0)) │ \(truncatedName.padding(toLength: 40, withPad: " ", startingAt: 0)) │ \(matchStr.padding(toLength: 5, withPad: " ", startingAt: 0)) │ \(status.padding(toLength: 12, withPad: " ", startingAt: 0)) │")
        }
        
        print("└───────┴──────────────────────────────────────────┴───────┴──────────────┘")
        print("\nFound \(results.count) result(s)")
    }
    
    private func printJSON(_ results: [SearchResult]) {
        struct JSONResult: Encodable {
            let path: String
            let score: Float
            let matchedIn: [String]
            let status: String
            let qualityScore: Float
        }
        
        let jsonResults = results.map { result in
            JSONResult(
                path: result.record.sourcePath,
                score: result.score,
                matchedIn: result.matchedIn,
                status: result.record.status.rawValue,
                qualityScore: result.record.qualityScore
            )
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        if let data = try? encoder.encode(jsonResults),
           let json = String(data: data, encoding: .utf8) {
            print(json)
        }
    }
    
    private func printPaths(_ results: [SearchResult]) {
        for result in results {
            print(result.record.sourcePath)
        }
    }
}

// MARK: - Helper Types

struct SearchResult {
    let record: IndexedFootageRecord
    let score: Float
    let matchedIn: [String]
}
