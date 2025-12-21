import Foundation

public final class GoogleProvider: ServiceProvider {
    
    public let id = "google.vertex"
    public let capabilities: Set<ServiceCapability> = [
        .textGeneration,    // Gemini 3 Pro Preview
        .sceneAnalysis,     // Gemini 3 Pro Preview (Vision)
        .videoGeneration,   // Veo 3.1
        .audioGeneration    // Lyria
    ]
    
    private var apiKey: String?
    private var projectId: String?
    private var geminiModel: String = "gemini-3-pro-preview"
    private let session: URLSession
    
    public init() {
        let config = URLSessionConfiguration.default
        // Gemini video uploads can exceed default timeouts.
        config.timeoutIntervalForRequest = 10 * 60 // 10 minutes
        config.timeoutIntervalForResource = 60 * 60 // 60 minutes
        self.session = URLSession(configuration: config)
    }
    
    public func initialize(loader: ConfigurationLoader) async throws {
        // Support both standard and API__ prefixed keys
        self.apiKey = loader.get("GOOGLE_API_KEY") ?? loader.get("API__GOOGLE_API_KEY")
        
        if self.apiKey == nil {
            throw ServiceError.configurationError("Missing required environment variable: GOOGLE_API_KEY or API__GOOGLE_API_KEY")
        }
        
        // Project ID might be needed for Vertex AI endpoints, but for Gemini API key is often enough
        self.projectId = loader.get("GOOGLE_PROJECT_ID")

        // Allow overriding Gemini model via env (.env or ProcessInfo)
        // Default remains Gemini 3 Pro Preview.
        if let override = loader.get("GEMINI_MODEL") ?? loader.get("GOOGLE_GEMINI_MODEL") {
            self.geminiModel = override
        }
    }
    
    public func generate(request: GenerationRequest) -> AsyncThrowingStream<ServiceEvent, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let apiKey = apiKey else {
                        throw ServiceError.configurationError("Google API Key not initialized")
                    }
                    
                    let startTime = Date()
                    continuation.yield(.progress(0.1))
                    
                    let response: GenerationResponse
                    switch request.type {
                    case .textGeneration, .sceneAnalysis:
                        response = try await callGemini(request: request, apiKey: apiKey, startTime: startTime)
                    case .videoGeneration:
                        response = try await callVeo(request: request, apiKey: apiKey, startTime: startTime)
                    case .audioGeneration:
                        response = try await callLyria(request: request, apiKey: apiKey, startTime: startTime)
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
    
    // MARK: - Private API Calls
    
    private func callGemini(request: GenerationRequest, apiKey: String, startTime: Date) async throws -> GenerationResponse {
        // Endpoint for Gemini (default Gemini 3 Pro Preview)
        let model = (request.parameters["model"]?.value as? String) ?? geminiModel
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            throw ServiceError.configurationError("Invalid URL")
        }
        
        // Construct Content Parts
        var parts: [[String: Any]] = []
        
        // 1. Add Text Prompt
        parts.append(["text": request.prompt])
        
        // 2. Add Image (if present in parameters)
        if let imagePath = request.parameters["imagePath"]?.value as? String {
            try appendInlineData(path: imagePath, mimeType: "image/png", to: &parts)
        }
        
        // 3. Add Video (if present)
        if let videoPath = request.parameters["videoPath"]?.value as? String {
            // Use File API for video
            let mimeType = videoPath.hasSuffix(".mov") ? "video/quicktime" : "video/mp4"
            let (fileUri, fileName) = try await uploadFile(path: videoPath, mimeType: mimeType, apiKey: apiKey)
            
            // Wait for file to be processed
            try await waitForFileActive(name: fileName, apiKey: apiKey)
            
            parts.append([
                "file_data": [
                    "mime_type": mimeType,
                    "file_uri": fileUri
                ]
            ])
        }
        
        // 4. Add Audio (if present)
        if let audioPath = request.parameters["audioPath"]?.value as? String {
            try appendInlineData(path: audioPath, mimeType: "audio/mp3", to: &parts)
        }
        
        // Construct JSON body
        let body: [String: Any] = [
            "contents": [
                [
                    "parts": parts
                ]
            ]
        ]
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        urlRequest.timeoutInterval = 10 * 60
        
        let (data, httpResponse) = try await session.data(for: urlRequest)
        
        guard let httpResp = httpResponse as? HTTPURLResponse else {
            throw ServiceError.requestFailed("Invalid response")
        }
        
        if httpResp.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ServiceError.requestFailed("Google API Error (\(httpResp.statusCode)): \(errorText)")
        }
        
        // Parse Response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let partsResp = content["parts"] as? [[String: Any]],
              let textPart = partsResp.first,
              let text = textPart["text"] as? String else {
            throw ServiceError.decodingError("Failed to parse Gemini response")
        }
        
        // Save response text to a temporary file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).txt")
        try text.write(to: tempURL, atomically: true, encoding: .utf8)
        
        let latency = Date().timeIntervalSince(startTime)
        
