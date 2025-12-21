import Foundation
import MetaVisServices

/// Generates scientific reports from test run contexts using AI.
public actor ReportGenerator {
    
    private let orchestrator: ServiceOrchestrator
    
    public init(orchestrator: ServiceOrchestrator) {
        self.orchestrator = orchestrator
    }
    
    public func generateReport(context: TestRunContext) async throws -> String {
        // 1. Serialize Context to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(context)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        
        // 2. Construct the "Scientist" Prompt
        let prompt = """
        You are the Chief Scientific Officer for the MetaVis Render Engine.
        Your goal is to analyze the following test run data and generate a strict, factual, and high-quality scientific report.
        
        We are building a Hollywood-grade rendering engine on Apple Silicon.
        
        DATA CONTEXT:
        \(jsonString)
        
        INSTRUCTIONS:
        1. Analyze the correlation between the Quantitative metrics (local stats) and the Qualitative observations (visual analysis).
        2. Evaluate the Performance metrics. Is the generation time acceptable for real-time workflows?
        3. Assess the Quality. Does this meet "Cinema Standards"? Look for aliasing, noise, or artifacts mentioned in the qualitative data.
        4. Provide a Pass/Fail rating.
        
        FORMAT (Markdown):
        # Scientific Report: Test Run \(context.id.uuidString.prefix(8))
        ## Executive Summary
        [Pass/Fail] - [Brief Conclusion]
        
        ## System Context
        - GPU: \(context.environment.gpuName)
        - Memory: \(ByteCountFormatter.string(fromByteCount: Int64(context.environment.physicalMemory), countStyle: .memory))
        
        ## Analysis
        ### Visual Quality
        [Analysis of qualitative data]
        
        ### Performance Profile
        [Analysis of timing data]
        
        ## Conclusion & Recommendations
        [Strict assessment and next steps]
        """
        
        // 3. Call Gemini (Text Generation)
        let request = GenerationRequest(
            type: .textGeneration,
            prompt: prompt
        )
        
        var reportContent = ""
        
        let stream = await orchestrator.generate(request: request)
        for try await event in stream {
            if case .completion(let response) = event {
                // In a real scenario, the text is in the artifacts or a message
                // For now, we assume the provider might send the text in a message or we need to parse the artifact
                // Let's assume the provider sends the text content in the artifact for textGeneration
                if let artifact = response.artifacts.first, artifact.type == .text {
                    reportContent = try String(contentsOf: artifact.uri)
                }
            }
        }
        
        // Fallback if the provider implementation differs (e.g. if it streams text via messages)
        // For this implementation, we'll rely on the artifact.
        
        return reportContent
    }
}
