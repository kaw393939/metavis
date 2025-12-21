import Foundation

/// Builds complete animation timeline from narration configuration
public struct TimelineBuilder: Sendable {
    public init() {}

    /// Build complete timeline with camera and graph tracks from narration config
    public func buildTimeline(
        from config: AnimationConfig,
        nodePositions: [String: SIMD3<Float>]
    ) throws -> AnimatedTimeline {
        // Analyze narration to get segment timing
        let analyzer = NarrationAnalyzer()
        let segments = analyzer.calculateSegmentTimes(config.narration)

        // Calculate total duration
        let totalDuration = segments.last.map { $0.startTime + $0.duration } ?? 0.0

        // Generate camera keyframes from all actions
        let cameraGenerator = CameraActionGenerator()
        var allCameraKeyframes: [Keyframe<CameraState>] = []

        // Start with initial camera position
        let initialCamera = CameraState(
            position: SIMD3<Float>(0, 10, 20),
            lookAt: SIMD3<Float>(0, 0, 0),
            up: SIMD3<Float>(0, 1, 0),
            fov: 60.0,
            roll: 0.0
        )
        allCameraKeyframes.append(Keyframe(time: 0.0, value: initialCamera, easing: .linear))

        var currentCamera = initialCamera
        var currentTime = 0.0

        // Process each segment's actions
        for (segment, _, _) in segments {
            for action in segment.actions {
                let unwrappedAction: AnimationAction

                switch action {
                case let .focus(focusAction):
                    unwrappedAction = focusAction
                case let .zoom(zoomAction):
                    unwrappedAction = zoomAction
                case let .orbit(orbitAction):
                    unwrappedAction = orbitAction
                case let .trace(traceAction):
                    unwrappedAction = traceAction
                case let .reveal(revealAction):
                    unwrappedAction = revealAction
                case let .highlight(highlightAction):
                    unwrappedAction = highlightAction
                case let .compare(compareAction):
                    unwrappedAction = compareAction
                }

                let keyframes = try cameraGenerator.generateKeyframes(
                    for: unwrappedAction,
                    startTime: currentTime,
                    currentCamera: currentCamera,
                    nodePositions: nodePositions
                )

                if !keyframes.isEmpty {
                    allCameraKeyframes.append(contentsOf: keyframes)
                    currentCamera = keyframes.last!.value
                    currentTime += unwrappedAction.duration
                }
            }
        }

        // Create camera track
        let cameraTrack = CameraAnimationTrack(keyframes: allCameraKeyframes)

        // Create graph track from reveal/highlight/trace actions
        var graphKeyframes: [Keyframe<GraphState>] = []
        let currentGraphState = GraphState.zero
        graphKeyframes.append(Keyframe(time: 0.0, value: currentGraphState, easing: .linear))

        currentTime = 0.0
        for (segment, _, _) in segments {
            for action in segment.actions {
                switch action {
                case let .reveal(revealAction):
                    // Add reveal keyframes
                    let revealTrack = GraphAnimationTrack.reveal(
                        nodeIds: revealAction.nodeIds,
                        startTime: currentTime,
                        duration: revealAction.duration,
                        staggerDelay: revealAction.staggerDelay,
                        easing: revealAction.easing
                    )
                    graphKeyframes.append(contentsOf: revealTrack.keyframes)
                    currentTime += revealAction.duration

                case let .highlight(highlightAction):
                    let highlightTrack = GraphAnimationTrack.highlight(
                        nodeIds: highlightAction.nodeIds,
                        startTime: currentTime,
                        duration: highlightAction.duration,
                        intensity: highlightAction.intensity,
                        easing: highlightAction.easing
                    )
                    graphKeyframes.append(contentsOf: highlightTrack.keyframes)
                    currentTime += highlightAction.duration

                case let .trace(traceAction):
                    // Build edge IDs from node path
                    var edgeIds: [String] = []
                    for i in 0 ..< (traceAction.edgePath.count - 1) {
                        let edgeId = "\(traceAction.edgePath[i])-\(traceAction.edgePath[i + 1])"
                        edgeIds.append(edgeId)
                    }

                    let traceTrack = GraphAnimationTrack.trace(
                        edgeIds: edgeIds,
                        startTime: currentTime,
                        duration: traceAction.duration,
                        easing: traceAction.easing
                    )
                    graphKeyframes.append(contentsOf: traceTrack.keyframes)
                    currentTime += traceAction.duration

                default:
                    // Camera-only actions
                    if let action = action as? AnimationAction {
                        currentTime += action.duration
                    }
                }
            }
        }

        let graphTrack = GraphAnimationTrack(keyframes: graphKeyframes)

        // Create markers for narration segments
        var markers: [TimelineMarker] = []
        for (segment, startTime, duration) in segments {
            markers.append(TimelineMarker(
                time: startTime,
                label: String(segment.text.prefix(50)), // Truncate long text
                duration: duration
            ))
        }

        return AnimatedTimeline(
            duration: totalDuration,
            fps: 30,
            cameraTrack: cameraTrack,
            graphTrack: graphTrack,
            markers: markers
        )
    }
}

/// Complete animation timeline with all tracks
public struct AnimatedTimeline: Sendable {
    public let duration: Double
    public let fps: Int
    public let cameraTrack: CameraAnimationTrack
    public let graphTrack: GraphAnimationTrack
    public let markers: [TimelineMarker]

    public init(
        duration: Double,
        fps: Int,
        cameraTrack: CameraAnimationTrack,
        graphTrack: GraphAnimationTrack,
        markers: [TimelineMarker]
    ) {
        self.duration = duration
        self.fps = fps
        self.cameraTrack = cameraTrack
        self.graphTrack = graphTrack
        self.markers = markers
    }

    /// Get frame count
    public var frameCount: Int {
        Int(ceil(duration * Double(fps)))
    }

    /// Evaluate all tracks at a specific time
    public func evaluate(at time: Double) -> TimelineState {
        TimelineState(
            time: time,
            camera: cameraTrack.evaluate(at: time),
            graph: graphTrack.evaluate(at: time)
        )
    }
}

/// Timeline marker for narration segment
public struct TimelineMarker: Sendable {
    public let time: Double
    public let label: String
    public let duration: Double

    public init(time: Double, label: String, duration: Double) {
        self.time = time
        self.label = label
        self.duration = duration
    }
}

/// State at a specific point in time
public struct TimelineState: Sendable {
    public let time: Double
    public let camera: CameraState
    public let graph: GraphState

    public init(time: Double, camera: CameraState, graph: GraphState) {
        self.time = time
        self.camera = camera
        self.graph = graph
    }
}
