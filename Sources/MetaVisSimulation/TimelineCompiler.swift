import Foundation
import MetaVisCore
import MetaVisTimeline

/// Responsible for transforming a generic Timeline into an executable RenderGraph.
/// This acts as the "Compiler" ensures strict separation between Editing and Rendering.
public struct TimelineCompiler {
    
    public init() {}

    public enum Error: Swift.Error, Sendable, Equatable {
        case unknownFeature(id: String)
        case unsupportedEffectInputPort(featureID: String, port: String)
    }
    
    /// Compiles the timeline into a RenderRequest for a specific frame time.
    /// Handles multiple overlapping clips with transitions (crossfades, etc.)
    /// - Parameters:
    ///   - timeline: The source editing timeline.
    ///   - time: The target frame time.
    ///   - quality: The quality constraints to apply.
    /// - Returns: A self-contained RenderRequest.
    public func compile(
        timeline: Timeline,
        at time: Time,
        quality: QualityProfile,
        frameContext: RenderFrameContext? = nil
    ) async throws -> RenderRequest {

        // Ensure built-in features are available for timeline effects.
        try await FeatureRegistryBootstrap.shared.ensureStandardFeaturesRegistered()
        
        var nodes: [RenderNode] = []
        
        // 1. Find ALL active clips at this time (can overlap during transitions)
        var activeClips: [(clip: Clip, alpha: Float)] = []
        
        for track in timeline.tracks {
            // This compiler produces a video render graph; ignore non-video tracks.
            guard track.kind == .video else { continue }

            for clip in track.clips {
                let alpha = clip.alpha(at: time)
                if alpha > 0.0 {
                    activeClips.append((clip, alpha))
                }
            }
        }
        
        // Handle empty timeline
        guard !activeClips.isEmpty else {
            let emptyNode = RenderNode(name: "Empty", shader: "clear_color", parameters: [:])
            return RenderRequest(
                graph: RenderGraph(nodes: [emptyNode], rootNodeID: emptyNode.id),
                time: time,
                quality: quality
            )
        }
        
        // 2. Create source nodes for each active clip
        var clipNodes: [(clip: Clip, node: RenderNode, alpha: Float)] = []
        
        for (clip, alpha) in activeClips {
            let sourceNode = try createSourceNode(for: clip, at: time)
            nodes.append(sourceNode)

            // Enforce a consistent working space (ACEScg) by inserting an IDT before compositing.
            // This is part of the "golden thread" assumptions across the simulation pipeline.
            let isEXR: Bool = {
                if clip.asset.sourceFn.lowercased().hasSuffix(".exr") { return true }
                if let u = URL(string: clip.asset.sourceFn), u.pathExtension.lowercased() == "exr" { return true }
                return false
            }()
            let idtNode = RenderNode(
                name: "IDT_Input",
                shader: isEXR ? "idt_linear_rec709_to_acescg" : "idt_rec709_to_acescg",
                inputs: ["input": sourceNode.id]
            )
            nodes.append(idtNode)

            // Apply clip effects in working space (ACEScg) before compositing.
            let (fxNodes, fxOutputID) = try await compileEffects(for: clip, at: time, inputNodeID: idtNode.id, frameContext: frameContext)
            nodes.append(contentsOf: fxNodes)

            // Use the last real compiled node as the clip's output.
            if fxOutputID == idtNode.id {
                clipNodes.append((clip, idtNode, alpha))
            } else if let real = (fxNodes.last { $0.id == fxOutputID } ?? fxNodes.last) {
                clipNodes.append((clip, real, alpha))
            } else {
                // Defensive: if compiler returned an output ID but no nodes, fall back.
                clipNodes.append((clip, idtNode, alpha))
            }
        }
        
        // 3. Composite clips together if multiple active
        let compositeRoot: RenderNode
        
        if clipNodes.count == 1 {
            // Single clip - no compositing needed
            compositeRoot = clipNodes[0].node
        } else if clipNodes.count == 2 {
            // Two clips - use a transition-aware compositor.
            // Sort by startTime so clipA is the earlier clip and clipB is the later (incoming) clip.
            let sorted = clipNodes.sorted {
                if $0.clip.startTime == $1.clip.startTime { return $0.clip.id.uuidString < $1.clip.id.uuidString }
                return $0.clip.startTime < $1.clip.startTime
            }
            let a = sorted[0]
            let b = sorted[1]

            let progress: Float = transitionProgress(outgoing: a.clip, incoming: b.clip, at: time) ?? {
                // Fallback: infer mix from the alpha overlap.
                let totalAlpha = a.alpha + b.alpha
                return totalAlpha > 0 ? (b.alpha / totalAlpha) : 0.5
            }()

            let shader: String
            var params: [String: NodeValue] = ["progress": .float(Double(progress))]

            if let tIn = b.clip.transitionIn {
                switch tIn.type {
                case .wipe(let dir):
                    shader = "compositor_wipe"
                    params["direction"] = .float(Double(wipeDirectionIndex(dir)))
                case .dip(let color):
                    shader = "compositor_dip"
                    params["dipColor"] = .vector3(SIMD3<Double>(Double(color.x), Double(color.y), Double(color.z)))
                case .crossfade, .cut:
                    shader = "compositor_crossfade"
                    params = ["mix": .float(Double(progress))]
                }
            } else {
                // Default to crossfade when no transition type is present.
                shader = "compositor_crossfade"
                params = ["mix": .float(Double(progress))]
            }

            let node = RenderNode(
                name: "Transition",
                shader: shader,
                inputs: ["clipA": a.node.id, "clipB": b.node.id],
                parameters: params
            )
            nodes.append(node)
            compositeRoot = node
        } else {
            // 3+ clips - use general compositor (bottom to top)
            // For now, simplified: composite pairs sequentially
            var currentRoot = clipNodes[0].node
            
            for i in 1..<clipNodes.count {
                let (_, nextNode, nextAlpha) = clipNodes[i]
                let (_, _, currentAlpha) = clipNodes[i-1]
                
                let compNode = RenderNode(
                    name: "Composite_\(i)",
                    shader: "compositor_alpha_blend",
                    inputs: ["layer1": nextNode.id, "layer2": currentRoot.id],
                    parameters: [
                        "alpha1": .float(Double(nextAlpha)),
                        "alpha2": .float(Double(currentAlpha))
                    ]
                )
                nodes.append(compNode)
                currentRoot = compNode
            }
            compositeRoot = currentRoot
        }
        
        // 4. Apply ODT (ACEScg → Rec.709 + gamma)
        let odtNode = RenderNode(
            name: "ODT_Display",
            shader: "odt_acescg_to_rec709",
            inputs: ["input": compositeRoot.id]
        )
        nodes.append(odtNode)
        
        // 5. Assemble final graph
        let graph = RenderGraph(nodes: nodes, rootNodeID: odtNode.id)
        
        return RenderRequest(
            graph: graph,
            time: time,
            quality: quality
        )
    }
    
