import Foundation
import Metal
import MetaVisCore
import MetaVisTimeline

/// The Conductor of the "Cinematic OS".
/// It binds the Session (Data), Timeline (Sequence), and Engine (Render) together.
/// It is responsible for the frame-by-frame execution loop.
public class SimulationOrchestrator {
    public let engine: SimulationEngine
    public let clock: MasterClock
    
    private let resolver: TimelineResolver
    public let graphBuilder: TimelineGraphBuilder
    private let compiler: GraphCompiler

    private var cachedSegments: [TimelineSegment] = []
    private var cachedTimelineSignature: Int = 0
    private var cachedSegmentId: UUID?
    private var cachedPass: RenderPass?
    
    /// The active session being played.
    public var session: MetaVisSession?
    
    public init(engine: SimulationEngine) {
        self.engine = engine
        self.clock = engine.clock
        self.resolver = TimelineResolver()
        self.graphBuilder = TimelineGraphBuilder()
        self.compiler = GraphCompiler(device: engine.device)
    }
    
    /// Renders the current frame based on the MasterClock time.
    /// - Parameter outputTexture: The texture to render into (usually the screen).
    public func render(to outputTexture: MTLTexture) async throws {
        guard let session = session else {
            // Render Black/Clear if no session
            return
        }
        
        let currentTime = await clock.currentTime
        let currentRationalTime = RationalTime(seconds: currentTime.seconds)
        
        // 1. Resolve Timeline (cached)
        // We avoid re-resolving and recompiling the graph if the active segment is unchanged.
        // For this to be safe, we key off timeline signature + active segment id.
        let timeline = session.activeTimeline
        var hasher = Hasher()
        hasher.combine(timeline.name)
        hasher.combine(timeline.tracks.count)
        for track in timeline.tracks {
            hasher.combine(track.name)
            hasher.combine(String(describing: track.type))
            hasher.combine(track.clips.count)
            for clip in track.clips {
                hasher.combine(clip.id)
                hasher.combine(clip.assetId)
                hasher.combine(clip.range.start.seconds)
                hasher.combine(clip.range.duration.seconds)
                hasher.combine(clip.sourceRange.start.seconds)
                hasher.combine(clip.sourceRange.duration.seconds)
                if let out = clip.outTransition {
                    hasher.combine(out.type)
                    hasher.combine(out.duration.seconds)
                } else {
                    hasher.combine(0)
                }
            }
        }
        let signature = hasher.finalize()

        let segments: [TimelineSegment]
        if signature == cachedTimelineSignature, !cachedSegments.isEmpty {
            segments = cachedSegments
        } else {
            let resolved = resolver.resolve(timeline: timeline)
            cachedSegments = resolved
            cachedTimelineSignature = signature
            cachedSegmentId = nil
            cachedPass = nil
            segments = resolved
        }
        
        // 2. Find Active Segment
        // We look for the segment that contains the current time.
        guard let activeSegment = segments.first(where: { $0.range.contains(currentRationalTime) }) else {
            // No content at this time.
            print("⚠️ No active segment found for time: \(currentRationalTime.seconds)s")
            return
        }
        
        // 3. Build + 4. Compile (cached per segment)
        let pass: RenderPass
        if cachedSegmentId == activeSegment.id, let cached = cachedPass {
            pass = cached
        } else {
            let graph = try await graphBuilder.build(from: activeSegment) { [weak self] assetId in
                guard let self = self else { return nil }
                return self.engine.assetManager.get(id: assetId)
            }
            pass = try compiler.compile(graph: graph)
            cachedSegmentId = activeSegment.id
            cachedPass = pass
        }
        
        // 5. Pre-Roll / Just-in-Time Asset Loading
        // Ensure all assets required for this frame are resident in memory.
        for command in pass.commands {
            switch command {
            case .loadTexture(_, let assetId, _, _, _):
                // Load Proxy for performance during playback
                engine.loadAsset(assetId: assetId, quality: .proxy)
                
            case .loadFITS(_, let assetId):
                engine.loadAsset(assetId: assetId, quality: .proxy)
                
            case .process:
                // If process nodes refer to other nodes, we don't need to load assets directly here,
                // as the inputs are usually previous render targets.
                break
                
            default:
                break
            }
        }
        
        // 6. Execute Render
        try await engine.render(pass: pass, outputTexture: outputTexture)
    }
}
