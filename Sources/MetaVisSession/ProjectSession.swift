import Foundation
import CoreVideo
import AVFoundation
import MetaVisCore
import MetaVisExport
import MetaVisTimeline
import MetaVisPerception
import MetaVisServices
import MetaVisQC

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

    // Throttle expensive perception so callers can safely invoke from playback/render loops.
    private var lastAnalysisWallClock: TimeInterval = 0
    private let minAnalysisInterval: TimeInterval = 0.2 // ~5Hz
    
    /// The Intelligence Engine (Brain).
    private let llm: LocalLLMService
    private let intentParser: IntentParser

    private let entitlements: EntitlementManager

    private let trace: any TraceSink
    
    public init(
        initialState: ProjectState = ProjectState(),
        entitlements: EntitlementManager = EntitlementManager(),
        trace: any TraceSink = NoOpTraceSink()
    ) {
        self.state = initialState
        self.aggregator = VisualContextAggregator()
        self.llm = LocalLLMService()
        self.intentParser = IntentParser()
        self.entitlements = entitlements
        self.trace = trace
    }

    public init<R: ProjectRecipe>(
        recipe: R,
        entitlements: EntitlementManager = EntitlementManager(),
        trace: any TraceSink = NoOpTraceSink()
    ) {
        self.state = recipe.makeInitialState()
        self.aggregator = VisualContextAggregator()
        self.llm = LocalLLMService()
        self.intentParser = IntentParser()
        self.entitlements = entitlements
        self.trace = trace
    }
    
    /// Dispatch an action to mutate the state.
    public func dispatch(_ action: EditAction) async {
        await trace.record("session.dispatch.begin", fields: ["action": String(describing: action)])
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

        await trace.record("session.dispatch.end", fields: ["action": String(describing: action)])
    }
    
    public func undo() async {
        guard let previous = undoStack.popLast() else { return }
        await trace.record("session.undo", fields: [:])
        redoStack.append(state)
        state = previous
    }
    
    public func redo() async {
        guard let next = redoStack.popLast() else { return }
        await trace.record("session.redo", fields: [:])
        undoStack.append(state)
        state = next
    }
    
    // MARK: - Perception
    
    /// Triggers analysis of the current frame (e.g., on Pause).
    /// Updates `state.visualContext`.
    public func analyzeFrame(pixelBuffer: CVPixelBuffer, time: TimeInterval) async {
        let now = Date().timeIntervalSince1970
        if (now - lastAnalysisWallClock) < minAnalysisInterval {
            return
        }
        lastAnalysisWallClock = now
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

        let parsed = intentParser.parse(response: textToParse)
        await trace.record(
            "intent.process.end",
            fields: [
                "hasIntent": parsed == nil ? "false" : "true",
                "rawWasJSON": response.intentJSON == nil ? "false" : "true"
            ]
        )
        return parsed
    }

    /// Processes a natural language command and applies it (intent -> typed commands -> timeline mutation).
    public func processAndApplyCommand(_ text: String) async throws -> UserIntent? {
        let intent = try await processCommand(text)
        if let intent {
            await applyIntent(intent)
        }
        return intent
    }

    public func applyIntent(_ intent: UserIntent) async {
        await trace.record(
            "intent.apply.begin",
            fields: [
                "action": intent.action.rawValue,
                "target": intent.target
            ]
        )

        let commands = IntentCommandRegistry.commands(for: intent)
        await trace.record("intent.commands.built", fields: ["count": String(commands.count)])

        var timeline = state.timeline
        let executor = CommandExecutor(trace: trace)
        await executor.execute(commands, in: &timeline)
        state.timeline = timeline

        await trace.record("intent.apply.end", fields: ["count": String(commands.count)])
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

        return QualityPolicyBundle(export: export, qc: qc, ai: nil, aiUsage: .localOnlyDefault, privacy: PrivacyPolicy())
    }

    public func exportMovie(
        using exporter: any VideoExporting,
        to outputURL: URL,
        quality: QualityProfile,
        frameRate: Int32 = 24,
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
        frameRate: Int32 = 24,
        codec: AVVideoCodecType = .hevc,
        audioPolicy: AudioPolicy = .auto,
        sidecars: [DeliverableSidecarRequest] = []
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
            let report = try await VideoQC.validateMovie(at: movieURL, policy: policyBundle.qc)
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

            let minDistance = 0.020
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

            // Deterministic content metrics (histogram-derived luma stats). We keep expectations fully permissive
            // so this never fails export; the goal is to record measured metrics in the manifest.
            let colorStatsSamples: [VideoContentQC.ColorStatsSample] = samples.map {
                .init(
                    timeSeconds: $0.timeSeconds,
                    label: $0.label,
                    minMeanLuma: 0,
                    maxMeanLuma: 1,
                    maxChannelDelta: 1,
                    minLowLumaFraction: 0,
                    minHighLumaFraction: 0
                )
            }

            let colorStatsResults = try await VideoContentQC.validateColorStats(
                movieURL: movieURL,
                samples: colorStatsSamples,
                maxDimension: 256
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
            let enforceTemporalVariety = videoClipCount >= 2
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
                        try await CaptionSidecarWriter.writeWebVTT(to: url)
                        writtenSidecars.append(DeliverableSidecar(kind: .captionsVTT, fileName: fileName))

                    case .captionsSRT(let fileName, _):
                        let url = stagingDir.appendingPathComponent(fileName)
                        try await CaptionSidecarWriter.writeSRT(to: url)
                        writtenSidecars.append(DeliverableSidecar(kind: .captionsSRT, fileName: fileName))

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
                    // Treat empty sidecars as a failure. Required requests already threw on write;
                    // for optional, record and continue.
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
                frameRate: frameRate,
                codec: codec.rawValue,
                audioPolicy: audioPolicy,
                governance: policyBundle.export,
                qcPolicy: policyBundle.qc,
                qcReport: qcReport,
                qcContentReport: qcContentReport,
                qcMetadataReport: qcMetadataReport,
                qcSidecarReport: qcSidecarReport,
                sidecars: writtenSidecars
            )
        }
    }
}

private extension DeliverableSidecarRequest {
    var sidecar: DeliverableSidecar {
        switch self {
        case .captionsVTT(let fileName, _):
            return DeliverableSidecar(kind: .captionsVTT, fileName: fileName)
        case .captionsSRT(let fileName, _):
            return DeliverableSidecar(kind: .captionsSRT, fileName: fileName)
        case .thumbnailJPEG(let fileName, _):
            return DeliverableSidecar(kind: .thumbnailJPEG, fileName: fileName)
        case .contactSheetJPEG(let fileName, _, _, _):
            return DeliverableSidecar(kind: .contactSheetJPEG, fileName: fileName)
        }
    }
}

