// GeminiAnalyzer.swift
// Sprint D Week 2: Qualitative video analysis using Gemini 2.0 Flash
// Provides AI-powered visual inspection complementing quantitative metrics

import Foundation
import AVFoundation
import CoreImage

/// Analyzes video quality using Gemini 2.0 Flash multimodal AI
/// Provides qualitative assessment complementing quantitative analyzers
public class GeminiAnalyzer {
    
    private let apiKey: String
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-exp:generateContent"
    
    public enum AnalysisPreset {
        case renderQuality
        case colorAccuracy
        case artifactDetection
        case motionSmoothness
        case comparison
        case comprehensive
        case custom(prompt: String)
        
        var systemPrompt: String {
            switch self {
            case .renderQuality:
                return """
                You are a video quality expert. Analyze this video frame for overall render quality.
                Focus on:
                - Visual clarity and sharpness
                - Color reproduction and accuracy
                - Exposure and dynamic range
                - Any visible rendering artifacts
                - Professional production quality
                
                Provide a brief assessment (2-3 sentences) and assign a grade: A+, A, B, C, or F.
                Format: {"analysis": "...", "grade": "A+"}
                """
            
            case .colorAccuracy:
                return """
                You are a color grading specialist. Analyze this video frame for color accuracy.
                Focus on:
                - Color cast or tint issues
                - Skin tone naturalness (if people present)
                - Color balance and saturation
                - Proper exposure of highlights and shadows
                - Any color banding or posterization
                
                Provide a brief assessment (2-3 sentences) and assign a grade: A+, A, B, C, or F.
                Format: {"analysis": "...", "grade": "A+"}
                """
            
            case .artifactDetection:
                return """
                You are a technical video analyst. Inspect this video frame for rendering artifacts.
                Look for:
                - Compression artifacts (blocking, banding)
                - Aliasing or jagged edges
                - Moiré patterns
                - Color fringing or chromatic aberration
                - Noise or grain issues
                - Any other visual defects
                
                List any artifacts found and rate severity (none, minor, moderate, severe).
                Format: {"artifacts": ["..."], "severity": "none"}
                """
            
            case .motionSmoothness:
                return """
                You are a motion analysis expert. Assess motion quality in this video.
                Focus on:
                - Motion smoothness and fluidity
                - Judder or stutter
                - Motion blur appropriateness
                - Frame pacing consistency
                - Camera movement quality (if applicable)
                
                Provide a brief assessment and grade: A+, A, B, C, or F.
                Format: {"analysis": "...", "grade": "A+"}
                """
            
            case .comparison:
                return """
                You are comparing two video frames (original vs processed).
                Analyze:
                - Quality differences between the two
                - Any improvements or degradations
                - Fidelity to the original
                - Which is subjectively better and why
                
                Provide comparison analysis and recommendation.
                Format: {"comparison": "...", "recommendation": "..."}
                """
            
            case .comprehensive:
                return """
                You are a comprehensive video quality expert. Provide a thorough analysis of this video.
                Evaluate ALL aspects:
                - Overall quality and professional appearance
                - Color accuracy and grading
                - Sharpness and detail
                - Exposure and dynamic range
                - Any artifacts or defects
                - Motion smoothness
                - Technical and artistic quality
                
                Provide detailed assessment (4-5 sentences) with specific observations.
                Assign grades for: overall, color, technical, artistic.
                Format: {"analysis": "...", "grades": {"overall": "A", "color": "A+", "technical": "B", "artistic": "A"}}
                """
            
            case .custom(let prompt):
                return prompt
            }
        }
    }
    
    // MARK: - Initialization
    
    public init(apiKey: String? = nil) throws {
        // Get API key from parameter or environment
        if let key = apiKey {
            self.apiKey = key
        } else if let envKey = ProcessInfo.processInfo.environment["GOOGLE_API_KEY"] {
            self.apiKey = envKey
        } else {
            throw GeminiAnalysisError.missingAPIKey
        }
    }
    
    // MARK: - Main Analysis
    
    /// Analyze video using specified preset
    public func analyzeVideo(
        videoURL: URL,
        preset: AnalysisPreset = .comprehensive,
        frameCount: Int = 5
    ) async throws -> GeminiAnalysisResult {
        
        // Extract sample frames
        let frames = try await extractSampleFrames(videoURL, count: frameCount)
        
        var frameAnalyses: [FrameAnalysis] = []
        
        for (index, frame) in frames.enumerated() {
            let analysis = try await analyzeFrame(frame, preset: preset, index: index)
            frameAnalyses.append(analysis)
        }
        
        // Aggregate results
        let overallGrade = calculateOverallGrade(frameAnalyses)
        let summary = generateSummary(frameAnalyses, preset: preset)
        
        return GeminiAnalysisResult(
            preset: String(describing: preset),
            frameAnalyses: frameAnalyses,
            overallGrade: overallGrade,
            summary: summary
        )
    }
    
