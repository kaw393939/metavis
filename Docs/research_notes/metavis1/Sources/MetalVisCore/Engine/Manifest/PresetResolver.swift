import Foundation
import simd

/// Resolves high-level presets (e.g. "studio_dramatic") into explicit engine parameters.
/// This acts as the "Director Agent" layer, translating creative intent into physical values.
public final class PresetResolver: Sendable {
    
    public static let shared = PresetResolver()
    
    private init() {}
    
    // MARK: - Lighting Presets
    
    public func resolveLighting(preset: String) -> LightingDefinition {
        switch preset {
        case "studio_dramatic":
            return LightingDefinition(
                ambientIntensity: 0.05,
                directionalLight: DirectionalLightDefinition(
                    color: "#EEF0FF", // Cool white key
                    direction: [0.5, -0.5, 0.5]
                ),
                preset: "studio_dramatic"
            )
        case "warm_sunset":
            return LightingDefinition(
                ambientIntensity: 0.2,
                directionalLight: DirectionalLightDefinition(
                    color: "#FF9900", // Warm orange
                    direction: [-0.8, -0.2, 0.0]
                ),
                preset: "warm_sunset"
            )
        case "cyberpunk_neon":
            return LightingDefinition(
                ambientIntensity: 0.0,
                directionalLight: DirectionalLightDefinition(
                    color: "#00FFCC", // Cyan
                    direction: [0.0, -1.0, 0.0]
                ),
                preset: "cyberpunk_neon"
            )
        default:
            // Default to neutral studio
            return LightingDefinition(
                ambientIntensity: 0.1,
                directionalLight: DirectionalLightDefinition(
                    color: "#FFFFFF",
                    direction: [0.0, -1.0, 1.0]
                ),
                preset: nil
            )
        }
    }
    
    // MARK: - Particle Presets
    
    public struct ResolvedParticlePhysics {
        public let emissionRate: Float
        public let lifetime: Float
        public let temperature: Float
        public let turbulence: Float
        public let blackbodyEnabled: Bool
    }
    
    public func resolveParticles(preset: String) -> ResolvedParticlePhysics {
        switch preset {
        case "blackbody_embers":
            return ResolvedParticlePhysics(
                emissionRate: 500,
                lifetime: 4.0,
                temperature: 1800,
                turbulence: 0.5,
                blackbodyEnabled: true
            )
        case "digital_rain":
            return ResolvedParticlePhysics(
                emissionRate: 1000,
                lifetime: 2.0,
                temperature: 0, // Not used for digital
                turbulence: 0.0,
                blackbodyEnabled: false
            )
        case "warp_speed":
            return ResolvedParticlePhysics(
                emissionRate: 2000,
                lifetime: 1.0,
                temperature: 8000, // Blue-hot
                turbulence: 0.1,
                blackbodyEnabled: true
            )
        case "STARS":
            return ResolvedParticlePhysics(
                emissionRate: 5000,
                lifetime: 100.0,
                temperature: 6500, // White
                turbulence: 0.0,
                blackbodyEnabled: false
            )
        default:
            return ResolvedParticlePhysics(
                emissionRate: 100,
                lifetime: 1.0,
                temperature: 1000,
                turbulence: 0.0,
                blackbodyEnabled: false
            )
        }
    }
    
    // MARK: - Post-Process Presets
    
    public func resolveLUT(name: String) -> String {
        // In a real system, this might map "TealOrange" to "Assets/LUTs/teal_orange_v3.cube"
        // For now, we pass through or normalize names
        return name
    }
}
