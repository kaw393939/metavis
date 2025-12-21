import Foundation

/// Defines the color primaries (gamut) of a color space.
public enum ColorPrimaries: String, Codable, Sendable, CaseIterable {
    /// Rec.709 / sRGB primaries (HDTV, Web)
    case rec709
    /// P3-D65 primaries (Apple Display, Digital Cinema)
    case p3d65
    /// Rec.2020 primaries (UHDTV)
    case rec2020
    /// ACES AP1 primaries (ACEScg working space)
    case acescg
    /// ACES AP0 primaries (ACES2065-1 archival space)
    case aces2065_1
    
    public var whitePoint: WhitePoint {
        switch self {
        case .rec709, .p3d65, .rec2020:
            return .d65
        case .acescg, .aces2065_1:
            return .d60
        }
    }
}

/// Defines the white point (illuminant) of the color space.
public enum WhitePoint: String, Codable, Sendable {
    /// Standard Daylight (6504K) - Used by sRGB, Rec.709, Rec.2020, P3
    case d65
    /// ACES White Point (6000K) - Used by ACEScg, ACES2065-1
    case d60
    /// Horizon Light (5000K) - Used by Print (D50)
    case d50
}

/// Defines the transfer function (gamma/curve) of a color space.
public enum TransferFunction: String, Codable, Sendable, CaseIterable {
    /// Linear light (Physical)
    case linear
    /// sRGB transfer function (Web)
    case sRGB
    /// Rec.709 / BT.1886 (Gamma 2.4)
    case rec709
    /// Perceptual Quantizer (ST.2084) - HDR
    case pq
    /// Hybrid Log-Gamma (BT.2100) - HDR
    case hlg
    /// Apple Log (iPhone 15 Pro+)
    case appleLog
    /// ARRI LogC3
    case logC3
    /// Sony S-Log3
    case sLog3
}

/// A complete definition of a Color Space, combining Primaries and Transfer Function.
public struct ColorProfile: Codable, Sendable, Equatable {
    public let primaries: ColorPrimaries
    public let transferFunction: TransferFunction
    
    public init(primaries: ColorPrimaries, transferFunction: TransferFunction) {
        self.primaries = primaries
        self.transferFunction = transferFunction
    }
    
    // MARK: - Common Profiles
    
    public static let sRGB = ColorProfile(primaries: .rec709, transferFunction: .sRGB)
    public static let rec709 = ColorProfile(primaries: .rec709, transferFunction: .rec709)
    public static let acescg = ColorProfile(primaries: .acescg, transferFunction: .linear)
    public static let appleLog = ColorProfile(primaries: .rec2020, transferFunction: .appleLog)
    public static let p3Display = ColorProfile(primaries: .p3d65, transferFunction: .sRGB) // Approximate for P3 displays
}
