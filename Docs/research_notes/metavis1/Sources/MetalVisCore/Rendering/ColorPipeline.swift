import Foundation

/// Defines the color primaries of the source media
public enum ColorPrimaries: String, Sendable {
    case rec709
    case rec2020
    case p3_d65
    case acescg
}

/// Defines the transfer function (gamma/log curve) of the source media
public enum TransferFunction: String, Sendable {
    case sRGB
    case rec709
    case appleLog
    case linear
    case pq
    case hlg
}

/// Defines the specific Input Device Transform (IDT) to normalize to ACEScg
public enum InputDeviceTransform: String, Sendable {
    case srgb_to_acescg
    case rec709_to_acescg
    case appleLog_to_acescg
    case p3d65_to_acescg
    case passthrough // Already ACEScg
}

/// Represents a specific camera or media input profile
public struct MediaProfile: Sendable {
    public let name: String
    public let description: String
    public let colorPrimaries: ColorPrimaries
    public let transferFunction: TransferFunction
    public let idt: InputDeviceTransform

    public init(
        name: String,
        description: String,
        colorPrimaries: ColorPrimaries,
        transferFunction: TransferFunction,
        idt: InputDeviceTransform
    ) {
        self.name = name
        self.description = description
        self.colorPrimaries = colorPrimaries
        self.transferFunction = transferFunction
        self.idt = idt
    }
}

/// Central registry for all supported Input Profiles
public final class ProfileRegistry: @unchecked Sendable {
    public static let shared = ProfileRegistry()

    private var profiles: [String: MediaProfile] = [:]
    private let lock = NSLock()

    private init() {
        registerDefaults()
    }

    private func registerDefaults() {
        // 1. iPhone SDR (Rec.709 / Rec.709 Gamma)
        // Note: iPhone "SDR" video is usually Rec.709 primaries with a transfer function close to Rec.709/2.4
        register(MediaProfile(
            name: "iPhone_SDR",
            description: "Standard iPhone Video (H.264/HEVC)",
            colorPrimaries: .rec709,
            transferFunction: .rec709,
            idt: .rec709_to_acescg
        ))

        // 2. iPhone Apple Log (Rec.2020 / Apple Log)
        register(MediaProfile(
            name: "iPhone_AppleLog",
            description: "iPhone ProRes Log (Apple Log)",
            colorPrimaries: .rec2020,
            transferFunction: .appleLog,
            idt: .appleLog_to_acescg
        ))

        // 3. AI Media (sRGB)
        // Most AI generators (Midjourney, Flux) output sRGB PNG/JPEG
        register(MediaProfile(
            name: "AI_SDR",
            description: "AI Generated Images/Video (sRGB)",
            colorPrimaries: .rec709,
            transferFunction: .sRGB,
            idt: .srgb_to_acescg
        ))

        // 4. Linear ACEScg (Passthrough/Synthetic)
        register(MediaProfile(
            name: "Linear_ACEScg",
            description: "Already normalized linear data",
            colorPrimaries: .acescg,
            transferFunction: .linear,
            idt: .passthrough
        ))
    }

    public func register(_ profile: MediaProfile) {
        lock.lock()
        defer { lock.unlock() }
        profiles[profile.name] = profile
    }

    public func profile(for name: String) -> MediaProfile? {
        lock.lock()
        defer { lock.unlock() }
        return profiles[name]
    }

    public var allProfiles: [MediaProfile] {
        lock.lock()
        defer { lock.unlock() }
        return Array(profiles.values).sorted { $0.name < $1.name }
    }
}
