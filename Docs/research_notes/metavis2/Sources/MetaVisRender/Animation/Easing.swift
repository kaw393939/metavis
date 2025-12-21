import Foundation

public enum Easing {
    case linear
    case easeInQuad
    case easeOutQuad
    case easeInOutQuad
    case easeInCubic
    case easeOutCubic
    case easeInOutCubic
    case easeOutBack
    case easeOutElastic
    
    public func apply(_ t: Double) -> Double {
        switch self {
        case .linear:
            return t
        case .easeInQuad:
            return t * t
        case .easeOutQuad:
            return t * (2 - t)
        case .easeInOutQuad:
            return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t
        case .easeInCubic:
            return t * t * t
        case .easeOutCubic:
            let t1 = t - 1
            return t1 * t1 * t1 + 1
        case .easeInOutCubic:
            return t < 0.5 ? 4 * t * t * t : (t - 1) * (2 * t - 2) * (2 * t - 2) + 1
        case .easeOutBack:
            let c1 = 1.70158
            let c3 = c1 + 1
            let t1 = t - 1
            return 1 + c3 * pow(t1, 3) + c1 * pow(t1, 2)
        case .easeOutElastic:
            let c4 = (2 * Double.pi) / 3
            return t == 0 ? 0 : t == 1 ? 1 : pow(2, -10 * t) * sin((t * 10 - 0.75) * c4) + 1
        }
    }
}
