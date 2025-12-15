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
        quality: QualityProfile
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
        var clipNodes: [(node: RenderNode, alpha: Float)] = []
        
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
            let (fxNodes, fxOutputID) = try await compileEffects(for: clip, inputNodeID: idtNode.id)
            nodes.append(contentsOf: fxNodes)

            // Use the last real compiled node as the clip's output.
            if fxOutputID == idtNode.id {
                clipNodes.append((idtNode, alpha))
            } else if let real = (fxNodes.last { $0.id == fxOutputID } ?? fxNodes.last) {
                clipNodes.append((real, alpha))
            } else {
                // Defensive: if compiler returned an output ID but no nodes, fall back.
                clipNodes.append((idtNode, alpha))
            }
        }
        
        // 3. Composite clips together if multiple active
        let compositeRoot: RenderNode
        
        if clipNodes.count == 1 {
            // Single clip - no compositing needed
            compositeRoot = clipNodes[0].node
        } else if clipNodes.count == 2 {
            // Two clips - use optimized crossfade
            let (clip1, alpha1) = clipNodes[0]
            let (clip2, alpha2) = clipNodes[1]
            
            // Calculate crossfade mix based on alphas
            let totalAlpha = alpha1 + alpha2
            let mix = totalAlpha > 0 ? alpha2 / totalAlpha : 0.5
            
            let crossfadeNode = RenderNode(
                name: "Crossfade",
                shader: "compositor_crossfade",
                inputs: ["clipA": clip1.id, "clipB": clip2.id],
                parameters: ["mix": .float(Double(mix))]
            )
            nodes.append(crossfadeNode)
            compositeRoot = crossfadeNode
        } else {
            // 3+ clips - use general compositor (bottom to top)
            // For now, simplified: composite pairs sequentially
            var currentRoot = clipNodes[0].node
            
            for i in 1..<clipNodes.count {
                let (nextNode, nextAlpha) = clipNodes[i]
                let (_, currentAlpha) = clipNodes[i-1]
                
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

    private func compileEffects(for clip: Clip, inputNodeID: UUID) async throws -> (nodes: [RenderNode], outputNodeID: UUID) {
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

            // For clip-level effects we currently only support single-image input features.
            // The common convention is a `source` port.
            var externalInputs: [String: UUID] = [:]
            for port in manifest.inputs {
                if port.name == "source" {
                    externalInputs[port.name] = currentOutput
                } else {
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
                    parameters: ["time": .float(time.seconds)]
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
            let localTime = (time - clip.startTime) + clip.offset
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
}