    /// Compare two videos
    public func compareVideos(
        originalURL: URL,
        processedURL: URL,
        frameCount: Int = 5
    ) async throws -> GeminiComparisonResult {
        
        let originalFrames = try await extractSampleFrames(originalURL, count: frameCount)
        let processedFrames = try await extractSampleFrames(processedURL, count: frameCount)
        
        var comparisons: [FrameComparison] = []
        
        for index in 0..<min(originalFrames.count, processedFrames.count) {
            let comparison = try await compareFrames(
                original: originalFrames[index],
                processed: processedFrames[index],
                index: index
            )
            comparisons.append(comparison)
        }
        
        let overallAssessment = generateComparisonSummary(comparisons)
        
        return GeminiComparisonResult(
            frameComparisons: comparisons,
            overallAssessment: overallAssessment
        )
    }
    
    // MARK: - Frame Analysis
    
    private func analyzeFrame(
        _ image: CIImage,
        preset: AnalysisPreset,
        index: Int
    ) async throws -> FrameAnalysis {
        
        // Convert CIImage to JPEG data
        let ciContext = CIContext()
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else {
            throw GeminiAnalysisError.imageConversionFailed
        }
        
        let jpegData = try createJPEGData(from: cgImage)
        let base64Image = jpegData.base64EncodedString()
        
        // Prepare request
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": preset.systemPrompt],
                        [
                            "inline_data": [
                                "mime_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.4,
                "topP": 0.95,
                "topK": 40,
                "maxOutputTokens": 1024
            ]
        ]
        
        // Make API request
        let response = try await makeAPIRequest(requestBody: requestBody)
        
        return FrameAnalysis(
            frameIndex: index,
            analysis: response["analysis"] as? String ?? "",
            grade: response["grade"] as? String ?? "N/A",
            rawResponse: response
        )
    }
    
    private func compareFrames(
        original: CIImage,
        processed: CIImage,
        index: Int
    ) async throws -> FrameComparison {
        
        let ciContext = CIContext()
        
        guard let originalCG = ciContext.createCGImage(original, from: original.extent),
              let processedCG = ciContext.createCGImage(processed, from: processed.extent) else {
            throw GeminiAnalysisError.imageConversionFailed
        }
        
        let originalData = try createJPEGData(from: originalCG).base64EncodedString()
        let processedData = try createJPEGData(from: processedCG).base64EncodedString()
        
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": AnalysisPreset.comparison.systemPrompt],
                        [
                            "inline_data": [
                                "mime_type": "image/jpeg",
                                "data": originalData
                            ]
                        ],
                        ["text": "Processed version:"],
                        [
                            "inline_data": [
                                "mime_type": "image/jpeg",
                                "data": processedData
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.4,
                "topP": 0.95,
                "topK": 40,
                "maxOutputTokens": 1024
            ]
        ]
        
        let response = try await makeAPIRequest(requestBody: requestBody)
        
        return FrameComparison(
            frameIndex: index,
            comparison: response["comparison"] as? String ?? "",
            recommendation: response["recommendation"] as? String ?? "",
            rawResponse: response
        )
    }
    
    // MARK: - API Communication
    
    private func makeAPIRequest(requestBody: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: "\(baseURL)?key=\(apiKey)") else {
            throw GeminiAnalysisError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiAnalysisError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw GeminiAnalysisError.apiError(statusCode: httpResponse.statusCode)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiAnalysisError.invalidJSONResponse
        }
        
