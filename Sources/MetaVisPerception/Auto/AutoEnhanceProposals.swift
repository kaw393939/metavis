import Foundation

public enum AutoEnhance {

    public struct ColorProposal: Sendable, Codable, Equatable {
        public var exposure: Double
        public var contrast: Double
        public var saturation: Double
        public var temperature: Double
        public var tint: Double

        public init(exposure: Double, contrast: Double, saturation: Double, temperature: Double, tint: Double) {
            self.exposure = exposure
            self.contrast = contrast
            self.saturation = saturation
            self.temperature = temperature
            self.tint = tint
        }

        public static let identity = ColorProposal(exposure: 0, contrast: 1, saturation: 1, temperature: 0, tint: 0)

        public func clamped() -> ColorProposal {
            func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }
            return ColorProposal(
                exposure: clamp(exposure, -0.5, 0.5),
                contrast: clamp(contrast, 0.9, 1.25),
                saturation: clamp(saturation, 0.85, 1.25),
                temperature: clamp(temperature, -1.0, 1.0),
                tint: clamp(tint, -0.35, 0.35)
            )
        }

        public func asGradeSimpleParameters() -> [String: Double] {
            [
                "exposure": exposure,
                "contrast": contrast,
                "saturation": saturation,
                "temperature": temperature,
                "tint": tint
            ]
        }
    }

    public struct SpeakerAudioProposal: Sendable, Codable, Equatable {
        public var enableDialogCleanwaterV1: Bool
        /// Applied only when enableDialogCleanwaterV1 is true.
        public var dialogCleanwaterGlobalGainDB: Double

        public init(enableDialogCleanwaterV1: Bool, dialogCleanwaterGlobalGainDB: Double) {
            self.enableDialogCleanwaterV1 = enableDialogCleanwaterV1
            self.dialogCleanwaterGlobalGainDB = dialogCleanwaterGlobalGainDB
        }

        public static let identity = SpeakerAudioProposal(enableDialogCleanwaterV1: false, dialogCleanwaterGlobalGainDB: 0)

        public func clamped() -> SpeakerAudioProposal {
            func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }
            return SpeakerAudioProposal(
                enableDialogCleanwaterV1: enableDialogCleanwaterV1,
                dialogCleanwaterGlobalGainDB: clamp(dialogCleanwaterGlobalGainDB, 0.0, 6.0)
            )
        }
    }

    public struct CombinedProposal: Sendable, Codable, Equatable {
        public var color: ColorProposal
        public var audio: SpeakerAudioProposal

        public init(color: ColorProposal, audio: SpeakerAudioProposal) {
            self.color = color
            self.audio = audio
        }

        public func clamped() -> CombinedProposal {
            CombinedProposal(color: color.clamped(), audio: audio.clamped())
        }
    }
}
