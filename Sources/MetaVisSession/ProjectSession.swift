import Foundation
import CoreVideo
import AVFoundation
import MetaVisCore
import MetaVisExport
import MetaVisTimeline
import MetaVisPerception
import MetaVisServices
import MetaVisQC
import MetaVisIngest

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

internal struct UndoStep {
    let label: String
    let undo: (inout ProjectState) -> Void
    let redo: (inout ProjectState) -> Void
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
    private var undoStack: [UndoStep] = []
    private var redoStack: [UndoStep] = []
    
    /// The Perception Engine (Eyes).
    private let aggregator: VisualContextAggregator

    // Throttle expensive perception so callers can safely invoke from playback/render loops.
    private var lastAnalysisTime: TimeInterval?
    private let minAnalysisInterval: TimeInterval = 0.2 // ~5Hz
    
    /// The Intelligence Engine (Brain).
    private let llm: any LLMProvider
    private let intentParser: IntentParser

    // Cancellation: keep only the most recent in-flight intent request.
    private var currentIntentTask: Task<UserIntent?, Error>?
    private var currentIntentTaskId: UUID?

    private let entitlements: EntitlementManager

    private let trace: any TraceSink
    
    public init(
        initialState: ProjectState = ProjectState(),
        entitlements: EntitlementManager = EntitlementManager(),
        llm: any LLMProvider = LocalLLMService(),
        trace: any TraceSink = NoOpTraceSink()
    ) {
        self.state = initialState
        self.aggregator = VisualContextAggregator()
        self.llm = llm
        self.intentParser = IntentParser()
        self.entitlements = entitlements
        self.trace = trace
    }

    public init<R: ProjectRecipe>(
        recipe: R,
        entitlements: EntitlementManager = EntitlementManager(),
        llm: any LLMProvider = LocalLLMService(),
        trace: any TraceSink = NoOpTraceSink()
    ) {
        self.state = recipe.makeInitialState()
        self.aggregator = VisualContextAggregator()
        self.llm = llm
        self.intentParser = IntentParser()
        self.entitlements = entitlements
        self.trace = trace
    }
    
    /// Dispatch an action to mutate the state.
    public func dispatch(_ action: EditAction) async {
        await trace.record("session.dispatch.begin", fields: ["action": String(describing: action)])

        let before = state
        
        // 2. Apply mutation
        var newState = state
        switch action {
        case .addTrack(let track):
            newState.timeline.tracks.append(track)
            newState.timeline.recomputeDuration()
            
        case .addClip(let clip, let trackId):
            if let index = newState.timeline.tracks.firstIndex(where: { $0.id == trackId }) {
                newState.timeline.tracks[index].clips.append(clip)
                newState.timeline.tracks[index].clips.sort(by: { $0.startTime < $1.startTime })
                newState.timeline.recomputeDuration()
            } else {
                // If track doesn't exist, maybe create it? Or fail silently?
                // For this MVP, let's auto-create if needed or just append logic
                // But strict TDD says do exactly what's needed.
                // If ID matches, append.
            }
            
        case .removeClip(let clipId, let trackId):
            if let index = newState.timeline.tracks.firstIndex(where: { $0.id == trackId }) {
                newState.timeline.tracks[index].clips.removeAll(where: { $0.id == clipId })
                newState.timeline.recomputeDuration()
            }
            
        case .setProjectName(let name):
            newState.config.name = name
        }
        
        // 3. Record undo/redo if the action actually mutated state.
        if newState != before {
            let step: UndoStep
            switch action {
            case .addTrack(let track):
                step = UndoStep(
                    label: "addTrack",
                    undo: { st in
                        st.timeline.tracks.removeAll(where: { $0.id == track.id })
                        st.timeline.recomputeDuration()
                    },
                    redo: { st in
                        st.timeline.tracks.append(track)
                        st.timeline.recomputeDuration()
                    }
                )

            case .addClip(let clip, let trackId):
                step = UndoStep(
                    label: "addClip",
                    undo: { st in
                        if let index = st.timeline.tracks.firstIndex(where: { $0.id == trackId }) {
                            st.timeline.tracks[index].clips.removeAll(where: { $0.id == clip.id })
                            st.timeline.recomputeDuration()
                        }
                    },
                    redo: { st in
                        if let index = st.timeline.tracks.firstIndex(where: { $0.id == trackId }) {
                            st.timeline.tracks[index].clips.append(clip)
                            st.timeline.tracks[index].clips.sort(by: { $0.startTime < $1.startTime })
                            st.timeline.recomputeDuration()
                        }
                    }
                )

            case .removeClip(let clipId, let trackId):
                let removedClips: [Clip]
                if let index = before.timeline.tracks.firstIndex(where: { $0.id == trackId }) {
                    removedClips = before.timeline.tracks[index].clips.filter { $0.id == clipId }
                } else {
                    removedClips = []
                }

                step = UndoStep(
                    label: "removeClip",
                    undo: { st in
                        guard !removedClips.isEmpty else { return }
                        if let index = st.timeline.tracks.firstIndex(where: { $0.id == trackId }) {
                            st.timeline.tracks[index].clips.append(contentsOf: removedClips)
                            st.timeline.tracks[index].clips.sort(by: { $0.startTime < $1.startTime })
                            st.timeline.recomputeDuration()
                        }
                    },
                    redo: { st in
                        if let index = st.timeline.tracks.firstIndex(where: { $0.id == trackId }) {
                            st.timeline.tracks[index].clips.removeAll(where: { $0.id == clipId })
                            st.timeline.recomputeDuration()
                        }
                    }
                )

            case .setProjectName(let name):
                let oldName = before.config.name
                step = UndoStep(
                    label: "setProjectName",
                    undo: { st in st.config.name = oldName },
                    redo: { st in st.config.name = name }
                )
            }

            undoStack.append(step)
            redoStack.removeAll()
        }

        // 4. Update State
        state = newState

        await trace.record("session.dispatch.end", fields: ["action": String(describing: action)])
    }
    
