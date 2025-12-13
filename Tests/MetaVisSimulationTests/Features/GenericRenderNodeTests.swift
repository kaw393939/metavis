import XCTest
import MetaVisCore
import simd
@testable import MetaVisSimulation

final class GenericRenderNodeTests: XCTestCase {
    
    func testRenderNodeFromManifest() async {
        // 1. define Manifest
        let manifest = FeatureManifest(
            id: "com.test.blur",
            version: "1.0.0",
            name: "Gaussian Blur",
            category: .blur,
            inputs: [
                PortDefinition(name: "image", type: .image),
                PortDefinition(name: "mask", type: .image)
            ],
            parameters: [
                .float(name: "radius", min: 0, max: 100, default: 10.0),
                .bool(name: "highQuality", default: true)
            ],
            kernelName: "gaussian_blur_kernel"
        )
        
        // 2. Initialize RenderNode (Extension to be implemented)
        let node = RenderNode(manifest: manifest)
        
        // 3. Verify
        XCTAssertEqual(node.shader, "gaussian_blur_kernel")
        XCTAssertEqual(node.name, "Gaussian Blur")
        
        // Check Parameters Defaults
        if case .float(let val) = node.parameters["radius"] {
            XCTAssertEqual(val, 10.0)
        } else {
            XCTFail("Radius parameter missing or wrong type")
        }
        
        if case .bool(let val) = node.parameters["highQuality"] {
            XCTAssertEqual(val, true)
        } else {
            XCTFail("HighQuality parameter missing or wrong type")
        }
    }
    
