import Foundation

/// Mathematical implementations of easing functions.
/// Separated from the Easing enum to keep the API surface clean.
public enum EasingFunctions {
    // MARK: - Quadratic

    public static func quadraticIn(_ t: Double) -> Double {
        return t * t
    }

    public static func quadraticOut(_ t: Double) -> Double {
        return 1.0 - (1.0 - t) * (1.0 - t)
    }

    public static func quadraticInOut(_ t: Double) -> Double {
        if t < 0.5 {
            return 2.0 * t * t
        } else {
            let f = t - 1.0
            return 1.0 - 2.0 * f * f
        }
    }

    // MARK: - Cubic

    public static func cubicIn(_ t: Double) -> Double {
        return t * t * t
    }

    public static func cubicOut(_ t: Double) -> Double {
        let f = t - 1.0
        return 1.0 + f * f * f
    }

    public static func cubicInOut(_ t: Double) -> Double {
        if t < 0.5 {
            return 4.0 * t * t * t
        } else {
            let f = 2.0 * t - 2.0
            return 1.0 + 0.5 * f * f * f
        }
    }

    // MARK: - Quartic

    public static func quarticIn(_ t: Double) -> Double {
        return t * t * t * t
    }

    public static func quarticOut(_ t: Double) -> Double {
        let f = t - 1.0
        return 1.0 - f * f * f * f
    }

    public static func quarticInOut(_ t: Double) -> Double {
        if t < 0.5 {
            return 8.0 * t * t * t * t
        } else {
            let f = t - 1.0
            return 1.0 - 8.0 * f * f * f * f
        }
    }

    // MARK: - Quintic

    public static func quinticIn(_ t: Double) -> Double {
        return t * t * t * t * t
    }

    public static func quinticOut(_ t: Double) -> Double {
        let f = t - 1.0
        return 1.0 + f * f * f * f * f
    }

    public static func quinticInOut(_ t: Double) -> Double {
        if t < 0.5 {
            return 16.0 * t * t * t * t * t
        } else {
            let f = 2.0 * t - 2.0
            return 1.0 + 0.5 * f * f * f * f * f
        }
    }

    // MARK: - Sine

    public static func sineIn(_ t: Double) -> Double {
        return 1.0 - cos(t * .pi / 2.0)
    }

    public static func sineOut(_ t: Double) -> Double {
        return sin(t * .pi / 2.0)
    }

    public static func sineInOut(_ t: Double) -> Double {
        return 0.5 * (1.0 - cos(t * .pi))
    }

    // MARK: - Exponential

    public static func exponentialIn(_ t: Double) -> Double {
        return t == 0.0 ? 0.0 : pow(2.0, 10.0 * (t - 1.0))
    }

    public static func exponentialOut(_ t: Double) -> Double {
        return t == 1.0 ? 1.0 : 1.0 - pow(2.0, -10.0 * t)
    }

    public static func exponentialInOut(_ t: Double) -> Double {
        if t == 0.0 { return 0.0 }
        if t == 1.0 { return 1.0 }

        if t < 0.5 {
            return 0.5 * pow(2.0, 20.0 * t - 10.0)
        } else {
            return 1.0 - 0.5 * pow(2.0, -20.0 * t + 10.0)
        }
    }

    // MARK: - Circular

    public static func circularIn(_ t: Double) -> Double {
        return 1.0 - sqrt(1.0 - t * t)
    }

    public static func circularOut(_ t: Double) -> Double {
        let f = t - 1.0
        return sqrt(1.0 - f * f)
    }

    public static func circularInOut(_ t: Double) -> Double {
        if t < 0.5 {
            return 0.5 * (1.0 - sqrt(1.0 - 4.0 * t * t))
        } else {
            let f = 2.0 * t - 2.0
            return 0.5 * (sqrt(1.0 - f * f) + 1.0)
        }
    }

    // MARK: - Back

    public static func backIn(_ t: Double) -> Double {
        let s = 1.70158
        return t * t * ((s + 1.0) * t - s)
    }

    public static func backOut(_ t: Double) -> Double {
        let s = 1.70158
        let f = t - 1.0
        return 1.0 + f * f * ((s + 1.0) * f + s)
    }

    public static func backInOut(_ t: Double) -> Double {
        let s = 1.70158 * 1.525
        if t < 0.5 {
            let f = 2.0 * t
            return 0.5 * f * f * ((s + 1.0) * f - s)
        } else {
            let f = 2.0 * t - 2.0
            return 0.5 * (f * f * ((s + 1.0) * f + s) + 2.0)
        }
    }