    public func undo() async {
        guard let step = undoStack.popLast() else { return }
        await trace.record("session.undo", fields: [:])
        var newState = state
        step.undo(&newState)
        redoStack.append(step)
        state = newState
    }
    
    public func redo() async {
        guard let step = redoStack.popLast() else { return }
        await trace.record("session.redo", fields: [:])
        var newState = state
        step.redo(&newState)
        undoStack.append(step)
        state = newState
    }
    
    // MARK: - Perception
    
    /// Triggers analysis of the current frame (e.g., on Pause).
    /// Updates `state.visualContext`.
    public func analyzeFrame(pixelBuffer: CVPixelBuffer, time: TimeInterval) async {
        if let last = lastAnalysisTime, (time - last) < minAnalysisInterval {
            return
        }
        lastAnalysisTime = time
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
        await trace.record("intent.process.begin", fields: ["text": text])

        // Cancel any in-flight request; we only care about the most recent user intent.
        currentIntentTask?.cancel()
        let taskId = UUID()
        currentIntentTaskId = taskId

        // 1. Build Context (timeline + clip IDs + optional visual context)
        let editingContext = LLMEditingContext.fromTimeline(state.timeline, visualContext: state.visualContext)
        let contextString: String
        if let data = try? JSONEncoder().encode(editingContext),
           let json = String(data: data, encoding: .utf8) {
            contextString = json
        } else {
            contextString = "{}"
        }

        // 2. Request LLM (in a cancellable task)
        let request = LLMRequest(userQuery: text, context: contextString)
        let task = Task<UserIntent?, Error> { [llm, intentParser, trace] in
            try Task.checkCancellation()
            let response = try await llm.generate(request: request)

            // 3. Parse Intent (prefer pre-extracted JSON if available)
            let textToParse = response.intentJSON ?? response.text
            let parsed = try intentParser.parseValidated(response: textToParse)
            await trace.record(
                "intent.process.end",
                fields: [
                    "hasIntent": parsed == nil ? "false" : "true",
                    "rawWasJSON": response.intentJSON == nil ? "false" : "true"
                ]
            )
            return parsed
        }
        currentIntentTask = task

        defer {
            // Only clear if we are still the current request.
            if currentIntentTaskId == taskId {
                currentIntentTask = nil
                currentIntentTaskId = nil
            }
        }

        do {
            let parsed = try await task.value
            return parsed
        } catch {
            // Preserve cancellation semantics for callers.
            if error is CancellationError { throw error }
            throw error
        }
    }

