// GenerateTestsCommand.swift
// MetaVisCLI
//
// Sprint 2: Color Pipeline Testing
// Generate test manifest files for TDD validation

import ArgumentParser
import Foundation
import MetaVisRender

struct GenerateTestsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate-tests",
        abstract: "Generate test manifest files for Sprint 2 color pipeline validation",
        discussion: """
        Creates standardized test files for validating HDR color pipeline fixes.
        
        USAGE:
            metavis generate-tests --all test_data/sprint_02/
            metavis generate-tests --type gradient test_data/gradient_test.json
            metavis generate-tests --type hdr-bright test_data/sun_test.json
        
        TEST TYPES:
            gradient      - Smooth gradient to detect banding (8-bit vs 16-bit)
            hdr-bright    - Bright HDR scene (values >1.0) to test clipping
            hdr-dark      - Dark scene to test shadow detail preservation
            color-neutral - Neutral tones to detect color shifts
            color-matrix  - Color space conversion accuracy test
            hdr-extreme   - Extreme HDR values (5.0+ nits) for stress testing
            
        FILES GENERATED (--all):
            test_gradient_smooth.json       - Detect banding in smooth gradients
            test_hdr_sun.json              - Test HDR highlights (>1.0 values)
            test_dark_scene.json           - Test shadow detail preservation
            test_neutral_colors.json       - Test gray neutrality (no color shifts)
            test_color_matrices.json       - Test RGB↔YUV conversion accuracy
            test_hdr_extreme.json          - Test extreme HDR values (5.0 nits)
            test_checkerboard.json         - Test sharp edges/aliasing
            test_color_ramps.json          - Test all primary/secondary colors
        
        VALIDATION WORKFLOW:
            1. Generate test files: metavis generate-tests --all test_data/sprint_02/
            2. Render with 8-bit:  metavis render test_gradient_smooth.json -o output/8bit.mov
            3. Apply 16-bit fix:   (implement fixes to CompositePass, RenderEngine, etc.)
            4. Render with 16-bit: metavis render test_gradient_smooth.json -o output/16bit.mov
            5. Compare outputs:    open output/8bit.mov output/16bit.mov
            6. Verify no banding, HDR preserved, colors accurate
        
        AUTOMATED TEST INTEGRATION:
            Generated files are designed for both:
            - Manual visual validation (render and inspect)
            - Automated XCTest integration (texture sampling)
        """
    )
    
    @Argument(help: "Output directory or file path for generated test files")
    var output: String
    
    @Option(name: .shortAndLong, help: "Type of test to generate (gradient, hdr-bright, hdr-dark, color-neutral, color-matrix, hdr-extreme)")
    var type: String?
    
    @Flag(name: .long, help: "Generate all test types")
    var all: Bool = false
    
    @Option(name: .long, help: "Resolution width")
    var width: Int = 1920
    
    @Option(name: .long, help: "Resolution height")
    var height: Int = 1080
    
    @Option(name: .long, help: "Duration in seconds")
    var duration: Double = 3.0
    
    @Option(name: .long, help: "Frame rate")
    var fps: Double = 30.0
    
    mutating func run() async throws {
        let outputURL = URL(fileURLWithPath: output)
        
        // Determine if output is directory or file
        let isDirectory = (try? outputURL.hasDirectoryPath) ?? false
        
        if all {
            guard isDirectory || !FileManager.default.fileExists(atPath: output) else {
                print("❌ Error: --all requires a directory path")
                throw ExitCode.failure
            }
            
            // Create directory if needed
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
            
            print("📁 Generating all test files in \(outputURL.path)")
            print("")
            
            try generateGradientTest(to: outputURL.appendingPathComponent("test_gradient_smooth.json"))
            try generateHDRBrightTest(to: outputURL.appendingPathComponent("test_hdr_sun.json"))
            try generateHDRDarkTest(to: outputURL.appendingPathComponent("test_dark_scene.json"))
            try generateNeutralColorsTest(to: outputURL.appendingPathComponent("test_neutral_colors.json"))
            try generateColorMatrixTest(to: outputURL.appendingPathComponent("test_color_matrices.json"))
            try generateHDRExtremeTest(to: outputURL.appendingPathComponent("test_hdr_extreme.json"))
            try generateCheckerboardTest(to: outputURL.appendingPathComponent("test_checkerboard.json"))
            try generateColorRampsTest(to: outputURL.appendingPathComponent("test_color_ramps.json"))
            
            print("")
            print("✅ Generated 8 test files")
            print("")
            print("NEXT STEPS:")
            print("1. Render baseline (8-bit):  for f in \(outputURL.path)/*.json; do metavis render \"$f\" -o \"output/8bit_$(basename $f .json).mov\"; done")
            print("2. Apply Sprint 2 fixes")
            print("3. Render fixed (16-bit):    for f in \(outputURL.path)/*.json; do metavis render \"$f\" -o \"output/16bit_$(basename $f .json).mov\"; done")
            print("4. Compare: open output/8bit_*.mov output/16bit_*.mov")
            
        } else if let testType = type {
            print("📝 Generating \(testType) test file...")
            
            switch testType {
            case "gradient":
                try generateGradientTest(to: outputURL)
            case "hdr-bright":
                try generateHDRBrightTest(to: outputURL)
            case "hdr-dark":
                try generateHDRDarkTest(to: outputURL)
            case "color-neutral":
                try generateNeutralColorsTest(to: outputURL)
            case "color-matrix":
                try generateColorMatrixTest(to: outputURL)
            case "hdr-extreme":
                try generateHDRExtremeTest(to: outputURL)
            case "checkerboard":
                try generateCheckerboardTest(to: outputURL)
            case "color-ramps":
                try generateColorRampsTest(to: outputURL)
            default:
                print("❌ Unknown test type: \(testType)")
                print("Available: gradient, hdr-bright, hdr-dark, color-neutral, color-matrix, hdr-extreme, checkerboard, color-ramps")
                throw ExitCode.failure
            }
            
            print("✅ Generated \(outputURL.path)")
            print("Render: metavis render \(outputURL.path) -o output/test.mov")
            
        } else {
            print("❌ Error: Must specify --type <type> or --all")
            print("Run: metavis generate-tests --help")
            throw ExitCode.failure
        }
    }
    
    // MARK: - Test Generators
    
    private func generateGradientTest(to url: URL) throws {
        let manifest: [String: Any] = [
            "metadata": [
                "testType": "gradient-banding",
                "purpose": "Detect banding in smooth gradients (8-bit shows bands, 16-bit smooth)",
                "validation": "Visual inspection - no visible bands",
                "duration": duration,
                "fps": fps,
                "resolution": [width, height]
            ],
            "scene": [
                "background": "#000000",
                "proceduralBackground": [
                    "type": "procedural",
                    "fieldType": "perlin",
                    "frequency": 0.5,
                    "octaves": 1,
                    "lacunarity": 2.0,
                    "gain": 0.5,
                    "domainWarp": "none",
                    "warpStrength": 0.0,
                    "scale": [1.0, 1.0],
                    "gradient": [
                        ["color": [0.0, 0.0, 0.0], "position": 0.0],
                        ["color": [0.05, 0.05, 0.05], "position": 0.5],
                        ["color": [0.1, 0.1, 0.1], "position": 1.0]
                    ],
                    "gradientColorSpace": "linear",
                    "animationSpeed": 0.0
                ]
            ],
            "camera": [
                "fov": 45.0,
                "position": [0, 0, 25],
                "target": [0, 0, 0]
            ],
            "layers": []
        ]
        
        try saveJSON(manifest, to: url)
        print("  ✓ test_gradient_smooth.json - Detects banding (expect bands in 8-bit, smooth in 16-bit)")
    }
    
    private func generateHDRBrightTest(to url: URL) throws {
        let manifest: [String: Any] = [
            "metadata": [
                "testType": "hdr-bright",
                "purpose": "Test HDR highlight preservation (values >1.0)",
                "validation": "Bright sun visible (not clipped white), HDR values preserved",
                "duration": duration,
                "fps": fps,
                "resolution": [width, height]
            ],
            "scene": [
                "background": "#1a1a2e",
                "proceduralBackground": [
                    "type": "procedural",
                    "fieldType": "fbm",
                    "frequency": 2.0,
                    "octaves": 4,
                    "gradient": [
                        ["color": [0.1, 0.1, 0.2], "position": 0.0],
                        ["color": [0.3, 0.4, 0.8], "position": 0.3],
                        ["color": [1.0, 0.9, 0.7], "position": 0.6],
                        ["color": [5.0, 4.5, 3.0], "position": 1.0]  // HDR sun (5.0 nits)
                    ],
                    "gradientColorSpace": "linear",
                    "animationSpeed": 0.1
                ]
            ],
            "camera": [
                "fov": 45.0,
                "position": [0, 0, 25],
                "target": [0, 0, 0]
            ],
            "layers": [
                [
                    "type": "text",
                    "content": "HDR Sun Test",
                    "position": [0.5, 0.9],
                    "fontSize": 48,
                    "color": [1.0, 1.0, 1.0, 1.0]
                ]
            ]
        ]
        
        try saveJSON(manifest, to: url)
        print("  ✓ test_hdr_sun.json - Tests HDR >1.0 (expect sun visible, not clipped)")
    }
    
    private func generateHDRDarkTest(to url: URL) throws {
        let manifest: [String: Any] = [
            "metadata": [
                "testType": "hdr-dark",
                "purpose": "Test shadow detail preservation in dark scenes",
                "validation": "Shadow detail visible (not crushed black)",
                "duration": duration,
                "fps": fps,
                "resolution": [width, height]
            ],
            "scene": [
                "background": "#000000",
                "proceduralBackground": [
                    "type": "procedural",
                    "fieldType": "fbm",
                    "frequency": 3.0,
                    "octaves": 6,
                    "gradient": [
                        ["color": [0.0, 0.0, 0.0], "position": 0.0],
                        ["color": [0.01, 0.01, 0.015], "position": 0.4],
                        ["color": [0.02, 0.025, 0.03], "position": 0.7],
                        ["color": [0.05, 0.06, 0.08], "position": 1.0]
                    ],
                    "gradientColorSpace": "linear",
                    "animationSpeed": 0.05
                ]
            ],
            "camera": [
                "fov": 45.0,
                "position": [0, 0, 25],
                "target": [0, 0, 0]
            ],
            "layers": [
                [
                    "type": "text",
                    "content": "Dark Scene Test",
                    "position": [0.5, 0.9],
                    "fontSize": 36,
                    "color": [0.5, 0.5, 0.5, 1.0]
                ]
            ]
        ]
        
        try saveJSON(manifest, to: url)
        print("  ✓ test_dark_scene.json - Tests shadow detail (expect visible structure, not crushed)")
    }
    
    private func generateNeutralColorsTest(to url: URL) throws {
        let manifest: [String: Any] = [
            "metadata": [
                "testType": "color-neutral",
                "purpose": "Detect color shifts in neutral grays",
                "validation": "All gray patches remain neutral (no tint)",
                "duration": duration,
                "fps": fps,
                "resolution": [width, height]
            ],
            "scene": [
                "background": "#808080"
            ],
            "camera": [
                "fov": 45.0,
                "position": [0, 0, 25],
                "target": [0, 0, 0]
            ],
            "layers": [
                // Gray scale patches
                ["type": "rectangle", "position": [0.1, 0.5], "size": [0.15, 0.3], "color": [0.1, 0.1, 0.1, 1.0]],
                ["type": "rectangle", "position": [0.25, 0.5], "size": [0.15, 0.3], "color": [0.2, 0.2, 0.2, 1.0]],
                ["type": "rectangle", "position": [0.4, 0.5], "size": [0.15, 0.3], "color": [0.5, 0.5, 0.5, 1.0]],
                ["type": "rectangle", "position": [0.55, 0.5], "size": [0.15, 0.3], "color": [0.7, 0.7, 0.7, 1.0]],
                ["type": "rectangle", "position": [0.7, 0.5], "size": [0.15, 0.3], "color": [0.9, 0.9, 0.9, 1.0]],
                ["type": "text", "content": "Neutral Gray Test", "position": [0.5, 0.1], "fontSize": 42, "color": [1.0, 1.0, 1.0, 1.0]]
            ]
        ]
        
        try saveJSON(manifest, to: url)
        print("  ✓ test_neutral_colors.json - Tests gray neutrality (expect no color tint)")
    }
    
    private func generateColorMatrixTest(to url: URL) throws {
        let manifest: [String: Any] = [
            "metadata": [
                "testType": "color-matrix",
                "purpose": "Test RGB↔YUV color matrix accuracy",
                "validation": "Pure colors remain pure after conversion",
                "duration": duration,
                "fps": fps,
                "resolution": [width, height]
            ],
            "scene": [
                "background": "#000000"
            ],
            "camera": [
                "fov": 45.0,
                "position": [0, 0, 25],
                "target": [0, 0, 0]
            ],
            "layers": [
                // Primary colors (top row)
                ["type": "rectangle", "position": [0.1, 0.25], "size": [0.2, 0.2], "color": [1.0, 0.0, 0.0, 1.0]],
                ["type": "rectangle", "position": [0.4, 0.25], "size": [0.2, 0.2], "color": [0.0, 1.0, 0.0, 1.0]],
                ["type": "rectangle", "position": [0.7, 0.25], "size": [0.2, 0.2], "color": [0.0, 0.0, 1.0, 1.0]],
                // Secondary colors (bottom row)
                ["type": "rectangle", "position": [0.1, 0.65], "size": [0.2, 0.2], "color": [1.0, 1.0, 0.0, 1.0]],
                ["type": "rectangle", "position": [0.4, 0.65], "size": [0.2, 0.2], "color": [0.0, 1.0, 1.0, 1.0]],
                ["type": "rectangle", "position": [0.7, 0.65], "size": [0.2, 0.2], "color": [1.0, 0.0, 1.0, 1.0]],
                ["type": "text", "content": "Color Matrix Test", "position": [0.5, 0.05], "fontSize": 42, "color": [1.0, 1.0, 1.0, 1.0]]
            ]
        ]
        
        try saveJSON(manifest, to: url)
        print("  ✓ test_color_matrices.json - Tests color conversion (expect accurate RGB/YUV)")
    }
    
    private func generateHDRExtremeTest(to url: URL) throws {
        let manifest: [String: Any] = [
            "metadata": [
                "testType": "hdr-extreme",
                "purpose": "Stress test with extreme HDR values (5.0+ nits)",
                "validation": "No clipping, extreme values preserved",
                "duration": duration,
                "fps": fps,
                "resolution": [width, height]
            ],
            "scene": [
                "background": "#000000",
                "proceduralBackground": [
                    "type": "procedural",
                    "fieldType": "fbm",
                    "frequency": 1.5,
                    "octaves": 4,
                    "gradient": [
                        ["color": [0.0, 0.0, 0.0], "position": 0.0],
                        ["color": [1.0, 0.5, 0.2], "position": 0.4],
                        ["color": [5.0, 3.0, 1.0], "position": 0.7],
                        ["color": [10.0, 8.0, 5.0], "position": 1.0]  // Extreme HDR (10.0 nits)
                    ],
                    "gradientColorSpace": "linear",
                    "animationSpeed": 0.2
                ]
            ],
            "camera": [
                "fov": 45.0,
                "position": [0, 0, 25],
                "target": [0, 0, 0]
            ],
            "layers": [
                ["type": "text", "content": "Extreme HDR Test (10.0 nits)", "position": [0.5, 0.9], "fontSize": 36, "color": [1.0, 1.0, 1.0, 1.0]]
            ]
        ]
        
        try saveJSON(manifest, to: url)
        print("  ✓ test_hdr_extreme.json - Tests extreme HDR (expect 10.0 nit values preserved)")
    }
    
    private func generateCheckerboardTest(to url: URL) throws {
        let manifest: [String: Any] = [
            "metadata": [
                "testType": "checkerboard",
                "purpose": "Test sharp edges and aliasing",
                "validation": "Clean edges, no color bleeding",
                "duration": duration,
                "fps": fps,
                "resolution": [width, height]
            ],
            "scene": [
                "background": "#ffffff"
            ],
            "camera": [
                "fov": 45.0,
                "position": [0, 0, 25],
                "target": [0, 0, 0]
            ],
            "layers": Array(0..<8).flatMap { row in
                Array(0..<8).compactMap { col in
                    let isBlack = (row + col) % 2 == 0
                    return [
                        "type": "rectangle",
                        "position": [Double(col) * 0.125 + 0.0625, Double(row) * 0.125 + 0.0625],
                        "size": [0.125, 0.125],
                        "color": isBlack ? [0.0, 0.0, 0.0, 1.0] : [1.0, 1.0, 1.0, 1.0]
                    ] as [String : Any]
                }
            }
        ]
        
        try saveJSON(manifest, to: url)
        print("  ✓ test_checkerboard.json - Tests edge sharpness (expect clean edges)")
    }
    
    private func generateColorRampsTest(to url: URL) throws {
        let manifest: [String: Any] = [
            "metadata": [
                "testType": "color-ramps",
                "purpose": "Test all primary and secondary color ramps",
                "validation": "Smooth ramps, no banding in any channel",
                "duration": duration,
                "fps": fps,
                "resolution": [width, height]
            ],
            "scene": [
                "background": "#000000"
            ],
            "camera": [
                "fov": 45.0,
                "position": [0, 0, 25],
                "target": [0, 0, 0]
            ],
            "layers": [
                // Red ramp
                ["type": "rectangle", "position": [0.125, 0.85], "size": [0.125, 0.1], "gradient": [[0.0, 0.0, 0.0], [1.0, 0.0, 0.0]]],
                // Green ramp
                ["type": "rectangle", "position": [0.375, 0.85], "size": [0.125, 0.1], "gradient": [[0.0, 0.0, 0.0], [0.0, 1.0, 0.0]]],
                // Blue ramp
                ["type": "rectangle", "position": [0.625, 0.85], "size": [0.125, 0.1], "gradient": [[0.0, 0.0, 0.0], [0.0, 0.0, 1.0]]],
                // Cyan ramp
                ["type": "rectangle", "position": [0.125, 0.65], "size": [0.125, 0.1], "gradient": [[0.0, 0.0, 0.0], [0.0, 1.0, 1.0]]],
                // Magenta ramp
                ["type": "rectangle", "position": [0.375, 0.65], "size": [0.125, 0.1], "gradient": [[0.0, 0.0, 0.0], [1.0, 0.0, 1.0]]],
                // Yellow ramp
                ["type": "rectangle", "position": [0.625, 0.65], "size": [0.125, 0.1], "gradient": [[0.0, 0.0, 0.0], [1.0, 1.0, 0.0]]],
                ["type": "text", "content": "Color Ramps Test", "position": [0.5, 0.1], "fontSize": 42, "color": [1.0, 1.0, 1.0, 1.0]]
            ]
        ]
        
        try saveJSON(manifest, to: url)
        print("  ✓ test_color_ramps.json - Tests all color channels (expect smooth ramps)")
    }
    
    // MARK: - Helpers
    
    private func saveJSON(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }
}
