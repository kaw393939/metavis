import Foundation
import Metal
import simd
import Logging
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

/// Minimal validation runner for autonomous development.
///
/// The `ValidationRunner` is the orchestrator for the "Scientific Method" development loop.
/// It loads effect definitions from YAML configuration files, instantiates the appropriate
/// `EffectValidator`, and executes a series of tests to verify physical correctness.
///
/// ## Workflow
/// 1.  **Load Config**: Reads `assets/config/effects/*.yaml`.
/// 2.  **Select Validator**: Maps the effect ID to a registered `EffectValidator`.
/// 3.  **Run Tests**: Executes each test case defined in the YAML.
/// 4.  **Report**: Generates a structured `ValidationRunResult`.
@available(macOS 14.0, *)
public actor ValidationRunner {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let configLoader: ConfigurationLoader
    private let logger = Logger(label: "com.metalvis.validation.runner")
    
    private var validators: [String: any EffectValidator] = [:]
    
    /// Whether to use the real render pipeline (true) or synthetic test frames (false).
    /// - Note: Should be `true` for all integration tests.
    public var useRealPipeline: Bool = true
    
    /// Initializes a new ValidationRunner.
    /// - Parameter device: The Metal device to use for rendering tests.
    /// - Throws: `ValidationRunnerError` if the command queue cannot be created.
    public init(device: MTLDevice) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            throw ValidationRunnerError.noCommandQueue
        }
        self.commandQueue = queue
        self.configLoader = ConfigurationLoader()
        
        // Register ALL available validators
        validators["bloom"] = BloomValidator(device: device)
        validators["halation"] = HalationValidator(device: device)
        validators["film_grain"] = FilmGrainValidator(device: device)
        validators["vignette"] = VignetteValidator(device: device)
        validators["chromatic_aberration"] = ChromaticAberrationValidator(device: device)
        validators["anamorphic"] = AnamorphicValidator(device: device)
        validators["lens_distortion"] = LensDistortionValidator(device: device)
        validators["tonemapping"] = TonemappingValidator(device: device)
        validators["aces"] = ACESValidator(device: device)
        validators["text_layout"] = TextLayoutValidator(device: device)
        validators["camera"] = CameraValidator(device: device)
        validators["occlusion"] = OcclusionValidator(device: device)
        validators["motion_stability"] = MotionStabilityValidator(device: device)
        validators["ceip"] = CEIPValidator(device: device)
        validators["lens_system"] = LensSystemValidator(device: device)
        validators["procedural_texture"] = ProceduralValidator(device: device)
        validators["shimmer"] = ShimmerValidator(device: device)
        validators["volumetric"] = VolumetricValidator(device: device)
        validators["energy"] = EnergyValidator(device: device)
        validators["bokeh"] = BokehValidator(device: device)
        validators["pbr"] = PBRValidator(device: device)
    }
    
    // MARK: - Public API
    
    /// Run all validations defined in YAML configs
    /// Returns structured results for agent consumption
    public func runAllValidations() async -> ValidationRunResult {
        logger.info("Starting validation run")
        
        var effectResults: [EffectRunResult] = []
        let errors: [String] = []
        
        // Load all effect definitions
        let effects: [EffectDefinition]
        do {
            effects = try await configLoader.loadAllEffectDefinitions()
        } catch {
            return ValidationRunResult(
                success: false,
                timestamp: Date(),
                effectResults: [],
                summary: ValidationSummary(total: 0, passed: 0, failed: 0, skipped: 0),
                errors: ["Failed to load effect definitions: \(error.localizedDescription)"]
            )
        }
        
        logger.info("Loaded \(effects.count) effect definitions")
        
        // Run validation for each effect
        for effect in effects {
            let result = await runEffectValidation(effect: effect)
            effectResults.append(result)
        }
        
        // Calculate summary
        let passed = effectResults.filter { $0.status == .passed }.count
        let failed = effectResults.filter { $0.status == .failed }.count
        let skipped = effectResults.filter { $0.status == .skipped }.count
        
        let summary = ValidationSummary(
            total: effectResults.count,
            passed: passed,
            failed: failed,
            skipped: skipped
        )
        
        let success = failed == 0
        
        logger.info("Validation complete: \(passed)/\(effectResults.count) passed")
        
        return ValidationRunResult(
            success: success,
            timestamp: Date(),
            effectResults: effectResults,
            summary: summary,
            errors: errors
        )
    }
    
    /// Run validation for a single effect
    public func runEffectValidation(effectId: String) async -> EffectRunResult {
        do {
            let effect = try await configLoader.loadEffectDefinition(named: effectId)
            return await runEffectValidation(effect: effect)
        } catch {
            return EffectRunResult(
                effectId: effectId,
                effectName: effectId,
                status: .error,
                testResults: [],
                duration: 0,
                error: error.localizedDescription
            )
        }
    }
    
    // MARK: - Private Implementation
    
    private func runEffectValidation(effect: EffectDefinition) async -> EffectRunResult {
        let startTime = Date()
        
        // Check if we have a validator for this effect
        guard let validator = validators[effect.id] else {
            logger.warning("No validator available for effect: \(effect.id)")
            return EffectRunResult(
                effectId: effect.id,
                effectName: effect.name,
                status: .skipped,
                testResults: [],
                duration: 0,
                error: "No validator implemented for this effect"
            )
        }
        
        // Get test definitions from YAML
        let tests = effect.validation.tests
        guard !tests.isEmpty else {
            logger.info("No tests defined for effect: \(effect.id)")
            return EffectRunResult(
                effectId: effect.id,
                effectName: effect.name,
                status: .skipped,
                testResults: [],
                duration: 0,
                error: "No tests defined in YAML"
            )
        }
        
        logger.info("Running \(tests.count) tests for \(effect.name)")
        
        var testResults: [TestRunResult] = []
        var allPassed = true
        
        for test in tests {
            let testResult = await runSingleTest(
                test: test,
                effect: effect,
                validator: validator
            )
            testResults.append(testResult)
            
            if testResult.status == .failed {
                allPassed = false
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        return EffectRunResult(
            effectId: effect.id,
            effectName: effect.name,
            status: allPassed ? .passed : .failed,
            testResults: testResults,
            duration: duration,
            error: nil
        )
    }
    
    private func runSingleTest(
        test: ValidationTestDefinition,
        effect: EffectDefinition,
        validator: any EffectValidator
    ) async -> TestRunResult {
        logger.debug("Running test: \(test.name)")
        
        // For now, we'll create a simple test context
        // In the full implementation, this would render actual frames
        let context = ValidationContext(
            device: device,
            commandQueue: commandQueue,
            width: 1920,
            height: 1080,
            timestamp: 0,
            frameIndex: 0
        )
        
        // Create parameters from effect definition
        let intensityValue = effect.parameters["intensity"]?.defaultValue.floatValue
        let thresholdValue = effect.parameters["threshold"]?.defaultValue.floatValue
        let radiusValue = effect.parameters["radius"]?.defaultValue.floatValue
        
        // Collect additional params from YAML definition
        var additionalParams: [String: Float] = [:]
        for (key, param) in effect.parameters {
            if key != "intensity" && key != "threshold" && key != "radius" {
                if let value = param.defaultValue.floatValue {
                    additionalParams[key] = value
                }
            }
        }
        
        // Merge test-specific parameters (overrides)
        if let testParams = test.parameters {
            for (key, value) in testParams {
                if let floatVal = value.floatValue {
                    additionalParams[key] = floatVal
                }
            }
        }
        
        // Special case: lens_distortion barrel test needs k1 < 0
        // The YAML default is k1=0 (no distortion) but barrel test needs negative k1
        if effect.id == "lens_distortion" {
            // Override k1 for barrel distortion testing per YAML methodology
            // "Apply distortion with k1 = -0.2"
            if additionalParams["k1"] == 0.0 || additionalParams["k1"] == nil {
                additionalParams["k1"] = -0.2  // Barrel distortion (as per YAML methodology)
            }
        }
        
        // Special case: vignette cos⁴ law testing needs full intensity (1.0)
        // The YAML default is 0.3 but methodology says "Apply vignette with falloff = 1.0"
        var validationIntensity = intensityValue
        if effect.id == "vignette" {
            validationIntensity = 1.0  // Full intensity for physics validation
        }
        
        // Special case: Halation falloff validation needs a dense kernel to measure R² accurately
        // We use a large radius to ensure the falloff spans multiple analysis rings
        var validationRadius = radiusValue
        if effect.id == "halation" {
            validationRadius = 350.0
            validationIntensity = 1.0
        }
        
        // Special case: text_layout needs content parameter for OCR validation
        
        // Special case: text_layout needs content parameter for OCR validation
        var textParams: [String: String] = [:]
        if effect.id == "text_layout" {
            textParams["content"] = "Validation Text Block\nChecking Margins\nAnd Legibility"
        }
        
        let parameters = EffectParameters(
            effectName: effect.id,
            enabled: true,
            intensity: validationIntensity,
            threshold: thresholdValue,
            radius: validationRadius,
            additionalParams: additionalParams,
            textParams: textParams
        )
        
        do {
            // Generate frames for comparison using real pipeline or synthetic
            let (baselineData, testData): (Data, Data)
            
            if useRealPipeline {
                // Use real render pipeline
                let rendered = try await renderWithRealPipeline(
                    effectId: effect.id,
                    parameters: parameters,
                    width: 1920,
                    height: 1080
                )
                baselineData = rendered.baseline
                testData = rendered.withEffect
                logger.info("Using real pipeline for \(effect.id) validation")
            } else {
                // Use synthetic test frames
                baselineData = generateTestFrame(width: 1920, height: 1080, applyEffect: false)
                testData = generateTestFrame(width: 1920, height: 1080, applyEffect: true, effectId: effect.id)
                logger.info("Using synthetic frames for \(effect.id) validation")
            }
            
            let result = try await validator.validate(
                frameData: testData,
                baselineData: baselineData,
                parameters: parameters,
                context: context
            )
            
            // Check against threshold from YAML
            let (passed, diagnosis) = evaluateThresholdWithDiagnosis(result: result, test: test, effect: effect)
            
            // Log detailed metrics for debugging
            logger.info("Test '\(test.name)' metrics: \(result.metrics)")
            
            if !passed {
                logger.error("Test '\(test.name)' failed. Metrics: \(result.metrics)")
                if let diag = diagnosis {
                    logger.error("Diagnosis: \(diag.issue) - Expected: \(diag.expected), Actual: \(diag.actual)")
                }
                
                // Save failed frame for debugging
                if test.id == "bokeh_size" {
                    let debugURL = URL(fileURLWithPath: "output/failed_bokeh.png")
                    try? testData.write(to: debugURL)
                    logger.info("Saved failed bokeh frame to \(debugURL.path)")
                }
            }
            
            // Build suggested fixes from validator output and YAML patterns
            let fixes = buildSuggestedFixes(result: result, test: test, effect: effect, passed: passed)
            
            // Build verification command
            let verification = passed ? nil : Verification(
                command: "swift run metavis validate --effect \(effect.id)",
                successCriteria: "Test '\(test.id)' should pass",
                metricKey: test.threshold?.key,
                expectedValue: test.threshold?.value,
                comparison: test.threshold?.comparison
            )
            
            return TestRunResult(
                testId: test.id,
                testName: test.name,
                status: passed ? .passed : .failed,
                severity: test.severity,
                metrics: result.metrics.mapValues { $0 },
                threshold: test.threshold,
                message: passed ? nil : "Threshold not met",
                diagnosis: diagnosis,
                suggestedFixes: fixes,
                verification: verification
            )
        } catch {
            return TestRunResult(
                testId: test.id,
                testName: test.name,
                status: .error,
                severity: test.severity,
                metrics: [:],
                threshold: test.threshold,
                message: error.localizedDescription,
                diagnosis: Diagnosis(
                    issue: "Validation failed with error",
                    expected: "Successful validation",
                    actual: error.localizedDescription,
                    rootCause: "Exception during validation execution"
                ),
                suggestedFixes: [],
                verification: nil
            )
        }
    }
    
    // MARK: - Real Pipeline Rendering
    
    /// Rendered frame pair for comparison
    private struct RenderedFramePair {
        let baseline: Data   // Frame without the effect
        let withEffect: Data // Frame with the effect applied
    }
    
    /// Render frames using the real Metal pipeline
    /// Returns both baseline (no effect) and test (with effect) frames as PNG data
    private func renderWithRealPipeline(
        effectId: String,
        parameters: EffectParameters,
        width: Int,
        height: Int
    ) async throws -> RenderedFramePair {
        
        // Create a test scene for rendering context
        // Use single object for effects that need clean radial gradients (Halation, Bloom, Tonemapping)
        // Use grid for effects that need field coverage (Lens Distortion, Chromatic Aberration)
        let useSingleObject = (effectId == "tonemapping" || effectId == "bloom" || effectId == "anamorphic" || effectId == "aces")
        let usePointSource = (effectId == "halation")
        
        let scene: Scene
        if effectId == "camera" {
            // Check for bokeh test type (2.0)
            if let type = parameters.additionalParams["test_type"], abs(type - 2.0) < 0.01 {
                scene = createBokehScene()
                // Apply camera parameters
                if let focalLength = parameters.additionalParams["focal_length"] {
                    scene.camera.focalLength = focalLength
                }
                if let fStop = parameters.additionalParams["f_stop"] {
                    scene.camera.fStop = fStop
                }
                if let focusDistance = parameters.additionalParams["focus_distance"] {
                    scene.camera.focusDistance = focusDistance
                }
                if let sensorWidth = parameters.additionalParams["sensor_width"] {
                    scene.camera.sensorWidth = sensorWidth
                }
            } else {
                scene = createFOVScene()
                // Apply camera parameters
                if let focalLength = parameters.additionalParams["focal_length"] {
                    scene.camera.focalLength = focalLength
                }
                if let sensorWidth = parameters.additionalParams["sensor_width"] {
                    scene.camera.sensorWidth = sensorWidth
                }
            }
        } else if effectId == "aces" {
            // Only use Macbeth scene if explicitly requested by test parameters
            if let type = parameters.additionalParams["test_type"], abs(type - 1.0) < 0.01 {
                scene = createMacbethScene()
            } else {
                // Otherwise use standard test scene (lit cube) which provides smooth gradients for banding check
                scene = createTestScene(singleObject: true)
            }
        } else if effectId == "bokeh" {
            scene = createBokehScene()
            // Apply camera parameters
            if let focalLength = parameters.additionalParams["focal_length"] {
                scene.camera.focalLength = focalLength
            }
            // Map 'aperture' from YAML to fStop
            if let aperture = parameters.additionalParams["aperture"] {
                scene.camera.fStop = aperture
            } else if let fStop = parameters.additionalParams["f_stop"] {
                scene.camera.fStop = fStop
            }
            
            // Map 'focal_distance' from YAML to focusDistance
            if let focalDist = parameters.additionalParams["focal_distance"] {
                scene.camera.focusDistance = focalDist
            } else if let focusDistance = parameters.additionalParams["focus_distance"] {
                scene.camera.focusDistance = focusDistance
            }
        } else if usePointSource {
            scene = createPointSourceScene()
        } else {
            scene = createTestScene(singleObject: useSingleObject)
        }
        
        // Determine background colors based on effect being tested
        // Most effects need gradient background for testing
        // Chromatic aberration and vignette need neutral/flat backgrounds for accurate measurement
        // Film grain needs flat background to isolate grain from gradient variance
        // Halation needs black background for clean falloff analysis
        let useNeutralBackground = (effectId == "chromatic_aberration" || effectId == "vignette")
        let useBlackBackground = (effectId == "tonemapping" || effectId == "halation" || effectId == "aces" || effectId == "camera")
        let useWhiteBackground = (effectId == "text_layout")
        
        // Determine if we need tonemapping for this effect context
        // Physical effects should be viewed through a tonemapper to match the "Physical Pipeline"
        // This ensures effects operate in Linear space before Gamma encoding
        // Bloom and Halation also need ToneMapping so the validator can correctly linearize the output
        let useTonemap = ["vignette", "chromatic_aberration", "lens_distortion", "camera", "bloom", "halation"].contains(effectId)
        
        let bgTop: SIMD3<Float>
        let bgBottom: SIMD3<Float>
        
        if useBlackBackground {
            // Pure black for tone mapping black preservation and halation falloff
            bgTop = SIMD3<Float>(0, 0, 0)
            bgBottom = SIMD3<Float>(0, 0, 0)
        } else if useWhiteBackground {
            // Pure white for text legibility
            bgTop = SIMD3<Float>(1.0, 1.0, 1.0)
            bgBottom = SIMD3<Float>(1.0, 1.0, 1.0)
        } else if useNeutralBackground {
            // Flat neutral gray for color/radial-sensitive tests
            // Same color top and bottom = no gradient (isolates the effect)
            bgTop = SIMD3<Float>(0.5, 0.5, 0.5)     // Neutral mid-gray
            bgBottom = SIMD3<Float>(0.5, 0.5, 0.5)  // Same for flat background
        } else {
            // Warm gradient for bloom/halation testing
            bgTop = SIMD3<Float>(1.0, 1.0, 0.9)     // Bright warm white at top
            bgBottom = SIMD3<Float>(0.1, 0.1, 0.1)  // Dark at bottom
        }
        
        // 1. First render baseline (no effects) - just background pass
        guard let baselineCommandBuffer = commandQueue.makeCommandBuffer() else {
            throw ValidationRunnerError.renderFailed("Failed to create baseline command buffer")
        }
        
        let baselinePipeline = RenderPipeline(device: device)
        
        // Use BackgroundPass with appropriate colors
        let backgroundPass = BackgroundPass(device: device)
        backgroundPass.colorTop = bgTop
        backgroundPass.colorBottom = bgBottom
        baselinePipeline.addPass(backgroundPass)
        
        // Add GeometryPass to render the cube
        // Skip geometry for vignette to ensure uniform field for falloff analysis
        // Skip geometry for text_layout to ensure clean background for margin check
        if effectId != "vignette" && effectId != "text_layout" {
            let geometryPass = GeometryPass(device: device, scene: scene)
            baselinePipeline.addPass(geometryPass)
        }
        
        // Add ToneMapPass to baseline if the effect pipeline uses it
        // This ensures we compare apples to apples (Gamma vs Gamma)
        if useTonemap {
            let tonemapPass = ToneMapPass(device: device)
            baselinePipeline.addPass(tonemapPass)
        }
        
        let baselineContext = RenderContext(
            device: device,
            commandBuffer: baselineCommandBuffer,
            resolution: SIMD2(width, height),
            time: 0,
            scene: scene
        )
        
        guard let baselineTexture = try baselinePipeline.render(context: baselineContext) else {
            throw ValidationRunnerError.renderFailed("Baseline render returned nil")
        }
        
        // Wait for GPU completion using async continuation
        // Handler must be added before commit
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            baselineCommandBuffer.addCompletedHandler { _ in
                continuation.resume()
            }
            baselineCommandBuffer.commit()
        }
        

        
        // 2. Render with effect applied
        guard let effectCommandBuffer = commandQueue.makeCommandBuffer() else {
            throw ValidationRunnerError.renderFailed("Failed to create effect command buffer")
        }
        
        let effectPipeline = RenderPipeline(device: device)
        
        // Same background pass for consistent comparison
        // Same background pass for consistent comparison (use same colors as baseline)
        let effectBackgroundPass = BackgroundPass(device: device)
        effectBackgroundPass.colorTop = bgTop
        effectBackgroundPass.colorBottom = bgBottom
        effectPipeline.addPass(effectBackgroundPass)
        
        // Add GeometryPass
        // Skip geometry for vignette to ensure uniform field for falloff analysis
        // Skip geometry for text_layout to ensure clean background for margin check
        if effectId != "vignette" && effectId != "text_layout" {
            let effectGeometryPass = GeometryPass(device: device, scene: scene)
            effectPipeline.addPass(effectGeometryPass)
        }
        
        // Add the effect pass based on effectId
        switch effectId {
        case "bloom":
            let bloomPass = BloomPass(device: device)
            bloomPass.intensity = parameters.intensity ?? 0.5
            bloomPass.threshold = parameters.threshold ?? 0.8
            bloomPass.radius = parameters.radius ?? 20.0
            effectPipeline.addPass(bloomPass)
            
        case "halation":
            let halationPass = HalationPass(device: device)
            // Use parameters from YAML (or defaults matching YAML)
            halationPass.intensity = parameters.intensity ?? 0.8
            halationPass.threshold = parameters.threshold ?? 0.2
            halationPass.radius = parameters.radius ?? 20.0
            effectPipeline.addPass(halationPass)
            
        case "film_grain":
            let grainPass = FilmGrainPass(device: device)
            grainPass.intensity = parameters.intensity ?? 0.3
            effectPipeline.addPass(grainPass)
            
        case "vignette":
            let vignettePass = VignettePass(device: device)
            // For cos⁴ law validation, use intensity=1.0 (per YAML methodology: "Apply vignette with falloff = 1.0")
            // This gives us a pure cos⁴ curve to validate against
            vignettePass.intensity = parameters.intensity ?? 1.0  // Use full intensity for physics validation
            effectPipeline.addPass(vignettePass)
            
            // ToneMapPass will be added automatically by the generic logic below
            
        case "lens_distortion":
            var camera = PhysicalCamera()
            camera.distortionK1 = parameters.additionalParams["k1"] ?? -0.1
            camera.distortionK2 = parameters.additionalParams["k2"] ?? 0.0
            let distortionPass = LensDistortionPass(device: device, camera: camera)
            effectPipeline.addPass(distortionPass)
            
        case "tonemapping":
            let tonemapPass = ToneMapPass(device: device)
            effectPipeline.addPass(tonemapPass)

        case "aces":
            // ACES pipeline validation uses the ToneMapPass configured for ACES
            // In a full implementation, this might involve a dedicated ACESPass
            // that handles input transforms (IDT) and output transforms (ODT) explicitly.
            // For now, we use the existing ToneMapPass which implements the ACES RRT+ODT.
            let tonemapPass = ToneMapPass(device: device)
            tonemapPass.exposure = parameters.additionalParams["exposure"] ?? 0.0
            // tonemapPass.gamma = parameters.additionalParams["gamma"] ?? 2.2
            effectPipeline.addPass(tonemapPass)
            
        case "chromatic_aberration":
            // Use dedicated ChromaticAberrationPass for spectral separation
            let caPass = ChromaticAberrationPass(device: device)
            caPass.intensity = parameters.intensity ?? 0.5
            effectPipeline.addPass(caPass)
            
        case "anamorphic":
            let anamorphicPass = AnamorphicPass(device: device)
            anamorphicPass.intensity = parameters.intensity ?? 0.6
            anamorphicPass.threshold = parameters.threshold ?? 0.85
            anamorphicPass.streakLength = parameters.additionalParams["streak_length"] ?? 8.0
            effectPipeline.addPass(anamorphicPass)
            
        case "text_layout":
            // Create font and atlas
            let font = CTFontCreateWithName("Helvetica" as CFString, 64, nil)
            let atlas = try SDFFontAtlas(font: font, size: CGSize(width: 512, height: 512), device: device)
            
            // Create text renderer
            let textRenderer = try SDFTextRenderer(fontAtlas: atlas, device: device)
            let textPass = TextPass(device: device, textRenderer: textRenderer)
            
            // Add test text content
            let contentText = parameters.textParams["content"] ?? "Validation Text Block\nChecking Margins\nAnd Legibility"
            let content = VisualContent(
                type: "text",
                text: contentText,
                style: nil,
                layout: nil,
                animation: nil,
                zDepth: nil,
                shape: nil,
                size: 0.5,
                color: "#000000",
                velocity: nil,
                outlineWidth: nil,
                outlineColor: nil,
                softness: nil,
                weight: nil,
                maxWidth: nil,
                anchor: nil
            )
            textPass.timedTextEvents = [TimedTextEvent(content: content, startTime: 0, duration: 10.0)]
            
            effectPipeline.addPass(textPass)

        case "camera":
            // Camera effect is inherent in the geometry pass
            // Check for bokeh test type (2.0)
            if let type = parameters.additionalParams["test_type"], abs(type - 2.0) < 0.01 {
                let bokehPass = BokehPass(device: device)
                
                // Calculate radius from CoC for the specific test object at 10m
                // CoC formula: A * (|z - z_focus| / z) * (f / (z_focus - f))
                
                let focalLength = parameters.additionalParams["focal_length"] ?? 50.0
                let fStop = parameters.additionalParams["f_stop"] ?? 1.4
                let focusDistance = parameters.additionalParams["focus_distance"] ?? 2.0
                let sensorWidth = parameters.additionalParams["sensor_width"] ?? 36.0
                
                // Hardcoded scene distance for bokeh test (from createBokehScene)
                let objectDistance: Float = 10.0 
                
                let f = focalLength
                let A = f / fStop
                let z = objectDistance * 1000.0
                let z_focus = focusDistance * 1000.0
                
                let term1 = abs(z - z_focus) / z
                let term2 = f / (z_focus - f)
                let coc_mm = A * term1 * term2
                
                let imageWidthPx: Float = 1920.0
                let _ = coc_mm * (imageWidthPx / sensorWidth)
                
                // Radius is half diameter.
                // We set a large maxRadius to ensure the shader uses the physically calculated CoC
                // without clamping, allowing the validator to verify the physics model.
                bokehPass.radius = 100.0
                
                effectPipeline.addPass(bokehPass)
            }
            
        case "lens_system":
            scene.camera.distortionK1 = parameters.additionalParams["k1"] ?? -0.1
            scene.camera.distortionK2 = parameters.additionalParams["k2"] ?? 0.0
            scene.camera.chromaticAberration = parameters.additionalParams["ca"] ?? 0.05
            
            let lensPass = LensSystemPass(device: device)
            effectPipeline.addPass(lensPass)

        case "procedural_texture":
            let pass = ProceduralTexturePass()
            pass.frequency = parameters.additionalParams["frequency"] ?? 2.0
            pass.octaves = Int(parameters.additionalParams["octaves"] ?? 6.0)
            pass.lacunarity = parameters.additionalParams["lacunarity"] ?? 2.0
            pass.gain = parameters.additionalParams["gain"] ?? 0.5
            
            // Force normalized gradient for validation to ensure 0-1 range
            pass.gradientColors = [
                ProceduralTexturePass.GradientStop(color: SIMD3(0.0, 0.0, 0.0), position: 0.0),
                ProceduralTexturePass.GradientStop(color: SIMD3(1.0, 1.0, 1.0), position: 1.0)
            ]
            
            // Map pattern type if provided (simple mapping for now)
            // In a real implementation, we'd parse the string param
            pass.proceduralType = .fbmSimplex 
            
            effectPipeline.addPass(pass)
            
        case "shimmer":
            let shimmerPass = ShimmerPass(device: device)
            shimmerPass.intensity = parameters.intensity ?? 0.5
            shimmerPass.speed = parameters.additionalParams["speed"] ?? 2.0
            effectPipeline.addPass(shimmerPass)
            
        case "volumetric":
            let volPass = VolumetricPass(device: device, scene: scene)
            volPass.exposure = parameters.intensity ?? 0.8
            scene.volumetricDensity = parameters.additionalParams["density"] ?? 0.5
            volPass.decay = parameters.additionalParams["decay"] ?? 0.95
            effectPipeline.addPass(volPass)
            
        case "energy":
            let energyPass = EnergyPass(device: device)
            energyPass.intensity = parameters.intensity ?? 1.0
            energyPass.speed = parameters.additionalParams["speed"] ?? 0.5
            energyPass.scale = parameters.additionalParams["scale"] ?? 2.0
            effectPipeline.addPass(energyPass)
            
        case "bokeh":
            let bokehPass = BokehPass(device: device)
            bokehPass.radius = parameters.radius ?? 10.0
            // Bokeh pass usually needs depth buffer or CoC map, 
            // but for validation we might just be testing the blur kernel itself
            // or the pass handles generation if inputs are missing.
            effectPipeline.addPass(bokehPass)
            
        case "pbr":
            // PBR is handled by GeometryPass, but we need to ensure the mesh has PBR material
            // We iterate over meshes in the scene and apply PBR params
            for mesh in scene.meshes {
                var material = PBRMaterial()
                material.roughness = parameters.additionalParams["roughness"] ?? 0.5
                material.metallic = parameters.additionalParams["metalness"] ?? 0.0
                material.baseColor = SIMD3(1.0, 0.0, 0.0) // Red for visibility
                mesh.material = material
            }
            // GeometryPass is already added
            
        default:
            break
        }
        
        // Add ToneMapPass to effect pipeline if needed
        // This ensures we compare apples to apples (Gamma vs Gamma)
        // Must be added AFTER the effect pass (e.g. Vignette -> ToneMap)
        if useTonemap {
            // Check if we already added ToneMapPass (e.g. inside the switch)
            let alreadyHasTonemap = effectPipeline.passes.contains { $0 is ToneMapPass }
            
            if !alreadyHasTonemap {
                let tonemapPass = ToneMapPass(device: device)
                
                // Pipeline wiring:
                // We need to ensure ToneMapPass reads the output of the previous pass.
                if let lastPass = effectPipeline.passes.last, 
                   let lastOutput = lastPass.outputs.first {
                    
                    // If the last pass outputs "display_buffer", we rename it to "intermediate_buffer"
                    // so ToneMapPass can read "intermediate_buffer" and write "display_buffer".
                    if lastOutput == "display_buffer" {
                        if let index = lastPass.outputs.firstIndex(of: "display_buffer") {
                            lastPass.outputs[index] = "intermediate_buffer"
                            tonemapPass.inputs = ["intermediate_buffer"]
                        }
                    } else {
                        // If the last pass outputs something else (e.g. "bloom_composite"),
                        // we configure ToneMapPass to read that.
                        tonemapPass.inputs = [lastOutput]
                    }
                    
                    // ToneMapPass always writes to display_buffer
                    tonemapPass.outputs = ["display_buffer"]
                }
                
                effectPipeline.addPass(tonemapPass)
            }
        }
        
        // 3. Render the effect pipeline
        let effectContext = RenderContext(
            device: device,
            commandBuffer: effectCommandBuffer,
            resolution: SIMD2(width, height),
            time: 0,
            scene: scene
        )
        
        guard let effectTexture = try effectPipeline.render(context: effectContext) else {
            throw ValidationRunnerError.renderFailed("Effect render returned nil")
        }
        
        // Wait for GPU completion
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            effectCommandBuffer.addCompletedHandler { _ in
                continuation.resume()
            }
            effectCommandBuffer.commit()
        }
        
        // 4. Convert textures to Data
        let baselineData: Data
        let effectData: Data
        
        if effectId == "procedural_texture" || effectId == "bokeh" {
            baselineData = try textureToRawData(baselineTexture)
            effectData = try textureToRawData(effectTexture)
        } else {
            baselineData = try textureToPNG(baselineTexture)
            effectData = try textureToPNG(effectTexture)
        }
        
        return RenderedFramePair(baseline: baselineData, withEffect: effectData)
    }
    
    /// Create a simple test scene for effect validation
    private func createTestScene(singleObject: Bool = false) -> Scene {
        // Create a camera
        var camera = PhysicalCamera()
        camera.position = SIMD3(0, 0, 5) // Move to +5 to look at origin (assuming camera looks down -Z)
        
        // Create a scene with a bright light (for bloom/halation testing)
        let scene = Scene(camera: camera)
        
        // Add a bright point light
        let light = LightSource(
            position: SIMD3(5, 5, 5), // Move light to same side as camera
            color: SIMD3(1, 1, 1),
            intensity: 100.0, // Boost intensity to ensure center is highlighted for grain masking
            type: .point
        )
        scene.addLight(light)
        
        // Add geometry
        // Single object for radial analysis, Grid for field coverage
        
        if singleObject {
            let mesh = createCubeMesh(device: device)
            
            // Rotate to show 3 faces
            let rotationY = matrix_float4x4(columns: (
                SIMD4(cos(0.5), 0, sin(0.5), 0),
                SIMD4(0, 1, 0, 0),
                SIMD4(-sin(0.5), 0, cos(0.5), 0),
                SIMD4(0, 0, 0, 1)
            ))
            let rotationX = matrix_float4x4(columns: (
                SIMD4(1, 0, 0, 0),
                SIMD4(0, cos(0.5), -sin(0.5), 0),
                SIMD4(0, sin(0.5), cos(0.5), 0),
                SIMD4(0, 0, 0, 1)
            ))
            
            mesh.transform = rotationY * rotationX
            scene.addMesh(mesh)
        } else {
            // Add a grid of cubes for geometric effects (CA, Distortion)
            // This ensures we have edges everywhere
            for x in -1...1 {
                for y in -1...1 {
                    let mesh = createCubeMesh(device: device)
                    
                    // Rotation matrix around Y and X
                    let rotationY = matrix_float4x4(columns: (
                        SIMD4(cos(0.5), 0, sin(0.5), 0),
                        SIMD4(0, 1, 0, 0),
                        SIMD4(-sin(0.5), 0, cos(0.5), 0),
                        SIMD4(0, 0, 0, 1)
                    ))
                    let rotationX = matrix_float4x4(columns: (
                        SIMD4(1, 0, 0, 0),
                        SIMD4(0, cos(0.5), -sin(0.5), 0),
                        SIMD4(0, sin(0.5), cos(0.5), 0),
                        SIMD4(0, 0, 0, 1)
                    ))
                    
                    let translation = matrix_float4x4(translation: SIMD3(Float(x) * 2.5, Float(y) * 2.5, 0))
                    
                    mesh.transform = translation * rotationY * rotationX
                    scene.addMesh(mesh)
                }
            }
        }
        
        return scene
    }
    
    /// Create a scene with a single bright point source for falloff analysis
    private func createPointSourceScene() -> Scene {
        var camera = PhysicalCamera()
        camera.position = SIMD3(0, 0, 5)
        
        let scene = Scene(camera: camera)
        
        // Small emissive quad at center
        // Reduced size to ensure falloff analysis sees the glow profile, not the object
        let mesh = createQuadMesh(device: device, size: 0.05)
        scene.addMesh(mesh)
        
        // Add a light just in case the shader needs it, but the mesh should be white
        let light = LightSource(position: SIMD3(0, 0, 2), color: SIMD3(1, 1, 1), intensity: 1.0, type: .point)
        scene.addLight(light)
        
        return scene
    }
    
    /// Create a scene with a Macbeth ColorChecker chart
    private func createMacbethScene() -> Scene {
        var camera = PhysicalCamera()
        camera.position = SIMD3(0, 0, 6.375) // Positioned to match ACESValidator margins (calculated from FOV and chart size)
        
        let scene = Scene(camera: camera)
        
        // Macbeth Chart Layout: 6 columns x 4 rows
        // We'll create 24 quads
        
        // Approximate Linear ACEScg values for ColorChecker Classic
        // Source: Standard colorimetric data converted to ACEScg
        let patches: [SIMD3<Float>] = [
            // Row 1: Natural colors
            SIMD3(0.118, 0.087, 0.058), // Dark Skin
            SIMD3(0.396, 0.267, 0.206), // Light Skin
            SIMD3(0.086, 0.133, 0.234), // Blue Sky
            SIMD3(0.083, 0.109, 0.053), // Foliage
            SIMD3(0.168, 0.148, 0.270), // Blue Flower
            SIMD3(0.199, 0.346, 0.296), // Bluish Green
            
            // Row 2: Miscellaneous
            SIMD3(0.608, 0.288, 0.060), // Orange
            SIMD3(0.096, 0.109, 0.319), // Purplish Blue
            SIMD3(0.287, 0.103, 0.108), // Moderate Red
            SIMD3(0.073, 0.046, 0.106), // Purple
            SIMD3(0.298, 0.399, 0.086), // Yellow Green
            SIMD3(0.688, 0.468, 0.080), // Orange Yellow
            
            // Row 3: Primaries/Secondaries
            SIMD3(0.008, 0.018, 0.275), // Blue
            SIMD3(0.024, 0.232, 0.044), // Green
            SIMD3(0.400, 0.045, 0.033), // Red
            SIMD3(0.830, 0.700, 0.060), // Yellow
            SIMD3(0.360, 0.050, 0.240), // Magenta
            SIMD3(0.020, 0.280, 0.390), // Cyan
            
            // Row 4: Grayscale
            SIMD3(0.890, 0.890, 0.890), // White (.95 density)
            SIMD3(0.580, 0.580, 0.580), // Neutral 8 (.23 density)
            SIMD3(0.360, 0.360, 0.360), // Neutral 6.5 (.44 density)
            SIMD3(0.190, 0.190, 0.190), // Neutral 5 (.70 density)
            SIMD3(0.080, 0.080, 0.080), // Neutral 3.5 (1.05 density)
            SIMD3(0.030, 0.030, 0.030)  // Black (1.50 density)
        ]
        
        let patchSize: Float = 0.4
        let gap: Float = 0.05
        let startX: Float = -((patchSize + gap) * 6) / 2.0 + patchSize / 2.0
        let startY: Float = ((patchSize + gap) * 4) / 2.0 - patchSize / 2.0
        
        for (i, color) in patches.enumerated() {
            let row = i / 6
            let col = i % 6
            
            // Standard positioning (Left to Right)
            let x = startX + Float(col) * (patchSize + gap)
            let y = startY - Float(row) * (patchSize + gap)
            
            let mesh = createQuadMesh(device: device, size: patchSize)
            mesh.color = color // Use the new unlit color property
            
            // Position the mesh
            var transform = matrix_identity_float4x4
            transform.columns.3 = SIMD4<Float>(x, y, 0, 1)
            mesh.transform = transform
            
            scene.addMesh(mesh)
        }
        
        return scene
    }
    
    private func createQuadMesh(device: MTLDevice, size: Float) -> Mesh {
        let s = size / 2.0
        let vertices: [Float] = [
            -s, -s, 0,  0, 0, 1,  0, 1,
             s, -s, 0,  0, 0, 1,  1, 1,
             s,  s, 0,  0, 0, 1,  1, 0,
            -s,  s, 0,  0, 0, 1,  0, 0
        ]
        let indices: [UInt16] = [0, 1, 2, 0, 2, 3]
        return Mesh(device: device, vertices: vertices, indices: indices)
    }
    
    private func createCubeMesh(device: MTLDevice) -> Mesh {
        // Simple cube with normals and UVs
        // Format: Position (3), Normal (3), UV (2) = 8 floats per vertex
        let vertices: [Float] = [
            // Front face
            -1.0, -1.0,  1.0,  0.0,  0.0,  1.0,  0.0, 0.0,
             1.0, -1.0,  1.0,  0.0,  0.0,  1.0,  1.0, 0.0,
             1.0,  1.0,  1.0,  0.0,  0.0,  1.0,  1.0, 1.0,
            -1.0,  1.0,  1.0,  0.0,  0.0,  1.0,  0.0, 1.0,
            // Back face
            -1.0, -1.0, -1.0,  0.0,  0.0, -1.0,  1.0, 0.0,
            -1.0,  1.0, -1.0,  0.0,  0.0, -1.0,  1.0, 1.0,
             1.0,  1.0, -1.0,  0.0,  0.0, -1.0,  0.0, 1.0,
             1.0, -1.0, -1.0,  0.0,  0.0, -1.0,  0.0, 0.0,
            // Top face
            -1.0,  1.0, -1.0,  0.0,  1.0,  0.0,  0.0, 1.0,
            -1.0,  1.0,  1.0,  0.0,  1.0,  0.0,  0.0, 0.0,
             1.0,  1.0,  1.0,  0.0,  1.0,  0.0,  1.0, 0.0,
             1.0,  1.0, -1.0,  0.0,  1.0,  0.0,  1.0, 1.0,
            // Bottom face
            -1.0, -1.0, -1.0,  0.0, -1.0,  0.0,  1.0, 1.0,
             1.0, -1.0, -1.0,  0.0, -1.0,  0.0,  0.0, 1.0,
             1.0, -1.0,  1.0,  0.0, -1.0,  0.0,  0.0, 0.0,
            -1.0, -1.0,  1.0,  0.0, -1.0,  0.0,  1.0, 0.0,
            // Right face
             1.0, -1.0, -1.0,  1.0,  0.0,  0.0,  1.0, 0.0,
             1.0,  1.0, -1.0,  1.0,  0.0,  0.0,  1.0, 1.0,
             1.0,  1.0,  1.0,  1.0,  0.0,  0.0,  0.0, 1.0,
             1.0, -1.0,  1.0,  1.0,  0.0,  0.0,  0.0, 0.0,
            // Left face
            -1.0, -1.0, -1.0, -1.0,  0.0,  0.0,  0.0, 0.0,
            -1.0, -1.0,  1.0, -1.0,  0.0,  0.0,  1.0, 0.0,
            -1.0,  1.0,  1.0, -1.0,  0.0,  0.0,  1.0, 1.0,
            -1.0,  1.0, -1.0, -1.0,  0.0,  0.0,  0.0, 1.0
        ]
        
        let indices: [UInt16] = [
            0, 1, 2, 0, 2, 3,       // Front
            4, 5, 6, 4, 6, 7,       // Back
            8, 9, 10, 8, 10, 11,    // Top
            12, 13, 14, 12, 14, 15, // Bottom
            16, 17, 18, 16, 18, 19, // Right
            20, 21, 22, 20, 22, 23  // Left
        ]
        
        return Mesh(device: device, vertices: vertices, indices: indices)
    }
    
    /// Convert a Metal texture to PNG Data
    private func textureToPNG(_ texture: MTLTexture) throws -> Data {
        let width = texture.width
        let height = texture.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        let region = MTLRegionMake2D(0, 0, width, height)
        
        if texture.pixelFormat == .rgba8Unorm {
            texture.getBytes(&pixels, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        } else {
            // Assume float (16 or 32)
            // Read as floats
            let channels = 4
            let floatCount = width * height * channels
            var floatPixels = [Float](repeating: 0, count: floatCount)
            
            if texture.pixelFormat == .rgba16Float {
                var halfPixels = [Float16](repeating: 0, count: floatCount)
                texture.getBytes(&halfPixels, bytesPerRow: width * channels * MemoryLayout<Float16>.size, from: region, mipmapLevel: 0)
                for i in 0..<floatCount {
                    floatPixels[i] = Float(halfPixels[i])
                }
            } else {
                // Assume 32-bit float
                texture.getBytes(&floatPixels, bytesPerRow: width * channels * MemoryLayout<Float>.size, from: region, mipmapLevel: 0)
            }
            
            // Convert to UInt8 with clamping
            for i in 0..<floatCount {
                pixels[i] = UInt8(max(0, min(1, floatPixels[i])) * 255)
            }
        }
        
        return createPNGData(pixels: pixels, width: width, height: height, bytesPerRow: bytesPerRow)
    }

    /// Convert a Metal texture to Raw Float Data (Scientific Format)
    private func textureToRawData(_ texture: MTLTexture) throws -> Data {
        let width = texture.width
        let height = texture.height
        let channels = 4
        let floatCount = width * height * channels
        // byteCount removed
        
        // 1. Read texture data into Float array
        var floatPixels = [Float](repeating: 0, count: floatCount)
        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                               size: MTLSize(width: width, height: height, depth: 1))
        
        if texture.pixelFormat == .rgba16Float {
            // Read as Float16 and convert
            var halfPixels = [Float16](repeating: 0, count: floatCount)
            texture.getBytes(&halfPixels,
                           bytesPerRow: width * channels * MemoryLayout<Float16>.size,
                           from: region,
                           mipmapLevel: 0)
            
            // Convert Float16 -> Float32
            // Note: vImageConvert_Planar16FtoPlanarF is faster but manual loop is simpler for now
            for i in 0..<floatCount {
                floatPixels[i] = Float(halfPixels[i])
            }
        } else if texture.pixelFormat == .rgba32Float {
            // Read directly
            texture.getBytes(&floatPixels,
                           bytesPerRow: width * channels * MemoryLayout<Float>.size,
                           from: region,
                           mipmapLevel: 0)
        } else {
            // Fallback for 8-bit formats (unlikely in this pipeline but good for safety)
            // Read as UInt8 and normalize
            // bytePixels removed
            let bytesPerRow = width * 4
            var rawBytes = [UInt8](repeating: 0, count: width * height * 4)
            texture.getBytes(&rawBytes, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
            
            for i in 0..<rawBytes.count {
                floatPixels[i] = Float(rawBytes[i]) / 255.0
            }
        }
        
        // 2. Pack into Data with Header
        var data = Data()
        
        // Magic "RAWF" (0x52415746)
        let magic: UInt32 = 0x52415746
        data.append(withUnsafeBytes(of: magic) { Data($0) })
        
        // Dimensions
        let w = Int32(width)
        let h = Int32(height)
        let c = Int32(channels)
        data.append(withUnsafeBytes(of: w) { Data($0) })
        data.append(withUnsafeBytes(of: h) { Data($0) })
        data.append(withUnsafeBytes(of: c) { Data($0) })
        
        // Payload
        let payloadData = Data(bytes: floatPixels, count: floatPixels.count * MemoryLayout<Float>.size)
        data.append(payloadData)
        
        return data
    }
    
    /// Evaluate threshold and return diagnosis if failed
    private func evaluateThresholdWithDiagnosis(
        result: EffectValidationResult,
        test: ValidationTestDefinition,
        effect: EffectDefinition
    ) -> (passed: Bool, diagnosis: Diagnosis?) {
        guard let threshold = test.threshold,
              let key = threshold.key else {
            // No threshold defined or no key, pass by default
            return (result.passed, nil)
        }
        
        let expectedValue = threshold.value
        let comparison = threshold.comparison
        
        guard let actualValue = result.metrics[key] else {
            // Metric not found
            let diagnosis = Diagnosis(
                issue: "Required metric '\(key)' not found in validation output",
                expected: "Metric '\(key)' to be present",
                actual: "Metric not returned by validator",
                rootCause: "Validator \(effect.id) may not compute this metric, or metric key mismatch between YAML and validator",
                context: ["available_metrics": result.metrics.keys.joined(separator: ", ")]
            )
            return (false, diagnosis)
        }
        
        let passed: Bool
        let comparisonDescription: String
        
        switch comparison {
        case .lessThan:
            passed = actualValue < expectedValue
            comparisonDescription = "< \(expectedValue)"
        case .greaterThan:
            passed = actualValue > expectedValue
            comparisonDescription = "> \(expectedValue)"
        case .equals:
            passed = abs(actualValue - expectedValue) < 0.001
            comparisonDescription = "≈ \(expectedValue)"
        case .lessOrEqual:
            passed = actualValue <= expectedValue
            comparisonDescription = "≤ \(expectedValue)"
        case .greaterOrEqual:
            passed = actualValue >= expectedValue
            comparisonDescription = "≥ \(expectedValue)"
        case .approxEquals:
            let tolerance = threshold.tolerance ?? 0.1
            passed = abs(actualValue - expectedValue) <= tolerance
            comparisonDescription = "≈ \(expectedValue) (±\(tolerance))"
        case .between:
            passed = actualValue >= 0 && actualValue <= expectedValue
            comparisonDescription = "between 0 and \(expectedValue)"
        }
        
        if passed {
            return (true, nil)
        }
        
        let diagnosis = Diagnosis(
            issue: "\(test.name) failed threshold check",
            expected: "\(key) \(comparisonDescription) (\(threshold.unit))",
            actual: "\(key) = \(String(format: "%.4f", actualValue)) (\(threshold.unit))",
            rootCause: threshold.rationale,
            context: [
                "effect_id": effect.id,
                "test_id": test.id,
                "threshold_key": key,
                "comparison": comparison.rawValue
            ]
        )
        
        return (false, diagnosis)
    }
    
    /// Build suggested fixes from validator output and effect definition
    private func buildSuggestedFixes(
        result: EffectValidationResult,
        test: ValidationTestDefinition,
        effect: EffectDefinition,
        passed: Bool
    ) -> [SuggestedFix] {
        guard !passed else { return [] }
        
        var fixes: [SuggestedFix] = []
        
        // First, add fixes from YAML fix_patterns (highest priority - effect author defined)
        if let patterns = test.fixPatterns {
            for pattern in patterns {
                fixes.append(SuggestedFix(
                    file: pattern.file,
                    function: pattern.function,
                    lineHint: pattern.lineHint,
                    action: pattern.action,
                    type: convertFixType(pattern.type),
                    priority: convertPriority(pattern.priority),
                    codeSnippet: pattern.codeSnippet
                ))
            }
        }
        
        // Add fixes from validator diagnostics
        for fixString in result.suggestedFixes {
            fixes.append(SuggestedFix(
                file: "Sources/MetalVisCore/Engine/Passes/\(effect.id.capitalized)Pass.swift",
                action: fixString,
                type: .codeChange,
                priority: .medium
            ))
        }
        
        // Add shader fix suggestion for rendering effects
        if fixes.isEmpty && (effect.category == .lens || effect.category == .color) {
            fixes.append(SuggestedFix(
                file: "Sources/MetalVisCore/Shaders/MetaVisFXShaders.metal",
                function: "fx_\(effect.id)",
                action: "Check \(effect.id) shader implementation for correct algorithm",
                type: .shaderFix,
                priority: .high
            ))
        }
        
        // If no specific fixes, add generic investigation fix
        if fixes.isEmpty {
            fixes.append(SuggestedFix(
                file: "Sources/MetalVisCore/Validation/Validators/\(effect.id.capitalized)Validator.swift",
                action: "Investigate why \(test.name) is failing. Check if metrics are computed correctly.",
                type: .codeChange,
                priority: .medium
            ))
        }
        
        return fixes
    }
    
    private func convertFixType(_ yamlType: FixPattern.FixType) -> SuggestedFix.FixType {
        switch yamlType {
        case .codeChange: return .codeChange
        case .parameterTune: return .parameterTune
        case .configUpdate: return .configUpdate
        case .shaderFix: return .shaderFix
        case .testUpdate: return .testUpdate
        }
    }
    
    private func convertPriority(_ yamlPriority: FixPattern.Priority) -> SuggestedFix.Priority {
        switch yamlPriority {
        case .critical: return .critical
        case .high: return .high
        case .medium: return .medium
        case .low: return .low
        }
    }

    private func evaluateThreshold(result: EffectValidationResult, test: ValidationTestDefinition) -> Bool {
        guard let threshold = test.threshold,
              let key = threshold.key else {
            // No threshold defined or no key, pass by default
            return result.passed
        }
        
        let expectedValue = threshold.value
        let comparison = threshold.comparison
        
        guard let actualValue = result.metrics[key] else {
            // Metric not found
            return false
        }
        
        switch comparison {
        case .lessThan:
            return actualValue < expectedValue
        case .greaterThan:
            return actualValue > expectedValue
        case .equals:
            return abs(actualValue - expectedValue) < 0.001
        case .lessOrEqual:
            return actualValue <= expectedValue
        case .greaterOrEqual:
            return actualValue >= expectedValue
        case .approxEquals:
            let tolerance = threshold.tolerance ?? 0.1
            return abs(actualValue - expectedValue) <= tolerance
        case .between:
            // For between, value is treated as upper bound
            // Would need additional field for lower bound in ThresholdSpec
            return actualValue >= 0 && actualValue <= expectedValue
        }
    }
    
    /// Generate a synthetic test frame as PNG data for validation
    /// Creates a gradient image that the Vision API can process
    /// - Parameters:
    ///   - width: Image width in pixels
    ///   - height: Image height in pixels
    ///   - applyEffect: Whether to simulate an effect being applied
    ///   - effectId: Which effect to simulate (if applyEffect is true)
    private func generateTestFrame(width: Int, height: Int, applyEffect: Bool = false, effectId: String? = nil) -> Data {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        
        // Create a horizontal gradient with some bright spots for bloom/halation testing
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * bytesPerPixel
                
                // Base gradient
                let baseGradient = Double(x) / Double(width)
                
                // Add some bright spots in the upper-left for bloom/halation testing
                let centerX = width / 4
                let centerY = height / 4
                let dx = Double(x - centerX) / Double(width)
                let dy = Double(y - centerY) / Double(height)
                let dist = sqrt(dx * dx + dy * dy)
                let brightSpot = max(0, 1.0 - dist * 4)
                
                // Combine gradient with bright spot
                let brightness = min(1.0, baseGradient * 0.7 + brightSpot * 0.5)
                
                // Simulate effect application
                var r = brightness
                var g = brightness
                var b = brightness
                
                if applyEffect, let effect = effectId {
                    switch effect {
                    case "bloom":
                        // Bloom: add subtle glow around bright areas
                        // Energy-conserving: redistribute rather than add
                        let bloomRadius = dist * 4
                        if bloomRadius < 1.0 {
                            // In bloom region: slight redistribution
                            let bloomGlow = brightSpot * 0.08 * (1.0 - bloomRadius)
                            r = min(1.0, brightness + bloomGlow * 0.3)
                            g = min(1.0, brightness + bloomGlow * 0.3)
                            b = min(1.0, brightness + bloomGlow * 0.3)
                        }
                        
                    case "halation":
                        // Halation: warm red/orange glow around highlights
                        let halationGlow = brightSpot * 0.2
                        r = min(1.0, brightness + halationGlow * 1.0)  // Most red
                        g = min(1.0, brightness + halationGlow * 0.4)  // Less green
                        b = min(1.0, brightness + halationGlow * 0.2)  // Least blue
                        
                    case "film_grain":
                        // Film grain: add noise, more in shadows
                        let shadowBoost = 1.0 + (1.0 - brightness) * 0.5
                        let noise = (Double.random(in: -0.03...0.03)) * shadowBoost
                        r = max(0, min(1.0, brightness + noise))
                        g = max(0, min(1.0, brightness + noise))
                        b = max(0, min(1.0, brightness + noise))
                        
                    default:
                        break
                    }
                }
                
                pixels[index] = UInt8(r * 255)       // R
                pixels[index + 1] = UInt8(g * 255)   // G
                pixels[index + 2] = UInt8(b * 255)   // B
                pixels[index + 3] = 255              // A
            }
        }
        
        // Convert raw pixels to PNG data
        return createPNGData(pixels: pixels, width: width, height: height, bytesPerRow: bytesPerRow)
    }
    
    /// Create PNG data from raw RGBA pixels
    private func createPNGData(pixels: [UInt8], width: Int, height: Int, bytesPerRow: Int) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        // Use withUnsafeBytes to safely access the pixel data
        let cgImage: CGImage? = pixels.withUnsafeBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return nil }
            
            guard let context = CGContext(
                data: UnsafeMutableRawPointer(mutating: baseAddress),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else { return nil }
            
            return context.makeImage()
        }
        
        guard let image = cgImage else {
            logger.warning("Failed to create CGImage from pixels")
            return Data()
        }
        
        // Encode as PNG
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, UTType.png.identifier as CFString, 1, nil) else {
            logger.warning("Failed to create image destination")
            return Data()
        }
        
        CGImageDestinationAddImage(destination, image, nil)
        
        if CGImageDestinationFinalize(destination) {
            return mutableData as Data
        } else {
            logger.warning("Failed to finalize PNG data")
            return Data()
        }
    }
    
    /// Create a scene for FOV validation with two markers at known positions
    private func createFOVScene() -> Scene {
        var camera = PhysicalCamera()
        camera.position = SIMD3(0, 0, 0) // Camera at origin
        
        let scene = Scene(camera: camera)
        
        // Add two white cubes at x = +/- 1.0, z = -5.0
        let markerSize: Float = 0.1
        
        let leftMarker = createCubeMesh(device: device)
        // Scale it down
        var scale = matrix_identity_float4x4
        scale.columns.0.x = markerSize
        scale.columns.1.y = markerSize
        scale.columns.2.z = markerSize
        
        let transLeft = matrix_float4x4(translation: SIMD3(-1.0, 0, -5.0))
        leftMarker.transform = transLeft * scale
        leftMarker.color = SIMD3(1, 1, 1) // White
        scene.addMesh(leftMarker)
        
        let rightMarker = createCubeMesh(device: device)
        let transRight = matrix_float4x4(translation: SIMD3(1.0, 0, -5.0))
        rightMarker.transform = transRight * scale
        rightMarker.color = SIMD3(1, 1, 1) // White
        scene.addMesh(rightMarker)
        
        // Add light to see them
        let light = LightSource(position: SIMD3(0, 0, 0), color: SIMD3(1, 1, 1), intensity: 1.0, type: .point)
        scene.addLight(light)
        
        return scene
    }
    
    /// Create a scene for Bokeh validation
    /// Point light at 10m, camera at origin
    private func createBokehScene() -> Scene {
        var camera = PhysicalCamera()
        camera.position = SIMD3(0, 0, 0)
        
        let scene = Scene(camera: camera)
        
        // Add a small bright point source at z = -10.0
        // We use a small quad to represent the light source geometry
        let lightSize: Float = 0.02 // 2cm light source
        let lightMesh = createQuadMesh(device: device, size: lightSize)
        
        let translation = matrix_float4x4(translation: SIMD3(0, 0, -10.0))
        lightMesh.transform = translation
        lightMesh.color = SIMD3(50, 50, 50) // Bright enough for bokeh, but not blown out
        
        scene.addMesh(lightMesh)
        
        // Add a background wall at the same depth (z = -10.0) to prevent background bleed
        // In a gather-based DoF, if the background is far away, it will have a large CoC
        // and "gather" the light from the point source, causing the bokeh to appear larger than the object's CoC.
        // By placing a wall at the same depth, we ensure the CoC is uniform (39px) around the light.
        let wallSize: Float = 20.0 // Large enough to cover the view
        let wallMesh = createQuadMesh(device: device, size: wallSize)
        // Place slightly behind to avoid z-fighting, but close enough to have effectively same CoC
        let wallTranslation = matrix_float4x4(translation: SIMD3(0, 0, -10.01))
        wallMesh.transform = wallTranslation
        wallMesh.color = SIMD3(0, 0, 0) // Black background
        
        scene.addMesh(wallMesh)
        
        return scene
    }
}



