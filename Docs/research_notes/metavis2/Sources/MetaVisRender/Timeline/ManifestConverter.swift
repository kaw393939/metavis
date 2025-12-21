// ManifestConverter.swift
// MetaVisRender
//
// Converts legacy RenderManifest to unified TimelineModel format
// Provides backward compatibility for existing render manifests

import Foundation

/// Converts legacy RenderManifest format to unified TimelineModel.
public struct ManifestConverter {
    
    /// Converts a RenderManifest to a TimelineModel.
    ///
    /// This creates a timeline with:
    /// - Single video track (if source video exists)
    /// - Single graphics track (if elements exist)
    /// - Scene, camera, and compositing settings preserved
    ///
    /// ## Example
    /// ```swift
    /// let renderManifest = try decoder.decode(RenderManifest.self, from: data)
    /// let timeline = ManifestConverter.convert(renderManifest)
    /// ```
    public static func convert(_ manifest: RenderManifest) -> TimelineModel {
        var timeline = TimelineModel(
            fps: manifest.metadata.fps,
            resolution: manifest.metadata.resolution,
            scene: manifest.scene,
            camera: manifest.camera,
            compositing: manifest.compositing
        )
        
        // Handle layer-based manifest
        if manifest.usesLayers, let layers = manifest.layers {
            convertLayers(layers, to: &timeline, metadata: manifest.metadata)
            // Set explicit duration for virtual content (procedural/graphics without video)
            if timeline.videoTracks.isEmpty && timeline.hasVirtualContent {
                timeline.explicitDuration = manifest.metadata.duration
            }
            return timeline
        }
        
        // Convert source video to clip on video track
        if let source = manifest.source {
            timeline.registerSource(
                id: "main_source",
                path: source.path,
                duration: nil,
                colorSpace: source.colorSpace
            )
            
            _ = timeline.addVideoTrack(name: "Main Video")
            
            // Calculate clip timing
            let sourceIn = source.trim?.inPoint ?? 0.0
            let sourceOut = source.trim?.outPoint ?? manifest.metadata.duration
            
            let clip = ClipDefinition(
                source: "main_source",
                sourceIn: sourceIn,
                sourceOut: sourceOut,
                timelineIn: 0.0,
                speed: Double(source.speed),
                volume: source.audioTrack == .mute ? 0.0 : 1.0,
                frameBlending: source.frameBlending
            )
            
            timeline.videoTracks[0].clips.append(clip)
        }
        
        // Convert elements to graphics track
        if let elements = manifest.elements, !elements.isEmpty {
            var graphicsElements: [GraphicsElement] = []
            
            for element in elements {
                switch element {
                case .text(let textElement):
                    graphicsElements.append(.text(textElement))
                    
                case .model(let modelElement):
                    graphicsElements.append(.model(modelElement))
                }
            }
            
            let graphicsTrack = GraphicsTrack(
                name: "Graphics",
                elements: graphicsElements
            )
            
            timeline.graphicsTracks.append(graphicsTrack)
        }
        
        // Fix: Ensure scene background color is preserved if no procedural background is set
        if timeline.scene?.proceduralBackground == nil {
            // If the manifest has a hex background color, convert it to a solid procedural background
            // This ensures StandardPipeline renders the background color
            if let hexColor = timeline.scene?.background, hexColor != "transparent" {
                // Simple hex parser (assuming #RRGGBB or #RRGGBBAA)
                // For now, just create a solid background definition
                // In a real implementation, we'd parse the hex string to RGB values
                // But since BackgroundDefinition.solid takes RGB values, we need to parse it.
                
                // Quick hack: If it's a known color or we can parse it simply
                // For now, let's just default to black if we can't parse, or rely on the hex string if we add support later.
                // Actually, let's try to parse it.
                
                if let color = parseHexColor(hexColor) {
                    let solidBg = BackgroundDefinition.solid(SolidBackground(color: color))
                    var newScene = timeline.scene ?? SceneDefinition()
                    newScene = SceneDefinition(
                        background: newScene.background,
                        ambientLight: newScene.ambientLight,
                        proceduralBackground: solidBg
                    )
                    timeline.scene = newScene
                }
            }
        }
        
        // Set explicit duration for virtual content (procedural/graphics without video)
        if timeline.videoTracks.isEmpty && timeline.hasVirtualContent {
            timeline.explicitDuration = manifest.metadata.duration
        }
        
        return timeline
    }
    
