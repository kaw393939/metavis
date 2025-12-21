import Foundation
import ArgumentParser
import MetaVisServices

struct AskExpertCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "ask-expert",
        abstract: "QA a rendered video using Gemini 3 (expert critique)."
    )

    @Option(name: .shortAndLong, help: "Path to the rendered video file.")
    var input: String

    @Option(name: .shortAndLong, help: "Output path for the report (defaults next to input as .qa.json or .qa.md).")
    var output: String?

    @Option(name: .shortAndLong, help: "Override the Gemini model (default comes from provider / GEMINI_MODEL).")
    var model: String?

    @Option(name: .shortAndLong, help: "Custom prompt for the expert (defaults to strict JSON QA rubric).")
        var prompt: String = #"""
You are a senior render QA expert for a cinematic scientific visualization engine.

Analyze the attached video and return STRICT JSON ONLY (no markdown, no prose) with this schema:
{
    "model": "string",
    "overallScore10": 0,
    "pass": true,
    "summary": "string",
    "issues": [
        {
            "type": "string",
            "severity": "low|medium|high|critical",
            "evidence": "string",
            "likelyCause": "string",
            "fix": "string"
        }
    ],
    "recommendedTweaks": ["string"],
    "nextExperiment": "string"
}

Focus on: white/black clipping, washed-out look, color cast, edge artifacts, banding, temporal shimmer, stability, and whether the look is cinematic.
"""#

    func run() async throws {
        print("🤖 Ask Expert (Gemini) QA...")

        let config = ConfigurationLoader()
        let provider = GoogleProvider()

        do {
            try await provider.initialize(loader: config)
        } catch {
            print("❌ Configuration Error: \(error)")
            print("   Ensure GOOGLE_API_KEY is set in your environment or .env file.")
            return
        }

        let videoURL = URL(fileURLWithPath: input)
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            print("❌ Error: Video file not found at \(videoURL.path)")
            return
        }

        print("📤 Uploading video: \(videoURL.lastPathComponent)...")

        var params: [String: ServiceParameterValue] = [
            "videoPath": .string(videoURL.path)
        ]
        if let model {
            params["model"] = .string(model)
        }

        let request = GenerationRequest(
            type: .sceneAnalysis,
            prompt: prompt,
            parameters: params
        )

        print("⏳ Waiting for analysis...")
        var fullResponse = ""
        var usedModel: String? = nil

        do {
            for try await event in provider.generate(request: request) {
                switch event {
                case .progress:
                    break
                case .message(let msg):
                    // GoogleProvider currently yields completion with artifact; this is future-proof.
                    print(msg, terminator: "")
                    fullResponse += msg
                case .completion(let response):
                    if let textArtifact = response.artifacts.first(where: { $0.type == .text }) {
                        usedModel = textArtifact.metadata["model"]
                        let text = try String(contentsOf: textArtifact.uri)
                        if fullResponse.isEmpty {
                            fullResponse = text
                        } else {
                            fullResponse += text
                        }
                    }
                }
            }

            let trimmed = fullResponse.trimmingCharacters(in: .whitespacesAndNewlines)
            let isJSON = trimmed.hasPrefix("{") && trimmed.hasSuffix("}")

            let reportURL: URL = {
                if let output {
                    return URL(fileURLWithPath: output)
                }
                if isJSON {
                    return videoURL.deletingPathExtension().appendingPathExtension("qa.json")
                }
                return videoURL.deletingPathExtension().appendingPathExtension("qa.md")
            }()

            if isJSON, let usedModel {
                // If the model field is missing, inject it via JSON parse/serialize.
                if let data = trimmed.data(using: .utf8),
                   var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if obj["model"] == nil {
                        obj["model"] = usedModel
                    }
                    let outData = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
                    try outData.write(to: reportURL)
                } else {
                    try trimmed.write(to: reportURL, atomically: true, encoding: .utf8)
                }
            } else {
                try trimmed.write(to: reportURL, atomically: true, encoding: .utf8)
            }

            print("\n✅ Expert QA complete.")
            if let usedModel {
                print("   Model: \(usedModel)")
            }
            print("📄 Report saved to: \(reportURL.path)")

            if let usedModel, !usedModel.contains("gemini-3") {
                print("⚠️ Warning: model does not look like Gemini 3: \(usedModel)")
            }

        } catch {
            print("❌ Error during generation: \(error)")
        }
    }
}
