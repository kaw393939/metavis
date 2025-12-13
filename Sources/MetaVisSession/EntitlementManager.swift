import Foundation
import MetaVisCore

/// Enforces the rules defined by the UserPlan.
public final class EntitlementManager: @unchecked Sendable {
    
    /// Thread-safe queue for plan updates.
    private let queue = DispatchQueue(label: "com.metavis.entitlements")

    private var _currentPlan: UserPlan

    /// The current active plan for this session/app instance.
    public var currentPlan: UserPlan {
        queue.sync { _currentPlan }
    }
    
    public init(initialPlan: UserPlan = .free) {
        self._currentPlan = initialPlan
    }
    
    /// Attempt to upgrade the plan using an Unlock Code.
    /// In a real app, this would verify a cryptographic signature.
    public func applyUnlockCode(_ code: String) -> Bool {
        // Mock Verification
        if code == "UNLOCK_PRO_2025" {
            queue.sync {
                _currentPlan = .pro
            }
            return true
        }
        return false
    }
    
    // MARK: - Checks
    
    /// Can the user create a new project of this type?
    public func canCreateProject(type: ProjectType, currentCount: Int) -> Bool {
        let plan = currentPlan
        // check limits
        if currentCount >= plan.maxProjectCount { return false }
        // check type
        return plan.allowedProjectTypes.contains(type)
    }
    
    /// Can the user export at this resolution?
    public func canExport(resolutionHeight: Int) -> Bool {
        let plan = currentPlan
        return resolutionHeight <= plan.maxResolution
    }
}
