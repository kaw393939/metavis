// Sources/MetaVisRender/Ingestion/Core/LUTLoader.swift
// Sprint 03: Parse .cube LUT files for color grading

import Foundation
import simd

// MARK: - LUT Loader

/// Loads and parses .cube LUT files
public struct LUTLoader {
    
    /// Load a LUT from a .cube file
    public static func load(from url: URL) throws -> LUTData {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LUTError.fileNotFound(url)
        }
        
        let content = try String(contentsOf: url, encoding: .utf8)
        return try parse(content, path: url.path)
    }
    
    /// Load a LUT from string content
    public static func parse(_ content: String, path: String = "") throws -> LUTData {
        var title: String?
        var size: Int?
        var type: LUTType = .cube3D
        var domainMin = SIMD3<Float>(0, 0, 0)
        var domainMax = SIMD3<Float>(1, 1, 1)
        var entries: [SIMD3<Float>] = []
        
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            
            // Parse keywords
            if trimmed.hasPrefix("TITLE") {
                title = parseQuotedString(from: trimmed)
            } else if trimmed.hasPrefix("LUT_3D_SIZE") {
                size = parseInt(from: trimmed)
                type = .cube3D
            } else if trimmed.hasPrefix("LUT_1D_SIZE") {
                size = parseInt(from: trimmed)
                type = .cube1D
            } else if trimmed.hasPrefix("DOMAIN_MIN") {
                domainMin = parseVector(from: trimmed) ?? domainMin
            } else if trimmed.hasPrefix("DOMAIN_MAX") {
                domainMax = parseVector(from: trimmed) ?? domainMax
            } else {
                // Try to parse as RGB values
                if let rgb = parseRGBLine(trimmed) {
                    entries.append(rgb)
                }
            }
        }
        
        guard let lutSize = size else {
            throw LUTError.missingSizeDeclaration
        }
        
        let expectedCount: Int
        switch type {
        case .cube1D:
            expectedCount = lutSize
        case .cube3D:
            expectedCount = lutSize * lutSize * lutSize
        }
        
        guard entries.count == expectedCount else {
            throw LUTError.invalidEntryCount(expected: expectedCount, got: entries.count)
        }
        
        return LUTData(
            path: path,
            title: title,
            type: type,
            size: lutSize,
            domainMin: domainMin,
            domainMax: domainMax,
            entries: entries
        )
    }
    
    // MARK: - Parsing Helpers
    
    private static func parseQuotedString(from line: String) -> String? {
        guard let firstQuote = line.firstIndex(of: "\""),
              let lastQuote = line.lastIndex(of: "\""),
              firstQuote < lastQuote else {
            // Try without quotes
            let parts = line.split(separator: " ", maxSplits: 1)
            return parts.count > 1 ? String(parts[1]) : nil
        }
        
        let start = line.index(after: firstQuote)
        return String(line[start..<lastQuote])
    }
    
    private static func parseInt(from line: String) -> Int? {
        let parts = line.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        return Int(parts[1])
    }
    
    private static func parseVector(from line: String) -> SIMD3<Float>? {
        let parts = line.split(separator: " ").compactMap { Float($0) }
        guard parts.count >= 3 else { return nil }
        return SIMD3(parts[0], parts[1], parts[2])
    }
    
    private static func parseRGBLine(_ line: String) -> SIMD3<Float>? {
        let parts = line.split(separator: " ").compactMap { Float($0) }
        guard parts.count >= 3 else { return nil }
        return SIMD3(parts[0], parts[1], parts[2])
    }
}

// MARK: - LUT Data

/// Loaded LUT data
public struct LUTData: Codable, Sendable, Equatable {
    /// Original file path
    public let path: String
    /// LUT title from file
    public let title: String?
    /// LUT type (1D or 3D)
    public let type: LUTType
    /// Grid size (e.g., 16, 33, 65)
    public let size: Int
    /// Input domain minimum (usually 0,0,0)
    public let domainMin: SIMD3<Float>
    /// Input domain maximum (usually 1,1,1)
    public let domainMax: SIMD3<Float>
    /// RGB entries (size^3 for 3D, size for 1D)
    public let entries: [SIMD3<Float>]
    
