import AVFoundation
import AudioToolbox
import MetaVisCore

public struct AudioDynamicsSettings: Sendable, Equatable {
    public var enabled: Bool
    /// Threshold in dBFS (negative values, e.g. -16).
    public var thresholdDB: Float
    /// Compression ratio (>= 1). Example: 4 means 4:1.
    public var ratio: Float
    /// Optional makeup gain applied after compression.
    public var makeupGainDB: Float

    public init(enabled: Bool = false, thresholdDB: Float = -16.0, ratio: Float = 3.0, makeupGainDB: Float = 0.0) {
        self.enabled = enabled
        self.thresholdDB = thresholdDB
        self.ratio = ratio
        self.makeupGainDB = makeupGainDB
    }
}

/// Represents a chain of audio processing effects for mastering.
/// This acts as the "AI Engineer's" mixing console.
public class AudioMasteringChain {
    
    // Nodes
    private let inputMixer = AVAudioMixerNode()
    private let eqNode = AVAudioUnitEQ(numberOfBands: 3)

    // Deterministic offline dynamics (applied post-render by AudioTimelineRenderer).
    private var dynamicsSettings = AudioDynamicsSettings()
    
    // Internal state
    private var isAttached = false
    
    public init() {
        // Default EQ Setup (Flat)
        // Band 0: Low Shelf
        eqNode.bands[0].filterType = .lowShelf
        eqNode.bands[0].frequency = 100.0
        eqNode.bands[0].gain = 0.0
        
        // Band 1: Parametric (Mid)
        eqNode.bands[1].filterType = .parametric
        eqNode.bands[1].frequency = 1000.0
        eqNode.bands[1].gain = 0.0
        
        // Band 2: High Shelf
        eqNode.bands[2].filterType = .highShelf
        eqNode.bands[2].frequency = 10000.0
        eqNode.bands[2].gain = 0.0
        
        eqNode.globalGain = 0.0
    }
    
    /// Attaches the mastering chain to the engine and returns the input/output nodes.
    /// - Parameter engine: The AVAudioEngine to attach nodes to.
    /// - Returns: A tuple of (inputNode, outputNode) for the chain.
    public func attach(to engine: AVAudioEngine, format: AVAudioFormat) -> (input: AVAudioNode, output: AVAudioNode) {
        if isAttached {
            return (inputMixer, eqNode)
        }

        engine.attach(inputMixer)
        engine.attach(eqNode)

        // Chain: Input Mixer -> EQ
        engine.connect(inputMixer, to: eqNode, format: format)
        
        isAttached = true
        return (inputMixer, eqNode)
    }

    public func setDynamicsSettings(_ settings: AudioDynamicsSettings) {
        self.dynamicsSettings = settings
    }

    public func dynamicsSettingsSnapshot() -> AudioDynamicsSettings {
        return dynamicsSettings
    }
    
    /// Apply "Engineer" settings based on analysis.
    public func applyEngineerSettings(
        targetLUFS: Float,
        currentAnalysis: AudioAnalysis
    ) {
        // 1. Calculate Gain Needed
        // Example: Target -14, Current -20. Needed: +6dB.
        let gainNeeded = targetLUFS - currentAnalysis.lufs
        
        // 2. Safety Cap (+12dB max gain to avoid blowing ears)
        let safeGain = min(max(gainNeeded, -20.0), 12.0)
        
        // 3. Apply to EQ Global Gain
        eqNode.globalGain = safeGain

        // Enable a mild deterministic compressor when we are applying non-trivial gain.
        if abs(safeGain) >= 3.0 {
            dynamicsSettings = AudioDynamicsSettings(enabled: true, thresholdDB: -12.0, ratio: 3.0, makeupGainDB: 0.0)
        }
        
        print("AI Engineer: Applied Gain \(safeGain)dB. Target: \(targetLUFS), Current: \(currentAnalysis.lufs)")
    }
    
    public func applyGoldenMasterSettings() {
        // Legacy Stub
    }

    /// Deterministic dialog cleanup preset.
    ///
    /// v1 goal: reduce low-frequency rumble, add intelligibility presence, and raise overall level.
    public func applyDialogCleanwaterPresetV1(globalGainDB: Float = 6.0) {
        // Low shelf: attenuate lows
        eqNode.bands[0].filterType = .lowShelf
        eqNode.bands[0].frequency = 120.0
        eqNode.bands[0].gain = -4.0

        // Presence: boost around 3kHz
        eqNode.bands[1].filterType = .parametric
        eqNode.bands[1].frequency = 3000.0
        eqNode.bands[1].bandwidth = 1.0
        eqNode.bands[1].gain = 2.0

        // High shelf: slight lift
        eqNode.bands[2].filterType = .highShelf
        eqNode.bands[2].frequency = 9000.0
        eqNode.bands[2].gain = 1.0

        // Fixed gain lift (deterministic, caller-bounded)
        eqNode.globalGain = globalGainDB

        // Dialog cleanup benefits from mild dynamics to reduce harsh peaks.
        dynamicsSettings = AudioDynamicsSettings(enabled: true, thresholdDB: -16.0, ratio: 2.5, makeupGainDB: 0.0)
    }
}