    // MARK: - Helper Methods

    private func compileEffects(for clip: Clip, at time: Time, inputNodeID: UUID, frameContext: RenderFrameContext?) async throws -> (nodes: [RenderNode], outputNodeID: UUID) {
        guard !clip.effects.isEmpty else {
            return ([], inputNodeID)
        }

        var compiledNodes: [RenderNode] = []
        var currentOutput = inputNodeID

        for effect in clip.effects {
            guard let manifest = await FeatureRegistry.shared.feature(for: effect.id) else {
                throw Error.unknownFeature(id: effect.id)
            }

            // Non-video domains are known/governable but do not compile to Metal nodes.
            // Keep them in the timeline, but ignore them in the render-graph compiler.
            guard manifest.domain == .video else {
                continue
            }

            // Clip-level effects can have multiple inputs (e.g. face enhance needs a face mask).
            // We supply conventional bindings here and create minimal generator nodes when required.
            var externalInputs: [String: UUID] = [:]

            // Primary input naming: support either `source` or `input`.
            for port in manifest.inputs {
                switch port.name {
                case "source", "input":
                    // Prefer `source` when requested; otherwise `input`.
                    externalInputs[port.name] = currentOutput

                case "faceMask":
                    let rects = frameContext?.faceRectsByClipID[clip.id] ?? []
                    // Pack as [Float] for NodeValue.floatArray.
                    var rectFloats: [Float] = []
                    rectFloats.reserveCapacity(rects.count * 4)
                    for r in rects {
                        rectFloats.append(r.x)
                        rectFloats.append(r.y)
                        rectFloats.append(r.z)
                        rectFloats.append(r.w)
                    }

                    let maskNode = RenderNode(
                        name: "FaceMask",
                        shader: "fx_generate_face_mask",
                        parameters: ["faceRects": .floatArray(rectFloats)]
                    )
                    compiledNodes.append(maskNode)
                    externalInputs[port.name] = maskNode.id

                default:
                    throw Error.unsupportedEffectInputPort(featureID: manifest.id, port: port.name)
                }
            }

            let (nodes, rootID) = try await manifest.compileNodes(
                externalInputs: externalInputs,
                parameterOverrides: effect.parameters
            )

            compiledNodes.append(contentsOf: nodes)
            currentOutput = rootID
        }

        return (compiledNodes, currentOutput)
    }
    
