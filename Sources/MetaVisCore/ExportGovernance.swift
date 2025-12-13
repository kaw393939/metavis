import Foundation

/// Optional export-time governance constraints.
///
/// This is intentionally lightweight and can be provided by higher layers (e.g. `MetaVisSession`).
public struct ExportGovernance: Codable, Sendable, Equatable {
    public var userPlan: UserPlan?
    public var projectLicense: ProjectLicense?
    public var watermarkSpec: WatermarkSpec?

    public init(userPlan: UserPlan? = nil, projectLicense: ProjectLicense? = nil, watermarkSpec: WatermarkSpec? = nil) {
        self.userPlan = userPlan
        self.projectLicense = projectLicense
        self.watermarkSpec = watermarkSpec
    }

    public static let none = ExportGovernance()
}

public enum ExportGovernanceError: Error, Sendable, Equatable, LocalizedError {
    case resolutionNotAllowed(requestedHeight: Int, maxAllowedHeight: Int)
    case watermarkRequired

    public var errorDescription: String? {
        switch self {
        case .resolutionNotAllowed(let requestedHeight, let maxAllowedHeight):
            return "Export resolution not allowed: requested height \(requestedHeight) exceeds max \(maxAllowedHeight)"
        case .watermarkRequired:
            return "Export requires watermark"
        }
    }
}