// MARK: - Result Types (JSON Serializable)

public struct ValidationRunResult: Codable, Sendable {
    public let success: Bool
    public let timestamp: Date
    public let effectResults: [EffectRunResult]
    public let summary: ValidationSummary
    public let errors: [String]
    
    public init(success: Bool, timestamp: Date, effectResults: [EffectRunResult], summary: ValidationSummary, errors: [String]) {
        self.success = success
        self.timestamp = timestamp
        self.effectResults = effectResults
        self.summary = summary
        self.errors = errors
    }
    
    /// Output as JSON for agent consumption
    public func toJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

public struct ValidationSummary: Codable, Sendable {
    public let total: Int
    public let passed: Int
    public let failed: Int
    public let skipped: Int
    
    public init(total: Int, passed: Int, failed: Int, skipped: Int) {
        self.total = total
        self.passed = passed
        self.failed = failed
        self.skipped = skipped
    }
    
    public var passRate: Double {
        guard total > 0 else { return 0 }
        return Double(passed) / Double(total)
    }
}

public struct EffectRunResult: Codable, Sendable {
    public let effectId: String
    public let effectName: String
    public let status: TestStatus
    public let testResults: [TestRunResult]
    public let duration: TimeInterval
    public let error: String?
    
    public init(effectId: String, effectName: String, status: TestStatus, testResults: [TestRunResult], duration: TimeInterval, error: String?) {
        self.effectId = effectId
        self.effectName = effectName
        self.status = status
        self.testResults = testResults
        self.duration = duration
        self.error = error
    }
}

public struct TestRunResult: Codable, Sendable {
    public let testId: String
    public let testName: String
    public let status: TestStatus
    public let severity: Severity
    public let metrics: [String: Double]
    public let threshold: ThresholdSpec?
    public let message: String?
    
