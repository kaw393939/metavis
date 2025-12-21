import Foundation
import simd

public class MaterialResolver {
    public static func resolve(_ definition: MaterialDefinition) -> PBRMaterial {
        let baseColor = parseHexColor(definition.baseColor) ?? SIMD3(1, 1, 1)
        let emissive = parseHexColor(definition.emissive) ?? SIMD3(0, 0, 0)
        
        return PBRMaterial(
            baseColor: baseColor,
            roughness: definition.roughness ?? 0.5,
            metallic: definition.metallic ?? 0.0,
            emissive: emissive
        )
    }
    
    private static func parseHexColor(_ hex: String?) -> SIMD3<Float>? {
        guard let hex = hex else { return nil }
        
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleanHex.hasPrefix("#") {
            cleanHex.removeFirst()
        }
        
        guard cleanHex.count == 6 || cleanHex.count == 8 else { return nil }
        
        var rgbValue: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&rgbValue)
        
        let r, g, b: Float
        if cleanHex.count == 6 {
            r = Float((rgbValue & 0xFF0000) >> 16) / 255.0
            g = Float((rgbValue & 0x00FF00) >> 8) / 255.0
            b = Float(rgbValue & 0x0000FF) / 255.0
        } else {
            r = Float((rgbValue & 0xFF000000) >> 24) / 255.0
            g = Float((rgbValue & 0x00FF0000) >> 16) / 255.0
            b = Float((rgbValue & 0x0000FF00) >> 8) / 255.0
            // Alpha ignored for SIMD3
        }
        
        return SIMD3(r, g, b)
    }
}
