import XCTest
import MetaVisCore
import simd
@testable import MetaVisSimulation

final class FeatureRegistryTests: XCTestCase {
    
    // MARK: - Manifest Tests
    
    func testManifestSerialization() throws {
        // Create a complex manifest
        let inputPorts = [
            PortDefinition(name: "main", type: .image),
            PortDefinition(name: "depth", type: .image)
        ]
        
        let parameters: [ParameterDefinition] = [
            .float(name: "threshold", min: 0.0, max: 1.0, default: 0.5),
            .bool(name: "enable", default: true),
            .color(name: "tint", default: SIMD4<Float>(1, 0, 0, 1))
        ]
        
        let manifest = FeatureManifest(
            id: "com.test.bloom",
            version: "1.0.0",
            name: "Test Bloom",
            category: .blur,
            inputs: inputPorts,
            parameters: parameters,
            kernelName: "test_bloom"
        )
        
        // Encode
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        
        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FeatureManifest.self, from: data)
        
        // Verify
        XCTAssertEqual(decoded.id, "com.test.bloom")
        XCTAssertEqual(decoded.name, "Test Bloom")
        XCTAssertEqual(decoded.parameters.count, 3)
        
        // Verify Float Param
        if case .float(let name, let min, let max, let def) = decoded.parameters[0] {
            XCTAssertEqual(name, "threshold")
            XCTAssertEqual(min, 0.0)
            XCTAssertEqual(max, 1.0)
            XCTAssertEqual(def, 0.5)
        } else {
            XCTFail("First parameter should be float")
        }
        
        // Verify Color Param
        if case .color(let name, let def) = decoded.parameters[2] {
            XCTAssertEqual(name, "tint")
            XCTAssertEqual(def.x, 1.0)
            XCTAssertEqual(def.w, 1.0)
        } else {
            XCTFail("Third parameter should be color")
        }
    }
    
    // MARK: - Registry Tests
    
    func testRegistryRegistration() async {
        let registry = FeatureRegistry()
        
        let manifest = FeatureManifest(
            id: "com.test.grain",
            version: "1.0.0",
            name: "Film Grain",
            category: .stylize,
            inputs: [],
            parameters: [],
            kernelName: "grain_kernel"
        )
        
        // Register (Actor call)
        await registry.register(manifest)
        
        // Retrieve
        let retrieved = await registry.feature(for: "com.test.grain")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.name, "Film Grain")
    }
    
    func testRegistryCategorization() async {
        let registry = FeatureRegistry()
        
        let m1 = FeatureManifest(id: "1", version: "1", name: "A", category: .blur, inputs: [], parameters: [], kernelName: "k")
        let m2 = FeatureManifest(id: "2", version: "1", name: "B", category: .stylize, inputs: [], parameters: [], kernelName: "k")
        let m3 = FeatureManifest(id: "3", version: "1", name: "C", category: .blur, inputs: [], parameters: [], kernelName: "k")
        
        await registry.register(m1)
        await registry.register(m2)
        await registry.register(m3)
        
        let blurs = await registry.features(in: .blur)
        XCTAssertEqual(blurs.count, 2)
        XCTAssertTrue(blurs.contains { $0.id == "1" })
        XCTAssertTrue(blurs.contains { $0.id == "3" })
    }
}
