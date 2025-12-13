import Foundation

public struct LUTHelper {
    public static func parseCube(data: Data) -> (size: Int, payload: [Float])? {
        guard let string = String(data: data, encoding: .utf8) else { return nil }
        
        let lines = string.components(separatedBy: .newlines)
        var size: Int = 0
        var floats: [Float] = []
        
        for line in lines {
            let trim = line.trimmingCharacters(in: .whitespaces)
            if trim.isEmpty || trim.hasPrefix("#") { continue }
            
            if trim.starts(with: "LUT_3D_SIZE") {
                let parts = trim.components(separatedBy: .whitespaces)
                if parts.count >= 2, let s = Int(parts[1]) {
                    size = s
                }
                continue
            }
            
            if trim.starts(with: "TITLE") { continue }
            
            // Data lines: "R G B"
            let parts = trim.split(separator: " ")
            if parts.count == 3 {
                if let r = Float(parts[0]), let g = Float(parts[1]), let b = Float(parts[2]) {
                    floats.append(r)
                    floats.append(g)
                    floats.append(b)
                    
                    // Alpha handling? Adobe Cube is usually RGB. We assume 1.0 Alpha or handle as RGB texture.
                }
            }
        }
        
        guard size > 0, floats.count == size * size * size * 3 else {
            print("❌ LUT Parse Failed: Size \(size), Got \(floats.count) floats, expected \(size*size*size*3)")
            return nil
        }
        
        return (size, floats)
    }
}