    func testStandardFeatures() async {
        // 1. Register
        await StandardFeatures.registerAll()
        
        // 2. Retrieve
        let registry = FeatureRegistry.shared
        guard let bloomManifest = await registry.feature(for: "com.metavis.fx.bloom") else {
            XCTFail("Bloom feature not registered")
            return
        }
        
        // 3. Create Node
        let node = RenderNode(manifest: bloomManifest)
        
        // 4. Verify
        XCTAssertEqual(node.name, "Cinematic Bloom")
        // Check default Threshold
        if case .float(let val) = node.parameters["threshold"] {
            XCTAssertEqual(val, 1.0)
        } else {
            XCTFail("Threshold default incorrect")
        }
        // 5. Verify Film Grain
        guard let grainManifest = await registry.feature(for: "com.metavis.fx.filmgrain") else {
            XCTFail("Film Grain feature not registered")
            return
        }
        let grainNode = RenderNode(manifest: grainManifest)
        XCTAssertEqual(grainNode.name, "Film Grain")
    
        // 6. Verify Volumetric
        guard let volManifest = await registry.feature(for: "com.metavis.fx.volumetric") else {
            XCTFail("Volumetric feature not registered")
            return
        }
        let volNode = RenderNode(manifest: volManifest)
        XCTAssertEqual(volNode.name, "Volumetric Light")
        // Check INT parameter mapped to Float
        if case .float(let val) = volNode.parameters["samples"] {
            // My init logic converts Int defaults to Float(Double).
            XCTAssertEqual(val, 50.0)
        } else {
            XCTFail("Samples parameter should be float")
        }
        
        // 7. Verify Anamorphic
        guard let anaManifest = await registry.feature(for: "com.metavis.fx.anamorphic") else {
            XCTFail("Anamorphic feature not registered")
            return
        }
        let anaNode = RenderNode(manifest: anaManifest)
        XCTAssertEqual(anaNode.name, "Anamorphic Streaks")
        
        // 8. Verify Halation
        guard let halManifest = await registry.feature(for: "com.metavis.fx.halation") else {
            XCTFail("Halation feature not registered")
            return
        }
        let halNode = RenderNode(manifest: halManifest)
        XCTAssertEqual(halNode.name, "Film Halation")
        
        // 9. Verify Vignette
        guard let vigManifest = await registry.feature(for: "com.metavis.fx.vignette") else {
            XCTFail("Vignette feature not registered")
            return
        }
        let vigNode = RenderNode(manifest: vigManifest)
        XCTAssertEqual(vigNode.name, "Physical Vignette")
        
        // 10. Verify Lens System
        guard let lensManifest = await registry.feature(for: "com.metavis.fx.lens") else {
            XCTFail("Lens feature not registered")
            return
        }
        let lensNode = RenderNode(manifest: lensManifest)
        XCTAssertEqual(lensNode.name, "Lens System")
        
        // 11. Verify Volumetric Nebula
        guard let nebManifest = await registry.feature(for: "com.metavis.fx.nebula") else {
            XCTFail("Nebula feature not registered")
            return
        }
        let nebNode = RenderNode(manifest: nebManifest)
        XCTAssertEqual(nebNode.name, "Volumetric Nebula")
        if case .float(let steps) = nebNode.parameters["maxSteps"] {
            XCTAssertEqual(steps, 64.0)
        } else {
            XCTFail("maxSteps should be float")
        }

        // 12. Verify Tone Map ACES
        guard let tmACES = await registry.feature(for: "com.metavis.fx.tonemap.aces") else {
            XCTFail("ACES Tone Map not registered")
            return
        }
        let tmNode = RenderNode(manifest: tmACES)
        XCTAssertEqual(tmNode.name, "ACES Tone Map (SDR)")
        
        // 13. Verify Tone Map PQ
        guard let tmPQ = await registry.feature(for: "com.metavis.fx.tonemap.pq") else {
            XCTFail("PQ Tone Map not registered")
            return
        }
        let pqNode = RenderNode(manifest: tmPQ)
        XCTAssertEqual(pqNode.name, "ST.2084 Tone Map (HDR)")
        
        // 14. Verify LUT
        guard let lutManifest = await registry.feature(for: "com.metavis.fx.lut") else {
            XCTFail("LUT feature not registered")
            return
        }
        let lutNode = RenderNode(manifest: lutManifest)
        XCTAssertEqual(lutNode.name, "3D LUT")
        
        // 15. Verify Simple Grade
        guard let gradeManifest = await registry.feature(for: "com.metavis.fx.grade.simple") else {
            XCTFail("Color Grade feature not registered")
            return
        }
        let gradeNode = RenderNode(manifest: gradeManifest)
        XCTAssertEqual(gradeNode.name, "Basic Color Grade")
        if case .float(let temp) = gradeNode.parameters["temperature"] {
            XCTAssertEqual(temp, 0.0)
        } else {
            XCTFail("Temperature should be float")
        }
        
        // 16. Verify Blur Gaussian H
        guard let blurH = await registry.feature(for: "com.metavis.fx.blur.gaussian.h") else {
            XCTFail("Blur H not registered")
            return
        }
        XCTAssertEqual(RenderNode(manifest: blurH).name, "Gaussian Blur H")
        
        // 17. Verify Bokeh
        guard let bokeh = await registry.feature(for: "com.metavis.fx.blur.bokeh") else {
            XCTFail("Bokeh not registered")
            return
        }
        XCTAssertEqual(RenderNode(manifest: bokeh).name, "Bokeh Blur")
        
        // 18. Verify Masked Blur
        guard let mBlur = await registry.feature(for: "com.metavis.fx.blur.masked") else {
            XCTFail("Masked Blur not registered")
            return
        }
        let mBlurNode = RenderNode(manifest: mBlur)
        XCTAssertEqual(mBlurNode.name, "Masked Blur")
        
        // 19. Verify Temporal Accum
        guard let tAccum = await registry.feature(for: "com.metavis.fx.temporal.accum") else {
            XCTFail("Temporal Accum not registered")
            return
        }
        XCTAssertEqual(RenderNode(manifest: tAccum).name, "Temporal Accumulate")
        
        // 20. Verify Face Enhance
        guard let fe = await registry.feature(for: "com.metavis.fx.face.enhance") else {
            XCTFail("Face Enhance not registered")
            return
        }
        XCTAssertEqual(RenderNode(manifest: fe).name, "Face Enhance")
        
        // 21. Verify Light Leak
        guard let leak = await registry.feature(for: "com.metavis.fx.lightleak") else {
            XCTFail("Light Leak not registered")
            return
        }
        XCTAssertEqual(RenderNode(manifest: leak).name, "Light Leak")
        
        // 22. Verify Spectral Dispersion
        guard let spectral = await registry.feature(for: "com.metavis.fx.spectral.dispersion") else {
            XCTFail("Spectral Dispersion not registered")
            return
        }
        XCTAssertEqual(RenderNode(manifest: spectral).name, "Spectral Dispersion")
        
        // 23. Verify Face Mask Generator
        guard let maskGen = await registry.feature(for: "com.metavis.fx.face.mask_gen") else {
            XCTFail("Face Mask Generator not registered")
            return
        }
        XCTAssertEqual(RenderNode(manifest: maskGen).name, "Face Mask Generator")
        
        // 24. Verify Masked Color Grade
        guard let grade = await registry.feature(for: "com.metavis.fx.masked_grade") else {
            XCTFail("Masked Grade not registered")
            return
        }
        XCTAssertEqual(RenderNode(manifest: grade).name, "Masked Color Grade")
    }
}