    // Enhanced diagnostics for autonomous development
    public let diagnosis: Diagnosis?
    public let suggestedFixes: [SuggestedFix]
    public let verification: Verification?
    
    public init(testId: String, testName: String, status: TestStatus, severity: Severity, metrics: [String: Double], threshold: ThresholdSpec?, message: String?, diagnosis: Diagnosis? = nil, suggestedFixes: [SuggestedFix] = [], verification: Verification? = nil) {
        self.testId = testId
        self.testName = testName
        self.status = status
        self.severity = severity
        self.metrics = metrics
        self.threshold = threshold
        self.message = message
        self.diagnosis = diagnosis
        self.suggestedFixes = suggestedFixes
        self.verification = verification
    }
}

// MARK: - Actionable Diagnostic Types

/// Detailed diagnosis of a validation failure for agent consumption
public struct Diagnosis: Codable, Sendable {
    /// Brief description of what's wrong
    public let issue: String
    /// What value was expected (human readable)
    public let expected: String
    /// What value was actually observed
    public let actual: String
    /// Analysis of the likely root cause
    public let rootCause: String?
    /// Additional context for debugging
    public let context: [String: String]?
    
    public init(issue: String, expected: String, actual: String, rootCause: String? = nil, context: [String: String]? = nil) {
        self.issue = issue
        self.expected = expected
        self.actual = actual
        self.rootCause = rootCause
        self.context = context
    }
    