    /// Processes a natural language command and applies it (intent -> typed commands -> timeline mutation).
    public func processAndApplyCommand(_ text: String) async throws -> UserIntent? {
        // Minimal batching: allow users to chain discrete edits with "then".
        // We interpret this as a single undoable action (atomic undo/redo).
        let clauses = splitClausesOnThen(text)

        // No batching detected.
        guard clauses.count > 1 else {
            let intent = try await processCommand(text)
            if let intent {
                await applyIntent(intent)
            }
            return intent
        }

        await trace.record("intent.batch.begin", fields: ["count": String(clauses.count)])

        let before = state
        var lastIntent: UserIntent? = nil

        for clause in clauses {
            let intent = try await processCommand(clause)
            if let intent {
                lastIntent = intent
                await applyIntent(intent, recordUndo: false)
            }
        }

        if state != before {
            let after = state
            let step = UndoStep(
                label: "intent.batch",
                undo: { st in st = before },
                redo: { st in st = after }
            )
            undoStack.append(step)
            redoStack.removeAll()
        }

        await trace.record(
            "intent.batch.end",
            fields: [
                "count": String(clauses.count),
                "didMutate": state == before ? "false" : "true"
            ]
        )
        return lastIntent
    }

    private func splitClausesOnThen(_ text: String) -> [String] {
        // Split on word-boundary "then" (case-insensitive), keeping everything else intact.
        // Examples:
        // - "move macbeth to 1s then ripple delete zone" => 2 clauses
        // - "strengthen" (contains "then") => 1 clause (no split)
        let pattern = "\\bthen\\b"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return [text.trimmingCharacters(in: .whitespacesAndNewlines)].filter { !$0.isEmpty }
        }

        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        let matches = re.matches(in: text, range: range)
        guard !matches.isEmpty else {
            return [text.trimmingCharacters(in: .whitespacesAndNewlines)].filter { !$0.isEmpty }
        }

        var clauses: [String] = []
        var lastEnd = 0
        for m in matches {
            let r = m.range
            if r.location > lastEnd {
                let seg = ns.substring(with: NSRange(location: lastEnd, length: r.location - lastEnd))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !seg.isEmpty { clauses.append(seg) }
            }
            lastEnd = r.location + r.length
        }

        if lastEnd < ns.length {
            let seg = ns.substring(with: NSRange(location: lastEnd, length: ns.length - lastEnd))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !seg.isEmpty { clauses.append(seg) }
        }

