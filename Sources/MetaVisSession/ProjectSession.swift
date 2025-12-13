import Foundation
import CoreVideo
import AVFoundation
import MetaVisCore
import MetaVisExport
import MetaVisTimeline
import MetaVisPerception
import MetaVisServices

/// Represents the global state of an open project.
public struct ProjectState: Codable, Sendable, Equatable {
    public var timeline: Timeline
    public var config: ProjectConfig
    
    /// The current visual analysis of the frame (The "Eyes" of the system).
    public var visualContext: SemanticFrame?
    
    public init(timeline: Timeline = Timeline(), config: ProjectConfig = ProjectConfig(), visualContext: SemanticFrame? = nil) {
        self.timeline = timeline
        self.config = config
        self.visualContext = visualContext
    }
}

public struct ProjectConfig: Codable, Sendable, Equatable {
    public var name: String = "Untitled Project"
    public var frameRate: Rational = Rational(24, 1)
    public var license: ProjectLicense = ProjectLicense(requiresWatermark: false)
    
    public init(name: String = "Untitled Project", license: ProjectLicense = ProjectLicense(requiresWatermark: false)) {
        self.name = name
        self.license = license
    }
}

/// A discrete mutation to the project state.
public enum EditAction: Sendable {
    case addTrack(Track)
    case addClip(Clip, toTrackId: UUID)
    case removeClip(id: UUID, fromTrackId: UUID)
    case setProjectName(String)
}

