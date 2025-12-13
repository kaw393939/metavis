import AVFoundation
import AudioToolbox
import MetaVisCore

/// Represents a chain of audio processing effects for mastering.
/// This acts as the "AI Engineer's" mixing console.
public class AudioMasteringChain {
    
    // Nodes
    private let inputMixer = AVAudioMixerNode()
    private let eqNode = AVAudioUnitEQ(numberOfBands: 3)
    // NOTE: DynamicsProcessor removed due to build unavailability. Using EQ Global Gain for leveling.
    
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
        
        print("AI Engineer: Applied Gain \(safeGain)dB. Target: \(targetLUFS), Current: \(currentAnalysis.lufs)")
    }
    
    public func applyGoldenMasterSettings() {
        // Legacy Stub
    }
}
