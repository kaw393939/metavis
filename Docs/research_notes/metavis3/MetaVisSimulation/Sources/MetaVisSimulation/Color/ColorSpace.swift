// ColorSpace.swift
// MetaVisSimulation
//
// Ported from MetaVisRender for Simulation Engine

import Foundation
import simd

// MARK: - Render Color Space

/// A render-focused color space definition for the pipeline.
/// Uses the existing ColorPrimaries and TransferFunction enums.
public struct RenderColorSpace: Equatable, Hashable, Sendable {
    
    /// The color primaries (defines the gamut)
    public let primaries: ColorPrimaries
    
    /// The transfer function (defines the encoding)
    public let transfer: TransferFunction
    
    /// Human-readable name
    public var name: String {
        "\(primaries.rawValue)_\(transfer.rawValue)"
    }
    
    public init(primaries: ColorPrimaries, transfer: TransferFunction) {
        self.primaries = primaries
        self.transfer = transfer
    }
    
    // MARK: - Common Color Spaces
    
    /// Linear ACEScg - The MetaVis working space (approximated as Linear BT.2020)
    /// All internal rendering happens in this space.
    public static let acescg = RenderColorSpace(primaries: .bt2020, transfer: .linear)
    
    /// Standard HD video (Rec.709 primaries with BT.1886 gamma)
    public static let rec709 = RenderColorSpace(primaries: .bt709, transfer: .bt709)
    
    /// sRGB - Standard web/display space
    public static let sRGB = RenderColorSpace(primaries: .sRGB, transfer: .sRGB)
    
    /// Display P3 - Apple displays
    public static let displayP3 = RenderColorSpace(primaries: .p3D65, transfer: .sRGB)
    
    /// Linear Rec.709 - For intermediate processing
    public static let linearRec709 = RenderColorSpace(primaries: .bt709, transfer: .linear)
    
    /// HDR10 - Rec.2020 with PQ transfer
    public static let hdr10 = RenderColorSpace(primaries: .bt2020, transfer: .pq)
    
    /// HLG HDR - Common for broadcast and iPhone
    public static let hlg = RenderColorSpace(primaries: .bt2020, transfer: .hlg)
    
    /// P3 HLG - iPhone HDR video
    public static let p3HLG = RenderColorSpace(primaries: .p3D65, transfer: .hlg)
    
    // MARK: - Conversion Matrices
    
    /// 3x3 matrix to convert from this color space's primaries to ACEScg (AP1)
    public var toACEScgMatrix: simd_float3x3 {
        switch primaries {
        case .bt709, .sRGB:
            // Rec.709 to ACEScg (AP1)
            return simd_float3x3(rows: [
                simd_float3(0.6131324224, 0.3395380158, 0.0473295618),
                simd_float3(0.0701934641, 0.9163940189, 0.0134125170),
                simd_float3(0.0205844026, 0.1095745716, 0.8698410258)
            ])
            
        case .p3DCI, .p3D65:
            // P3-D65 to ACEScg (AP1)
            return simd_float3x3(rows: [
                simd_float3(0.7552984714, 0.1989753246, 0.0457262040),
                simd_float3(0.0538656600, 0.9432320991, 0.0029022409),
                simd_float3(-0.0092892530, 0.0175662269, 0.9917230261)
            ])
            
        case .bt2020:
            // Rec.2020 to ACEScg (AP1)
            return simd_float3x3(rows: [
                simd_float3(0.9752692986, 0.0193603288, 0.0053703726),
                simd_float3(0.0170327418, 0.9777882457, 0.0051790125),
                simd_float3(-0.0025241304, 0.0037378438, 0.9987862866)
            ])
            
        case .adobeRGB, .unknown:
            // Default to identity for unknown
            return matrix_identity_float3x3
        }
    }
    