    /// Converts layer-based RenderManifest to TimelineModel.
    private static func convertLayers(_ layers: [Layer], to timeline: inout TimelineModel, metadata: ManifestMetadata) {
        print("ManifestConverter: convertLayers called with \(layers.count) layers")
        for layer in layers {
            let base = layer.baseProperties
            
            // Skip disabled layers
            guard base.enabled else { continue }
            
            switch layer {
            case .video(let videoLayer):
                // Generate source ID from layer name
                let sourceId = "source_" + base.name.replacingOccurrences(of: " ", with: "_")
                
                // Register source
                timeline.registerSource(
                    id: sourceId,
                    path: videoLayer.source.path,
                    duration: nil
                )
                
                // Create video track if needed
                if timeline.videoTracks.isEmpty {
                    _ = timeline.addVideoTrack(name: base.name)
                }
                
                // Add clip
                let clip = ClipDefinition(
                    source: sourceId,
                    sourceIn: 0.0,
                    sourceOut: Double(base.duration),
                    timelineIn: Double(base.startTime),
                    speed: 1.0,
                    volume: 1.0,
                    frameBlending: false
                )
                timeline.videoTracks[0].clips.append(clip)
                
            case .graphics(let graphicsLayer):
                // Convert graphics elements
                var graphicsElements: [GraphicsElement] = []
                for element in graphicsLayer.elements {
                    switch element {
                    case .text(let textElement):
                        var adjusted = textElement
                        adjusted.startTime += Float(base.startTime)
                        print("ManifestConverter: Adjusted text element start time from \(textElement.startTime) to \(adjusted.startTime) (Layer start: \(base.startTime))")
                        graphicsElements.append(.text(adjusted))
                    case .model(let modelElement):
                        var adjusted = modelElement
                        adjusted.startTime += Float(base.startTime)
                        graphicsElements.append(.model(adjusted))
                    }
                }
                
                let graphicsTrack = GraphicsTrack(
                    name: base.name,
                    elements: graphicsElements
                )
                timeline.graphicsTracks.append(graphicsTrack)
                
            case .procedural(let proceduralLayer):
                // Set procedural background in scene
                if var scene = timeline.scene {
                    scene = SceneDefinition(
                        background: scene.background,
                        ambientLight: scene.ambientLight,
                        proceduralBackground: proceduralLayer.background
                    )
                    timeline.scene = scene
                } else {
                    // Create new scene with procedural background
                    timeline.scene = SceneDefinition(
                        background: "#000000",
                        ambientLight: 1.0,
                        proceduralBackground: proceduralLayer.background
                    )
                }
                
            case .solid, .adjustment:
                // Not yet supported in TimelineModel
                print("Warning: \(layer) layer type not yet supported in TimelineModel conversion")
            }
        }
    }
    
    /// Detects if JSON data is a legacy RenderManifest format.
    ///
    /// Checks for presence of RenderManifest-specific keys:
    /// - Has "elements" OR "layers" key (RenderManifest)
    /// - Does NOT have "videoTracks" key (TimelineModel)
    public static func isLegacyManifest(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("isLegacyManifest: Failed to parse JSON")
            return false
        }
        
        // RenderManifest has "elements" or "layers" or "source" but NOT "videoTracks"
        let hasElements = json["elements"] != nil
        let hasLayers = json["layers"] != nil
        let hasSource = json["source"] != nil
        let hasVideoTracks = json["videoTracks"] != nil
        
        print("isLegacyManifest: hasElements=\(hasElements), hasLayers=\(hasLayers), hasSource=\(hasSource), hasVideoTracks=\(hasVideoTracks)")
        let result = (hasElements || hasLayers || hasSource) && !hasVideoTracks
        print("isLegacyManifest: returning \(result)")
        return result
    }
    
    /// Loads a manifest from JSON data, auto-converting if legacy format.
    ///
    /// This is the recommended way to load manifests as it handles both
    /// legacy RenderManifest and modern TimelineModel formats transparently.
    ///
    /// ## Example
    /// ```swift
    /// let data = try Data(contentsOf: manifestURL)
    /// let timeline = try ManifestConverter.load(from: data)
    /// ```
    public static func load(from data: Data) throws -> TimelineModel {
        let decoder = JSONDecoder()
        
        // Check if legacy format
        let isLegacy = isLegacyManifest(data)
        print("ManifestConverter: isLegacyManifest = \(isLegacy)")
        
        if isLegacy {
            // Convert from RenderManifest
            print("ManifestConverter: Decoding as RenderManifest...")
            do {
                let renderManifest = try decoder.decode(RenderManifest.self, from: data)
                print("ManifestConverter: RenderManifest decoded successfully")
                print("ManifestConverter: Converting to TimelineModel...")
                let timeline = convert(renderManifest)
                print("ManifestConverter: Conversion complete")
                return timeline
            } catch {
                print("ManifestConverter: Failed to decode RenderManifest: \(error)")
                throw error
            }
        } else {
            // Load as TimelineModel directly
            print("ManifestConverter: Decoding as TimelineModel...")
            return try decoder.decode(TimelineModel.self, from: data)
        }
    }
    
    private static func parseHexColor(_ hex: String) -> SIMD3<Float>? {
        var cString: String = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if (cString.hasPrefix("#")) {
            cString.remove(at: cString.startIndex)
        }

        if ((cString.count) != 6) {
            return nil
        }

        var rgbValue: UInt64 = 0
        Scanner(string: cString).scanHexInt64(&rgbValue)

        return SIMD3<Float>(
            Float((rgbValue & 0xFF0000) >> 16) / 255.0,
            Float((rgbValue & 0x00FF00) >> 8) / 255.0,
            Float(rgbValue & 0x0000FF) / 255.0
        )
    }
}