    /// Number of entries
    public var entryCount: Int { entries.count }
    
    /// Expected entry count for validation
    public var expectedEntryCount: Int {
        switch type {
        case .cube1D: return size
        case .cube3D: return size * size * size
        }
    }
    
    /// Is the LUT valid?
    public var isValid: Bool { entryCount == expectedEntryCount }
    
    /// Apply LUT to a color value (3D only)
    public func apply(to color: SIMD3<Float>) -> SIMD3<Float> {
        guard type == .cube3D && isValid else { return color }
        
        // Normalize to domain
        let normalized = (color - domainMin) / (domainMax - domainMin)
        let clamped = simd_clamp(normalized, SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 1, 1))
        
        // Scale to LUT indices
        let scaled = clamped * Float(size - 1)
        
        // Get base indices
        let r0 = Int(scaled.x)
        let g0 = Int(scaled.y)
        let b0 = Int(scaled.z)
        
        let r1 = min(r0 + 1, size - 1)
        let g1 = min(g0 + 1, size - 1)
        let b1 = min(b0 + 1, size - 1)
        
        // Fractional parts
        let fr = scaled.x - Float(r0)
        let fg = scaled.y - Float(g0)
        let fb = scaled.z - Float(b0)
        
        // Trilinear interpolation
        let c000 = entry(r: r0, g: g0, b: b0)
        let c001 = entry(r: r0, g: g0, b: b1)
        let c010 = entry(r: r0, g: g1, b: b0)
        let c011 = entry(r: r0, g: g1, b: b1)
        let c100 = entry(r: r1, g: g0, b: b0)
        let c101 = entry(r: r1, g: g0, b: b1)
        let c110 = entry(r: r1, g: g1, b: b0)
        let c111 = entry(r: r1, g: g1, b: b1)
        
        let c00 = mix(c000, c100, t: fr)
        let c01 = mix(c001, c101, t: fr)
        let c10 = mix(c010, c110, t: fr)
        let c11 = mix(c011, c111, t: fr)
        
        let c0 = mix(c00, c10, t: fg)
        let c1 = mix(c01, c11, t: fg)
        
        return mix(c0, c1, t: fb)
    }
    
    private func entry(r: Int, g: Int, b: Int) -> SIMD3<Float> {
        let index = r + g * size + b * size * size
        return entries[index]
    }
    
    private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        return a * (1 - t) + b * t
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case path, title, type, size, domainMin, domainMax, entries
    }
    
    public init(
        path: String,
        title: String?,
        type: LUTType,
        size: Int,
        domainMin: SIMD3<Float>,
        domainMax: SIMD3<Float>,
        entries: [SIMD3<Float>]
    ) {
        self.path = path
        self.title = title
        self.type = type
        self.size = size
        self.domainMin = domainMin
        self.domainMax = domainMax
        self.entries = entries
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        type = try container.decode(LUTType.self, forKey: .type)
        size = try container.decode(Int.self, forKey: .size)
        
        let domainMinArray = try container.decode([Float].self, forKey: .domainMin)
        domainMin = SIMD3(domainMinArray[0], domainMinArray[1], domainMinArray[2])
        
        let domainMaxArray = try container.decode([Float].self, forKey: .domainMax)
        domainMax = SIMD3(domainMaxArray[0], domainMaxArray[1], domainMaxArray[2])
        
        let entriesArray = try container.decode([[Float]].self, forKey: .entries)
        entries = entriesArray.map { SIMD3($0[0], $0[1], $0[2]) }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encode(type, forKey: .type)
        try container.encode(size, forKey: .size)
        try container.encode([domainMin.x, domainMin.y, domainMin.z], forKey: .domainMin)
        try container.encode([domainMax.x, domainMax.y, domainMax.z], forKey: .domainMax)
        try container.encode(entries.map { [$0.x, $0.y, $0.z] }, forKey: .entries)
    }
}