        // Parse Gemini response structure
        return try parseGeminiResponse(json)
    }
    
    private func parseGeminiResponse(_ json: [String: Any]) throws -> [String: Any] {
        guard let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw GeminiAnalysisError.responseParsingFailed
        }
        
        // Try to parse as JSON (for structured responses)
        if let jsonData = text.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            return parsed
        }
        
        // Fall back to plain text response
        return ["analysis": text, "grade": "N/A"]
    }
    
    // MARK: - Helpers
    
    private func extractSampleFrames(_ videoURL: URL, count: Int) async throws -> [CIImage] {
        let asset = AVAsset(url: videoURL)
        
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw GeminiAnalysisError.noVideoTrack
        }
        
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        
        var frames: [CIImage] = []
        
        for i in 0..<count {
            let progress = Double(i) / Double(count - 1)
            let timeSeconds = progress * durationSeconds
            let time = CMTime(seconds: timeSeconds, preferredTimescale: 600)
            
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            let ciImage = CIImage(cgImage: cgImage)
            frames.append(ciImage)
        }
        
        return frames
    }
    
    private func createJPEGData(from cgImage: CGImage, quality: CGFloat = 0.9) throws -> Data {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, "public.jpeg" as CFString, 1, nil) else {
            throw GeminiAnalysisError.imageConversionFailed
        }
        
        CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        
        guard CGImageDestinationFinalize(destination) else {
            throw GeminiAnalysisError.imageConversionFailed
        }
        
        return mutableData as Data
    }
    
    private func calculateOverallGrade(_ analyses: [FrameAnalysis]) -> String {
        let gradeValues: [String: Int] = ["A+": 5, "A": 4, "B": 3, "C": 2, "F": 1, "N/A": 0]
        let values = analyses.compactMap { gradeValues[$0.grade] }.filter { $0 > 0 }
        
        guard !values.isEmpty else { return "N/A" }
        
        let average = Double(values.reduce(0, +)) / Double(values.count)
        
        switch average {
        case 4.5...: return "A+"
        case 3.5..<4.5: return "A"
        case 2.5..<3.5: return "B"
        case 1.5..<2.5: return "C"
        case 1.0..<1.5: return "F"
        default: return "N/A"
        }
    }
    
    private func generateSummary(_ analyses: [FrameAnalysis], preset: AnalysisPreset) -> String {
        let allAnalyses = analyses.map { $0.analysis }.joined(separator: " ")
        return allAnalyses.isEmpty ? "No analysis available" : allAnalyses
    }
    
    private func generateComparisonSummary(_ comparisons: [FrameComparison]) -> String {
        let allComparisons = comparisons.map { $0.comparison }.joined(separator: " ")
        return allComparisons.isEmpty ? "No comparison available" : allComparisons
    }
}

// MARK: - Result Types

public struct GeminiAnalysisResult: Codable {
    public let preset: String
    public let frameAnalyses: [FrameAnalysis]
    public let overallGrade: String
    public let summary: String
}

public struct FrameAnalysis: Codable {
    public let frameIndex: Int
    public let analysis: String
    public let grade: String
    public let rawResponse: [String: Any]
    
    enum CodingKeys: String, CodingKey {
        case frameIndex, analysis, grade
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(frameIndex, forKey: .frameIndex)
        try container.encode(analysis, forKey: .analysis)
        try container.encode(grade, forKey: .grade)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frameIndex = try container.decode(Int.self, forKey: .frameIndex)
        analysis = try container.decode(String.self, forKey: .analysis)
        grade = try container.decode(String.self, forKey: .grade)
        rawResponse = [:]
    }
    
    init(frameIndex: Int, analysis: String, grade: String, rawResponse: [String: Any]) {
        self.frameIndex = frameIndex
        self.analysis = analysis
        self.grade = grade
        self.rawResponse = rawResponse
    }
}

public struct GeminiComparisonResult: Codable {
    public let frameComparisons: [FrameComparison]
    public let overallAssessment: String
}

public struct FrameComparison: Codable {
    public let frameIndex: Int
    public let comparison: String
    public let recommendation: String
    public let rawResponse: [String: Any]
    
    enum CodingKeys: String, CodingKey {
        case frameIndex, comparison, recommendation
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(frameIndex, forKey: .frameIndex)
        try container.encode(comparison, forKey: .comparison)
        try container.encode(recommendation, forKey: .recommendation)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frameIndex = try container.decode(Int.self, forKey: .frameIndex)
        comparison = try container.decode(String.self, forKey: .comparison)
        recommendation = try container.decode(String.self, forKey: .recommendation)
        rawResponse = [:]
    }
    
    init(frameIndex: Int, comparison: String, recommendation: String, rawResponse: [String: Any]) {
        self.frameIndex = frameIndex
        self.comparison = comparison
        self.recommendation = recommendation
        self.rawResponse = rawResponse
    }
}

// MARK: - Errors

public enum GeminiAnalysisError: Error {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case invalidJSONResponse
    case responseParsingFailed
    case apiError(statusCode: Int)
    case noVideoTrack
    case imageConversionFailed
}
