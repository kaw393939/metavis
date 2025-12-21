import Metal
import CoreGraphics

public class GlyphAtlasBuilder {
    private let device: MTLDevice
    public private(set) var texture: MTLTexture?
    public let size: Int
    
    public struct SkylineNode: Codable, Sendable {
        var x: Int
        var y: Int
        var width: Int
    }
    
    private var nodes: [SkylineNode] = []
    
    public struct State: Codable, Sendable {
        let nodes: [SkylineNode]
    }
    
    public func getState() -> State {
        return State(nodes: nodes)
    }
    
    public func restore(state: State, texture: MTLTexture) {
        self.nodes = state.nodes
        self.texture = texture
    }
    
    public init(device: MTLDevice, size: Int = 2048) {
        self.device = device
        self.size = size
        self.nodes = [SkylineNode(x: 0, y: 0, width: size)]
        createTexture()
    }
    
    private func createTexture() {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        self.texture = device.makeTexture(descriptor: descriptor)
    }
    
    public func add(glyph: SDFResult) -> GlyphAtlasLocation? {
        let width = glyph.width
        let height = glyph.height
        
        // 1. Find best position (Bottom-Left heuristic)
        var bestHeight = Int.max
        var bestWidth = Int.max
        var bestIndex = -1
        var bestY = 0
        
        for i in 0..<nodes.count {
            let y = fit(index: i, width: width, height: height)
            if y >= 0 {
                // Score: minimize y + height (top edge), then minimize width (best fit)
                if y + height < bestHeight || (y + height == bestHeight && nodes[i].width < bestWidth) {
                    bestHeight = y + height
                    bestIndex = i
                    bestWidth = nodes[i].width
                    bestY = y
                }
            }
        }
        
        if bestIndex == -1 {
            return nil // Atlas full
        }
        
        // 2. Place it
        let region = MTLRegionMake2D(nodes[bestIndex].x, bestY, width, height)
        texture?.replace(region: region, mipmapLevel: 0, withBytes: glyph.buffer, bytesPerRow: width)
        
        // 3. Update Skyline
        addSkylineLevel(index: bestIndex, x: nodes[bestIndex].x, y: bestY, width: width, height: height)
        
        return GlyphAtlasLocation(
            textureIndex: 0,
            region: CGRect(x: CGFloat(region.origin.x) / CGFloat(size),
                           y: CGFloat(region.origin.y) / CGFloat(size),
                           width: CGFloat(width) / CGFloat(size),
                           height: CGFloat(height) / CGFloat(size)),
            padding: 0,
            metrics: glyph.metrics
        )
    }
    
    private func fit(index: Int, width: Int, height: Int) -> Int {
        let x = nodes[index].x
        if x + width > size { return -1 }
        
        var widthLeft = width
        var i = index
        var y = nodes[index].y
        
        while widthLeft > 0 {
            if i >= nodes.count { return -1 }
            y = max(y, nodes[i].y)
            if y + height > size { return -1 }
            widthLeft -= nodes[i].width
            i += 1
        }
        return y
    }
    
    private func addSkylineLevel(index: Int, x: Int, y: Int, width: Int, height: Int) {
        let newNode = SkylineNode(x: x, y: y + height, width: width)
        
        var currentWidth = 0
        var nodesToRemove = 0
        var remainingWidthOfLastNode = 0
        
        for k in index..<nodes.count {
            currentWidth += nodes[k].width
            nodesToRemove += 1
            if currentWidth >= width {
                remainingWidthOfLastNode = currentWidth - width
                break
            }
        }
        
        var nextNode: SkylineNode? = nil
        if remainingWidthOfLastNode > 0 {
            let lastNode = nodes[index + nodesToRemove - 1]
            // The remaining part starts after the new node
            // x position is: start of last node + (width of last node - remaining)
            // Wait, simpler: x position is x + width (end of new node)
            nextNode = SkylineNode(x: x + width,
                                   y: lastNode.y,
                                   width: remainingWidthOfLastNode)
        }
        
        nodes.removeSubrange(index..<(index + nodesToRemove))
        
        if let next = nextNode {
            nodes.insert(next, at: index)
        }
        nodes.insert(newNode, at: index)
        
        merge()
    }
    
    private func merge() {
        var i = 0
        while i < nodes.count - 1 {
            if nodes[i].y == nodes[i+1].y {
                nodes[i].width += nodes[i+1].width
                nodes.remove(at: i+1)
            } else {
                i += 1
            }
        }
    }
    
    public func reset() {
        nodes = [SkylineNode(x: 0, y: 0, width: size)]
    }
}
