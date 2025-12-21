// Sources/MetaVisRender/Ingestion/Audio/TranscriptionEngine.swift
// Sprint 03: Speech-to-text with Apple Speech framework

import AVFoundation
import Foundation
import Speech

// MARK: - Transcription Engine

/// Unified transcription engine with Apple Speech and future Whisper support
public actor TranscriptionEngine {
    
    // MARK: - Types
    
    public enum EngineType: String, Codable, Sendable {
        case apple = "apple"
        case whisper = "whisper"
        case auto = "auto"
    }
    
    public enum TranscriptionError: Error, LocalizedError {
        case notAuthorized
        case notAvailable
        case recognitionFailed(String)
        case languageNotSupported(String)
        case cancelled
        
        public var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Speech recognition not authorized"
            case .notAvailable:
                return "Speech recognition not available"
            case .recognitionFailed(let reason):
                return "Recognition failed: \(reason)"
            case .languageNotSupported(let lang):
                return "Language not supported: \(lang)"
            case .cancelled:
                return "Transcription cancelled"
            }
        }
    }
    
    // MARK: - Properties
    
    private let speechRecognizer: SFSpeechRecognizer?
    private let preferredEngine: EngineType
    
    // MARK: - Initialization
    
    public init(engine: EngineType = .auto, language: String? = nil) {
        self.preferredEngine = engine
        
        if let lang = language {
            self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: lang))
        } else {
            self.speechRecognizer = SFSpeechRecognizer()
        }
    }
    
    // MARK: - Authorization
    
    /// Request speech recognition authorization
    public static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
    
    /// Check current authorization status
    public static var authorizationStatus: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }
    
    /// Check if speech recognition is available
    public var isAvailable: Bool {
        speechRecognizer?.isAvailable ?? false
    }
    
    // MARK: - Transcription
    
    /// Transcribe audio file
    public func transcribe(
        audioURL: URL,
        options: TranscriptionOptions = .default,
        progress: ((Float) -> Void)? = nil
    ) async throws -> Transcript {
        
        // Check authorization
        var status = Self.authorizationStatus
        if status == .notDetermined {
            status = await Self.requestAuthorization()
        }
        
        guard status == .authorized else {
            throw TranscriptionError.notAuthorized
        }
        
        // Check availability
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw TranscriptionError.notAvailable
        }
        
        // Create recognition request
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        
        if #available(macOS 13.0, iOS 16.0, *) {
            request.addsPunctuation = true
        }
        
        // Get audio duration for progress
        let asset = AVURLAsset(url: audioURL)
        let duration = try await asset.load(.duration).seconds
        
        // Perform recognition
        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SFSpeechRecognitionResult, Error>) in
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: TranscriptionError.recognitionFailed(error.localizedDescription))
                    return
                }
                
                guard let result = result else {
                    continuation.resume(throwing: TranscriptionError.recognitionFailed("No result"))
                    return
                }
                
                if result.isFinal {
                    continuation.resume(returning: result)
                }
            }
        }
        
        // Convert to our transcript format
        return convertToTranscript(result, duration: duration, options: options)
    }
    
    /// Transcribe audio buffer directly
    public func transcribe(
        buffer: AVAudioPCMBuffer,
        options: TranscriptionOptions = .default
    ) async throws -> Transcript {
        
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw TranscriptionError.notAvailable
        }
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        
        if #available(macOS 13.0, iOS 16.0, *) {
            request.addsPunctuation = true
        }
        
        request.append(buffer)
        request.endAudio()
        
        let duration = Double(buffer.frameLength) / buffer.format.sampleRate
        
        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SFSpeechRecognitionResult, Error>) in
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: TranscriptionError.recognitionFailed(error.localizedDescription))
                    return
                }
                
                guard let result = result else {
                    continuation.resume(throwing: TranscriptionError.recognitionFailed("No result"))
                    return
                }
                
                if result.isFinal {
                    continuation.resume(returning: result)
                }
            }
        }
        
        return convertToTranscript(result, duration: duration, options: options)
    }
    
    // MARK: - Conversion
    
    private func convertToTranscript(
        _ result: SFSpeechRecognitionResult,
        duration: Double,
        options: TranscriptionOptions
    ) -> Transcript {
        
        let bestTranscription = result.bestTranscription
        
        // Build words with timing
        var words: [TranscriptWord] = []
        
        if options.enableWordTiming {
            for segment in bestTranscription.segments {
                words.append(TranscriptWord(
                    word: segment.substring,
                    start: segment.timestamp,
                    end: segment.timestamp + segment.duration,
                    confidence: Float(segment.confidence)
                ))
            }
        }
        
        // Build segments (sentences/phrases)
        let segments = buildSegments(from: bestTranscription, options: options)
        
        // Detect language
        let language = speechRecognizer?.locale.identifier ?? "en-US"
        
        // Calculate overall confidence
        let avgConfidence: Float
        if !words.isEmpty {
            avgConfidence = words.map { $0.confidence }.reduce(0, +) / Float(words.count)
        } else {
            avgConfidence = 0.8  // Default for Apple Speech
        }
        
        return Transcript(
            text: bestTranscription.formattedString,
            language: language,
            segments: segments,
            words: words,
            confidence: avgConfidence,
            engine: .apple,
            duration: duration
        )
    }
    
    private func buildSegments(
        from transcription: SFTranscription,
        options: TranscriptionOptions
    ) -> [TranscriptSegment] {
        
        let words = transcription.segments
        guard !words.isEmpty else { return [] }
        
        var segments: [TranscriptSegment] = []
        var currentSegmentWords: [SFTranscriptionSegment] = []
        var segmentId = 0
        
        // Split by sentence boundaries or max length
        for word in words {
            currentSegmentWords.append(word)
            
            let text = currentSegmentWords.map { $0.substring }.joined(separator: " ")
            let duration = (currentSegmentWords.last?.timestamp ?? 0) + 
                          (currentSegmentWords.last?.duration ?? 0) - 
                          (currentSegmentWords.first?.timestamp ?? 0)
            
            // Check for sentence boundary or max length
            let isSentenceEnd = word.substring.hasSuffix(".") || 
                               word.substring.hasSuffix("?") || 
                               word.substring.hasSuffix("!")
            
            let exceedsMaxLength = duration >= options.maxSegmentLength
            
            if isSentenceEnd || exceedsMaxLength {
                let start = currentSegmentWords.first?.timestamp ?? 0
                let end = (currentSegmentWords.last?.timestamp ?? 0) + 
                         (currentSegmentWords.last?.duration ?? 0)
                
                let confidence = currentSegmentWords.map { Float($0.confidence) }.reduce(0, +) / 
                                Float(currentSegmentWords.count)
                
                segments.append(TranscriptSegment(
                    id: segmentId,
                    start: start,
                    end: end,
                    text: text,
                    confidence: confidence
                ))
                
                segmentId += 1
                currentSegmentWords = []
            }
        }
        
        // Handle remaining words
        if !currentSegmentWords.isEmpty {
            let text = currentSegmentWords.map { $0.substring }.joined(separator: " ")
            let start = currentSegmentWords.first?.timestamp ?? 0
            let end = (currentSegmentWords.last?.timestamp ?? 0) + 
                     (currentSegmentWords.last?.duration ?? 0)
            
            let confidence = currentSegmentWords.map { Float($0.confidence) }.reduce(0, +) / 
                            Float(currentSegmentWords.count)
            
            segments.append(TranscriptSegment(
                id: segmentId,
                start: start,
                end: end,
                text: text,
                confidence: confidence
            ))
        }
        
        return segments
    }
}

// MARK: - Supported Languages

extension TranscriptionEngine {
    
    /// Get list of supported languages
    public static var supportedLanguages: [String] {
        SFSpeechRecognizer.supportedLocales().map { $0.identifier }.sorted()
    }
    
    /// Check if a language is supported
    public static func isLanguageSupported(_ language: String) -> Bool {
        let locale = Locale(identifier: language)
        return SFSpeechRecognizer.supportedLocales().contains(locale)
    }
    
    /// Get the best available recognizer for a language
    public static func recognizer(for language: String) -> SFSpeechRecognizer? {
        return SFSpeechRecognizer(locale: Locale(identifier: language))
    }
}

// MARK: - Quick Transcription

extension TranscriptionEngine {
    
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
