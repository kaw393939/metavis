// Sources/MetaVisRender/Ingestion/Audio/WhisperTranscriptionEngine.swift
// Sprint 03: On-device Whisper transcription using WhisperKit

import AVFoundation
import Foundation
import WhisperKit

// MARK: - Whisper Transcription Engine

/// On-device transcription engine using WhisperKit (OpenAI Whisper + CoreML)
public actor WhisperTranscriptionEngine {
    
    // MARK: - Types
    
    public enum WhisperModel: String, CaseIterable, Sendable {
        case tiny = "tiny"
        case tinyEn = "tiny.en"
        case base = "base"
        case baseEn = "base.en"
        case small = "small"
        case smallEn = "small.en"
        case medium = "medium"
        case mediumEn = "medium.en"
        case large = "large-v3"
        case distilLargeV3 = "distil-large-v3"
        
        public var isEnglishOnly: Bool {
            rawValue.hasSuffix(".en")
        }
        
        public var description: String {
            switch self {
            case .tiny: return "Tiny (~75MB, fastest)"
            case .tinyEn: return "Tiny English (~75MB, fastest)"
            case .base: return "Base (~150MB, fast)"
            case .baseEn: return "Base English (~150MB, fast)"
            case .small: return "Small (~500MB, balanced)"
            case .smallEn: return "Small English (~500MB, balanced)"
            case .medium: return "Medium (~1.5GB, accurate)"
            case .mediumEn: return "Medium English (~1.5GB, accurate)"
            case .large: return "Large V3 (~3GB, most accurate)"
            case .distilLargeV3: return "Distil Large V3 (~1.5GB, fast + accurate)"
            }
        }
    }
    
    public enum WhisperError: Error, LocalizedError {
        case modelNotLoaded
        case modelDownloadFailed(String)
        case transcriptionFailed(String)
        case audioExtractionFailed
        case unsupportedFormat
        case cancelled
        
        public var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "Whisper model not loaded"
            case .modelDownloadFailed(let reason):
                return "Model download failed: \(reason)"
            case .transcriptionFailed(let reason):
                return "Transcription failed: \(reason)"
            case .audioExtractionFailed:
                return "Failed to extract audio from media"
            case .unsupportedFormat:
                return "Unsupported audio format"
            case .cancelled:
                return "Transcription cancelled"
            }
        }
    }
    
    // MARK: - Properties
    
    private var whisperKit: WhisperKit?
    private let modelName: String
    private var isLoaded: Bool = false
    
    // MARK: - Initialization
    
    public init(model: WhisperModel = .base) {
        self.modelName = model.rawValue
    }
    
    public init(modelName: String) {
        self.modelName = modelName
    }
    
    // MARK: - Model Management
    
    /// Load the Whisper model (downloads if needed)
    public func loadModel(progress: ((Float) -> Void)? = nil) async throws {
        guard !isLoaded else { return }
        
        do {
            // WhisperKit automatically downloads the model if not cached
            let config = WhisperKitConfig(
                model: modelName,
                verbose: false,
                prewarm: true
            )
            
            whisperKit = try await WhisperKit(config)
            isLoaded = true
        } catch {
            throw WhisperError.modelDownloadFailed(error.localizedDescription)
        }
    }
    
    /// Check if model is loaded
    public var modelLoaded: Bool {
        isLoaded
    }
    
    /// Unload the model to free memory
    public func unloadModel() {
        whisperKit = nil
        isLoaded = false
    }
    
    // MARK: - Transcription
    
    /// Transcribe an audio file
    public func transcribe(
        audioURL: URL,
        options: TranscriptionOptions = .default,
        progress: ((Float) -> Void)? = nil
    ) async throws -> Transcript {
        
        // Ensure model is loaded
        if !isLoaded {
            try await loadModel(progress: progress)
        }
        
        guard let whisper = whisperKit else {
            throw WhisperError.modelNotLoaded
        }
        
        // Get audio duration
        let asset = AVURLAsset(url: audioURL)
        let duration = try await asset.load(.duration).seconds
        
        // Transcribe
        let results = try await whisper.transcribe(audioPath: audioURL.path)
        
        guard let result = results.first else {
            throw WhisperError.transcriptionFailed("No transcription result")
        }
        
        // Convert to our Transcript format
        return convertToTranscript(result, duration: duration, options: options)
    }
    
    /// Transcribe audio from a video file (extracts audio first)
    public func transcribeVideo(
        videoURL: URL,
        options: TranscriptionOptions = .default,
        progress: ((Float) -> Void)? = nil
    ) async throws -> Transcript {
        
        // Extract audio to temporary file
        let tempAudioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        
        defer {
            try? FileManager.default.removeItem(at: tempAudioURL)
        }
        
        // Extract audio using AudioExtractor
        let extractor = AudioExtractor()
        _ = try await extractor.extract(
            from: videoURL,
            to: tempAudioURL,
            format: .wav16kMono  // Optimal for Whisper
        )
        
        return try await transcribe(
            audioURL: tempAudioURL,
            options: options,
            progress: progress
        )
    }
    
    // MARK: - Conversion
    
    private func convertToTranscript(
        _ result: TranscriptionResult,
        duration: Double,
        options: TranscriptionOptions
    ) -> Transcript {
        
        // Build words with timing - allWords is a computed property returning [WordTiming]
        var words: [TranscriptWord] = []
        
        if options.enableWordTiming {
            let wordTimings = result.allWords
            for wordTiming in wordTimings {
                words.append(TranscriptWord(
                    word: wordTiming.word,
                    start: Double(wordTiming.start),
                    end: Double(wordTiming.end),
                    confidence: wordTiming.probability
                ))
            }
        }
        
        // Build segments - segments is [TranscriptionSegment]
        var transcriptSegments: [TranscriptSegment] = []
        
        for (index, segment) in result.segments.enumerated() {
            // Clean text of Whisper special tokens
            let cleanedText = cleanWhisperText(segment.text)
            guard !cleanedText.isEmpty else { continue }
            
            transcriptSegments.append(TranscriptSegment(
                id: index,
                start: Double(segment.start),
                end: Double(segment.end),
                text: cleanedText,
                confidence: exp(segment.avgLogprob),
                speakerId: nil
            ))
        }
        
        // Detect language - language is a String (not optional)
        let language = result.language
        
        // Calculate average confidence
        let avgConfidence: Float
        if !words.isEmpty {
            avgConfidence = words.map { $0.confidence }.reduce(0, +) / Float(words.count)
        } else if !result.segments.isEmpty {
            let logprobs = result.segments.map { $0.avgLogprob }
            avgConfidence = exp(logprobs.reduce(0, +) / Float(logprobs.count))
        } else {
            avgConfidence = 0.8
        }
        
        // Clean the main text
        let cleanedText = cleanWhisperText(result.text)
        
        return Transcript(
            text: cleanedText,
            language: language,
            segments: transcriptSegments,
            words: words,
            confidence: avgConfidence,
            engine: .whisper,
            duration: duration
        )
    }
    
    /// Clean Whisper special tokens from text
    private func cleanWhisperText(_ text: String) -> String {
        var cleaned = text
        
        // Remove special tokens like <|en|>, <|transcribe|>, <|0.00|>, etc.
        let pattern = "<\\|[^|]+\\|>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }
        
        // Clean up whitespace
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Static Helpers
    
    /// Get list of available models
    public static var availableModels: [WhisperModel] {
        WhisperModel.allCases
    }
    
    /// Get recommended model for device
    public static var recommendedModel: WhisperModel {
        // Check available memory and return appropriate model
        let memoryGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        
        if memoryGB >= 16 {
            return .distilLargeV3  // Best quality/speed tradeoff for 16GB+
        } else if memoryGB >= 8 {
            return .small  // Good balance for 8GB
        } else {
            return .base  // Safe choice for lower memory
        }
    }
    
    /// Check if a model is cached locally
    public static func isModelCached(_ model: WhisperModel) -> Bool {
        // Check if model exists in WhisperKit's cache directory
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("huggingface")
            .appendingPathComponent("models")
        
        guard let cacheDir = cacheDir else { return false }
        
        // Check for model folder
        let modelPath = cacheDir.appendingPathComponent("argmaxinc")
            .appendingPathComponent("whisperkit-coreml")
            .appendingPathComponent("openai_whisper-\(model.rawValue)")
        
        return FileManager.default.fileExists(atPath: modelPath.path)
    }
}

// MARK: - Quick Transcription Extension

extension WhisperTranscriptionEngine {
    
    /// Quick transcription with default settings
    public func quickTranscribe(audioURL: URL) async throws -> String {
        let transcript = try await transcribe(audioURL: audioURL, options: .fast)
        return transcript.text
    }
    
    /// Transcribe with word timing
    public func transcribeWithTiming(audioURL: URL) async throws -> Transcript {
        return try await transcribe(
            audioURL: audioURL,
            options: TranscriptionOptions(enableWordTiming: true)
        )
    }
}
