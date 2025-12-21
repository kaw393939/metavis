import simd

/// Errors that can occur during action generation
public enum ActionGeneratorError: Error {
    case nodeNotFound(String)
    case invalidPath(String)
    case invalidParameter(String)
}

/// Generates camera animation keyframes from high-level actions
public struct CameraActionGenerator: Sendable {
    public init() {}

    /// Generate camera keyframes for an action
    public func generateKeyframes(
        for action: AnimationAction,
        startTime: Double,
        currentCamera: CameraState,
        nodePositions: [String: SIMD3<Float>] = [:]
    ) throws -> [Keyframe<CameraState>] {
        // Route to specific generator based on action type
        switch action {
        case let action as FocusAction:
            return try generateFocusKeyframes(
                action: action,
                startTime: startTime,
                currentCamera: currentCamera,
                nodePositions: nodePositions
            )

        case let action as ZoomAction:
            return generateZoomKeyframes(
                action: action,
                startTime: startTime,
                currentCamera: currentCamera
            )

        case let action as OrbitAction:
            return generateOrbitKeyframes(
                action: action,
                startTime: startTime,
                currentCamera: currentCamera
            )

        case let action as TraceAction:
            return try generateTraceKeyframes(
                action: action,
                startTime: startTime,
                currentCamera: currentCamera,
                nodePositions: nodePositions
            )

        case is RevealAction:
            // Reveal actions don't generate camera keyframes
            // They're handled by GraphAnimationTrack
            return []

        case is HighlightAction:
            // Highlight actions don't generate camera keyframes
            return []

        case let action as CompareAction:
            return try generateCompareKeyframes(
                action: action,
                startTime: startTime,
                currentCamera: currentCamera,
                nodePositions: nodePositions
            )

        default:
            return []
        }
    }

    // MARK: - Focus Action

    private func generateFocusKeyframes(
        action: FocusAction,
        startTime: Double,
        currentCamera: CameraState,
        nodePositions: [String: SIMD3<Float>]
    ) throws -> [Keyframe<CameraState>] {
        guard let targetPosition = nodePositions[action.nodeId] else {
            throw ActionGeneratorError.nodeNotFound(action.nodeId)
        }

        // Calculate camera position: move along view direction to be 'distance' from target
        let viewDirection = normalize(currentCamera.lookAt - currentCamera.position)
        let newPosition = targetPosition - viewDirection * action.distance

        let finalCamera = CameraState(
            position: newPosition,
            lookAt: targetPosition,
            up: currentCamera.up,
            fov: currentCamera.fov,
            roll: currentCamera.roll
        )

        return [
            Keyframe(time: startTime, value: currentCamera, easing: .linear),
            Keyframe(time: startTime + action.duration, value: finalCamera, easing: action.easing)
        ]
    }

    // MARK: - Zoom Action

    private func generateZoomKeyframes(
        action: ZoomAction,
        startTime: Double,
        currentCamera: CameraState
    ) -> [Keyframe<CameraState>] {
        // Calculate new position by scaling distance from lookAt
        let direction = currentCamera.position - currentCamera.lookAt
        let currentDistance = length(direction)
        let newDistance = currentDistance * action.factor
        let newPosition = currentCamera.lookAt + normalize(direction) * newDistance

        let finalCamera = CameraState(
            position: newPosition,
            lookAt: currentCamera.lookAt,
            up: currentCamera.up,
            fov: currentCamera.fov,
            roll: currentCamera.roll
        )

        return [
            Keyframe(time: startTime, value: currentCamera, easing: .linear),
            Keyframe(time: startTime + action.duration, value: finalCamera, easing: action.easing)
        ]
    }

    // MARK: - Orbit Action

    private func generateOrbitKeyframes(
        action: OrbitAction,
        startTime: Double,
        currentCamera: CameraState
    ) -> [Keyframe<CameraState>] {
        // Rotate position around lookAt point
        let offset = currentCamera.position - currentCamera.lookAt
        let angleRadians = action.angle * .pi / 180.0

        // Create rotation matrix around axis
        let rotationMatrix = matrix4x4_rotation(
            radians: Float(angleRadians),
            axis: normalize(action.axis)
        )

        // Apply rotation to offset
        let rotatedOffset = (rotationMatrix * SIMD4<Float>(offset, 0.0)).xyz
        let newPosition = currentCamera.lookAt + rotatedOffset

        let finalCamera = CameraState(
            position: newPosition,
            lookAt: currentCamera.lookAt,
            up: currentCamera.up,
            fov: currentCamera.fov,
            roll: currentCamera.roll
        )

        return [
            Keyframe(time: startTime, value: currentCamera, easing: .linear),
            Keyframe(time: startTime + action.duration, value: finalCamera, easing: action.easing)
        ]
    }

