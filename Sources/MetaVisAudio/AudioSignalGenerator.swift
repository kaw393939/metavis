import Foundation
import AVFoundation

/// Defines the types of test signals we can generate.
public enum SignalWaveform: Sendable {
    case sine(frequency: Float) // 1kHz Reference
    case sweep(start: Float, end: Float, duration: TimeInterval) // Log Sweep
    case whiteNoise
    case pinkNoise
    case silence
    case impulse // 1 sample tick
    case dualTone(left: Float, right: Float) // Stereo Imaging
}

/// A service that generates reference audio signals using AVAudioSourceNode.
public actor AudioSignalGenerator {
    
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    
    public init() {}
    
    /// Starts generating the specified waveform.
    public func start(waveform: SignalWaveform, amplitude: Float = 0.1) throws { // -20dBFS approx 0.1
        
        // Stop any existing node
        if let node = sourceNode {
             engine.detach(node)
        }
        
        // Define the render block based on waveform
        let renderBlock = createRenderBlock(for: waveform, amplitude: amplitude)
        
        let format = engine.outputNode.inputFormat(forBus: 0)
        sourceNode = AVAudioSourceNode(format: format, renderBlock: renderBlock)
        
        guard let source = sourceNode else { return }
        
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        
        if !engine.isRunning {
             try engine.start()
        }
    }
    
    public func stop() {
        if let node = sourceNode {
            engine.detach(node)
        }
        engine.stop()
    }
    
    /// Installs a tap on the main mixer to capture audio buffers (for visualization or verification).
    public func installTap(bufferSize: AVAudioFrameCount = 1024, tapBlock: @escaping AVAudioNodeTapBlock) {
        let mixer = engine.mainMixerNode
        let format = mixer.outputFormat(forBus: 0)
        mixer.installTap(onBus: 0, bufferSize: bufferSize, format: format, block: tapBlock)
    }
    
    public func removeTap() {
        engine.mainMixerNode.removeTap(onBus: 0)
    }
    
    // MARK: - Render Logic
    
    private func createRenderBlock(for waveform: SignalWaveform, amplitude: Float) -> AVAudioSourceNodeRenderBlock {
        var phaseL: Float = 0
        var phaseR: Float = 0
        var currentFrame: Double = 0
        var pinkNoiseState = PinkNoiseState()
        
        let sampleRate = Float(engine.outputNode.inputFormat(forBus: 0).sampleRate)
        
        return { (isSilence, timestamp, frameCount, outputData) -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(outputData)
            let twoPi = 2.0 * Float.pi
            
            for frame in 0..<Int(frameCount) {
                currentFrame += 1
                
                // --- Signal Generation ---
                var sampleL: Float = 0
                var sampleR: Float = 0
                
                switch waveform {
                case .sine(let freq):
                    let val = sin(phaseL) * amplitude
                    sampleL = val
                    sampleR = val
                    phaseL += (twoPi * freq) / sampleRate
                    
                case .whiteNoise:
                    let val = Float.random(in: -1...1) * amplitude
                    sampleL = val
                    sampleR = val
                    
                case .pinkNoise:
                    let val = pinkNoiseState.next() * amplitude
                    sampleL = val
                    sampleR = val
                    
                case .sweep(let start, let end, let duration):
                    let t = Float(currentFrame) / sampleRate
                    if t <= Float(duration) {
                        // Logarithmic Sweep Formula: f(t) = start * (end/start)^(t/duration)
                        let freq = start * pow((end / start), (t / Float(duration)))
                        let val = sin(phaseL) * amplitude
                        sampleL = val
                        sampleR = val
                        phaseL += (twoPi * freq) / sampleRate
                    }
                    
                case .dualTone(let leftFreq, let rightFreq):
                    sampleL = sin(phaseL) * amplitude
                    sampleR = sin(phaseR) * amplitude
                    phaseL += (twoPi * leftFreq) / sampleRate
                    phaseR += (twoPi * rightFreq) / sampleRate
                    
                case .silence:
                    sampleL = 0
                    sampleR = 0
                    
                default:
                    sampleL = 0
                    sampleR = 0
                }
                
                if phaseL > twoPi { phaseL -= twoPi }
                if phaseR > twoPi { phaseR -= twoPi }
                
                // --- Channel Mapping ---
                
                if abl.count > 0 {
                   let bufL = UnsafeMutableBufferPointer<Float>(abl[0])
                   if frame < bufL.count { bufL[frame] = sampleL }
                }
                
                if abl.count > 1 {
                   let bufR = UnsafeMutableBufferPointer<Float>(abl[1])
                   if frame < bufR.count { bufR[frame] = sampleR }
                }
            }
            return noErr
        }
    }
}

// Simple Pink Noise Filter
struct PinkNoiseState {
    var b0: Float = 0
    var b1: Float = 0
    var b2: Float = 0
    var b3: Float = 0
    var b4: Float = 0
    var b5: Float = 0
    var b6: Float = 0

    mutating func next() -> Float {
        let white = Float.random(in: -1...1)
        b0 = 0.99886 * b0 + white * 0.0555179
        b1 = 0.99332 * b1 + white * 0.0750759
        b2 = 0.96900 * b2 + white * 0.1538520
        b3 = 0.86650 * b3 + white * 0.3104856
        b4 = 0.55000 * b4 + white * 0.5329522
        b5 = -0.7616 * b5 - white * 0.0168980
        let pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362
        b6 = white * 0.115926
        return pink * 0.11 // Normalize roughly to -1..1 range
    }
}
