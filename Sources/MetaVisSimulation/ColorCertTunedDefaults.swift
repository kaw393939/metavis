import Foundation

enum ColorCertTunedDefaults {
    enum SDRRec709Studio {
        // Best-known tuned defaults (from SDR ΔE2000 sweep) for shader fallback parity.
        static let gamutCompress: Double = 0.08
        static let highlightDesatStrength: Double = 0.06
        static let redModStrength: Double = 0.16
    }

    enum HDRPQ1000 {
        // Best-known tuned defaults (from HDR Macbeth sweep) for shader fallback parity.
        static let maxNits: Double = 1000.0
        static let pqScale: Double = 0.136
        static let highlightDesat: Double = 0.0
        static let kneeNits: Double = 10000.0
        static let gamutCompress: Double = 0.0
    }
}
