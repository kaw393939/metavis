import Foundation

// MARK: - App Level Governance

/// Defines the types of projects a user can create.
public enum ProjectType: String, Codable, Sendable, CaseIterable {
    case basic          // Restricted features
    case cinema         // Full feature set
    case lab            // Validation/Dev
    case commercial     // Enterprise features
}

public extension ProjectType {
    /// Default project recipe ID for this project type.
    ///
    /// Note: This is intentionally a string mapping (no module dependency on MetaVisSession).
    var defaultRecipeID: String {
        switch self {
        case .basic:
            return "com.metavis.recipe.smoke_test_2s"
        case .cinema:
            return "com.metavis.recipe.god_test_20s"
        case .lab:
            return "com.metavis.recipe.god_test_20s"
        case .commercial:
            return "com.metavis.recipe.god_test_20s"
        }
    }
}

/// Defines the capabilities of a User Account.
public struct UserPlan: Codable, Sendable, Equatable {
    public let name: String
    public let maxProjectCount: Int
    public let allowedProjectTypes: Set<ProjectType>
    public let maxResolution: Int // e.g., 1080 (height)
    
    public init(
        name: String,
        maxProjectCount: Int,
        allowedProjectTypes: Set<ProjectType>,
        maxResolution: Int
    ) {
        self.name = name
        self.maxProjectCount = maxProjectCount
        self.allowedProjectTypes = allowedProjectTypes
        self.maxResolution = maxResolution
    }
    
    // Default Plans
    public static let free = UserPlan(
        name: "Free",
        maxProjectCount: 3,
        allowedProjectTypes: [.basic],
        maxResolution: 1080
    )
    
    public static let pro = UserPlan(
        name: "Pro",
        maxProjectCount: Int.max,
        allowedProjectTypes: [.basic, .cinema, .lab],
        maxResolution: 4320 // 8K
    )
}

// MARK: - Project Level Governance

/// Defines the rights associated with a specific Project.
public struct ProjectLicense: Codable, Sendable, Equatable {
    public let licenseId: UUID
    public let ownerId: String
    public var maxExportResolution: Int
    public var requiresWatermark: Bool
    public var allowOpenEXR: Bool
    
    public init(
        licenseId: UUID = UUID(),
        ownerId: String = "anonymous",
        maxExportResolution: Int = 1080,
        requiresWatermark: Bool = true,
        allowOpenEXR: Bool = false
    ) {
        self.licenseId = licenseId
        self.ownerId = ownerId
        self.maxExportResolution = maxExportResolution
        self.requiresWatermark = requiresWatermark
        self.allowOpenEXR = allowOpenEXR
    }
}

// MARK: - Watermarking

/// Describes how an export watermark should be applied.
public struct WatermarkSpec: Codable, Sendable, Equatable {
    public enum Style: String, Codable, Sendable {
        case diagonalStripes
    }

    public var style: Style
    /// 0...1. Higher means more visible.
    public var opacity: Float
    /// Stripe thickness in pixels.
    public var stripeWidth: Int
    /// Stripe repeat period in pixels.
    public var stripeSpacing: Int

    public init(
        style: Style = .diagonalStripes,
        opacity: Float = 0.35,
        stripeWidth: Int = 12,
        stripeSpacing: Int = 96
    ) {
        self.style = style
        self.opacity = opacity
        self.stripeWidth = stripeWidth
        self.stripeSpacing = stripeSpacing
    }

    public static var diagonalStripesDefault: WatermarkSpec {
        WatermarkSpec(style: .diagonalStripes)
    }
}

// MARK: - Quality Profile

/// Defines the target fidelity for a render job.
/// This travels from Scheduler -> Engine -> Export.
public struct QualityProfile: Codable, Sendable, Equatable {
    public enum Fidelity: String, Codable, Sendable {
        case draft
        case high
        case master
    }
    
    public let name: String
    public let fidelity: Fidelity
    public let resolutionHeight: Int
    public let colorDepth: Int // 8, 10, 16, 32
    
    public init(name: String, fidelity: Fidelity, resolutionHeight: Int, colorDepth: Int) {
        self.name = name
        self.fidelity = fidelity
        self.resolutionHeight = resolutionHeight
        self.colorDepth = colorDepth
    }
}

// MARK: - Audio Governance

/// Defines audio mastering standards.
public struct LoudnessGovernance: Codable, Sendable, Equatable {
    public enum Standard: String, Codable, Sendable {
        case ebuR128    // -23 LUFS
        case aesStreaming // -14 LUFS
        case none
    }
    
    public let standard: Standard
    public let truePeakLimit: Float // dB
    
    public init(standard: Standard = .aesStreaming, truePeakLimit: Float = -1.0) {
        self.standard = standard
        self.truePeakLimit = truePeakLimit
    }
    
    public static let spotify = LoudnessGovernance(standard: .aesStreaming, truePeakLimit: -1.0)
    public static let broadcast = LoudnessGovernance(standard: .ebuR128, truePeakLimit: -1.0)
}
