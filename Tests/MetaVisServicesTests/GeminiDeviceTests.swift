import XCTest
import Foundation
@testable import MetaVisServices

final class GeminiDeviceTests: XCTestCase {

    private final class CapturingURLProtocol: URLProtocol {
        static var lastRequestBody: Data?
        static var lastRequestHeaders: [String: String]?

        private static func readAll(from stream: InputStream) -> Data {
            stream.open()
            defer { stream.close() }

            var data = Data()
            let bufferSize = 16 * 1024
            var buffer = [UInt8](repeating: 0, count: bufferSize)

            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: bufferSize)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            return data
        }

        override class func canInit(with request: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            if let body = request.httpBody {
                Self.lastRequestBody = body
            } else if let stream = request.httpBodyStream {
                Self.lastRequestBody = Self.readAll(from: stream)
            } else {
                Self.lastRequestBody = nil
            }
            if let headers = request.allHTTPHeaderFields {
                Self.lastRequestHeaders = headers
            }

            let responseJSON = """
            {
              "candidates": [
                { "content": { "parts": [ { "text": "ok" } ] } }
              ]
            }
            """

            let data = Data(responseJSON.utf8)
            let http = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.invalid")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!

            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {
        }
    }

    func testAskExpert_withImageData_encodesInlineData() async throws {
        let cfg = GeminiConfig(apiKey: "TEST_KEY", baseURL: URL(string: "https://example.invalid/v1beta")!, model: "gemini-test")

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [CapturingURLProtocol.self]
        let urlSession = URLSession(configuration: sessionConfig)

        let device = try GeminiDevice(config: cfg, urlSession: urlSession)

        let jpegHeader = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let _ = try await device.perform(action: "ask_expert", with: [
            "prompt": .string("What is in this image?"),
            "imageData": .data(jpegHeader),
            "imageMimeType": .string("image/jpeg")
        ])

        guard let body = CapturingURLProtocol.lastRequestBody,
              let json = String(data: body, encoding: .utf8) else {
            XCTFail("Missing request body")
            return
        }

        // We accept snake_case or camelCase depending on endpoint behavior; the client may retry.
        let hasInlineDataKey = json.contains("inline_data") || json.contains("inlineData")
        let hasMimeTypeKey = json.contains("mime_type") || json.contains("mimeType")
        let hasMimeTypeValue = json.contains("image/jpeg") || json.contains("image\\/jpeg")

        if !hasInlineDataKey {
            XCTFail("Expected inline data in request body; got: \(json)")
        }
        if !hasMimeTypeKey {
            XCTFail("Expected mime type field in request body; got: \(json)")
        }
        if !hasMimeTypeValue {
            XCTFail("Expected image/jpeg in request body; got: \(json)")
        }
    }
}
