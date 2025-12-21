import Foundation

/// Coordinator for handling file ingestion and triggering analysis.
public class IngestCoordinator {
    private let database: DatabaseManager
    private let transcriptionService: any TranscriptionService
    private let embeddingService: any VectorEmbeddingService
    
    public init(database: DatabaseManager, 
                transcriptionService: any TranscriptionService = MockWhisperService(),
                embeddingService: any VectorEmbeddingService = MockVectorEmbeddingService()) {
        self.database = database
        self.transcriptionService = transcriptionService
        self.embeddingService = embeddingService
    }
    
    /// Ingests a file at the given path.
    /// - Parameter path: Absolute path to the file.
    /// - Returns: The UUID of the created Asset.
    public func ingest(file path: String) async throws -> String? {
        print("Ingesting file: \(path)")
        let fileURL = URL(fileURLWithPath: path)
        let assetID = UUID().uuidString
        
        // 1. Create Asset Record
        let techSpecs = "{}"
        try await database.dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO assets (id, path, tier, tech_specs)
                VALUES (?, ?, ?, ?)
            """, arguments: [assetID, path, 0, techSpecs])
        }
        
        // 2. Transcribe (Simulated using Mock for now)
        // In a real app, we'd check file type (video/audio).
        let segments = try await transcriptionService.transcribe(audioURL: fileURL)
        
        // 3. Process Segments
        for segment in segments {
            // Generate embedding for the text
            let embedding = try await embeddingService.embed(text: segment.text)
            let vectorBlob = try VectorUtils.serialize(embedding)
            
            let entityID = UUID().uuidString
            let timeRangeID = UUID().uuidString
            
            try await database.dbWriter.write { db in
                // A. Create Entity (The Semantic Content)
                try db.execute(sql: """
                    INSERT INTO entities (id, type, name, embedding)
                    VALUES (?, ?, ?, ?)
                """, arguments: [entityID, "SpeechSegment", segment.text, vectorBlob])
                
                // B. Create TimeRange (The Temporal Locator)
                try db.execute(sql: """
                    INSERT INTO time_ranges (id, asset_id, start_time, end_time, type, entity_id, data)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                """, arguments: [timeRangeID, assetID, segment.start, segment.end, "Speech", entityID, segment.text])
            }
        }
        
        print("Ingestion complete for \(assetID). Processed \(segments.count) segments.")
        return assetID
    }
}
