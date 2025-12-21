import Foundation

public enum AutoColorCorrector {

    public struct Options: Sendable, Equatable {
        public var conservativeWhenConfidenceLow: Bool

        public init(conservativeWhenConfidenceLow: Bool = true) {
            self.conservativeWhenConfidenceLow = conservativeWhenConfidenceLow
        }
    }

    public static func propose(from sensors: MasterSensors, options: Options = Options()) -> AutoEnhance.ColorProposal {
        // Base: identity
        var proposal = AutoEnhance.ColorProposal.identity

        // Use mean luma to propose exposure nudges (very conservative).
        // Target: ~0.45 in [0,1] mean luma space.
        if !sensors.videoSamples.isEmpty {
            let mean = sensors.videoSamples.reduce(0.0) { $0 + $1.meanLuma } / Double(sensors.videoSamples.count)
            let delta = 0.45 - mean
            // Map delta to exposure EV-ish adjustment with a gentle slope.
            // If mean=0.25 => delta=0.20 => exposure +0.20
            // If mean=0.70 => delta=-0.25 => exposure -0.25
            proposal.exposure = delta
        }

        // Mild contrast/sat normalization.
        proposal.contrast = 1.05
        proposal.saturation = 1.05

        // No deterministic white balance signals yet; keep neutral.
        proposal.temperature = 0.0
        proposal.tint = 0.0

        // Descriptor-driven safety.
        let descriptors = sensors.descriptors ?? []
        let avoidHeavy = descriptors.contains(where: { $0.label == .avoidHeavyGrade && ($0.veto ?? false) })
            || descriptors.contains(where: { $0.label == .gradeConfidenceLow && ($0.veto ?? false) })

        if options.conservativeWhenConfidenceLow && avoidHeavy {
            // Clamp to very small moves.
            proposal.exposure = min(max(proposal.exposure, -0.15), 0.15)
            proposal.contrast = min(max(proposal.contrast, 0.98), 1.08)
            proposal.saturation = min(max(proposal.saturation, 0.98), 1.08)
            proposal.temperature = 0.0
            proposal.tint = 0.0
        }

        return proposal.clamped()
    }
}