        return clauses
    }

    public func applyIntent(_ intent: UserIntent) async {
        await applyIntent(intent, recordUndo: true)
    }

    private func applyIntent(_ intent: UserIntent, recordUndo: Bool) async {
        await trace.record(
            "intent.apply.begin",
            fields: [
                "action": intent.action.rawValue,
                "target": intent.target
            ]
        )

        let commands = IntentCommandRegistry.commands(for: intent)
        await trace.record("intent.commands.built", fields: ["count": String(commands.count)])

        guard !commands.isEmpty else {
            await trace.record("intent.apply.end", fields: ["count": "0"])
            return
        }

        let before = state

        var timeline = state.timeline
        let executor = CommandExecutor(trace: trace)
        await executor.execute(commands, in: &timeline)
        state.timeline = timeline

        if recordUndo, state != before {
            let after = state
            let step = UndoStep(
                label: "intent.apply",
                undo: { st in st = before },
                redo: { st in st = after }
            )
            undoStack.append(step)
            redoStack.removeAll()
        }

        await trace.record("intent.apply.end", fields: ["count": String(commands.count)])
    }

    // MARK: - Export

    public func buildPolicyBundle(
        quality: QualityProfile,
        frameRate: Int = 24,
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
            expectedWidth: {
                let raw = max(2, quality.resolutionHeight * 16 / 9)
                return (raw % 2 == 0) ? raw : (raw - 1)
            }(),
            expectedHeight: quality.resolutionHeight,
            expectedNominalFrameRate: fps,
            minVideoSampleCount: minSamples
        )

        let qc = DeterministicQCPolicy(
            video: video,
            requireAudioTrack: requireAudioTrack,
            requireAudioNotSilent: requireAudioTrack
        )

        return QualityPolicyBundle(export: export, qc: qc, ai: nil, aiUsage: .localOnlyDefault, privacy: PrivacyPolicy())
    }

    public func exportMovie(
        using exporter: any VideoExporting,
        to outputURL: URL,
        quality: QualityProfile,
        frameRate: Int = 24,
        codec: AVVideoCodecType = .hevc,
        audioPolicy: AudioPolicy = .auto
    ) async throws {
        await trace.record(
            "session.exportMovie.begin",
            fields: [
                "output": outputURL.lastPathComponent,
                "quality": quality.name,
                "fps": String(frameRate),
                "codec": codec.rawValue,
                "audioPolicy": String(describing: audioPolicy)
            ]
        )
        let bundle = buildPolicyBundle(quality: quality, frameRate: frameRate, audioPolicy: audioPolicy)

        await traceVFRDecisionsIfNeeded(timeline: state.timeline, exportFrameRate: frameRate)

        try await exporter.export(
            timeline: state.timeline,
            to: outputURL,
            quality: quality,
            frameRate: frameRate,
            codec: codec,
            audioPolicy: audioPolicy,
            governance: bundle.export
        )

        await trace.record("session.exportMovie.end", fields: ["output": outputURL.lastPathComponent])
    }

    public func exportDeliverable(
        using exporter: any VideoExporting,
        to bundleURL: URL,
        deliverable: ExportDeliverable = .youtubeMaster,
        quality: QualityProfile,
        frameRate: Int = 24,
        codec: AVVideoCodecType = .hevc,
        audioPolicy: AudioPolicy = .auto,
        sidecars: [DeliverableSidecarRequest] = [],
        qcPolicyOverrides: DeterministicQCPolicy? = nil
    ) async throws -> DeliverableManifest {
        await trace.record(
            "session.exportDeliverable.begin",
            fields: [
                "bundle": bundleURL.lastPathComponent,
                "deliverable": deliverable.id,
                "quality": quality.name,
                "fps": String(frameRate),
                "codec": codec.rawValue,
                "audioPolicy": String(describing: audioPolicy),
                "sidecars": String(sidecars.count)
            ]
        )
        let policyBundle = buildPolicyBundle(quality: quality, frameRate: frameRate, audioPolicy: audioPolicy)
        let qcPolicy = qcPolicyOverrides ?? policyBundle.qc

        // Best-effort caption discovery: if the timeline clearly comes from a single file URL,
        // look for sibling caption files (e.g. foo.captions.vtt) and copy them into the bundle.
        let captionSidecarCandidates = captionSidecarCandidates(from: state.timeline)

        await traceVFRDecisionsIfNeeded(timeline: state.timeline, exportFrameRate: frameRate)

        return try await DeliverableWriter.writeBundle(at: bundleURL) { stagingDir in
            let movieURL = stagingDir.appendingPathComponent("video.mov")

            await trace.record("session.exportDeliverable.movie.export.begin", fields: ["output": movieURL.lastPathComponent])

            try await exporter.export(
                timeline: state.timeline,
                to: movieURL,
                quality: quality,
                frameRate: frameRate,
                codec: codec,
                audioPolicy: audioPolicy,
                governance: policyBundle.export
            )

            await trace.record("session.exportDeliverable.movie.export.end", fields: ["output": movieURL.lastPathComponent])

            await trace.record("session.exportDeliverable.qc.begin", fields: [:])
            let report = try await VideoQC.validateMovie(at: movieURL, policy: qcPolicy)
            let qcReport = DeterministicQCReport(
                durationSeconds: report.durationSeconds,
                width: report.width,
                height: report.height,
                nominalFrameRate: report.nominalFrameRate,
                estimatedDataRate: report.estimatedDataRate,
                videoSampleCount: report.videoSampleCount
            )

            let metadata = try await VideoMetadataQC.inspectMovie(at: movieURL)
            let qcMetadataReport = DeliverableMetadataQCReport(
                hasVideoTrack: metadata.hasVideoTrack,
                hasAudioTrack: metadata.hasAudioTrack,
                videoCodecFourCC: metadata.video?.codecFourCC,
                videoFormatName: metadata.video?.formatName,
                videoBitsPerComponent: metadata.video?.bitsPerComponent,
                videoFullRangeVideo: metadata.video?.fullRangeVideo,
                videoIsHDR: metadata.video?.isHDR,
                colorPrimaries: metadata.video?.colorPrimaries,
                transferFunction: metadata.video?.transferFunction,
                yCbCrMatrix: metadata.video?.yCbCrMatrix,
                audioChannelCount: metadata.audio?.channelCount,
                audioSampleRateHz: metadata.audio?.sampleRateHz
            )

            let minDistance = max(0.0, qcPolicy.content?.minAdjacentDistance ?? 0.020)
            let duration = max(0.0, qcReport.durationSeconds)
            // Keep samples strictly inside the timeline to avoid edge cases where a sample lands exactly at
            // (or beyond) duration and yields no decodable frames.
            let endEpsilon = 1.0 / 600.0
            let maxSampleTime = max(0.0, duration - endEpsilon)
            let times = [0.10, 0.50, 0.90].map { min(maxSampleTime, duration * $0) }
            let samples = times.enumerated().map { (i, t) in
                VideoContentQC.Sample(timeSeconds: t, label: ["p10", "p50", "p90"][min(i, 2)])
            }

            let fps = try await VideoContentQC.fingerprints(movieURL: movieURL, samples: samples)

            // Deterministic content metrics (histogram-derived luma stats).
            // By default we keep expectations permissive so this never fails export. Policy can opt-in to enforcement.
            let colorPolicy = qcPolicy.content?.colorStats
            let enforceColorStats = colorPolicy?.enforce == true
            let colorStatsSamples: [VideoContentQC.ColorStatsSample] = samples.map {
                .init(
                    timeSeconds: $0.timeSeconds,
                    label: $0.label,
                    minMeanLuma: enforceColorStats ? (colorPolicy?.minMeanLuma ?? 0) : 0,
                    maxMeanLuma: enforceColorStats ? (colorPolicy?.maxMeanLuma ?? 1) : 1,
                    maxChannelDelta: enforceColorStats ? (colorPolicy?.maxChannelDelta ?? 1) : 1,
                    minLowLumaFraction: enforceColorStats ? (colorPolicy?.minLowLumaFraction ?? 0) : 0,
                    minHighLumaFraction: enforceColorStats ? (colorPolicy?.minHighLumaFraction ?? 0) : 0
                )
            }

            let colorStatsResults = try await VideoContentQC.validateColorStats(
                movieURL: movieURL,
                samples: colorStatsSamples,
                maxDimension: max(16, colorPolicy?.maxDimension ?? 256)
            )

            await trace.record("session.exportDeliverable.qc.end", fields: [:])
            let lumaStatsByLabel: [String: VideoContentQC.ColorStatsResult] = Dictionary(
                uniqueKeysWithValues: colorStatsResults.map { ($0.label, $0) }
            )

            var contentSamples: [DeliverableContentQCReport.Sample] = []
            contentSamples.reserveCapacity(fps.count)
            for (idx, item) in fps.enumerated() {
                let label = item.0
                let fp = item.1
                let t = samples[min(idx, samples.count - 1)].timeSeconds

                let lumaStats: DeliverableContentQCReport.Sample.LumaStats?
                if let stats = lumaStatsByLabel[label] {
                    lumaStats = .init(
                        meanLuma: Double(stats.meanLuma),
                        lowLumaFraction: Double(stats.lowLumaFraction),
                        highLumaFraction: Double(stats.highLumaFraction),
                        peakLumaBin: stats.peakBin
                    )
                } else {
                    lumaStats = nil
                }

                contentSamples.append(DeliverableContentQCReport.Sample(
                    label: label,
                    timeSeconds: t,
                    fingerprint: .init(
                        meanR: fp.meanR,
                        meanG: fp.meanG,
                        meanB: fp.meanB,
                        stdR: fp.stdR,
                        stdG: fp.stdG,
                        stdB: fp.stdB
                    ),
                    lumaStats: lumaStats
                )
                )
            }

            var adjacent: [DeliverableContentQCReport.AdjacentDistance] = []
            adjacent.reserveCapacity(max(0, contentSamples.count - 1))

            let videoClipCount = state.timeline.tracks
                .filter { $0.kind == .video }
                .reduce(0) { $0 + $1.clips.count }

            // Policy-driven gating: only enforce temporal-variety when a timeline plausibly expects change.
            // (e.g. multi-clip edits). Always record the distances.
            let enforceTemporalVariety = (qcPolicy.content?.enforceTemporalVarietyIfMultipleClips ?? true) && videoClipCount >= 2
            var violations: [DeliverableContentQCReport.AdjacentDistance] = []
            violations.reserveCapacity(2)

            for i in 1..<contentSamples.count {
                let prev = contentSamples[i - 1]
                let cur = contentSamples[i]

                let dm = (prev.fingerprint.meanR - cur.fingerprint.meanR) * (prev.fingerprint.meanR - cur.fingerprint.meanR)
                    + (prev.fingerprint.meanG - cur.fingerprint.meanG) * (prev.fingerprint.meanG - cur.fingerprint.meanG)
                    + (prev.fingerprint.meanB - cur.fingerprint.meanB) * (prev.fingerprint.meanB - cur.fingerprint.meanB)
                let ds = (prev.fingerprint.stdR - cur.fingerprint.stdR) * (prev.fingerprint.stdR - cur.fingerprint.stdR)
                    + (prev.fingerprint.stdG - cur.fingerprint.stdG) * (prev.fingerprint.stdG - cur.fingerprint.stdG)
                    + (prev.fingerprint.stdB - cur.fingerprint.stdB) * (prev.fingerprint.stdB - cur.fingerprint.stdB)
                let d = (dm + ds).squareRoot()

                let entry = DeliverableContentQCReport.AdjacentDistance(fromLabel: prev.label, toLabel: cur.label, distance: d)
                adjacent.append(entry)
                if d < minDistance {
                    violations.append(entry)
                }
            }

            if enforceTemporalVariety, !violations.isEmpty {
                let worst = violations.min(by: { $0.distance < $1.distance })
                let dStr = String(format: "%.5f", worst?.distance ?? 0)
                throw NSError(
                    domain: "MetaVisQC",
                    code: 30,
                    userInfo: [NSLocalizedDescriptionKey: "Frames too similar (d=\(dStr)). Possible stuck source."]
                )
            }

            let qcContentReport = DeliverableContentQCReport(
                minDistance: minDistance,
                samples: contentSamples,
                adjacentDistances: adjacent,
                enforced: enforceTemporalVariety,
                violations: violations.isEmpty ? nil : violations
            )

            var writtenSidecars: [DeliverableSidecar] = []
            writtenSidecars.reserveCapacity(sidecars.count)
            var optionalFailures: [DeliverableSidecar] = []
            optionalFailures.reserveCapacity(sidecars.count)

            for request in sidecars {
                do {
                    switch request {
                    case .captionsVTT(let fileName, _):
                        let url = stagingDir.appendingPathComponent(fileName)
                        try await CaptionSidecarWriter.writeWebVTT(to: url, sidecarCandidates: captionSidecarCandidates)
                        writtenSidecars.append(DeliverableSidecar(kind: .captionsVTT, fileName: fileName))

                    case .captionsSRT(let fileName, _):
                        let url = stagingDir.appendingPathComponent(fileName)
                        try await CaptionSidecarWriter.writeSRT(to: url, sidecarCandidates: captionSidecarCandidates)
                        writtenSidecars.append(DeliverableSidecar(kind: .captionsSRT, fileName: fileName))

                    case .transcriptWordsJSON(let fileName, let cues, _):
                        let url = stagingDir.appendingPathComponent(fileName)
                        try await TranscriptSidecarWriter.writeTranscriptWordsJSON(to: url, sidecarCandidates: captionSidecarCandidates, cues: cues)
                        writtenSidecars.append(DeliverableSidecar(kind: .transcriptWordsJSON, fileName: fileName))

                    case .thumbnailJPEG(let fileName, _):
                        let url = stagingDir.appendingPathComponent(fileName)
                        let t = max(0.0, qcReport.durationSeconds * 0.5)
                        try await ThumbnailSidecarWriter.writeThumbnailJPEG(from: movieURL, to: url, timeSeconds: t)
                        writtenSidecars.append(DeliverableSidecar(kind: .thumbnailJPEG, fileName: fileName))

                    case .contactSheetJPEG(let fileName, let columns, let rows, _):
                        let url = stagingDir.appendingPathComponent(fileName)
                        try await ThumbnailSidecarWriter.writeContactSheetJPEG(from: movieURL, to: url, columns: columns, rows: rows)
                        writtenSidecars.append(DeliverableSidecar(kind: .contactSheetJPEG, fileName: fileName))
                    }
                } catch {
                    if request.isRequired {
                        throw error
                    }
                    optionalFailures.append(DeliverableSidecar(kind: request.kind, fileName: request.fileName))
                }
            }

            await trace.record(
                "session.exportDeliverable.sidecars.complete",
                fields: [
                    "requested": String(sidecars.count),
                    "written": String(writtenSidecars.count),
                    "optionalFailures": String(optionalFailures.count)
                ]
            )

            var writtenEntries: [DeliverableSidecarQCReport.Entry] = []
            writtenEntries.reserveCapacity(writtenSidecars.count)

            let requiredByKey: [String: Bool] = Dictionary(uniqueKeysWithValues: sidecars.map {
                ("\($0.kind.rawValue)|\($0.fileName)", $0.isRequired)
            })

            for s in writtenSidecars {
                let url = stagingDir.appendingPathComponent(s.fileName)
                let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
                if size <= 0 {
                    // Caption sidecars are allowed to be empty (no cues).
                    // VTT will still be non-empty due to its header; SRT may be a 0-byte file.
                    if s.kind == .captionsSRT {
                        writtenEntries.append(.init(kind: s.kind, fileName: s.fileName, fileBytes: size))
                        continue
                    }

                    // Treat other empty sidecars as a failure.
                    let key = "\(s.kind.rawValue)|\(s.fileName)"
                    if requiredByKey[key] == true {
                        throw NSError(
                            domain: "MetaVisExport",
                            code: 301,
                            userInfo: [NSLocalizedDescriptionKey: "Required sidecar appears empty: \(s.fileName)"]
                        )
                    }
                    optionalFailures.append(s)
                    continue
                }
                writtenEntries.append(.init(kind: s.kind, fileName: s.fileName, fileBytes: size))
            }

            let requestedSidecars = sidecars.map { $0.sidecar }
            let requestedWithRequirements = sidecars.map {
                DeliverableSidecarQCReport.Requested(kind: $0.kind, fileName: $0.fileName, required: $0.isRequired)
            }
            let qcSidecarReport = DeliverableSidecarQCReport(
                requested: requestedSidecars,
                requestedWithRequirements: requestedWithRequirements,
                written: writtenEntries,
                optionalFailures: optionalFailures.isEmpty ? nil : optionalFailures
            )

            return DeliverableManifest(
                deliverable: deliverable,
                timeline: TimelineSummary.fromTimeline(state.timeline),
                quality: quality,
                frameRate: Int32(frameRate),
                codec: codec.rawValue,
                audioPolicy: audioPolicy,
                governance: policyBundle.export,
                qcPolicy: qcPolicy,
                qcReport: qcReport,
                qcContentReport: qcContentReport,
                qcMetadataReport: qcMetadataReport,
                qcSidecarReport: qcSidecarReport,
                sidecars: writtenSidecars
            )
        }
    }

    private func captionSidecarCandidates(from timeline: Timeline) -> [URL] {
        // Prefer video clips, since those are most likely to carry spoken content.
        let preferred = uniqueFileURLs(from: timeline, preferredTrackKind: .video)
        if preferred.count == 1 {
            return captionSidecarCandidates(forSingleSource: preferred[0])
        }

        // Fall back to any clip sources.
        let all = uniqueFileURLs(from: timeline, preferredTrackKind: nil)
        if all.count == 1 {
            return captionSidecarCandidates(forSingleSource: all[0])
        }

        // Multiple sources: do not guess.
        return []
    }

    private func uniqueFileURLs(from timeline: Timeline, preferredTrackKind: TrackKind?) -> [URL] {
        let tracks = preferredTrackKind == nil
            ? timeline.tracks
            : timeline.tracks.filter { $0.kind == preferredTrackKind }

        var seen: Set<String> = []
        var out: [URL] = []

        for track in tracks {
            for clip in track.clips {
                guard let url = parseLocalFileURL(from: clip.asset.sourceFn) else { continue }
                let key = url.standardizedFileURL.path
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                out.append(url)
            }
        }

        return out
    }

    private func parseLocalFileURL(from sourceFn: String) -> URL? {
        if let url = URL(string: sourceFn), url.isFileURL {
            return url
        }

        // Some recipes may pass a raw path.
        if sourceFn.hasPrefix("/") {
            let url = URL(fileURLWithPath: sourceFn)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        return nil
    }

    private func captionSidecarCandidates(forSingleSource sourceURL: URL) -> [URL] {
        let dir = sourceURL.deletingLastPathComponent()
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        return [
            dir.appendingPathComponent(stem + ".captions.vtt"),
            dir.appendingPathComponent(stem + ".vtt"),
            dir.appendingPathComponent(stem + ".captions.srt"),
            dir.appendingPathComponent(stem + ".srt")
        ]
    }

    private func traceVFRDecisionsIfNeeded(timeline: Timeline, exportFrameRate: Int) async {
        let urls = uniqueFileURLs(from: timeline, preferredTrackKind: .video)
        if urls.isEmpty { return }

        // Keep export deterministic and reasonably fast: probe only a few sources.
        let maxProbeCount = 3
        for url in urls.prefix(maxProbeCount) {
            let ext = url.pathExtension.lowercased()
            let isLikelyVideo = ["mov", "mp4", "m4v"].contains(ext)
            if !isLikelyVideo { continue }

            do {
                let profile = try await VideoTimingProbe.probe(url: url)
                let decision = VideoTimingNormalization.decide(profile: profile, fallbackFPS: Double(max(1, exportFrameRate)))
                await trace.record(
                    "session.export.vfrDecision",
                    fields: [
                        "source": url.lastPathComponent,
                        "nominalFPS": profile.nominalFPS.map { String(format: "%.3f", $0) } ?? "nil",
                        "estimatedFPS": profile.estimatedFPS.map { String(format: "%.3f", $0) } ?? "nil",
                        "vfrLikely": String(profile.isVFRLikely),
                        "mode": decision.mode.rawValue,
                        "targetFPS": String(format: "%.3f", decision.targetFPS),
                        "exportFPS": String(exportFrameRate)
                    ]
                )
            } catch {
                await trace.record(
                    "session.export.vfrDecision.error",
                    fields: [
                        "source": url.lastPathComponent,
                        "error": String(describing: error)
                    ]
                )
            }
        }
    }

    public func exportBatch(
        using exporter: any VideoExporting,
        to baseDirectory: URL,
        deliverables: [ExportDeliverable],
        quality: QualityProfile,
        frameRate: Int = 24,
        codec: AVVideoCodecType = .hevc,
        audioPolicy: AudioPolicy = .auto,
        sidecars: [DeliverableSidecarRequest] = [],
        qcPolicyOverrides: DeterministicQCPolicy? = nil
    ) async throws -> [DeliverableManifest] {
        await trace.record(
            "session.exportBatch.begin",
            fields: [
                "base": baseDirectory.lastPathComponent,
                "count": String(deliverables.count),
                "quality": quality.name,
                "fps": String(frameRate),
                "codec": codec.rawValue,
                "audioPolicy": String(describing: audioPolicy),
                "sidecars": String(sidecars.count)
            ]
        )

        if deliverables.isEmpty {
            await trace.record("session.exportBatch.end", fields: ["count": "0"])
            return []
        }

        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        var manifests: [DeliverableManifest] = []
        manifests.reserveCapacity(deliverables.count)

        for deliverable in deliverables {
            let bundleURL = baseDirectory.appendingPathComponent(deliverable.id, isDirectory: true)

            await trace.record(
                "session.exportBatch.item.begin",
                fields: [
                    "bundle": bundleURL.lastPathComponent,
                    "deliverable": deliverable.id
                ]
            )

            do {
                let manifest = try await exportDeliverable(
                    using: exporter,
                    to: bundleURL,
                    deliverable: deliverable,
                    quality: quality,
                    frameRate: frameRate,
                    codec: codec,
                    audioPolicy: audioPolicy,
                    sidecars: sidecars,
                    qcPolicyOverrides: qcPolicyOverrides
                )
                manifests.append(manifest)

                await trace.record(
                    "session.exportBatch.item.end",
                    fields: [
                        "bundle": bundleURL.lastPathComponent,
                        "deliverable": deliverable.id
                    ]
                )
            } catch {
                await trace.record(
                    "session.exportBatch.item.error",
                    fields: [
                        "bundle": bundleURL.lastPathComponent,
                        "deliverable": deliverable.id,
                        "error": String(describing: error)
                    ]
                )
                await trace.record(
                    "session.exportBatch.error",
                    fields: [
                        "deliverable": deliverable.id,
                        "exported": String(manifests.count)
                    ]
                )
                throw error
            }
        }

        await trace.record("session.exportBatch.end", fields: ["count": String(manifests.count)])
        return manifests
    }
}