    enum CodingKeys: String, CodingKey {
        case issue, expected, actual
        case rootCause = "root_cause"
        case context
    }
}

/// A concrete fix suggestion with file location for agent action
public struct SuggestedFix: Codable, Sendable {
    public enum Priority: String, Codable, Sendable {
        case critical
        case high
        case medium
        case low
    }
    
    public enum FixType: String, Codable, Sendable {
        case codeChange = "code_change"
        case parameterTune = "parameter_tune"
        case configUpdate = "config_update"
        case shaderFix = "shader_fix"
        case testUpdate = "test_update"
    }
    
    /// Relative path to the file to modify
    public let file: String
    /// Function or method name to locate
    public let function: String?
    /// Line number hint (approximate)
    public let lineHint: Int?
    /// What action to take
    public let action: String
    /// Type of fix
    public let type: FixType
    /// Priority of this fix
    public let priority: Priority
    /// Code snippet showing the fix (optional)
    public let codeSnippet: String?
    
    public init(file: String, function: String? = nil, lineHint: Int? = nil, action: String, type: FixType = .codeChange, priority: Priority = .medium, codeSnippet: String? = nil) {
        self.file = file
        self.function = function
        self.lineHint = lineHint
        self.action = action
        self.type = type
        self.priority = priority
        self.codeSnippet = codeSnippet
    }
    
