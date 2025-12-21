// ElevenLabsClient.swift
// MetaVisRender
//
// Created for Sprint 14: Validation
// ElevenLabs API client for voice generation and sound effects

import Foundation
import AVFoundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - ElevenLabs Client

/// Client for ElevenLabs API (voice generation and sound effects)
public actor ElevenLabsClient {
    
    // MARK: - Configuration
    
    public struct Config: Sendable {
        public let apiKey: String
        public let baseURL: String
        public let timeout: TimeInterval
        
        public init(
            apiKey: String,
            baseURL: String = "https://api.elevenlabs.io/v1",
            timeout: TimeInterval = 60
        ) {
            self.apiKey = apiKey
            self.baseURL = baseURL
            self.timeout = timeout
        }
        
        public static func fromEnvironment() throws -> Config {
            guard let apiKey = ProcessInfo.processInfo.environment["API__ELEVENLABS_API_KEY"] else {
                throw ElevenLabsError.missingAPIKey
            }
            return Config(apiKey: apiKey)
        }
    }
    
    // MARK: - Properties
    
    private let config: Config
    private let session: URLSession
    
    // MARK: - Initialization
    
    public init(config: Config) {
        self.config = config
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = config.timeout
        sessionConfig.timeoutIntervalForResource = config.timeout * 2
        self.session = URLSession(configuration: sessionConfig)
    }
    
    public init() throws {
        try self.init(config: Config.fromEnvironment())
    }
    
    // MARK: - Voice Generation
    
    /// Generate speech from text
    public func generateSpeech(
        text: String,
        voiceId: String = "21m00Tcm4TlvDq8ikWAM",  // Default: Rachel voice
        modelId: String = "eleven_turbo_v2_5",
        outputPath: URL? = nil
    ) async throws -> URL {
        let url = URL(string: "\(config.baseURL)/text-to-speech/\(voiceId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "text": text,
            "model_id": modelId,
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75,
                "style": 0.0,
                "use_speaker_boost": true
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ElevenLabsError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ElevenLabsError.apiError(httpResponse.statusCode, errorMessage)
        }
        
        // Save audio data
        let outputURL = outputPath ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("elevenlabs_\(UUID().uuidString).mp3")
        
        try data.write(to: outputURL)
        return outputURL
    }
    
    // MARK: - Sound Effects
    
    /// Generate a sound effect from text description
    public func generateSoundEffect(
        description: String,
        durationSeconds: Double? = nil,
        promptInfluence: Double = 0.3,
        outputPath: URL? = nil
    ) async throws -> URL {
        let url = URL(string: "\(config.baseURL)/sound-generation")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var requestBody: [String: Any] = [
            "text": description,
            "prompt_influence": promptInfluence
        ]
        
        if let duration = durationSeconds {
            requestBody["duration_seconds"] = duration
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ElevenLabsError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ElevenLabsError.apiError(httpResponse.statusCode, errorMessage)
        }
        
        // Save audio data
        let outputURL = outputPath ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("elevenlabs_sfx_\(UUID().uuidString).mp3")
        
        try data.write(to: outputURL)
        return outputURL
    }
    
    // MARK: - Voice Listing
    
    /// Get available voices
    public func listVoices() async throws -> [Voice] {
        let url = URL(string: "\(config.baseURL)/voices")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(config.apiKey, forHTTPHeaderField: "xi-api-key")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ElevenLabsError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ElevenLabsError.apiError(httpResponse.statusCode, errorMessage)
        }
        
        let voicesResponse = try JSONDecoder().decode(VoicesResponse.self, from: data)
        return voicesResponse.voices
    }
    
    // MARK: - Positional Audio Test Generator
    
    /// Generate audio clips for spatial/positional audio testing
    public func generatePositionalAudioTest(
        positions: [ElevenLabsSpatialPosition],
        outputDirectory: URL
    ) async throws -> [URL] {
        var outputURLs: [URL] = []
        
        for (index, position) in positions.enumerated() {
            let text = "This sound is positioned at \(position.description)"
            let outputPath = outputDirectory
                .appendingPathComponent("position_\(index)_\(position.label).mp3")
            
            let audioURL = try await generateSpeech(
                text: text,
                voiceId: "21m00Tcm4TlvDq8ikWAM",  // Rachel voice
                outputPath: outputPath
            )
            
            outputURLs.append(audioURL)
        }
        
        return outputURLs
    }
}

// MARK: - Types

public struct Voice: Codable {
    public let voiceId: String
    public let name: String
    public let category: String?
    public let description: String?
    public let previewUrl: String?
    public let labels: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case voiceId = "voice_id"
        case name
        case category
        case description
        case previewUrl = "preview_url"
        case labels
    }
}

struct VoicesResponse: Codable {
    let voices: [Voice]
}

public struct ElevenLabsSpatialPosition {
    public let x: Float  // -1 (left) to 1 (right)
    public let y: Float  // -1 (back) to 1 (front)
    public let z: Float  // -1 (down) to 1 (up)
    public let label: String
    
    public init(x: Float, y: Float, z: Float, label: String) {
        self.x = x
        self.y = y
        self.z = z
        self.label = label
    }
    
    public var description: String {
        let horizontal = x < -0.3 ? "left" : x > 0.3 ? "right" : "center"
        let vertical = z < -0.3 ? "below" : z > 0.3 ? "above" : "level"
        let depth = y < -0.3 ? "behind" : y > 0.3 ? "front" : "middle"
        return "\(horizontal) \(vertical) \(depth)"
    }
    
    // Preset positions for testing
    public static let presets: [ElevenLabsSpatialPosition] = [
        ElevenLabsSpatialPosition(x: 0, y: 0, z: 0, label: "center"),
        ElevenLabsSpatialPosition(x: -1, y: 0, z: 0, label: "left"),
        ElevenLabsSpatialPosition(x: 1, y: 0, z: 0, label: "right"),
        ElevenLabsSpatialPosition(x: 0, y: 1, z: 0, label: "front"),
        ElevenLabsSpatialPosition(x: 0, y: -1, z: 0, label: "back"),
        ElevenLabsSpatialPosition(x: 0, y: 0, z: 1, label: "above"),
        ElevenLabsSpatialPosition(x: 0, y: 0, z: -1, label: "below"),
        ElevenLabsSpatialPosition(x: -0.7, y: 0.7, z: 0, label: "front_left"),
        ElevenLabsSpatialPosition(x: 0.7, y: 0.7, z: 0, label: "front_right"),
    ]
}

// MARK: - Errors

public enum ElevenLabsError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(Int, String)
    
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API__ELEVENLABS_API_KEY not found in environment"
        case .invalidResponse:
            return "Invalid response from ElevenLabs API"
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        }
    }
}