    /// Creates a source render node for a clip
    private func createSourceNode(for clip: Clip, at time: Time) throws -> RenderNode {
        let sourceNode: RenderNode

        // Clip-local time is required for correct editing semantics (move/trim/slip/retime).
        // Even procedural generators should use the clip-local time so that they can be edited.
        let baseLocalTime = (time - clip.startTime) + clip.offset
        let localTime: Time = {
            guard let factor = retimeFactor(for: clip) else { return baseLocalTime }
            // Retime semantics: map timeline-local time to source-local time.
            // factor > 1.0 => faster playback (source time advances more per timeline second).
            return Time(seconds: baseLocalTime.seconds * factor)
        }()
        
        if clip.asset.sourceFn.hasPrefix("ligm://") {
            // Procedural generation
            let url = URL(string: clip.asset.sourceFn)
            // Note: For URLs like `ligm://fx_macbeth`, the identifier is in `host`, not `path`.
            let host = url?.host ?? ""
            let path = url?.path ?? ""
            let id = (host + path).lowercased()
            
            if id.contains("source_test_color") || id.contains("test_color") {
                sourceNode = RenderNode(
                    name: "TestColor_\(clip.id.uuidString)",
                    shader: "source_test_color",
                    parameters: [:]
                )
            } else if id.contains("linear_ramp") || id.contains("linearramp") {
                sourceNode = RenderNode(
                    name: "LinearRamp_\(clip.id.uuidString)",
                    shader: "source_linear_ramp",
                    parameters: [:]
                )
            } else if id.contains("macbeth") {
                sourceNode = RenderNode(
                    name: "Macbeth_\(clip.id.uuidString)",
                    shader: "fx_macbeth",
                    parameters: [:]
                )
            } else if id.contains("zone_plate") || id.contains("zoneplate") {
                sourceNode = RenderNode(
                    name: "ZonePlate_\(clip.id.uuidString)",
                    shader: "fx_zone_plate",
                    parameters: ["time": .float(localTime.seconds)]
                )
            } else if id.contains("smpte") {
                sourceNode = RenderNode(
                    name: "SMPTE_\(clip.id.uuidString)",
                    shader: "fx_smpte_bars",
                    parameters: [:]
                )
            } else {
                // Fallback to SMPTE
                sourceNode = RenderNode(
                    name: "LIGM_Fallback_\(clip.id.uuidString)",
                    shader: "fx_smpte_bars",
                    parameters: [:]
                )
            }
        } else {
            // Video file - would need IDT in full implementation
            sourceNode = RenderNode(
                name: "Clip_\(clip.id.uuidString)",
                shader: "source_texture",
                parameters: [
                    "asset_id": .string(clip.asset.sourceFn),
                    "time_seconds": .float(localTime.seconds)
                ]
            )
        }
        
        return sourceNode
    }

    private func retimeFactor(for clip: Clip) -> Double? {
        guard let app = clip.effects.first(where: { $0.id == "mv.retime" }) else { return nil }
        guard let raw = app.parameters["factor"] else { return nil }
        let factor: Double?
        switch raw {
        case .float(let v):
            factor = v
        case .string(let s):
            factor = Double(s)
        default:
            factor = nil
        }
        guard let f = factor, f.isFinite, f > 0 else { return nil }
        return f
    }

    private func transitionProgress(outgoing: Clip, incoming: Clip, at time: Time) -> Float? {
        // Prefer incoming transition (progress is naturally 0->1).
        if let tIn = incoming.transitionIn, tIn.duration.seconds > 0 {
            let start = incoming.startTime
            let end = incoming.startTime + tIn.duration
            if time >= start && time <= end {
                let raw = Float((time - start).seconds / tIn.duration.seconds)
                return clamp01(tIn.easing.apply(raw))
            }
        }

        // Fall back to outgoing transition, derived from alpha.
        if let tOut = outgoing.transitionOut, tOut.duration.seconds > 0 {
            let start = outgoing.endTime - tOut.duration
            let end = outgoing.endTime
            if time >= start && time <= end {
                let raw = Float((outgoing.endTime - time).seconds / tOut.duration.seconds) // 1->0
                let alpha = tOut.easing.apply(clamp01(raw))
                return clamp01(1.0 - alpha)
            }
        }
        return nil
    }

    private func wipeDirectionIndex(_ d: TransitionType.WipeDirection) -> Int {
        switch d {
        case .leftToRight: return 0
        case .rightToLeft: return 1
        case .topToBottom: return 2
        case .bottomToTop: return 3
        }
    }

    private func clamp01(_ v: Float) -> Float { min(1.0, max(0.0, v)) }
}
