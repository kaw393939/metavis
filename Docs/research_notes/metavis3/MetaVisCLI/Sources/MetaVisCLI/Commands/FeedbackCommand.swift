import Foundation
import ArgumentParser
import MetaVisServices

struct FeedbackCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "feedback",
        abstract: "Sends a rendered video to Gemini 3 Pro for feedback."
    )
    
    @Option(name: .shortAndLong, help: "Path to the video file.")
    var input: String
    
    @Option(name: .shortAndLong, help: "Custom prompt for the AI.")
    var prompt: String = "Analyze this scientific visualization. Describe the astronomical features visible, the color palette used (and its scientific validity if inferable), and any potential rendering artifacts. Provide constructive feedback on the visual clarity."
    
    func run() async throws {
        print("🤖 Initializing Feedback Agent (Gemini 3 Pro)...")
        
        // 1. Load Config
        let config = ConfigurationLoader()
        
        // 2. Init Provider
        let provider = GoogleProvider()
        do {
            try await provider.initialize(loader: config)
        } catch {
            print("❌ Configuration Error: \(error)")
            print("   Ensure GOOGLE_API_KEY is set in your environment or .env file.")
            return
        }
        
        // 3. Prepare Request
        let videoURL = URL(fileURLWithPath: input)
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            print("❌ Error: Video file not found at \(videoURL.path)")
            return
        }
        
        print("📤 Uploading video: \(videoURL.lastPathComponent)...")
        
        let request = GenerationRequest(
            type: .sceneAnalysis,
            prompt: prompt,
            parameters: [
                "videoPath": .string(videoURL.path)
            ]
        )
        
        // 4. Stream Response
        print("⏳ Waiting for analysis...")
        var fullResponse = ""
        
        do {
            for try await event in provider.generate(request: request) {
                switch event {
                case .progress(_):
                    // print("   Progress: \(Int(p * 100))%")
                    break
                case .message(let msg):
                    print(msg, terminator: "")
                    fullResponse += msg
                case .completion(let response):
                    // If the provider returns the full text in artifacts:
                    if let textArtifact = response.artifacts.first(where: { $0.type == .text }) {
                        let text = try String(contentsOf: textArtifact.uri)
                        // Only use artifact if we didn't get streaming messages
                        if fullResponse.isEmpty {
                            print(text)
                            fullResponse = text
                        }
                    }
                }
            }
            print("\n✅ Analysis Complete.")
            
            // 5. Save Report
            let reportPath = videoURL.deletingPathExtension().appendingPathExtension("report.md")
            try fullResponse.write(to: reportPath, atomically: true, encoding: .utf8)
            print("📄 Report saved to: \(reportPath.path)")
            
        } catch {
            print("❌ Error during generation: \(error)")
        }
    }
}