    /// 3x3 matrix to convert from ACEScg (AP1) to this color space's primaries
    public var fromACEScgMatrix: simd_float3x3 {
        switch primaries {
        case .bt709, .sRGB:
            // ACEScg (AP1) to Rec.709
            return simd_float3x3(rows: [
                simd_float3(1.7050509310, -0.6217921210, -0.0832588100),
                simd_float3(-0.1302564950, 1.1408047740, -0.0105482790),
                simd_float3(-0.0240033570, -0.1289689740, 1.1529723310)
            ])
            
        case .p3DCI, .p3D65:
            // ACEScg (AP1) to P3-D65
            return simd_float3x3(rows: [
                simd_float3(1.3434094292, -0.2820294141, -0.0613800152),
                simd_float3(-0.0653203441, 1.0757827759, -0.0104624318),
                simd_float3(0.0028161583, -0.0195617718, 1.0167456135)
            ])
            
        case .bt2020:
            // ACEScg (AP1) to Rec.2020
            return simd_float3x3(rows: [
                simd_float3(1.0258246660, -0.0200052287, -0.0058194373),
                simd_float3(-0.0178571150, 1.0228070989, -0.0049499839),
                simd_float3(0.0025862681, -0.0038143971, 1.0012281290)
            ])
            
        case .adobeRGB, .unknown:
            // Default to identity for unknown
            return matrix_identity_float3x3
        }
    }
    
    /// Whether this color space requires linearization before matrix conversion
    public var needsLinearization: Bool {
        transfer != .linear
    }
    
    /// Whether this is a log-encoded camera format
    public var isLogEncoded: Bool {
        transfer == .log
    }
    
    /// Whether this is an HDR format
    public var isHDR: Bool {
        switch transfer {
        case .pq, .hlg:
            return true
        default:
            return false
        }
    }
}

// MARK: - CustomStringConvertible

extension RenderColorSpace: CustomStringConvertible {
    public var description: String {
        name
    }
}

// MARK: - CaseIterable Support

extension RenderColorSpace {
    /// Common color spaces for UI selection
    public static var commonSpaces: [RenderColorSpace] {
        [.rec709, .sRGB, .displayP3, .hdr10, .hlg, .acescg]
    }
    
    /// Create from string identifier (e.g. "rec709", "log", "slog3")
    public static func from(identifier: String) -> RenderColorSpace {
        switch identifier.lowercased() {
        case "rec709", "bt709": return .rec709
        case "srgb": return .sRGB
        case "p3", "displayp3": return .displayP3
        case "bt2020": return RenderColorSpace(primaries: .bt2020, transfer: .bt709) // Default to BT.709 gamma if only primaries specified
        case "hdr10", "pq": return .hdr10
        case "hlg": return .hlg
        case "log", "logc3": return RenderColorSpace(primaries: .bt709, transfer: .log) // Assuming LogC3 uses BT.709 primaries or similar wide gamut? Actually LogC3 usually uses Alexa Wide Gamut.
        // For now, let's map "log" to BT.709 primaries + Log transfer, which maps to LogC3 in shader.
        // Ideally we should add .alexaWideGamut primaries.
        case "slog3": return RenderColorSpace(primaries: .bt2020, transfer: .slog3) // S-Log3 often used with S-Gamut3.Cine (close to P3/2020)
        case "applelog": return RenderColorSpace(primaries: .bt2020, transfer: .appleLog)
        default: return .rec709
        }
    }
}

// MARK: - ColorPrimaries Shader Value

extension ColorPrimaries {
    /// Maps to the Metal shader enum value
    var idtShaderValue: UInt32 {
        switch self {
        case .bt709, .sRGB: return 0
        case .p3DCI, .p3D65: return 1
        case .bt2020: return 2
        case .adobeRGB, .unknown: return 0  // Default to Rec.709
        }
    }
}

// MARK: - TransferFunction Shader Value

extension TransferFunction {
    /// Maps to the Metal shader enum value
    var idtShaderValue: UInt32 {
        switch self {
        case .linear: return 0
        case .sRGB: return 1
        case .bt709: return 2
        case .pq: return 3
        case .hlg: return 4
        case .log: return 5  // Map to LogC3
        case .slog3: return 6 // Map to SLog3
        case .appleLog: return 7
        case .gamma22, .gamma28: return 1  // Approximate as sRGB
        case .unknown: return 2  // Default to Rec.709
        }
    }
}
