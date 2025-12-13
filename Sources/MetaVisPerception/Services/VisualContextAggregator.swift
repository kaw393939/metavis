import Foundation
import CoreImage
import MetaVisCore

/// Aggregates specific vision service data into a unified Semantic Frame for LLM consumption.
public actor VisualContextAggregator {
    
    let faceDetector: FaceDetectionService
    // let segmenter: PersonSegmentationService // Not used for metadata text, used for masks.
    
    public init(faceDetector: FaceDetectionService = FaceDetectionService()) {
        self.faceDetector = faceDetector
    }
    
    /// Analyzes the frame and returns a semantic description.
    public func analyze(pixelBuffer: CVPixelBuffer, at timestamp: TimeInterval) async throws -> SemanticFrame {
        
        // 1. Run Tracking (Diarization)
        // We assume trackFaces is stateful and continuous.
        // For a single random frame analysis, we might just detect.
        // But the "Eyes" implies awareness of identity.
        
        let identityMap = try await faceDetector.trackFaces(in: pixelBuffer)
        
        var subjects: [DetectedSubject] = []
        
        // 2. Map Identities to Subjects
        for (uuid, rect) in identityMap {
            // In a real system, we'd lookup Metadata for this UUID (e.g. "Person A").
            // For now, we just report the raw identity.
            
            let subject = DetectedSubject(
                id: uuid,
                rect: rect,
                label: "Person",
                attributes: ["identity_confidence": "high"] // Placeholder
            )
            subjects.append(subject)
        }
        
        // 3. (Future) Object Detection / MobileSAM could run here to add "Shirt", "Car", etc.
        
        return SemanticFrame(timestamp: timestamp, subjects: subjects, contextTags: ["Processed"])
    }
}
