import Foundation
import MetaVisCore
import MetaVisTimeline
import MetaVisSimulation

public enum ExportPreflightError: Error, Sendable, Equatable {
    case unknownFeature(id: String)
    case unsupportedEffectInputPort(featureID: String, port: String)
}

public enum ExportPreflight {
    public static func validateTimelineFeatureIDs(
        _ timeline: Timeline,
        trace: any TraceSink = NoOpTraceSink()
    ) async throws {
        await trace.record("export.preflight.begin", fields: [:])

        // Ensure registry has both built-ins and bundle manifests.
        try await FeatureRegistryBootstrap.shared.ensureStandardFeaturesRegistered(trace: trace)

        for track in timeline.tracks {
            for clip in track.clips {
                for fx in clip.effects {
                    guard let manifest = await FeatureRegistry.shared.feature(for: fx.id) else {
                        await trace.record("export.preflight.unknown_feature", fields: ["id": fx.id])
                        throw ExportPreflightError.unknownFeature(id: fx.id)
                    }

                    if track.kind == .video {
                        if manifest.domain != .video {
                            await trace.record(
                                "export.preflight.non_video_effect_on_video_track",
                                fields: ["id": manifest.id, "domain": manifest.domain.rawValue]
                            )
                        } else {
                            // Allow known multi-input video effects.
                            // TimelineCompiler/MetalSimulationEngine support a small set of secondary inputs
                            // (e.g. `faceMask` for face enhance).
                            let allowedPorts: Set<String> = ["source", "input", "faceMask", "mask"]
                            for port in manifest.inputs where !allowedPorts.contains(port.name) {
                                await trace.record(
                                    "export.preflight.unsupported_effect_input_port",
                                    fields: ["id": manifest.id, "port": port.name]
                                )
                                throw ExportPreflightError.unsupportedEffectInputPort(featureID: manifest.id, port: port.name)
                            }
                        }
                    }
                }
            }
        }

        await trace.record("export.preflight.end", fields: [:])
    }
}