/// The Brain. Manages state, undo/redo, and coordination.
public actor ProjectSession: Identifiable {
    public nonisolated let id: UUID = UUID()
    
    /// The current state of the project.
    /// Implementation Note: Exposed via async getter or stream in future.
    public private(set) var state: ProjectState
    
    /// History stack.
    private var undoStack: [ProjectState] = []
    private var redoStack: [ProjectState] = []
    
    /// The Perception Engine (Eyes).
    private let aggregator: VisualContextAggregator
    
    /// The Intelligence Engine (Brain).
    private let llm: LocalLLMService
    private let intentParser: IntentParser

    private let entitlements: EntitlementManager
    
    public init(initialState: ProjectState = ProjectState(), entitlements: EntitlementManager = EntitlementManager()) {
        self.state = initialState
        self.aggregator = VisualContextAggregator()
        self.llm = LocalLLMService()
        self.intentParser = IntentParser()
        self.entitlements = entitlements
    }

    public init<R: ProjectRecipe>(recipe: R, entitlements: EntitlementManager = EntitlementManager()) {
        self.state = recipe.makeInitialState()
        self.aggregator = VisualContextAggregator()
        self.llm = LocalLLMService()
        self.intentParser = IntentParser()
        self.entitlements = entitlements
    }
    
    /// Dispatch an action to mutate the state.
    public func dispatch(_ action: EditAction) {
        // 1. Push current state to undo stack
        undoStack.append(state)
        redoStack.removeAll() // Clear redo on new action
        
        // 2. Apply mutation
        var newState = state
        switch action {
        case .addTrack(let track):
            newState.timeline.tracks.append(track)
            
        case .addClip(let clip, let trackId):
            if let index = newState.timeline.tracks.firstIndex(where: { $0.id == trackId }) {
                newState.timeline.tracks[index].clips.append(clip)
            } else {
                // If track doesn't exist, maybe create it? Or fail silently?
                // For this MVP, let's auto-create if needed or just append logic
                // But strict TDD says do exactly what's needed.
                // If ID matches, append.
            }
            
        case .removeClip(let clipId, let trackId):
            if let index = newState.timeline.tracks.firstIndex(where: { $0.id == trackId }) {
                newState.timeline.tracks[index].clips.removeAll(where: { $0.id == clipId })
            }
            
        case .setProjectName(let name):
            newState.config.name = name
        }
        
        // 3. Update State
        state = newState
    }
    
    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(state)
        state = previous
    }
    
    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(state)
        state = next
    }
    
    // MARK: - Perception
    
    /// Triggers analysis of the current frame (e.g., on Pause).
    /// Updates `state.visualContext`.
    public func analyzeFrame(pixelBuffer: CVPixelBuffer, time: TimeInterval) async {
        do {
            let frame = try await aggregator.analyze(pixelBuffer: pixelBuffer, at: time)
            // Should this be an Undoable Action? 
            // Probably not, it's transient context. But for now, direct mutation.
            state.visualContext = frame
        } catch {
            print("Visual Analysis Failed: \(error)")
        }
    }
    
    // MARK: - Intelligence (Jarvis)
    
    /// Processes a natural language command using the Local LLM.
    /// Returns the parsed intent for the UI to display or confirm.
    public func processCommand(_ text: String) async throws -> UserIntent? {
        
        // 1. Build Context
        // Convert SemanticFrame to JSON String
        let contextString: String
        if let frame = state.visualContext,
           let data = try? JSONEncoder().encode(frame),
           let json = String(data: data, encoding: .utf8) {
            contextString = json
        } else {
            contextString = "{}"
        }
        
        // 2. Request LLM
        let request = LLMRequest(userQuery: text, context: contextString)
        let response = try await llm.generate(request: request)
        
        // 3. Parse Intent
        // Prioritize pre-extracted JSON from the service
        let textToParse = response.intentJSON ?? response.text
        return intentParser.parse(response: textToParse)
    }

    // MARK: - Export

    public func buildPolicyBundle(
        quality: QualityProfile,
        frameRate: Int32 = 24,
        audioPolicy: AudioPolicy = .auto
    ) -> QualityPolicyBundle {
        let license = state.config.license
        let watermarkSpec: WatermarkSpec? = license.requiresWatermark ? .diagonalStripesDefault : nil

        let export = ExportGovernance(
            userPlan: entitlements.currentPlan,
            projectLicense: license,
            watermarkSpec: watermarkSpec
        )

        let hasAudioClips = state.timeline.tracks.contains(where: { $0.kind == .audio && !$0.clips.isEmpty })
        let requireAudioTrack: Bool
        switch audioPolicy {
        case .auto:
            requireAudioTrack = hasAudioClips
        case .required:
            requireAudioTrack = true
        case .forbidden:
            requireAudioTrack = false
        }

        let durationSeconds = max(0.0, state.timeline.duration.seconds)
        let fps = max(1.0, Double(frameRate))
        let tol = max(0.25, min(1.0, durationSeconds * 0.02))
        let expectedFrames = Int((durationSeconds * fps).rounded())
        let minSamples = max(1, Int(Double(expectedFrames) * 0.85))

        let video = VideoContainerPolicy(
            minDurationSeconds: durationSeconds - tol,
            maxDurationSeconds: durationSeconds + tol,
            expectedWidth: quality.resolutionHeight * 16 / 9,
            expectedHeight: quality.resolutionHeight,
            expectedNominalFrameRate: fps,
            minVideoSampleCount: minSamples
        )

        let qc = DeterministicQCPolicy(
            video: video,
            requireAudioTrack: requireAudioTrack,
            requireAudioNotSilent: requireAudioTrack
        )

        return QualityPolicyBundle(export: export, qc: qc, ai: nil, privacy: PrivacyPolicy())
    }

    public func exportMovie(
        using exporter: any VideoExporting,
        to outputURL: URL,
        quality: QualityProfile,
        frameRate: Int32 = 24,
        codec: AVVideoCodecType = .hevc,
        audioPolicy: AudioPolicy = .auto
    ) async throws {
        let bundle = buildPolicyBundle(quality: quality, frameRate: frameRate, audioPolicy: audioPolicy)

        try await exporter.export(
            timeline: state.timeline,
            to: outputURL,
            quality: quality,
            frameRate: frameRate,
            codec: codec,
            audioPolicy: audioPolicy,
            governance: bundle.export
        )
    }
}

