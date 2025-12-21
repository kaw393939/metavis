import XCTest
@testable import MetaVisCore

final class CompoundNodeTests: XCTestCase {
    
    func testPresetDefinition() {
        // 1. Define the internal graph for the preset (e.g. "Vintage Look")
        var internalGraph = NodeGraph()
        let blurNode = Node(name: "Blur", type: "core.filter.blur")
        let colorNode = Node(name: "Sepia", type: "core.color.grade")
        
        internalGraph.add(node: blurNode)
        internalGraph.add(node: colorNode)
        try? internalGraph.connect(fromNode: blurNode.id, fromPort: "out", toNode: colorNode.id, toPort: "in")
        
        // 2. Define the Preset (Compound Node Definition)
        let preset = Preset(
            id: UUID(),
            name: "Vintage Look",
            description: "Old school film look",
            internalGraph: internalGraph,
            exposedParameters: [
                "Intensity": "Sepia.saturation", // Mapping exposed param to internal node param
                "Softness": "Blur.radius"
            ]
        )
        
        // 3. Verify structure
        XCTAssertEqual(preset.internalGraph.nodes.count, 2)
        XCTAssertEqual(preset.exposedParameters["Intensity"], "Sepia.saturation")
    }
}
