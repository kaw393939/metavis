import Metal
import MetalKit
import simd
import CoreText

public class ManifestResolver {
    
    public enum ResolutionPreset {
        case hd // 1920x1080
        case uhd // 3840x2160
        
        var size: (width: Int, height: Int) {
            switch self {
            case .hd: return (1920, 1080)
            case .uhd: return (3840, 2160)
            }
        }
    }
    
    public static func resolve(manifest: RenderManifest, device: MTLDevice) throws -> (RenderPipeline, Scene) {
        print("ManifestResolver: Resolving manifest with \(manifest.elements.count) elements") // DEBUG
        
        // Calculate Resolution (Shared logic with LabRunner)
        let is4K = manifest.metadata.intendedQualityProfile.lowercased().contains("4k")
        var renderWidth = is4K ? 3840 : 1920
        var renderHeight = is4K ? 2160 : 1080
        
        // Handle Aspect Ratio
        let aspectRatioStr = manifest.metadata.targetAspectRatio
        if aspectRatioStr == "9:16" {
            let temp = renderWidth
            renderWidth = renderHeight
            renderHeight = temp
        } else if aspectRatioStr.contains(":") {
            let parts = aspectRatioStr.split(separator: ":")
            if parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]), h > 0 {
                let ratio = w / h
                renderHeight = Int(Double(renderWidth) / ratio)
                if renderHeight % 2 != 0 { renderHeight += 1 }
            }
        }
        
        // 1. Create Scene
        let scene = Scene()
        
        // 2. Apply Scene Settings (Lighting & Atmosphere)
        applySceneDefinition(manifest.scene, to: scene)
        
        // 3. Apply Camera Settings (Initial State)
        scene.cameraKeyframes = manifest.camera.keyframes
        if let firstKeyframe = manifest.camera.keyframes.first {
            applyCameraKeyframe(firstKeyframe, to: &scene.camera)
        }
        
        // Apply Depth of Field Settings (V5.7)
        if let dof = manifest.postProcessing.depthOfField, dof.enabled {
            if let fStop = dof.apertureFstop {
                scene.camera.fStop = fStop
            }
            if let focusDist = dof.focalDistanceM {
                scene.camera.focusDistance = focusDist
            }
            // Apply Focus Zones (V5.8)
            if let zones = dof.focusZones {
                scene.focusZones = zones
            }
        }
        
        // 4. Parse Elements
        var timedTextEvents: [TimedTextEvent] = []
        var proceduralPasses: [ProceduralTexturePass] = []
        var volumetricNebulaPasses: [VolumetricNebulaPass] = []
        var resourceMap: [String: MTLTexture] = [:]
        
        for element in manifest.elements {
            print("ManifestResolver: Processing element type: '\(element.type)' id: '\(element.id)'") // DEBUG
            
            let start = element.activeTime?.first ?? element.animation?.start ?? 0.0
            let end = element.activeTime?.last ?? element.animation?.end ?? manifest.metadata.durationSeconds
            let duration = Double(end - start)
            
            if element.type == "text" || element.type == "credit_roll" {
                // Determine content based on type
                var textContent = element.content
                var layoutMode: String? = nil
                
                if element.type == "credit_roll", let items = element.lineItems {
                    // Format credit roll text
                    textContent = items.map { "\($0.role.uppercased())\n\($0.name)" }.joined(separator: "\n\n")
                    layoutMode = "credit_roll"
                }
                
                // Create VisualContent from Element
                let content = VisualContent(
                    type: "text",
                    text: textContent,
                    style: element.style,
                    layout: layoutMode,
                    animation: element.animation?.type,
                    zDepth: element.worldTransform?.position[2] ?? 0.0,
                    shape: nil,
                    size: element.scale.map { Double($0) },
                    color: element.color ?? element.textColor,
                    velocity: element.scrollSpeedNormalized.map { [0.0, Double($0)] },
                    outlineWidth: element.stylingProfile?.hasOutline == true ? 1.0 : nil,
                    outlineColor: nil,
                    softness: element.stylingProfile?.hasSoftGlow == true ? 0.5 : (element.softness.map { Double($0) }),
                    weight: nil,
                    maxWidth: nil,
                    anchor: element.screenAlignment?.anchor,
                    rotation: element.worldTransform?.rotationDegrees,
                    fadeStart: element.fadeStart,
                    fadeEnd: element.fadeEnd,
                    tracking: element.tracking
                )
                
                let timedEvent = TimedTextEvent(
                    content: content,
                    startTime: Double(start),
                    duration: duration,
                    animation: element.animation
                )
                timedTextEvents.append(timedEvent)
            } else if element.type == "particle_system" {
                // Create Particle System Mesh
                // For V5.2, we simulate the fire with a static mesh of random particles (triangles)
                // In a real engine, this would be a dynamic particle system
                
                var emissionRate: Float = 1000
                var colorHex = "#FFCC00" // Fire Color Default
                var isStars = false
                
                if let physics = element.particlePhysics {
                    if let presetName = physics.preset {
                        print("DEBUG: Found preset '\(presetName)'")
                        if presetName == "STARS" {
                            colorHex = "#FFFFFF"
                            isStars = true
                            emissionRate = 100 // Even sparser stars
                        }
                    } else {
                        emissionRate = physics.emissionRate
                    }
                }
                
                let count = Int(emissionRate)
                // let color = SIMD3<Float>(0.0, 1.0, 0.0) // DEBUG: Force GREEN stars
                let color = hexToSIMD3(colorHex)
                
                // Stars need tiny particles since they may be scaled up in manifest
                let particleSize: Float = isStars ? 0.03 : 0.1
                
                if let mesh = createParticleCloudMesh(device: device, count: Int(count), radius: 1.0, particleSize: particleSize) {
                    mesh.color = color
                    mesh.animation = element.animation
                    
                    // Fix Orientation: Rotate 180 degrees to face camera
                    var baseTransform = element.worldTransform
                    if var t = baseTransform {
                        var rot = t.rotationDegrees ?? [0, 0, 0]
                        rot[1] += 180.0
                        t.rotationDegrees = rot
                        baseTransform = t
                    }
                    mesh.baseTransform = baseTransform
                    
                    mesh.postProcessFX = element.postProcessFx
                    
                    // Use Soft Dot Texture
                    if isStars {
                        mesh.texture = createSoftDotTexture(device: device)
                        mesh.twinkleStrength = 0.5
                    } else {
                        mesh.texture = createSoftDotTexture(device: device)
                    }
                    mesh.isTransparent = true
                    
                    if let active = element.activeTime, active.count == 2 {
                        mesh.activeTime = (active[0], active[1])
                    }
                    
                    if let t = baseTransform {
                        mesh.transform = transformToMatrix(t)
                    }
                    scene.addMesh(mesh)
                    print("ManifestResolver: Created particle system '\(element.id)' with \(count) particles")
                }
                
            } else if element.type == "logo_element" {
                // Create Logo Mesh
                // We use a quad for the logo, colored white/glowing
                if let mesh = createQuadMesh(device: device, size: SIMD2<Float>(1.0, 1.0)) {
                    if let matDef = element.material {
                        mesh.material = resolveMaterial(matDef)
                        mesh.color = nil // Force PBR
                    } else {
                        let colorHex = element.material?.color ?? "#FFFFFF"
                        mesh.color = hexToSIMD3(colorHex)
                    }
                    
                    mesh.animation = element.animation
                    
                    // Fix Orientation: Rotate 180 degrees to face camera
                    var baseTransform = element.worldTransform
                    if var t = baseTransform {
                        // Fix Z-Fighting: Move Logo slightly forward
                        t.position[2] += 0.1
                        
                        var rot = t.rotationDegrees ?? [0, 0, 0]
                        rot[1] += 180.0
                        t.rotationDegrees = rot
                        baseTransform = t
                    }
                    mesh.baseTransform = baseTransform
                    
                    mesh.postProcessFX = element.postProcessFx
                    
                    // Generate Checkerboard Texture for Logo
                    mesh.texture = createCheckerboardTexture(device: device, colorA: SIMD3<Float>(1, 1, 1), colorB: SIMD3<Float>(0.8, 0.8, 0.8))
                    
                    if let active = element.activeTime, active.count == 2 {
                        mesh.activeTime = (active[0], active[1])
                    }
                    
                    if let t = baseTransform {
                        mesh.transform = transformToMatrix(t)
                    }
                    scene.addMesh(mesh)
                    print("ManifestResolver: Created logo element '\(element.id)'")
                }
                
            } else if element.type == "fractal_sphere" {
                // Create Sphere Mesh
                if let mesh = createSphereMesh(device: device, radius: 1.0, segments: 64, rings: 64) {
                    
                    // Create Procedural Texture Pass for the Fractal
                    let pass = ProceduralTexturePass()
                    pass.name = "\(element.id)_texture"
                    pass.proceduralType = .fbmPerlin // Changed from .julia to .fbmPerlin for safer nebula look
                    pass.resolution = SIMD2<Int>(512, 512) // Reduced from 1024 for performance
                    
                    // Configure Fractal
                    // Default Julia Set parameters for a nice look
                    pass.juliaC = SIMD2<Float>(-0.8, 0.156)
                    pass.zoom = 0.8
                    pass.fractalCenter = SIMD2<Float>(0, 0)
                    pass.maxIterations = 64 // Reduced iterations for performance
                    pass.smoothColoring = true
                    
                    // Configure Noise (FBM)
                    pass.frequency = 3.0 // Increased frequency for more detail
                    pass.octaves = 5
                    pass.lacunarity = 2.0
                    pass.gain = 0.5
                    pass.domainWarp = true
                    pass.warpStrength = 0.2 // Reduced from 0.5 to prevent rapid flashing
                    
                    // Gradient (Deep Blue Nebula look - Fixed White Blowout)
                    pass.gradientColors = [
                        ProceduralTexturePass.GradientStop(color: SIMD3(0.0, 0.0, 0.0), position: 0.0),
                        ProceduralTexturePass.GradientStop(color: SIMD3(0.0, 0.05, 0.1), position: 0.3), // Very Dark Blue
                        ProceduralTexturePass.GradientStop(color: SIMD3(0.0, 0.2, 0.5), position: 0.6), // Deep Blue
                        ProceduralTexturePass.GradientStop(color: SIMD3(0.0, 0.4, 0.7), position: 0.8), // Mid Blue
                        ProceduralTexturePass.GradientStop(color: SIMD3(0.0, 0.6, 0.8), position: 1.0)  // Cyan (Max brightness capped)
                    ]
                    
                    // Create Texture
                    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                        pixelFormat: .rgba16Float,
                        width: 512,
                        height: 512,
                        mipmapped: false
                    )
                    descriptor.usage = [.shaderWrite, .shaderRead]
                    descriptor.storageMode = .private
                    
                    if let texture = device.makeTexture(descriptor: descriptor) {
                        texture.label = pass.name
                        pass.outputTexture = texture
                        pass.outputs = [] // Prevent pipeline from allocating/blitting mismatching texture
                        proceduralPasses.append(pass)
                        
                        // Assign to Mesh
                        // Re-enabled texture after NaN fix
                        mesh.texture = texture
                        
                        // FIX: Use Unlit/Textured mode instead of PBR to prevent blowout from co-located light
                        // The texture itself provides the color and "emission" look.
                        mesh.material = nil
                        mesh.color = SIMD3<Float>(1.0, 1.0, 1.0) // White tint to preserve texture colors
                        
                        /* PBR Setup Disabled
                        // Setup PBR Material (Emissive)
                        var mat = PBRMaterial()
                        mat.baseColor = SIMD3<Float>(0.0, 0.0, 0.0) // Black base
                        mat.roughness = 0.2
                        mat.metallic = 0.0
                        mat.emissiveColor = SIMD3<Float>(0.0, 0.0, 0.0) // Zero constant emission
                        mat.emissiveIntensity = 0.8 // Reduced from 1.0 to prevent blowout
                        mat.hasBaseColorMap = 1 // Enable map so texture is sampled
                        mesh.material = mat
                        */
                    }
                    
                    // Transform
                    var baseTransform = element.worldTransform
                    if let t = baseTransform {
                        mesh.transform = transformToMatrix(t)
                    }
                    mesh.baseTransform = baseTransform
                    mesh.animation = element.animation
                    
                    scene.addMesh(mesh)
                    
                    // Create Co-located Light
                    var light = LightSource()
                    light.position = SIMD3<Float>(
                        baseTransform?.position[0] ?? 0,
                        baseTransform?.position[1] ?? 0,
                        baseTransform?.position[2] ?? 0
                    )
                    light.color = SIMD3<Float>(0.2, 0.6, 1.0) // Blueish light
                    light.intensity = 10.0 // Reduced from 50.0 to prevent blowing out other objects
                    light.isVolumetric = true
                    scene.addLight(light)
                    
                    print("ManifestResolver: Created fractal_sphere '\(element.id)'")
                }
                
            } else if element.type == "volumetric_nebula" {
                // Create true 3D volumetric nebula pass
                let pass = VolumetricNebulaPass(device: device, scene: scene)
                pass.label = "Volumetric Nebula: \(element.id)"
                
                // Apply Carina preset as default
                pass.configureForCarinaNebula()
                
                // Override with manifest values if provided
                if let transform = element.worldTransform {
                    let pos = SIMD3<Float>(transform.position[0], transform.position[1], transform.position[2])
                    let scale = transform.scale ?? 10.0
                    // Volume centered at pos, extending scale units in each direction
                    pass.volumeMin = pos - SIMD3<Float>(scale, scale * 0.5, scale * 0.5)
                    pass.volumeMax = pos + SIMD3<Float>(scale, scale * 0.5, scale * 0.5)
                    print("ManifestResolver: Volumetric bounds: \(pass.volumeMin) to \(pass.volumeMax)")
                }
                
                // Apply procedural field parameters if provided
                if let field = element.proceduralField, let params = field.parameters {
                    if let freq = params["frequency"] { pass.baseFrequency = freq }
                    if let oct = params["octaves"] { pass.octaves = Int(oct) }
                    if let lac = params["lacunarity"] { pass.lacunarity = lac }
                    if let g = params["gain"] { pass.gain = g }
                }
                
                // Apply color map for emission colors
                if let colorMap = element.colorMap, let gradient = colorMap.gradient, gradient.count >= 2 {
                    pass.emissionColorCool = hexToSIMD3(gradient.first!)
                    pass.emissionColorWarm = hexToSIMD3(gradient.last!)
                    if let hdr = colorMap.hdrScale { pass.hdrScale = hdr }
                }
                
                volumetricNebulaPasses.append(pass)
                print("ManifestResolver: Created volumetric_nebula '\(element.id)'")
                
            } else if element.type == "procedural_texture" {
                // Create Procedural Texture Pass
                let pass = ProceduralTexturePass()
                pass.fieldDefinition = element.proceduralField
                pass.name = element.id
                
                // FIX: Apply Color Map from Manifest
                if let colorMap = element.colorMap, let gradientHex = colorMap.gradient {
                    print("ManifestResolver: Applying custom gradient to pass '\(element.id)'")
                    var stops: [ProceduralTexturePass.GradientStop] = []
                    let count = gradientHex.count
                    
                    for (i, hex) in gradientHex.enumerated() {
                        let color = hexToSIMD3(hex)
                        // Distribute evenly for now (0.0 to 1.0)
                        let pos = Float(i) / Float(max(1, count - 1))
                        stops.append(ProceduralTexturePass.GradientStop(color: color, position: pos))
                    }
                    pass.gradientColors = stops
                }
                
                // Determine resolution (Default to 1920x1080 if not specified)
                // In a real app, this should match the render resolution
                // let width = 1920
                // let height = 1080
                // pass.resolution = SIMD2<Int>(width, height)
                // Fix: Let pass use context resolution to match aspect ratio
                pass.resolution = nil
                
                // Pre-allocate texture so we can bind it to meshes
                // Note: We need the device to do this.
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .rgba16Float,
                    width: renderWidth,
                    height: renderHeight,
                    mipmapped: false
                )
                descriptor.usage = [.shaderWrite, .shaderRead]
                descriptor.storageMode = .private
                
                if let texture = device.makeTexture(descriptor: descriptor) {
                    texture.label = element.id
                    pass.outputTexture = texture // Inject the texture into the pass
                    resourceMap[element.id] = texture
                    proceduralPasses.append(pass)
                    print("ManifestResolver: Created procedural pass '\(element.id)'")
                }
                
            } else if element.type == "media_plane" {
                // Create Media Plane Mesh
                // We use a quad for the media plane
                if let mesh = createQuadMesh(device: device, size: SIMD2<Float>(1.0, 1.0)) {
                    // Media plane usually has a texture, but Mesh class only supports color for now
                    // We'll give it a placeholder color
                    if let matDef = element.material {
                        mesh.material = resolveMaterial(matDef)
                        mesh.color = nil // Force PBR
                    } else {
                        // mesh.color = SIMD3<Float>(1.0, 0.0, 0.0) // DEBUG: Force RED
                        mesh.color = SIMD3<Float>(1.0, 1.0, 1.0) // White to multiply with texture
                    }
                    
                    mesh.animation = element.animation
                    
                    // Fix Orientation: Rotate 180 degrees to face camera
                    var baseTransform = element.worldTransform
                    
                    // FIX #2: Force Fire Plane Position (Updated to match demo)
                    if element.id == "fire_plane" {
                        print("ManifestResolver: Forcing fire_plane transform to demo spec")
                        baseTransform = TransformDefinition(
                            position: [0.0, 0.0, 5.0],
                            rotationDegrees: [0.0, 180.0, 0.0],
                            scale: 4.0,
                            billboardMode: nil
                        )
                    } else if var t = baseTransform {
                        // Fix Z-Fighting: Move Media Plane slightly backward
                        t.position[2] -= 0.1
                        
                        var rot = t.rotationDegrees ?? [0, 0, 0]
                        rot[1] += 180.0
                        t.rotationDegrees = rot
                        baseTransform = t
                    }
                    mesh.baseTransform = baseTransform
                    
                    mesh.postProcessFX = element.postProcessFx
                    
                    // FIX: Force solid fire color instead of procedural texture
                    // The procedural texture isn't being generated, so use solid color
                    if element.id == "fire_plane" {
                        print("ManifestResolver: Using solid color for fire_plane (procedural texture disabled)")
                        mesh.color = SIMD3<Float>(1.0, 0.4, 0.1)  // Bright orange fire color
                        mesh.texture = nil
                        mesh.material = nil
                        mesh.isTransparent = false
                    } else if let assetId = element.assetId {
                        if assetId == "solid" {
                            let colorHex = element.material?.color ?? "#FFFFFF"
                            let color = hexToSIMD4(colorHex)
                            mesh.texture = createSolidTexture(device: device, color: color)
                            if color.w < 1.0 {
                                mesh.isTransparent = true
                            }
                        } else if let proceduralTex = resourceMap[assetId] {
                            print("ManifestResolver: Linked media_plane '\(element.id)' to texture '\(assetId)'")
                            // Link to Procedural Texture
                            mesh.texture = proceduralTex
                            // If transparent (e.g. clouds), enable blending
                            // For now assume all procedural textures might have alpha
                            mesh.isTransparent = true 
                            
                            // Fix: Force Unlit/Textured mode for procedural media planes
                            // If we are in PBR mode (color == nil), the texture won't be used by GeometryPass.
                            // We switch back to Textured mode by setting color and clearing material.
                            // NOTE: We must ensure material is nil to avoid PBR shader.
                            mesh.color = SIMD3<Float>(1.0, 1.0, 1.0)
                            mesh.material = nil
                        } else if assetId.contains(".") || assetId.contains("/") {
                            // Try to load from file
                            if let tex = loadTexture(device: device, path: assetId) {
                                print("ManifestResolver: Loaded texture from file '\(assetId)'")
                                print("ManifestResolver: Texture Info: \(tex.width)x\(tex.height) format=\(tex.pixelFormat.rawValue)")
                                mesh.texture = tex
                                mesh.isTransparent = true
                                mesh.color = SIMD3<Float>(1.0, 1.0, 1.0)
                                mesh.material = nil
                            } else {
                                print("ManifestResolver: FAILED to load texture from file '\(assetId)'")
                                mesh.texture = createGridTexture(device: device)
                            }
                        } else {
                            print("ManifestResolver: WARNING - Could not find texture '\(assetId)' for media_plane '\(element.id)'. Available: \(resourceMap.keys)")
                            // Generate Grid Texture for Media Plane
                            mesh.texture = createGridTexture(device: device)
                        }
                    } else {
                        // Generate Grid Texture for Media Plane
                        mesh.texture = createGridTexture(device: device)
                    }
                    
                    if let active = element.activeTime, active.count == 2 {
                        mesh.activeTime = (active[0], active[1])
                    }
                    
                    if let t = baseTransform {
                    mesh.transform = transformToMatrix(t)
                    }
                    scene.addMesh(mesh)
                    print("ManifestResolver: Created media plane '\(element.id)'")
                }
            }
        }
        
        // 5. Create Pipeline
        let pipeline = RenderPipeline(device: device)
        
        // Resolve Quality Mode
        let qualityMode: MVQualityMode
        switch manifest.metadata.intendedQualityProfile.lowercased() {
        case "realtime": qualityMode = .realtime
        case "lab": qualityMode = .lab
        default: qualityMode = .cinema
        }
        
        // 6. Add Passes
        
        // Pass 0: Procedural Generation
        for pass in proceduralPasses {
            pipeline.addPass(pass)
        }
        
        // Pass 1: Background
        let backgroundPass = BackgroundPass(device: device)
        pipeline.addPass(backgroundPass)
        
        // Pass 2: Geometry
        let geometryPass = GeometryPass(device: device, scene: scene)
        pipeline.addPass(geometryPass)
        
        // Pass 2.5: Volumetric Nebula (True 3D Raymarching)
        for nebulaPass in volumetricNebulaPasses {
            nebulaPass.applyQualityPreset(qualityMode)
            pipeline.addPass(nebulaPass)
            
            // Composite volumetric over scene using explicit two-texture blend
            // Input 0 = foreground (volumetric_nebula_buffer)
            // Input 1 = background (main_buffer)
            // Output = main_buffer (overwritten with composite)
            let compositePass = FullscreenPass(device: device,
                                               label: "Volumetric Nebula Composite",
                                               fragmentShader: "fragment_over_blend",
                                               inputs: ["volumetric_nebula_buffer", "main_buffer"],
                                               outputs: ["main_buffer"])
            pipeline.addPass(compositePass)
        }
        
        // Pass 3: Volumetrics (Legacy Screen-Space God Rays)
        if manifest.scene.atmosphere.volumetricsEnabled {
            let volPass = VolumetricPass(device: device, scene: scene)
            volPass.quality = qualityMode
            
            // Apply V5.7 Parameters
            if let decay = manifest.scene.atmosphere.decay { volPass.decay = decay }
            if let weight = manifest.scene.atmosphere.weight { volPass.weight = weight }
            if let exposure = manifest.scene.atmosphere.exposure { volPass.exposure = exposure }
            
            // Wire V6.3 parameters
            volPass.color = hexToSIMD3(manifest.scene.atmosphere.volumetricColor)
            
            volPass.inputs = ["main_buffer", "depth_buffer"]
            volPass.outputs = ["volumetric_buffer"]
            pipeline.addPass(volPass)
            
            let compositePass = FullscreenPass(device: device,
                                               label: "Volumetric Composite",
                                               fragmentShader: "fragment_add",
                                               inputs: ["volumetric_buffer"],
                                               outputs: ["main_buffer"])
            pipeline.addPass(compositePass)
        }
        
        /* DEBUG: DISABLE VOLUMETRICS
        if manifest.scene.atmosphere.volumetricsEnabled {
            let volPass = VolumetricPass(device: device, scene: scene)
            volPass.quality = qualityMode
            
            // Apply V5.7 Parameters
            if let decay = manifest.scene.atmosphere.decay { volPass.decay = decay }
            if let weight = manifest.scene.atmosphere.weight { volPass.weight = weight }
            if let exposure = manifest.scene.atmosphere.exposure { volPass.exposure = exposure }
            
            // Wire V6.3 parameters
            volPass.color = hexToSIMD3(manifest.scene.atmosphere.volumetricColor)
            
            volPass.inputs = ["main_buffer", "depth_buffer"]
            volPass.outputs = ["volumetric_buffer"]
            pipeline.addPass(volPass)
            
            let compositePass = FullscreenPass(device: device,
                                               label: "Volumetric Composite",
                                               fragmentShader: "fragment_add",
                                               inputs: ["volumetric_buffer"],
                                               outputs: ["main_buffer"])
            pipeline.addPass(compositePass)
        }
        */
        
        // Pass 3.5: Text Overlay (Before Post-Processing)
        // We render text into the main HDR buffer so it receives Bloom and Optical effects.
        if !timedTextEvents.isEmpty {
            let fontName = "Helvetica" as CFString
            let font = CTFontCreateWithName(fontName, 64, nil)
            if let atlas = try? SDFFontAtlas(font: font, size: CGSize(width: 512, height: 512), device: device) {
                if let renderer = try? SDFTextRenderer(fontAtlas: atlas, device: device, pixelFormat: .rgba16Float) {
                    let textPass = TextPass(device: device, textRenderer: renderer)
                    textPass.timedTextEvents = timedTextEvents
                    textPass.inputs = ["main_buffer"]
                    textPass.outputs = ["main_buffer"]
                    pipeline.addPass(textPass)
                }
            }
        }
        
        // Pass 4: Uber Post-Processing
        // Replaces individual passes for Bloom, Halation, Lens Distortion, CA, Vignette, ToneMap, Grain.
        // Uses the optimized "Ping-Pong" renderer.
        
        // 1. Determine Quality Preset
        let preset: PostProcessingConfig.QualityPreset
        switch qualityMode {
        case .realtime: preset = .mobile
        case .lab: preset = .balanced
        case .cinema: preset = .reference
        }
        
        var config = PostProcessingConfig(preset: preset)
        
        // 2. Override with Manifest Settings
        
        // Bloom
        if let bloom = manifest.postProcessing.bloom {
            config.bloomEnabled = bloom.enabled
            if let i = bloom.intensity { config.bloomStrength = i } // Note: Mapping intensity to strength
            if let t = bloom.threshold { config.bloomThreshold = t }
            if let r = bloom.radius { config.bloomRadius = Int(r) }
        }
        
        // Halation
        if let halation = manifest.postProcessing.halation {
            config.halationEnabled = halation.enabled
            if let i = halation.magnitude { config.halationIntensity = i }
            if let t = halation.threshold { config.halationThreshold = t }
            // config.halationRadius? Not in manifest directly, maybe derived?
        }
        
        // Lens Distortion
        if let ld = manifest.postProcessing.lensDistortion {
            config.lensDistortionEnabled = ld.enabled
            if let k1 = ld.intensity { config.lensDistortionK1 = k1 }
        }
        
        // Chromatic Aberration
        // Not explicitly in PostProcessDefinition, so we rely on QualityPreset or Camera defaults.
        // If we wanted to support it from manifest, we'd need to add it to the struct.
        // For now, we assume it's enabled for 'balanced'/'reference' presets.
        
        // Vignette
        if let v = manifest.postProcessing.vignette {
            if let i = v.intensity { config.vignetteIntensity = v.enabled ? i : 0.0 }
            if let s = v.smoothness { config.vignetteSmoothness = s }
        }
        
        // Film Grain
        if let g = manifest.postProcessing.filmGrain {
            config.filmGrainStrength = g.enabled ? (g.intensity ?? 0.0) : 0.0
        }
        
        // Anamorphic (V6.0 - inferred from Shimmer or explicit?)
        // Manifest has 'shimmer', but PostProcessingConfig has 'anamorphic'.
        // Let's map shimmer to anamorphic for now if needed, or just disable anamorphic if not in manifest.
        // V5.1 manifest doesn't have explicit 'anamorphic' block, but V6.0 might.
        // Let's leave anamorphic as per preset default, or disable if not requested.
        // Actually, let's disable anamorphic unless preset is reference, to be safe.
        if qualityMode != .cinema {
            config.anamorphicEnabled = false
        }
        
        // Create and Add Pass
        let postPass = PostProcessingPass(device: device, config: config)
        postPass.inputs = ["main_buffer"]
        postPass.outputs = ["display_buffer"]
        pipeline.addPass(postPass)
        
        /* DEBUG: DISABLE POST-PROCESSING
        // 1. Determine Quality Preset
        let preset: PostProcessingConfig.QualityPreset
        switch qualityMode {
        case .realtime: preset = .mobile
        case .lab: preset = .balanced
        case .cinema: preset = .reference
        }
        
        var config = PostProcessingConfig(preset: preset)
        
        // 2. Override with Manifest Settings
        
        // Bloom
        if let bloom = manifest.postProcessing.bloom {
            config.bloomEnabled = bloom.enabled
            if let i = bloom.intensity { config.bloomStrength = i } // Note: Mapping intensity to strength
            if let t = bloom.threshold { config.bloomThreshold = t }
            if let r = bloom.radius { config.bloomRadius = Int(r) }
        }
        
        // Halation
        if let halation = manifest.postProcessing.halation {
            config.halationEnabled = halation.enabled
            if let i = halation.magnitude { config.halationIntensity = i }
            if let t = halation.threshold { config.halationThreshold = t }
            // config.halationRadius? Not in manifest directly, maybe derived?
        }
        
        // Lens Distortion
        if let ld = manifest.postProcessing.lensDistortion {
            config.lensDistortionEnabled = ld.enabled
            if let k1 = ld.intensity { config.lensDistortionK1 = k1 }
        }
        
        // Chromatic Aberration
        // Not explicitly in PostProcessDefinition, so we rely on QualityPreset or Camera defaults.
        // If we wanted to support it from manifest, we'd need to add it to the struct.
        // For now, we assume it's enabled for 'balanced'/'reference' presets.
        
        // Vignette
        if let v = manifest.postProcessing.vignette {
            if let i = v.intensity { config.vignetteIntensity = v.enabled ? i : 0.0 }
            if let s = v.smoothness { config.vignetteSmoothness = s }
        }
        
        // Film Grain
        if let g = manifest.postProcessing.filmGrain {
            config.filmGrainStrength = g.enabled ? (g.intensity ?? 0.0) : 0.0
        }
        
        // Anamorphic (V6.0 - inferred from Shimmer or explicit?)
        // Manifest has 'shimmer', but PostProcessingConfig has 'anamorphic'.
        // Let's map shimmer to anamorphic for now if needed, or just disable anamorphic if not in manifest.
        // V5.1 manifest doesn't have explicit 'anamorphic' block, but V6.0 might.
        // Let's leave anamorphic as per preset default, or disable if not requested.
        // Actually, let's disable anamorphic unless preset is reference, to be safe.
        if qualityMode != .cinema {
            config.anamorphicEnabled = false
        }
        
        // Create and Add Pass
        let postPass = PostProcessingPass(device: device, config: config)
        postPass.inputs = ["main_buffer"]
        postPass.outputs = ["display_buffer"]
        pipeline.addPass(postPass)
        */
        
        // DEBUG: Bypass Post-Processing
        // let copyPass = FullscreenPass(device: device, label: "Debug Copy", fragmentShader: "fragment_copy", inputs: ["main_buffer"], outputs: ["display_buffer"])
        // pipeline.addPass(copyPass)
        
        // Build Effect Timeline from Camera Keyframes
        // We map camera properties (chromatic aberration) to the effect timeline
        for keyframe in manifest.camera.keyframes {
            let time = Double(keyframe.timeSeconds)
            
            // Chromatic Aberration
            var caState: (enabled: Bool, intensity: Float)? = nil
            if let ca = keyframe.chromaticAberration {
                caState = (enabled: ca > 0.001, intensity: ca)
            }
            
            // Create or update state at this timestamp
            // Note: This is a simple implementation that creates a new state for each keyframe.
            // In a real system, we'd merge with existing states if we had other effects.
            let state = TimedEffectState(
                timestamp: time,
                chromaticAberration: caState
            )
            pipeline.effectTimeline.append(state)
        }
        
        // Sort timeline by timestamp
        pipeline.effectTimeline.sort { $0.timestamp < $1.timestamp }
        
        // FINAL DEBUG: Verify scene content
        print("=== SCENE CONTENT SUMMARY ===")
        print("Meshes: \(scene.meshes.count)")
        for (i, mesh) in scene.meshes.enumerated() {
            print("  Mesh \(i): indexCount=\(mesh.indexCount), color=\(String(describing: mesh.color))")
        }
        print("Lights: \(scene.lights.count)")
        print("Background: \(scene.background?.type ?? "nil")")
        print("Text Events: \(timedTextEvents.count)")
        for event in timedTextEvents {
            print("  Text: '\(event.content.text ?? "nil")' at \(event.startTime)s for \(event.duration)s")
        }
        print("==============================")
        
        return (pipeline, scene)
    }
    
    private static func applySceneDefinition(_ def: SceneDefinition, to scene: Scene) {
        // Lighting
        var ambient = def.lighting.ambientIntensity ?? 0.1
        var dirLightDef = def.lighting.directionalLight
        
        // Apply Preset if present
        if let presetName = def.lighting.preset {
            let preset = PresetResolver.shared.resolveLighting(preset: presetName)
            if def.lighting.ambientIntensity == nil {
                ambient = preset.ambientIntensity ?? 0.1
            }
            if dirLightDef == nil {
                dirLightDef = preset.directionalLight
            }
        }
        
        scene.ambientLight = SIMD3<Float>(ambient, ambient, ambient)
        
        if let dirLight = dirLightDef {
            var light = LightSource()
            // Parse hex color
            let color = hexToSIMD3(dirLight.color)
            light.color = color
            light.position = SIMD3<Float>(dirLight.direction[0] * -10, dirLight.direction[1] * -10, dirLight.direction[2] * -10) // Inverse direction for position
            light.intensity = 100.0 // Increased from 5.0 to compensate for quadratic falloff
            
            if def.atmosphere.volumetricsEnabled {
                light.isVolumetric = true
            }
            scene.addLight(light)
        }
        
        // Atmosphere
        scene.volumetricDensity = def.atmosphere.density
        
        // Background
        if let bg = def.background {
            scene.background = bg
            // DEBUG: Force Blue Background
            /*
            scene.background = BackgroundDefinition(
                type: "SOLID",
                color: "#0000FF",
                colorTop: nil,
                colorBottom: nil,
                starDensity: nil
            )
            */
        } else {
            // Force black background if not specified to prevent debug defaults
            scene.background = BackgroundDefinition(
                type: "SOLID",
                color: "#000000",
                colorTop: nil,
                colorBottom: nil,
                starDensity: nil
            )
        }
    }
    
    private static func applyCameraKeyframe(_ keyframe: CameraKeyframe, to camera: inout PhysicalCamera) {
        let pos = SIMD3<Float>(keyframe.position[0], keyframe.position[1], keyframe.position[2])
        let target = SIMD3<Float>(keyframe.target[0], keyframe.target[1], keyframe.target[2])
        
        camera.position = pos
        camera.initialPosition = pos // Fix: Set initial position for motion logic
        
        // LookAt Logic
        // Camera looks down -Z by default.
        // We want to orient it so -Z points to target.
        // Forward = normalize(target - pos)
        // But wait, if default is -Z, then we want -Z axis to align with Forward.
        // So Forward (camera space) = (0, 0, -1).
        // We want to rotate (0, 0, -1) to (target - pos).
        
        let forward = normalize(target - pos)
        let up = SIMD3<Float>(0, 1, 0)
        
        // Right = cross(Forward, Up) ?? No, standard LookAt:
        // Z = normalize(eye - target) (This is backward vector, +Z)
        // X = normalize(cross(up, Z))
        // Y = cross(Z, X)
        
        // Metal/simd_quatf usually expects a rotation matrix.
        // Let's build the basis vectors.
        // We want the camera's -Z to point to target.
        // So Camera +Z points away from target.
        let zAxis = normalize(pos - target) // +Z
        let xAxis = normalize(cross(up, zAxis)) // +X
        let yAxis = cross(zAxis, xAxis) // +Y
        
        let rotationMatrix = matrix_float3x3(columns: (xAxis, yAxis, zAxis))
        camera.orientation = simd_quatf(rotationMatrix)
        
        // FOV Logic
        // FOV = 2 * atan(sensorWidth / (2 * focalLength))
        // focalLength = sensorWidth / (2 * tan(FOV / 2))
        let fovRad = keyframe.fov * .pi / 180.0
        camera.focalLength = camera.sensorWidth / (2.0 * tan(fovRad / 2.0))
        
        // Distortion (V5.7)
        if let k1 = keyframe.distortionK1 { camera.distortionK1 = k1 }
        if let k2 = keyframe.distortionK2 { camera.distortionK2 = k2 }
        if let ca = keyframe.chromaticAberration { camera.chromaticAberration = ca }
        
        // Focus (V5.8)
        if let fd = keyframe.focusDistance { camera.focusDistance = fd }
        if let fs = keyframe.fStop { camera.fStop = fs }
    }
    
    // MARK: - Mesh Generation Helpers
    
    private static func createSphereMesh(device: MTLDevice, radius: Float, segments: Int, rings: Int) -> Mesh? {
        var vertices: [Float] = []
        var indices: [UInt16] = []
        
        for r in 0...rings {
            let phi = Float.pi * Float(r) / Float(rings)
            let y = radius * cos(phi)
            let ringRadius = radius * sin(phi)
            
            for s in 0...segments {
                let theta = 2.0 * Float.pi * Float(s) / Float(segments)
                let x = ringRadius * cos(theta)
                let z = ringRadius * sin(theta)
                
                let u = 1.0 - Float(s) / Float(segments)
                let v = Float(r) / Float(rings)
                
                let nx = x / radius
                let ny = y / radius
                let nz = z / radius
                
                vertices.append(contentsOf: [x, y, z, nx, ny, nz, u, v])
            }
        }
        
        for r in 0..<rings {
            for s in 0..<segments {
                let nextRow = UInt16(segments + 1)
                let current = UInt16(r * (segments + 1) + s)
                let next = current + nextRow
                
                indices.append(current)
                indices.append(next)
                indices.append(current + 1)
                
                indices.append(current + 1)
                indices.append(next)
                indices.append(next + 1)
            }
        }
        
        return Mesh(device: device, vertices: vertices, indices: indices)
    }
    
    private static func createQuadMesh(device: MTLDevice, size: SIMD2<Float>) -> Mesh? {
        let w = size.x / 2.0
        let h = size.y / 2.0
        
        // Vertex Format: Pos(3) + Norm(3) + UV(2) = 8 floats
        // UVs: BL(0,1), BR(1,1), TR(1,0), TL(0,0) - Standard Metal/Vulkan Top-Left Origin?
        // Actually, let's stick to standard texture coords: (0,0) top-left usually?
        // In Metal, (0,0) is top-left of texture.
        // Our quad is Y-up in world space.
        // So Top-Left vertex (-w, h) should map to (0,0).
        
        let vertices: [Float] = [
            // BL (-w, -h) -> (0, 1)
            -w, -h, 0,   0, 0, 1,   0, 1,
            // BR (w, -h) -> (1, 1)
             w, -h, 0,   0, 0, 1,   1, 1,
            // TR (w, h) -> (1, 0)
             w,  h, 0,   0, 0, 1,   1, 0,
            // TL (-w, h) -> (0, 0)
            -w,  h, 0,   0, 0, 1,   0, 0
        ]
        
        let indices: [UInt16] = [
            0, 1, 2,
            0, 2, 3
        ]
        
        return Mesh(device: device, vertices: vertices, indices: indices)
    }
    
    private static func createParticleCloudMesh(device: MTLDevice, count: Int, radius: Float, particleSize: Float = 0.1) -> Mesh? {
        var vertices: [Float] = []
        var indices: [UInt16] = []
        
        // Create random quads (billboards)
        for i in 0..<count {
            // FIX #1: Use Box Distribution for full screen coverage
            // The previous spherical distribution might have been clipped or offset
            let range: Float = 1.0 // Normalized range
            let x = Float.random(in: -range...range) * radius
            let y = Float.random(in: -range...range) * radius
            let z = Float.random(in: -range...range) * radius
            
            /* Previous Spherical Logic
            let u = Float.random(in: 0...1)
            let v = Float.random(in: 0...1)
            let theta = 2.0 * Float.pi * u
            let phi = acos(2.0 * v - 1.0)
            let r = cbrt(Float.random(in: 0...1)) * radius
            
            let x = r * sin(phi) * cos(theta)
            let y = r * sin(phi) * sin(theta)
            let z = r * cos(phi)
            */
            
            // Make particles larger for soft glow look
            let size: Float = particleSize
            
            // Quad Offset (facing +Z)
            let baseIndex = UInt16(vertices.count / 8)
            
            // BL
            vertices.append(contentsOf: [x - size, y - size, z, 0, 0, 1, 0, 1])
            // BR
            vertices.append(contentsOf: [x + size, y - size, z, 0, 0, 1, 1, 1])
            // TR
            vertices.append(contentsOf: [x + size, y + size, z, 0, 0, 1, 1, 0])
            // TL
            vertices.append(contentsOf: [x - size, y + size, z, 0, 0, 1, 0, 0])
            
            indices.append(baseIndex)
            indices.append(baseIndex + 1)
            indices.append(baseIndex + 2)
            indices.append(baseIndex)
            indices.append(baseIndex + 2)
            indices.append(baseIndex + 3)
        }
        
        return Mesh(device: device, vertices: vertices, indices: indices)
    }
    
    private static func createCheckerboardTexture(device: MTLDevice, colorA: SIMD3<Float>, colorB: SIMD3<Float>) -> MTLTexture? {
        let width = 256
        let height = 256
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: true)
        descriptor.usage = [.shaderRead]
        
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        
        for y in 0..<height {
            for x in 0..<width {
                let check = ((x / 32) + (y / 32)) % 2 == 0
                let color = check ? colorA : colorB
                let alpha: UInt8 = check ? 255 : 0 // Transparent holes
                
                let i = (y * width + x) * 4
                bytes[i] = UInt8(color.x * 255)
                bytes[i+1] = UInt8(color.y * 255)
                bytes[i+2] = UInt8(color.z * 255)
                bytes[i+3] = alpha
            }
        }
        
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: bytes, bytesPerRow: width * 4)
        return texture
    }
    
    private static func createGridTexture(device: MTLDevice) -> MTLTexture? {
        let width = 512
        let height = 512
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: true)
        descriptor.usage = [.shaderRead]
        
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        
        for y in 0..<height {
            for x in 0..<width {
                let border = 2
                let isGrid = (x % 64 < border) || (y % 64 < border)
                let color: SIMD3<Float> = isGrid ? SIMD3<Float>(0.8, 0.8, 0.8) : SIMD3<Float>(0.0, 0.0, 0.0)
                let alpha: UInt8 = isGrid ? 100 : 0 // Semi-transparent grid, fully transparent background
                
                let i = (y * width + x) * 4
                bytes[i] = UInt8(color.x * 255)
                bytes[i+1] = UInt8(color.y * 255)
                bytes[i+2] = UInt8(color.z * 255)
                bytes[i+3] = alpha
            }
        }
        
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: bytes, bytesPerRow: width * 4)
        return texture
    }
    
    private static func createSoftDotTexture(device: MTLDevice) -> MTLTexture? {
        let size = 64
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: size, height: size, mipmapped: true)
        descriptor.usage = [.shaderRead]
        
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        
        for y in 0..<size {
            for x in 0..<size {
                let cx = Float(x) - Float(size)/2.0
                let cy = Float(y) - Float(size)/2.0
                let dist = sqrt(cx*cx + cy*cy) / (Float(size)/2.0)
                
                let alpha = max(0.0, 1.0 - dist)
                // Smoothstep for nicer falloff
                let smoothAlpha = alpha * alpha * (3.0 - 2.0 * alpha)
                
                let i = (y * size + x) * 4
                bytes[i] = 255   // R
                bytes[i+1] = 255 // G
                bytes[i+2] = 255 // B
                bytes[i+3] = UInt8(smoothAlpha * 255) // A
            }
        }
        
        texture.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0, withBytes: bytes, bytesPerRow: size * 4)
        return texture
    }
    
    private static func createStarTexture(device: MTLDevice) -> MTLTexture? {
        let size = 64
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: size, height: size, mipmapped: true)
        descriptor.usage = [.shaderRead]
        
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        
        for y in 0..<size {
            for x in 0..<size {
                let cx = Float(x) - Float(size)/2.0
                let cy = Float(y) - Float(size)/2.0
                let dist = sqrt(cx*cx + cy*cy) / (Float(size)/2.0)
                
                // Sharper falloff for stars
                let alpha = max(0.0, 1.0 - dist)
                let sharpAlpha = pow(alpha, 10.0) // Very sharp point
                
                let i = (y * size + x) * 4
                bytes[i] = 255   // R
                bytes[i+1] = 255 // G
                bytes[i+2] = 255 // B
                bytes[i+3] = UInt8(sharpAlpha * 255) // A
            }
        }
        
        texture.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0, withBytes: bytes, bytesPerRow: size * 4)
        return texture
    }
    
    // MARK: - Utility Helpers
    
    private static func createSolidTexture(device: MTLDevice, color: SIMD4<Float>) -> MTLTexture? {
        let width = 1
        let height = 1
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead]
        
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes[0] = UInt8(color.x * 255)
        bytes[1] = UInt8(color.y * 255)
        bytes[2] = UInt8(color.z * 255)
        bytes[3] = UInt8(color.w * 255)
        
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: bytes, bytesPerRow: 4)
        return texture
    }

    private static func hexToSIMD4(_ hex: String) -> SIMD4<Float> {
        var cString: String = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        if (cString.hasPrefix("#")) {
            cString.remove(at: cString.startIndex)
        }
        
        var a: Float = 1.0
        
        if cString.count == 8 {
            let alphaHex = String(cString.suffix(2))
            cString = String(cString.prefix(6))
            
            var alphaValue: UInt64 = 0
            Scanner(string: alphaHex).scanHexInt64(&alphaValue)
            a = Float(alphaValue) / 255.0
        }
        
        if ((cString.count) != 6) {
            return SIMD4<Float>(0.5, 0.5, 0.5, 1.0)
        }
        
        var rgbValue: UInt64 = 0
        Scanner(string: cString).scanHexInt64(&rgbValue)
        
        let r = Float((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Float((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Float(rgbValue & 0x0000FF) / 255.0
        
        return SIMD4<Float>(r, g, b, a)
    }
    
    private static func hexToSIMD3(_ hex: String) -> SIMD3<Float> {
        let c = hexToSIMD4(hex)
        return SIMD3<Float>(c.x, c.y, c.z)
    }
    
    private static func transformToMatrix(_ t: TransformDefinition) -> matrix_float4x4 {
        // 1. Scale
        let s = t.scale ?? 1.0
        let scale = matrix_float4x4(diagonal: SIMD4<Float>(s, s, s, 1))
        
        // 2. Rotation (Euler XYZ)
        let rotDeg = t.rotationDegrees ?? [0.0, 0.0, 0.0]
        let radX = rotDeg[0] * .pi / 180.0
        let radY = rotDeg[1] * .pi / 180.0
        let radZ = rotDeg[2] * .pi / 180.0
        
        let rotX = matrix_float4x4(rows: [
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, cos(radX), -sin(radX), 0),
            SIMD4<Float>(0, sin(radX), cos(radX), 0),
            SIMD4<Float>(0, 0, 0, 1)
        ])
        
        let rotY = matrix_float4x4(rows: [
            SIMD4<Float>(cos(radY), 0, sin(radY), 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(-sin(radY), 0, cos(radY), 0),
            SIMD4<Float>(0, 0, 0, 1)
        ])
        
        let rotZ = matrix_float4x4(rows: [
            SIMD4<Float>(cos(radZ), -sin(radZ), 0, 0),
            SIMD4<Float>(sin(radZ), cos(radZ), 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ])
        
        let rotation = rotZ * rotY * rotX
        
        // 3. Translation
        var translation = matrix_identity_float4x4
        translation.columns.3 = SIMD4<Float>(t.position[0], t.position[1], t.position[2], 1)
        
        return translation * rotation * scale
    }
    
    private static func resolveMaterial(_ def: MaterialDefinition?) -> PBRMaterial {
        guard let def = def else { return PBRMaterial() }
        
        let color = hexToSIMD3(def.color)
        
        return PBRMaterial(
            baseColor: color,
            metallic: def.metallic ?? 0.0,
            roughness: def.roughness ?? 0.5,
            specular: def.specular ?? 0.5,
            specularTint: def.specularTint ?? 0.0,
            sheen: def.sheen ?? 0.0,
            sheenTint: def.sheenTint ?? 0.0,
            clearcoat: def.clearcoat ?? 0.0,
            clearcoatGloss: def.clearcoatGloss ?? 1.0,
            ior: def.ior ?? 1.45,
            transmission: def.transmission ?? 0.0
        )
    }
    
    private static func loadTexture(device: MTLDevice, path: String) -> MTLTexture? {
        let loader = MTKTextureLoader(device: device)
        
        // Debug: Print CWD
        let cwd = FileManager.default.currentDirectoryPath
        print("ManifestResolver: CWD is '\(cwd)'")
        
        // 1. Try Absolute Path (if provided) or Relative to CWD
        var url: URL
        if path.hasPrefix("/") {
            url = URL(fileURLWithPath: path)
        } else {
            url = URL(fileURLWithPath: cwd).appendingPathComponent(path)
        }
        
        print("ManifestResolver: Attempting to load texture from '\(url.path)'")
        
        if !FileManager.default.fileExists(atPath: url.path) {
            print("ManifestResolver: ERROR - File does not exist at '\(url.path)'")
            // Try checking if it exists in the bundle or other locations?
            // For CLI, we stick to CWD.
        }
        
        let options: [MTKTextureLoader.Option: Any] = [
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .origin: MTKTextureLoader.Origin.topLeft,
            .generateMipmaps: true
        ]
        
        do {
            return try loader.newTexture(URL: url, options: options)
        } catch {
            print("ManifestResolver: Failed to load texture: \(error)")
            return nil
        }
    }
}