private extension DeliverableSidecarRequest {
    var sidecar: DeliverableSidecar {
        switch self {
        case .captionsVTT(let fileName, _):
            return DeliverableSidecar(kind: .captionsVTT, fileName: fileName)
        case .captionsSRT(let fileName, _):
            return DeliverableSidecar(kind: .captionsSRT, fileName: fileName)
        case .transcriptWordsJSON(let fileName, _, _):
            return DeliverableSidecar(kind: .transcriptWordsJSON, fileName: fileName)
        case .thumbnailJPEG(let fileName, _):
            return DeliverableSidecar(kind: .thumbnailJPEG, fileName: fileName)
        case .contactSheetJPEG(let fileName, _, _, _):
            return DeliverableSidecar(kind: .contactSheetJPEG, fileName: fileName)
        }
    }
}

// MARK: - Project persistence

public extension ProjectSession {

    /// Saves the current project state as a deterministic JSON document.
    ///
    /// Note: by default, this does not persist `visualContext` because it is transient and can contain
    /// privacy-sensitive content.
    func saveProject(
        to url: URL,
        recipeID: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        includeVisualContext: Bool = false
    ) throws {
        try ProjectPersistence.save(
            state: state,
            to: url,
            recipeID: recipeID,
            createdAt: createdAt,
            updatedAt: updatedAt,
            includeVisualContext: includeVisualContext
        )
    }

    /// Loads a project JSON document and returns a new session.
    static func loadProject(
        from url: URL,
        entitlements: EntitlementManager = EntitlementManager(),
        trace: any TraceSink = NoOpTraceSink()
    ) throws -> ProjectSession {
        let doc = try ProjectPersistence.load(from: url)
        return ProjectSession(initialState: doc.state, entitlements: entitlements, trace: trace)
    }
}

