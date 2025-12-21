import Foundation

public final class ElevenLabsProvider: ServiceProvider {
    
    public let id = "elevenlabs"
    public let capabilities: Set<ServiceCapability> = [
        .speechSynthesis,   // TTS
        .speechToSpeech,    // STS
        .audioGeneration    // SFX
    ]
    
    private var apiKey: String?
    private let session = URLSession.shared
    
    public init() {}
    
    public func initialize(loader: ConfigurationLoader) async throws {
        self.apiKey = loader.get("ELEVENLABS_API_KEY") ?? loader.get("API__ELEVENLABS_API_KEY")
        
        if self.apiKey == nil {
             // Optional: Don't throw if you want to allow partial initialization, 
             // but for now let's be strict if it's registered.
             // Actually, if we throw here, the whole orchestrator setup fails.
             // Maybe we should just log warning? But the interface throws.
             // Let's throw for now as per original intent.
             throw ServiceError.configurationError("Missing required environment variable: ELEVENLABS_API_KEY or API__ELEVENLABS_API_KEY")
        }
    }
    
    public func generate(request: GenerationRequest) -> AsyncThrowingStream<ServiceEvent, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let apiKey = apiKey else {
                        throw ServiceError.configurationError("ElevenLabs API Key not initialized")
                    }
                    
                    let startTime = Date()
                    continuation.yield(.progress(0.1))
                    
                    let response: GenerationResponse
                    switch request.type {
                    case .speechSynthesis:
                        response = try await callTTS(request: request, apiKey: apiKey, startTime: startTime)
                    case .audioGeneration:
                        response = try await callSFX(request: request, apiKey: apiKey, startTime: startTime)
                    default:
                        throw ServiceError.unsupportedCapability(request.type)
                    }
                    
                    continuation.yield(.progress(1.0))
                    continuation.yield(.completion(response))
                    continuation.finish()
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    private func callTTS(request: GenerationRequest, apiKey: String, startTime: Date) async throws -> GenerationResponse {
        // Default to Turbo v2.5 for speed
        let voiceId = request.parameters["voiceId"]?.value as? String ?? "21m00Tcm4TlvDq8ikWAM" // Rachel
        let modelId = "eleven_turbo_v2_5"
        
        let urlString = "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)"
        guard let url = URL(string: urlString) else { throw ServiceError.configurationError("Invalid URL") }
        
        let body: [String: Any] = [
            "text": request.prompt,
            "model_id": modelId,
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.5
            ]
        ]
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue(apiKey, forHTTPHeaderField: "xi-api-key")
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ServiceError.requestFailed("ElevenLabs API Error: \(response)")
        }
        
        let latency = Date().timeIntervalSince(startTime)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).mp3")
        try data.write(to: tempURL)
        
        return GenerationResponse(
            requestId: request.id,
            status: .success,
            artifacts: [
                ServiceArtifact(type: .audio, uri: tempURL, metadata: ["model": modelId, "voice": voiceId])
            ],
            metrics: ServiceMetrics(latency: latency)
        )
    }
    
    private func callSFX(request: GenerationRequest, apiKey: String, startTime: Date) async throws -> GenerationResponse {
        // Placeholder for SFX API
        let urlString = "https://api.elevenlabs.io/v1/sound-generation"
        guard let url = URL(string: urlString) else { throw ServiceError.configurationError("Invalid URL") }
        
        let body: [String: Any] = [
            "text": request.prompt,
            "duration_seconds": 5.0
        ]
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue(apiKey, forHTTPHeaderField: "xi-api-key")
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        // Simulate call for now as SFX might be in alpha/beta
        try await Task.sleep(nanoseconds: 1 * 1_000_000_000)
        
        let latency = Date().timeIntervalSince(startTime)
        let mockURL = URL(fileURLWithPath: "/tmp/sfx_generated.mp3")
        
        return GenerationResponse(
            requestId: request.id,
            status: .success,
            artifacts: [
                ServiceArtifact(type: .audio, uri: mockURL, metadata: ["type": "sfx"])
            ],
            metrics: ServiceMetrics(latency: latency)
        )
    }
}
