import Foundation
import simd

/// Represents a named color grading preset.
public struct ColorPreset: Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let params: ColorGradeParams
    
    public init(id: String, name: String, description: String, params: ColorGradeParams) {
        self.id = id
        self.name = name
        self.description = description
        self.params = params
    }
}

/// A collection of "Hollywood-grade" presets for the MetaVis pipeline.
public struct ColorPresetLibrary {
    
    public static let all: [ColorPreset] = [
        standard,
        tealAndOrange,
        noir,
        bleachBypass,
        warmRetro,
        cyberpunk,
        matrix,
        dayForNight
    ]
    
    // MARK: - Presets
    
    /// The default starting point. Neutral.
    public static let standard = ColorPreset(
        id: "std_neutral",
        name: "Cinema Standard",
        description: "A neutral, balanced starting point with slight contrast for a filmic look.",
        params: ColorGradeParams(
            saturation: 1.05,
            contrast: 1.05
        )
    )
    
    /// The classic blockbuster look.
    /// Pushes shadows towards teal and highlights towards orange.
    public static let tealAndOrange = ColorPreset(
        id: "look_teal_orange",
        name: "Blockbuster (Teal & Orange)",
        description: "The classic Hollywood action look. Warm skin tones, cool shadows.",
        params: ColorGradeParams(
            // Warm Highlights (Gain/Slope)
            slope: SIMD3<Float>(1.1, 1.0, 0.9),
            // Cool Shadows (Lift/Offset)
            offset: SIMD3<Float>(-0.02, -0.01, 0.02),
            saturation: 1.1,
            contrast: 1.1
        )
    )
    
    /// High contrast black and white.
    public static let noir = ColorPreset(
        id: "look_noir",
        name: "Film Noir",
        description: "High contrast black and white. Moody and dramatic.",
        params: ColorGradeParams(
            exposure: -0.5,
            saturation: 0.0,
            contrast: 1.3
        )
    )
    
    /// Simulates the silver retention process.
    /// High contrast, low saturation.
    public static let bleachBypass = ColorPreset(
        id: "look_bleach",
        name: "Bleach Bypass",
        description: "Gritty, high-contrast, desaturated look common in war films.",
        params: ColorGradeParams(
            saturation: 0.6,
            contrast: 1.4,
            contrastPivot: 0.5 // Pivot higher to crush blacks more
        )
    )
    
    /// Warm, nostalgic feel.
    public static let warmRetro = ColorPreset(
        id: "look_retro",
        name: "Warm Retro",
        description: "Nostalgic, golden-hour feel with lifted blacks.",
        params: ColorGradeParams(
            temperature: 1500, // Warmer
            offset: SIMD3<Float>(0.02, 0.01, 0.0), // Lifted blacks (faded)
            contrast: 0.9
        )
    )
    
    /// Neon, high saturation, cool bias.
    public static let cyberpunk = ColorPreset(
        id: "look_cyber",
        name: "Cyberpunk",
        description: "Vibrant, neon-soaked aesthetic with a cool magenta bias.",
        params: ColorGradeParams(
            tint: 20, // Magenta shift
            slope: SIMD3<Float>(0.9, 1.0, 1.2), // Cool gain
            saturation: 1.3,
            contrast: 1.1
        )
    )
    
    /// Green tint, crushed blacks.
    public static let matrix = ColorPreset(
        id: "look_matrix",
        name: "System Failure",
        description: "Sickly green tint with crushed blacks.",
        params: ColorGradeParams(
            tint: -30, // Green shift
            slope: SIMD3<Float>(0.8, 1.1, 0.8), // Green gain
            contrast: 1.2
        )
    )
    
    /// Simulates night time shooting during the day.
    /// Blue tint, underexposed.
    public static let dayForNight = ColorPreset(
        id: "look_daynight",
        name: "Day for Night",
        description: "Simulates moonlight. Blue cast and underexposed.",
        params: ColorGradeParams(
            exposure: -2.0,
            temperature: -2000, // Cool
            saturation: 0.7,
            contrast: 1.1
        )
    )
}

// MARK: - Codable Conformance for ColorGradeParams
// We need to add Codable conformance to the struct defined in SimulationEngine.swift
// Since it's defined inside the Engine file but not as a nested type of the class (based on my edit),
// we can extend it here or ensure the original definition has Codable.
//
// Note: SIMD types are not Codable by default in Swift Standard Library.
// We need to add conformance or use a wrapper. For simplicity in this prototype,
// we will assume the UI Agent handles the mapping, or we add a helper here.

// Extension moved to ColorMatchSolver.swift to avoid redundant conformance.