// MARK: - LUT Type

public enum LUTType: String, Codable, Sendable {
    case cube1D = "1D"
    case cube3D = "3D"
}

// MARK: - Errors

public enum LUTError: LocalizedError, Sendable {
    case fileNotFound(URL)
    case missingSizeDeclaration
    case invalidEntryCount(expected: Int, got: Int)
    case invalidFormat(String)
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "LUT file not found: \(url.path)"
        case .missingSizeDeclaration:
            return "LUT file missing LUT_3D_SIZE or LUT_1D_SIZE declaration"
        case .invalidEntryCount(let expected, let got):
            return "Invalid LUT entry count: expected \(expected), got \(got)"
        case .invalidFormat(let message):
            return "Invalid LUT format: \(message)"
        }
    }
}

// MARK: - LUT Analysis

/// Analyzes a LUT to extract characteristics
public struct LUTAnalyzer {
    
    /// Analyze a LUT to understand its effect
    public static func analyze(_ lut: LUTData) -> LUTAnalysis {
        guard lut.type == .cube3D && lut.isValid else {
            return LUTAnalysis.neutral
        }
        
        // Sample the LUT at key points
        let shadows = lut.apply(to: SIMD3<Float>(0.1, 0.1, 0.1))
        let midtones = lut.apply(to: SIMD3<Float>(0.5, 0.5, 0.5))
        let highlights = lut.apply(to: SIMD3<Float>(0.9, 0.9, 0.9))
        
        // Neutral reference
        let neutralShadows = SIMD3<Float>(0.1, 0.1, 0.1)
        let neutralMidtones = SIMD3<Float>(0.5, 0.5, 0.5)
        let neutralHighlights = SIMD3<Float>(0.9, 0.9, 0.9)
        
        // Calculate color shift
        let colorShift = calculateColorShift(
            shadows: shadows - neutralShadows,
            midtones: midtones - neutralMidtones,
            highlights: highlights - neutralHighlights
        )
        
        // Calculate contrast adjustment
        let inputRange = simd_length(neutralHighlights - neutralShadows)
        let outputRange = simd_length(highlights - shadows)
        let contrastAdjustment = (outputRange / inputRange) - 1.0
        
        // Calculate saturation adjustment
        let saturationAdjustment = calculateSaturationChange(lut)
        
        // Categorize the look
        let category = categorizeLook(
            colorShift: colorShift,
            contrast: contrastAdjustment,
            saturation: saturationAdjustment
        )
        
        // Generate description
        let description = generateDescription(
            colorShift: colorShift,
            contrast: contrastAdjustment,
            saturation: saturationAdjustment
        )
        
        return LUTAnalysis(
            colorShift: colorShift,
            contrastAdjustment: contrastAdjustment,
            saturationAdjustment: saturationAdjustment,
            category: category,
            description: description
        )
    }
    
    private static func calculateColorShift(
        shadows: SIMD3<Float>,
        midtones: SIMD3<Float>,
        highlights: SIMD3<Float>
    ) -> ColorShift {
        // Average shift across tonal ranges
        let avgShift = (shadows + midtones + highlights) / 3
        
        // Determine direction
        let direction: String
        if avgShift.x > avgShift.z + 0.02 {
            direction = "warm"
        } else if avgShift.z > avgShift.x + 0.02 {
            direction = "cool"
        } else if avgShift.y > (avgShift.x + avgShift.z) / 2 + 0.02 {
            direction = "green"
        } else if avgShift.y < (avgShift.x + avgShift.z) / 2 - 0.02 {
            direction = "magenta"
        } else {
            direction = "neutral"
        }
        
        let magnitude = simd_length(avgShift)
        
        return ColorShift(
            direction: direction,
            magnitude: magnitude,
            rgb: avgShift
        )
    }
    