    // MARK: - Trace Action

    private func generateTraceKeyframes(
        action: TraceAction,
        startTime: Double,
        currentCamera: CameraState,
        nodePositions: [String: SIMD3<Float>]
    ) throws -> [Keyframe<CameraState>] {
        guard !action.edgePath.isEmpty else {
            throw ActionGeneratorError.invalidPath("Edge path is empty")
        }

        // Verify all nodes exist
        for nodeId in action.edgePath {
            guard nodePositions[nodeId] != nil else {
                throw ActionGeneratorError.nodeNotFound(nodeId)
            }
        }

        // Generate keyframe for each node
        var keyframes: [Keyframe<CameraState>] = []
        let segmentDuration = action.duration / Double(action.edgePath.count)

        // Add initial state
        keyframes.append(Keyframe(time: startTime, value: currentCamera, easing: .linear))

        // Calculate camera offset (maintain consistent viewing distance)
        let viewDirection = normalize(currentCamera.lookAt - currentCamera.position)
        let distance = length(currentCamera.lookAt - currentCamera.position)

        // Add keyframe for each node
        for (index, nodeId) in action.edgePath.enumerated() {
            let position = nodePositions[nodeId]!
            let time = startTime + Double(index + 1) * segmentDuration

            let cameraPosition = position - viewDirection * distance
            let camera = CameraState(
                position: cameraPosition,
                lookAt: position,
                up: currentCamera.up,
                fov: currentCamera.fov,
                roll: currentCamera.roll
            )

            keyframes.append(Keyframe(time: time, value: camera, easing: action.easing))
        }

        return keyframes
    }

    // MARK: - Compare Action

    private func generateCompareKeyframes(
        action: CompareAction,
        startTime: Double,
        currentCamera: CameraState,
        nodePositions: [String: SIMD3<Float>]
    ) throws -> [Keyframe<CameraState>] {
        guard action.nodeIds.count >= 2 else {
            throw ActionGeneratorError.invalidParameter("Compare requires at least 2 nodes")
        }

        // Verify nodes exist
        for nodeId in action.nodeIds {
            guard nodePositions[nodeId] != nil else {
                throw ActionGeneratorError.nodeNotFound(nodeId)
            }
        }

        // Calculate center point between nodes
        let positions = action.nodeIds.compactMap { nodePositions[$0] }
        let center = positions.reduce(SIMD3<Float>.zero, +) / Float(positions.count)

        // Calculate bounding sphere radius
        let maxDistance = positions.map { length($0 - center) }.max() ?? 1.0

        // Position camera to view all nodes
        let viewDirection = normalize(currentCamera.lookAt - currentCamera.position)
        let distance = maxDistance * 2.5 // Give some margin
        let newPosition = center - viewDirection * distance

        let finalCamera = CameraState(
            position: newPosition,
            lookAt: center,
            up: currentCamera.up,
            fov: currentCamera.fov,
            roll: currentCamera.roll
        )

        return [
            Keyframe(time: startTime, value: currentCamera, easing: .linear),
            Keyframe(time: startTime + action.duration, value: finalCamera, easing: action.easing)
        ]
    }
}

// MARK: - Matrix Helper

private func matrix4x4_rotation(radians: Float, axis: SIMD3<Float>) -> simd_float4x4 {
    let c = cos(radians)
    let s = sin(radians)
    let t = 1 - c

    let x = axis.x
    let y = axis.y
    let z = axis.z

    return simd_float4x4(
        SIMD4<Float>(t * x * x + c, t * x * y + z * s, t * x * z - y * s, 0),
        SIMD4<Float>(t * x * y - z * s, t * y * y + c, t * y * z + x * s, 0),
        SIMD4<Float>(t * x * z + y * s, t * y * z - x * s, t * z * z + c, 0),
        SIMD4<Float>(0, 0, 0, 1)
    )
}

// Helper extension to access xyz from SIMD4
private extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> {
        SIMD3<Float>(x, y, z)
    }
}