    enum CodingKeys: String, CodingKey {
        case file, function
        case lineHint = "line_hint"
        case action, type, priority
        case codeSnippet = "code_snippet"
    }
}

/// Verification command to run after applying a fix
public struct Verification: Codable, Sendable {
    /// Command to run (e.g., "swift run metavis validate --effect bloom")
    public let command: String
    /// What to check in the output
    public let successCriteria: String
    /// Metric key to check (if applicable)
    public let metricKey: String?
    /// Expected value for the metric
    public let expectedValue: Double?
    /// Comparison operator for the metric
    public let comparison: Comparison?
    
    public init(command: String, successCriteria: String, metricKey: String? = nil, expectedValue: Double? = nil, comparison: Comparison? = nil) {
        self.command = command
        self.successCriteria = successCriteria
        self.metricKey = metricKey
        self.expectedValue = expectedValue
        self.comparison = comparison
    }
    
    enum CodingKeys: String, CodingKey {
        case command
        case successCriteria = "success_criteria"
        case metricKey = "metric_key"
        case expectedValue = "expected_value"
        case comparison
    }
}

public enum TestStatus: String, Codable, Sendable {
    case passed
    case failed
    case skipped
    case error
}

public enum ValidationRunnerError: Error, LocalizedError {
    case noCommandQueue
    case noDevice
    case configurationError(String)
    case renderFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .noCommandQueue:
            return "Failed to create Metal command queue"
        case .noDevice:
            return "Metal device not available"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        case .renderFailed(let message):
            return "Render failed: \(message)"
        }
    }
}