    // MARK: - Elastic

    public static func elasticIn(_ t: Double) -> Double {
        if t == 0.0 { return 0.0 }
        if t == 1.0 { return 1.0 }

        let p = 0.3
        let s = p / 4.0
        let f = t - 1.0
        return -pow(2.0, 10.0 * f) * sin((f - s) * (2.0 * .pi) / p)
    }

    public static func elasticOut(_ t: Double) -> Double {
        if t == 0.0 { return 0.0 }
        if t == 1.0 { return 1.0 }

        let p = 0.3
        let s = p / 4.0
        return pow(2.0, -10.0 * t) * sin((t - s) * (2.0 * .pi) / p) + 1.0
    }

    public static func elasticInOut(_ t: Double) -> Double {
        if t == 0.0 { return 0.0 }
        if t == 1.0 { return 1.0 }

        let p = 0.45
        let s = p / 4.0

        if t < 0.5 {
            let f = 2.0 * t - 1.0
            return -0.5 * pow(2.0, 10.0 * f) * sin((f - s) * (2.0 * .pi) / p)
        } else {
            let f = 2.0 * t - 1.0
            return 0.5 * pow(2.0, -10.0 * f) * sin((f - s) * (2.0 * .pi) / p) + 1.0
        }
    }

    // MARK: - Bounce

    public static func bounceIn(_ t: Double) -> Double {
        return 1.0 - bounceOut(1.0 - t)
    }

    public static func bounceOut(_ t: Double) -> Double {
        if t < 1.0 / 2.75 {
            return 7.5625 * t * t
        } else if t < 2.0 / 2.75 {
            let f = t - 1.5 / 2.75
            return 7.5625 * f * f + 0.75
        } else if t < 2.5 / 2.75 {
            let f = t - 2.25 / 2.75
            return 7.5625 * f * f + 0.9375
        } else {
            let f = t - 2.625 / 2.75
            return 7.5625 * f * f + 0.984375
        }
    }

    public static func bounceInOut(_ t: Double) -> Double {
        if t < 0.5 {
            return 0.5 * bounceIn(t * 2.0)
        } else {
            return 0.5 * bounceOut(t * 2.0 - 1.0) + 0.5
        }
    }

    // MARK: - Cubic Bezier

    /// Evaluate cubic Bezier curve using Newton-Raphson method
    /// Control points: P0=(0,0), P1=(x1,y1), P2=(x2,y2), P3=(1,1)
    public static func cubicBezier(_ t: Double, x1: Double, y1: Double, x2: Double, y2: Double) -> Double {
        // Find t value for given x using Newton-Raphson
        let epsilon = 0.0001
        let maxIterations = 10

        var currentT = t
        for _ in 0 ..< maxIterations {
            let currentX = cubicBezierX(t: currentT, x1: x1, x2: x2)
            let error = currentX - t

            if abs(error) < epsilon {
                break
            }

            let derivative = cubicBezierDerivative(t: currentT, x1: x1, x2: x2)
            if abs(derivative) < epsilon {
                break
            }

            currentT -= error / derivative
        }

        // Calculate y value for found t
        return cubicBezierY(t: currentT, y1: y1, y2: y2)
    }

    private static func cubicBezierX(t: Double, x1: Double, x2: Double) -> Double {
        // Bezier formula: B(t) = (1-t)³P0 + 3(1-t)²tP1 + 3(1-t)t²P2 + t³P3
        // For x: P0=0, P3=1
        let t2 = t * t
        let t3 = t2 * t
        let mt = 1.0 - t
        let mt2 = mt * mt

        return 3.0 * mt2 * t * x1 + 3.0 * mt * t2 * x2 + t3
    }

    private static func cubicBezierY(t: Double, y1: Double, y2: Double) -> Double {
        let t2 = t * t
        let t3 = t2 * t
        let mt = 1.0 - t
        let mt2 = mt * mt

        return 3.0 * mt2 * t * y1 + 3.0 * mt * t2 * y2 + t3
    }

    private static func cubicBezierDerivative(t: Double, x1: Double, x2: Double) -> Double {
        let mt = 1.0 - t
        let mt2 = mt * mt
        let t2 = t * t

        return 3.0 * mt2 * x1 + 6.0 * mt * t * (x2 - x1) + 3.0 * t2 * (1.0 - x2)
    }
}