        return GenerationResponse(
            requestId: request.id,
            status: .success,
            artifacts: [
                ServiceArtifact(type: .text, uri: tempURL, metadata: ["model": model])
            ],
            metrics: ServiceMetrics(latency: latency)
        )
    }
    
    private func uploadFile(path: String, mimeType: String, apiKey: String) async throws -> (uri: String, name: String) {
        let fileURL = URL(fileURLWithPath: path)
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = (attrs[.size] as? NSNumber)?.intValue ?? 0
        if fileSize <= 0 {
            throw ServiceError.requestFailed("Could not determine file size at \(path)")
        }
        
        // 1. Initial Upload Request
        let uploadURLString = "https://generativelanguage.googleapis.com/upload/v1beta/files?key=\(apiKey)"
        guard let uploadURL = URL(string: uploadURLString) else {
            throw ServiceError.configurationError("Invalid Upload URL")
        }
        
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(mimeType, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        request.addValue("\(fileSize)", forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        request.timeoutInterval = 10 * 60
        
        let metadata = ["file": ["display_name": fileURL.lastPathComponent]]
        request.httpBody = try JSONSerialization.data(withJSONObject: metadata)
        
        // Perform Resumable Upload
        request.addValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        request.addValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResp = response as? HTTPURLResponse, 
              let uploadUrlString = httpResp.value(forHTTPHeaderField: "X-Goog-Upload-URL"),
              let uploadSessionURL = URL(string: uploadUrlString) else {
             throw ServiceError.requestFailed("Failed to initiate upload session")
        }
        
        // Step 2: Upload Bytes
        var uploadRequest = URLRequest(url: uploadSessionURL)
        uploadRequest.httpMethod = "POST"
        uploadRequest.addValue("\(fileSize)", forHTTPHeaderField: "Content-Length")
        uploadRequest.addValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        uploadRequest.addValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        uploadRequest.timeoutInterval = 60 * 60
        
        // Stream file upload from disk to avoid large in-memory payloads and reduce timeout risk.
        let (uploadData, uploadResponse) = try await session.upload(for: uploadRequest, fromFile: fileURL)
        
        guard let uploadResp = uploadResponse as? HTTPURLResponse, uploadResp.statusCode == 200 else {
             throw ServiceError.requestFailed("Failed to upload file bytes")
        }
        
        // Parse Result to get URI and Name
        guard let json = try JSONSerialization.jsonObject(with: uploadData) as? [String: Any],
              let fileInfo = json["file"] as? [String: Any],
              let uri = fileInfo["uri"] as? String,
              let name = fileInfo["name"] as? String else {
            throw ServiceError.decodingError("Failed to parse upload response")
        }
        
        print("   ✅ Uploaded file: \(uri)")
        return (uri, name)
    }
    
    private func waitForFileActive(name: String, apiKey: String) async throws {
        print("   ⏳ Waiting for file processing...")
        let fileURLString = "https://generativelanguage.googleapis.com/v1beta/\(name)?key=\(apiKey)"
        guard let fileURL = URL(string: fileURLString) else {
            throw ServiceError.configurationError("Invalid File URL")
        }
        
        var attempts = 0
        let maxAttempts = 60 // Wait up to 60 seconds
        
        while attempts < maxAttempts {
            let (data, response) = try await session.data(from: fileURL)
            
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                throw ServiceError.requestFailed("Failed to check file status")
            }
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let state = json["state"] as? String {
                
                if state == "ACTIVE" {
                    print("   ✅ File is ACTIVE")
                    return
                } else if state == "FAILED" {
                    print("❌ File processing failed. Details: \(json)")
                    throw ServiceError.requestFailed("File processing failed")
                }
                
                // Still processing
                print("      Status: \(state)...")
            }
            
            try await Task.sleep(nanoseconds: 1 * 1_000_000_000) // Sleep 1 second
            attempts += 1
        }
        
        throw ServiceError.requestFailed("Timeout waiting for file to become active")
    }

    private func appendInlineData(path: String, mimeType: String, to parts: inout [[String: Any]]) throws {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else {
            print("⚠️ Warning: Could not read file at \(path)")
            return
        }
        
        // Check size limit (approx 20MB for inline)
        if data.count > 20 * 1024 * 1024 {
            print("⚠️ Warning: File at \(path) is too large for inline transfer (\(data.count) bytes).")
        }
        
        let base64 = data.base64EncodedString()
        let part: [String: Any] = [
            "inline_data": [
                "mime_type": mimeType,
                "data": base64
            ]
        ]
        parts.append(part)
    }
    
    private func callVeo(request: GenerationRequest, apiKey: String, startTime: Date) async throws -> GenerationResponse {
        // Placeholder for Veo 3.1 API
        try await Task.sleep(nanoseconds: 2 * 1_000_000_000) // Simulate 2s latency
        
        let latency = Date().timeIntervalSince(startTime)
        let mockVideoURL = URL(fileURLWithPath: "/tmp/veo_generated.mp4")
        
        return GenerationResponse(
            requestId: request.id,
            status: .success,
            artifacts: [
                ServiceArtifact(type: .video, uri: mockVideoURL, metadata: ["model": "veo-3.1"])
            ],
            metrics: ServiceMetrics(latency: latency)
        )
    }
    
    private func callLyria(request: GenerationRequest, apiKey: String, startTime: Date) async throws -> GenerationResponse {
        // Placeholder for Lyria API
        try await Task.sleep(nanoseconds: 1 * 1_000_000_000)
        
        let latency = Date().timeIntervalSince(startTime)
        let mockAudioURL = URL(fileURLWithPath: "/tmp/lyria_generated.wav")
        
        return GenerationResponse(
            requestId: request.id,
            status: .success,
            artifacts: [
                ServiceArtifact(type: .audio, uri: mockAudioURL, metadata: ["model": "lyria"])
            ],
            metrics: ServiceMetrics(latency: latency)
        )
    }
}
