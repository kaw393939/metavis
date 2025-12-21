// GeminiClient.swift
// MetaVisRender
//
// Created for Sprint 14: Validation
// Gemini 3 Pro API client for document analysis and video validation

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Gemini Client

/// Client for Google Gemini API (Gemini 3 Pro, Veo 3)
public actor GeminiClient {
    
    // MARK: - Configuration
    
    public struct Config: Sendable {
        public let apiKey: String
        public let model: String
        public let baseURL: String
        public let timeout: TimeInterval
        
        public init(
            apiKey: String,
            model: String = "gemini-2.0-flash-exp",
            baseURL: String = "https://generativelanguage.googleapis.com",
            timeout: TimeInterval = 120
        ) {
            self.apiKey = apiKey
            self.model = model
            self.baseURL = baseURL
            self.timeout = timeout
        }
        
        public static func fromEnvironment() throws -> Config {
            guard let apiKey = ProcessInfo.processInfo.environment["API__GOOGLE_API_KEY"] else {
                throw GeminiError.missingAPIKey
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
    
    // MARK: - File Upload
    
    /// Upload a file to Gemini Files API
    public func uploadFile(_ url: URL, mimeType: String? = nil) async throws -> FileUploadResponse {
        let fileData = try Data(contentsOf: url)
        let fileName = url.lastPathComponent
        
        // Detect MIME type if not provided
        let detectedMimeType = mimeType ?? detectMimeType(for: url)
        
        // Create multipart form data
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        
        // Add file metadata
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"metadata\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
        
        let metadata = [
            "file": [
                "display_name": fileName,
                "mime_type": detectedMimeType
            ]
        ]
        let metadataJSON = try JSONSerialization.data(withJSONObject: metadata)
        body.append(metadataJSON)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add file data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(detectedMimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        // Create request
        let uploadURL = URL(string: "\(config.baseURL)/upload/v1beta/files?key=\(config.apiKey)")!
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GeminiError.uploadFailed(httpResponse.statusCode, errorMessage)
        }
        
        let uploadResponse = try JSONDecoder().decode(FileUploadResponse.self, from: data)
        return uploadResponse
    }
    
    // MARK: - Document Analysis
    
    /// Analyze a PDF document with Gemini
    public func analyzePDF(_ fileURI: String, prompt: String? = nil) async throws -> String {
        let defaultPrompt = """
        Analyze this PDF document and provide:
        1. A comprehensive summary of the main content
        2. Key themes and topics covered
        3. Document structure and organization
        4. Important quotes or highlights
        5. Target audience and purpose
        
        Format your response in clear sections with bullet points.
        """
        
        return try await generateContent(
            prompt: prompt ?? defaultPrompt,
            fileURI: fileURI,
            mimeType: "application/pdf"
        )
    }
    
    // MARK: - Video Analysis
    
    /// Analyze a video file with Gemini
    public func analyzeVideo(_ fileURI: String, prompt: String) async throws -> String {
        return try await generateContent(
            prompt: prompt,
            fileURI: fileURI,
            mimeType: "video/mp4"
        )
    }
    
    // MARK: - Video Validation
    
    /// Validate a generated video against expected criteria
    public func validateVideo(
        _ fileURI: String,
        expectedEffects: [String],
        technicalChecks: [String]
    ) async throws -> ValidationResult {
        let prompt = """
        Analyze this video with technical precision. Check for:
        
        Expected Effects:
        \(expectedEffects.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
        
        Technical Quality Checks:
        \(technicalChecks.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
        
        For each item, provide:
        - PASS or FAIL status
        - Timestamp(s) where the effect/issue occurs (if applicable)
        - Brief explanation
        
        Format your response as JSON:
        {
          "overall_pass": true/false,
          "checks": [
            {
              "item": "description",
              "status": "PASS/FAIL",
              "timestamps": ["00:05", "00:12"],
              "notes": "explanation"
            }
          ]
        }
        """
        
        let response = try await analyzeVideo(fileURI, prompt: prompt)
        
        // Parse JSON response
        guard let jsonData = extractJSON(from: response),
              let result = try? JSONDecoder().decode(ValidationResult.self, from: jsonData) else {
            // Fallback: parse text response
            return ValidationResult(
                overallPass: response.contains("PASS"),
                checks: [],
                rawResponse: response
            )
        }
        
        return result
    }
    
    // MARK: - Content Generation
    
    private func generateContent(
        prompt: String,
        fileURI: String? = nil,
        mimeType: String? = nil
    ) async throws -> String {
        var parts: [[String: Any]] = [
            ["text": prompt]
        ]
        
        if let fileURI = fileURI, let mimeType = mimeType {
            parts.append([
                "file_data": [
                    "mime_type": mimeType,
                    "file_uri": fileURI
                ]
            ])
        }
        
        let requestBody: [String: Any] = [
            "contents": [
                ["parts": parts]
            ],
            "generationConfig": [
                "temperature": 0.4,
                "maxOutputTokens": 8192
            ]
        ]
        
        let url = URL(string: "\(config.baseURL)/v1beta/models/\(config.model):generateContent?key=\(config.apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GeminiError.apiError(httpResponse.statusCode, errorMessage)
        }
        
        let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
        
        guard let firstCandidate = geminiResponse.candidates.first,
              let firstPart = firstCandidate.content.parts.first,
              let text = firstPart.text else {
            throw GeminiError.noContentGenerated
        }
        
        return text
    }
    
    // MARK: - Helpers
    
    private func detectMimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf": return "application/pdf"
        case "mp4", "mov": return "video/mp4"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        default: return "application/octet-stream"
        }
    }
    
    private func extractJSON(from text: String) -> Data? {
        // Try to extract JSON from markdown code block
        if let jsonStart = text.range(of: "```json")?.upperBound,
           let jsonEnd = text.range(of: "```", range: jsonStart..<text.endIndex)?.lowerBound {
            let jsonString = String(text[jsonStart..<jsonEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            return jsonString.data(using: .utf8)
        }
        
        // Try raw JSON
        if let jsonStart = text.range(of: "{"),
           let jsonEnd = text.range(of: "}", options: .backwards) {
            let jsonString = String(text[jsonStart.lowerBound...jsonEnd.upperBound])
            return jsonString.data(using: .utf8)
        }
        
        return nil
    }
}

// MARK: - Response Types

public struct FileUploadResponse: Codable {
    public let file: FileInfo
    
    public struct FileInfo: Codable {
        public let name: String
        public let displayName: String?
        public let mimeType: String
        public let sizeBytes: String?
        public let createTime: String?
        public let updateTime: String?
        public let expirationTime: String?
        public let sha256Hash: String?
        public let uri: String
        public let state: String?
    }
}

struct GeminiResponse: Codable {
    let candidates: [Candidate]
    
    struct Candidate: Codable {
        let content: Content
        let finishReason: String?
        let safetyRatings: [SafetyRating]?
    }
    
    struct Content: Codable {
        let parts: [Part]
        let role: String?
    }
    
    struct Part: Codable {
        let text: String?
    }
    
    struct SafetyRating: Codable {
        let category: String
        let probability: String
    }
}

public struct ValidationResult: Codable {
    public let overallPass: Bool
    public let checks: [ValidationCheck]
    public let rawResponse: String?
    
    public struct ValidationCheck: Codable {
        public let item: String
        public let status: String
        public let timestamps: [String]?
        public let notes: String?
    }
}

// MARK: - Errors

public enum GeminiError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case uploadFailed(Int, String)
    case apiError(Int, String)
    case noContentGenerated
    
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API__GOOGLE_API_KEY not found in environment"
        case .invalidResponse:
            return "Invalid response from Gemini API"
        case .uploadFailed(let code, let message):
            return "File upload failed (\(code)): \(message)"
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        case .noContentGenerated:
            return "No content generated by Gemini"
        }
    }
}