    private static func calculateSaturationChange(_ lut: LUTData) -> Float {
        // Test with saturated colors
        let red = lut.apply(to: SIMD3<Float>(1, 0, 0))
        let green = lut.apply(to: SIMD3<Float>(0, 1, 0))
        let blue = lut.apply(to: SIMD3<Float>(0, 0, 1))
        
        let inputSat = (saturation(SIMD3<Float>(1, 0, 0)) +
                       saturation(SIMD3<Float>(0, 1, 0)) +
                       saturation(SIMD3<Float>(0, 0, 1))) / 3
        
        let outputSat = (saturation(red) + saturation(green) + saturation(blue)) / 3
        
        return (outputSat / inputSat) - 1.0
    }
    
    private static func saturation(_ rgb: SIMD3<Float>) -> Float {
        let maxC = max(rgb.x, max(rgb.y, rgb.z))
        let minC = min(rgb.x, min(rgb.y, rgb.z))
        let delta = maxC - minC
        
        if maxC > 0 {
            return delta / maxC
        }
        return 0
    }
    
    private static func categorizeLook(
        colorShift: ColorShift,
        contrast: Float,
        saturation: Float
    ) -> LookCategory {
        // Desaturated and warm = vintage
        if saturation < -0.2 && colorShift.direction == "warm" {
            return .vintage
        }
        
        // Heavy contrast and slight desaturation = cinematic
        if contrast > 0.1 && saturation < 0 {
            return .cinematic
        }
        
        // Significant color shift = stylized
        if colorShift.magnitude > 0.1 {
            return .stylized
        }
        
        // Nearly neutral = clean
        if abs(contrast) < 0.05 && abs(saturation) < 0.05 {
            return .clean
        }
        
        return .custom
    }
    
    private static func generateDescription(
        colorShift: ColorShift,
        contrast: Float,
        saturation: Float
    ) -> String {
        var parts: [String] = []
        
        // Color
        if colorShift.direction != "neutral" {
            parts.append(colorShift.direction)
        }
        
        // Saturation
        if saturation < -0.2 {
            parts.append("desaturated")
        } else if saturation > 0.2 {
            parts.append("saturated")
        }
        
        // Contrast
        if contrast > 0.15 {
            parts.append("high contrast")
        } else if contrast < -0.15 {
            parts.append("low contrast")
        }
        
        if parts.isEmpty {
            return "neutral"
        }
        
        return parts.joined(separator: ", ")
    }
}

// MARK: - Analysis Types

/// Color shift analysis
public struct ColorShift: Codable, Sendable, Equatable {
    public let direction: String
    public let magnitude: Float
    public let rgb: SIMD3<Float>
    
    enum CodingKeys: String, CodingKey {
        case direction, magnitude, rgb
    }
    
    public init(direction: String, magnitude: Float, rgb: SIMD3<Float>) {
        self.direction = direction
        self.magnitude = magnitude
        self.rgb = rgb
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        direction = try container.decode(String.self, forKey: .direction)
        magnitude = try container.decode(Float.self, forKey: .magnitude)
        let rgbArray = try container.decode([Float].self, forKey: .rgb)
        rgb = SIMD3(rgbArray[0], rgbArray[1], rgbArray[2])
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(direction, forKey: .direction)
        try container.encode(magnitude, forKey: .magnitude)
        try container.encode([rgb.x, rgb.y, rgb.z], forKey: .rgb)
    }
}

/// Look category
public enum LookCategory: String, Codable, Sendable {
    case cinematic
    case vintage
    case clean
    case stylized
    case custom
}

/// LUT analysis result
public struct LUTAnalysis: Codable, Sendable, Equatable {
    public let colorShift: ColorShift
    public let contrastAdjustment: Float
    public let saturationAdjustment: Float
    public let category: LookCategory
    public let description: String
    
    /// Neutral/identity LUT analysis
    public static let neutral = LUTAnalysis(
        colorShift: ColorShift(direction: "neutral", magnitude: 0, rgb: SIMD3<Float>(0, 0, 0)),
        contrastAdjustment: 0,
        saturationAdjustment: 0,
        category: .clean,
        description: "neutral"
    )
}
