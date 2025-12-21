import Foundation

struct EDT {
    /// Computes the Signed Distance Field from a binary grid.
    /// - Parameters:
    ///   - input: Boolean array where true = inside (feature), false = outside.
    ///   - width: Width of the grid.
    ///   - height: Height of the grid.
    ///   - spread: The maximum distance (in pixels) to map to the 0-1 range.
    /// - Returns: Normalized SDF values [0, 1] where 0.5 is the edge.
    static func generateSDF(input: [Bool], width: Int, height: Int, spread: Float) -> [Float] {
        // 1. Compute squared distance to nearest 'false' for all pixels (Inner distance)
        //    For inner, 'false' is the target (distance 0). 'true' is infinity.
        let innerGrid = input.map { $0 ? Float.infinity : 0.0 }
        let innerDistSq = computeSquaredDistanceTransform(grid: innerGrid, width: width, height: height)
        
        // 2. Compute squared distance to nearest 'true' for all pixels (Outer distance)
        //    For outer, 'true' is the target (distance 0). 'false' is infinity.
        let outerGrid = input.map { $0 ? 0.0 : Float.infinity }
        let outerDistSq = computeSquaredDistanceTransform(grid: outerGrid, width: width, height: height)
        
        // 3. Combine and Normalize
        var output = [Float](repeating: 0, count: width * height)
        for i in 0..<output.count {
            let inDist = sqrt(innerDistSq[i])
            let outDist = sqrt(outerDistSq[i])
            
            // Distance from edge. Positive inside, negative outside.
            // If pixel is inside (input=true), outDist is 0. Dist = inDist.
            // If pixel is outside (input=false), inDist is 0. Dist = -outDist.
            // Note: The distance transform calculates distance to the center of the nearest pixel.
            // For a binary grid, the "edge" is implicitly between pixels.
            // A common adjustment is to subtract 0.5 to center the edge, but for simple SDF text,
            // using the raw distance is usually sufficient if resolution is high enough.
            
            let dist = input[i] ? inDist : -outDist
            
            // Normalize: 0.5 is edge.
            // range [-spread, spread] maps to [0, 1]
            // value = 0.5 + 0.5 * (dist / spread)
            
            let normalized = 0.5 + 0.5 * (dist / spread)
            output[i] = min(max(normalized, 0.0), 1.0)
        }
        
        return output
    }
    
    /// Computes the Squared Euclidean Distance Transform using a separable algorithm.
    /// Based on "Distance Transforms of Sampled Functions" by Felzenszwalb & Huttenlocher.
    private static func computeSquaredDistanceTransform(grid: [Float], width: Int, height: Int) -> [Float] {
        var g = grid // Mutable copy
        
        // Pass 1: Columns
        for x in 0..<width {
            var column = [Float](repeating: 0, count: height)
            for y in 0..<height { column[y] = g[y * width + x] }
            
            let dt = distanceTransform1D(f: column)
            
            for y in 0..<height { g[y * width + x] = dt[y] }
        }
        
        // Pass 2: Rows
        for y in 0..<height {
            var row = [Float](repeating: 0, count: width)
            for x in 0..<width { row[x] = g[y * width + x] }
            
            let dt = distanceTransform1D(f: row)
            
            for x in 0..<width { g[y * width + x] = dt[x] }
        }
        
        return g
    }
    
    /// 1D Squared Distance Transform
    /// f: input function (squared distance values)
    /// returns: squared distance transform
    private static func distanceTransform1D(f: [Float]) -> [Float] {
        let n = f.count
        var d = [Float](repeating: 0, count: n)
        var v = [Int](repeating: 0, count: n) // Locations of parabolas
        var z = [Float](repeating: 0, count: n + 1) // Boundaries between parabolas
        var k = 0 // Number of parabolas
        
        v[0] = 0
        z[0] = -Float.infinity
        z[1] = Float.infinity
        
        for q in 1..<n {
            // If f[q] is infinity, it doesn't define a parabola
            if f[q] == Float.infinity { continue }
            
            while true {
                let vk = v[k]
                // Intersection of parabola from q and v[k]
                // s = ((f[q] + q^2) - (f[vk] + vk^2)) / (2*q - 2*vk)
                let s = ((f[q] + Float(q*q)) - (f[vk] + Float(vk*vk))) / (2.0 * Float(q - vk))
                
                if s <= z[k] {
                    k -= 1
                    if k < 0 {
                        // This happens if the new parabola q dominates everything so far
                        k = 0
                        v[0] = q
                        z[0] = -Float.infinity
                        z[1] = Float.infinity
                        break // Restart with q as the first parabola
                    }
                    continue
                } else {
                    k += 1
                    v[k] = q
                    z[k] = s
                    z[k+1] = Float.infinity
                    break
                }
            }
        }
        
        // Fill in values
        k = 0
        for q in 0..<n {
            while z[k+1] < Float(q) {
                k += 1
            }
            let vk = v[k]
            d[q] = Float((q - vk) * (q - vk)) + f[vk]
        }
        
        return d
    }
}
