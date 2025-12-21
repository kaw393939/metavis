// AudioEncoder.swift
// MetaVisRender
//
// Audio encoding using AudioToolbox for AAC, PCM, ALAC formats

import Foundation
import AudioToolbox
import AVFoundation
import CoreMedia

// MARK: - Audio Encoder Error

/// Errors that can occur during audio encoding
public enum AudioEncoderError: Error, LocalizedError {
    case encoderCreationFailed(OSStatus)
    case encodingFailed(OSStatus)
    case invalidInputFormat
    case invalidOutputFormat
    case bufferAllocationFailed
    case converterCreationFailed(OSStatus)
    case fileCreationFailed(OSStatus)
    case writeError(OSStatus)
    case unsupportedFormat(AudioCodec)
    
    public var errorDescription: String? {
        switch self {
        case .encoderCreationFailed(let status):
            return "Failed to create audio encoder: OSStatus \(status)"
        case .encodingFailed(let status):
            return "Audio encoding failed: OSStatus \(status)"
        case .invalidInputFormat:
            return "Invalid input audio format"
        case .invalidOutputFormat:
            return "Invalid output audio format"
        case .bufferAllocationFailed:
            return "Failed to allocate audio buffer"
        case .converterCreationFailed(let status):
            return "Failed to create audio converter: OSStatus \(status)"
        case .fileCreationFailed(let status):
            return "Failed to create audio file: OSStatus \(status)"
        case .writeError(let status):
            return "Failed to write audio data: OSStatus \(status)"
        case .unsupportedFormat(let codec):
            return "Unsupported audio codec: \(codec)"
        }
    }
}

// MARK: - Audio Encoder Settings

/// Settings for audio encoding
public struct AudioEncoderSettings: Sendable {
    /// Output codec
    public let codec: AudioCodec
    
    /// Sample rate in Hz
    public let sampleRate: Double
    
    /// Number of channels
    public let channels: Int
    
    /// Bit rate in bits per second (for compressed formats)
    public let bitRate: Int
    
    /// Bit depth (for PCM formats)
    public let bitDepth: Int
    
    /// Quality setting (0.0 - 1.0)
    public let quality: Float
    
    public init(
        codec: AudioCodec = .aac,
        sampleRate: Double = 48000,
        channels: Int = 2,
        bitRate: Int = 192_000,
        bitDepth: Int = 24,
        quality: Float = 0.8
    ) {
        self.codec = codec
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitRate = bitRate
        self.bitDepth = bitDepth
        self.quality = quality
    }
    
    /// Create from audio encoding settings
    public init(from settings: AudioEncodingSettings) {
        self.codec = settings.codec
        self.sampleRate = settings.sampleRate
        self.channels = settings.channelCount
        self.bitRate = settings.bitrate ?? 192_000
        self.bitDepth = settings.bitDepth
        self.quality = 0.8
    }
}

// MARK: - Encoded Audio Packet

/// Represents an encoded audio packet
public struct EncodedAudioPacket: Sendable {
    /// The encoded data
    public let data: Data
    
    /// Number of frames in this packet
    public let frameCount: Int
    
    /// Presentation timestamp
    public let presentationTime: CMTime
    
    /// Duration of this packet
    public let duration: CMTime
    
    public init(data: Data, frameCount: Int, presentationTime: CMTime, duration: CMTime) {
        self.data = data
        self.frameCount = frameCount
        self.presentationTime = presentationTime
        self.duration = duration
    }
}

// MARK: - Audio Encoder

/// Hardware-accelerated audio encoder using AudioToolbox
public actor AudioEncoder {
    
    // MARK: - Properties
    
    private let settings: AudioEncoderSettings
    private var converter: AudioConverterRef?
    private var inputFormat: AudioStreamBasicDescription
    private var outputFormat: AudioStreamBasicDescription
    private var outputBuffer: UnsafeMutablePointer<UInt8>?
    private var outputBufferSize: Int = 0
    private var encodedPackets: [EncodedAudioPacket] = []
    private var isEncoding = false
    private var currentPresentationTime: CMTime = .zero
    private var totalFramesEncoded: Int64 = 0
    
    // MARK: - Initialization
    
    public init(settings: AudioEncoderSettings) throws {
        self.settings = settings
        
        // Set up input format (assuming 32-bit float planar PCM)
        var localInputFormat = AudioStreamBasicDescription(
            mSampleRate: settings.sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(settings.channels * 4),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(settings.channels * 4),
            mChannelsPerFrame: UInt32(settings.channels),
            mBitsPerChannel: 32,
            mReserved: 0
        )
        self.inputFormat = localInputFormat
        
        // Set up output format based on codec
        var localOutputFormat = try Self.createOutputFormat(for: settings)
        self.outputFormat = localOutputFormat
        
        // Create converter
        var converter: AudioConverterRef?
        let status = AudioConverterNew(&localInputFormat, &localOutputFormat, &converter)
        
        guard status == noErr, let conv = converter else {
            throw AudioEncoderError.converterCreationFailed(status)
        }
        
        self.converter = conv
        
        // Set bit rate for compressed formats
        if settings.codec == .aac || settings.codec == .mp3 {
            var bitRate = UInt32(settings.bitRate)
            AudioConverterSetProperty(
                conv,
                kAudioConverterEncodeBitRate,
                UInt32(MemoryLayout<UInt32>.size),
                &bitRate
            )
        }
        
        // Set quality
        var quality = UInt32(kAudioConverterQuality_High)
        AudioConverterSetProperty(
            conv,
            kAudioConverterCodecQuality,
            UInt32(MemoryLayout<UInt32>.size),
            &quality
        )
        
        // Allocate output buffer
        let bufferSize = 32768 // 32KB buffer
        self.outputBufferSize = bufferSize
        self.outputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    }
    
    deinit {
        if let converter = converter {
            AudioConverterDispose(converter)
        }
        outputBuffer?.deallocate()
    }
    
    // MARK: - Public Methods
    
    /// Encode audio samples
    /// - Parameters:
    ///   - samples: Float32 interleaved audio samples
    ///   - frameCount: Number of audio frames
    ///   - presentationTime: Optional presentation timestamp
    /// - Returns: Encoded audio packet, or nil if buffering
    public func encode(
        samples: [Float],
        frameCount: Int,
        presentationTime: CMTime? = nil
    ) async throws -> EncodedAudioPacket? {
        guard let converter = converter else {
            throw AudioEncoderError.encoderCreationFailed(0)
        }
        
        if let pts = presentationTime {
            currentPresentationTime = pts
        }
        
        isEncoding = true
        defer { isEncoding = false }
        
        // For PCM output, just package the data directly
        if settings.codec.isLossless && settings.codec != .alac && settings.codec != .flac {
            return try encodePCM(samples: samples, frameCount: frameCount)
        }
        
        // For compressed formats, use AudioConverter
        return try encodeCompressed(
            samples: samples,
            frameCount: frameCount,
            converter: converter
        )
    }
    
    /// Encode from CMSampleBuffer
    public func encode(sampleBuffer: CMSampleBuffer) async throws -> EncodedAudioPacket? {
        guard CMSampleBufferGetFormatDescription(sampleBuffer) != nil else {
            throw AudioEncoderError.invalidInputFormat
        }
        
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        
        // Get audio buffer list
        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList()
        var audioBufferListSize = 0
        
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &audioBufferListSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )
        
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        
        guard status == noErr,
              let dataPointer = audioBufferList.mBuffers.mData else {
            throw AudioEncoderError.invalidInputFormat
        }
        
        // Convert to Float array
        let sampleCount = frameCount * settings.channels
        let floatPointer = dataPointer.assumingMemoryBound(to: Float.self)
        let samples = Array(UnsafeBufferPointer(start: floatPointer, count: sampleCount))
        
        return try await encode(
            samples: samples,
            frameCount: frameCount,
            presentationTime: presentationTime
        )
    }
    
    /// Flush remaining encoded data
    public func flush() async throws -> [EncodedAudioPacket] {
        guard let converter = converter else { return [] }
        
        var packets: [EncodedAudioPacket] = []
        
        // Flush converter
        var outputData = AudioBufferList()
        outputData.mNumberBuffers = 1
        outputData.mBuffers.mNumberChannels = UInt32(settings.channels)
        outputData.mBuffers.mDataByteSize = UInt32(outputBufferSize)
        outputData.mBuffers.mData = UnsafeMutableRawPointer(outputBuffer)
        
        var outputDataPacketSize: UInt32 = 1
        
        let status = AudioConverterFillComplexBuffer(
            converter,
            { _, ioNumberDataPackets, ioData, outDataPacketDescription, _ in
                ioNumberDataPackets.pointee = 0
                return noErr
            },
            nil,
            &outputDataPacketSize,
            &outputData,
            nil
        )
        
        if status == noErr && outputData.mBuffers.mDataByteSize > 0 {
            let data = Data(bytes: outputBuffer!, count: Int(outputData.mBuffers.mDataByteSize))
            let duration = CMTime(
                value: CMTimeValue(outputDataPacketSize),
                timescale: CMTimeScale(settings.sampleRate)
            )
            
            packets.append(EncodedAudioPacket(
                data: data,
                frameCount: Int(outputDataPacketSize),
                presentationTime: currentPresentationTime,
                duration: duration
            ))
        }
        
        return packets
    }
    
    /// Reset encoder state
    public func reset() async throws {
        if let converter = converter {
            AudioConverterReset(converter)
        }
        encodedPackets.removeAll()
        currentPresentationTime = .zero
        totalFramesEncoded = 0
    }
    
    /// Get output format description for muxing
    public func getOutputFormatDescription() -> AudioStreamBasicDescription {
        return outputFormat
    }
    
    /// Get total frames encoded
    public func getTotalFramesEncoded() -> Int64 {
        return totalFramesEncoded
    }
    
    // MARK: - Private Methods
    
    fileprivate static func createOutputFormat(for settings: AudioEncoderSettings) throws -> AudioStreamBasicDescription {
        switch settings.codec {
        case .aac, .aacLC, .aacHE:
            return AudioStreamBasicDescription(
                mSampleRate: settings.sampleRate,
                mFormatID: kAudioFormatMPEG4AAC,
                mFormatFlags: 0,
                mBytesPerPacket: 0,
                mFramesPerPacket: 1024,
                mBytesPerFrame: 0,
                mChannelsPerFrame: UInt32(settings.channels),
                mBitsPerChannel: 0,
                mReserved: 0
            )
            
        case .pcmS16LE, .pcmS24LE, .pcmS32LE, .pcmFloat:
            let bytesPerSample = UInt32(settings.bitDepth / 8)
            return AudioStreamBasicDescription(
                mSampleRate: settings.sampleRate,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                mBytesPerPacket: bytesPerSample * UInt32(settings.channels),
                mFramesPerPacket: 1,
                mBytesPerFrame: bytesPerSample * UInt32(settings.channels),
                mChannelsPerFrame: UInt32(settings.channels),
                mBitsPerChannel: UInt32(settings.bitDepth),
                mReserved: 0
            )
            
        case .alac:
            return AudioStreamBasicDescription(
                mSampleRate: settings.sampleRate,
                mFormatID: kAudioFormatAppleLossless,
                mFormatFlags: 0,
                mBytesPerPacket: 0,
                mFramesPerPacket: 4096,
                mBytesPerFrame: 0,
                mChannelsPerFrame: UInt32(settings.channels),
                mBitsPerChannel: UInt32(settings.bitDepth),
                mReserved: 0
            )
            
        case .opus:
            // Opus would require external library, fall back to AAC
            return AudioStreamBasicDescription(
                mSampleRate: settings.sampleRate,
                mFormatID: kAudioFormatMPEG4AAC,
                mFormatFlags: 0,
                mBytesPerPacket: 0,
                mFramesPerPacket: 1024,
                mBytesPerFrame: 0,
                mChannelsPerFrame: UInt32(settings.channels),
                mBitsPerChannel: 0,
                mReserved: 0
            )
            
        case .flac:
            return AudioStreamBasicDescription(
                mSampleRate: settings.sampleRate,
                mFormatID: kAudioFormatFLAC,
                mFormatFlags: 0,
                mBytesPerPacket: 0,
                mFramesPerPacket: 0,
                mBytesPerFrame: 0,
                mChannelsPerFrame: UInt32(settings.channels),
                mBitsPerChannel: UInt32(settings.bitDepth),
                mReserved: 0
            )
            
        case .mp3:
            return AudioStreamBasicDescription(
                mSampleRate: settings.sampleRate,
                mFormatID: kAudioFormatMPEGLayer3,
                mFormatFlags: 0,
                mBytesPerPacket: 0,
                mFramesPerPacket: 1152,
                mBytesPerFrame: 0,
                mChannelsPerFrame: UInt32(settings.channels),
                mBitsPerChannel: 0,
                mReserved: 0
            )
            
        case .ac3, .eac3, .unknown:
            // Fall back to AAC for unsupported codecs
            return AudioStreamBasicDescription(
                mSampleRate: settings.sampleRate,
                mFormatID: kAudioFormatMPEG4AAC,
                mFormatFlags: 0,
                mBytesPerPacket: 0,
                mFramesPerPacket: 1024,
                mBytesPerFrame: 0,
                mChannelsPerFrame: UInt32(settings.channels),
                mBitsPerChannel: 0,
                mReserved: 0
            )
        }
    }
    

    private func encodePCM(samples: [Float], frameCount: Int) throws -> EncodedAudioPacket {
        // Convert float to target bit depth
        var data: Data
        
        switch settings.bitDepth {
        case 16:
            var int16Samples = [Int16]()
            int16Samples.reserveCapacity(samples.count)
            for sample in samples {
                let clamped = max(-1.0, min(1.0, sample))
                int16Samples.append(Int16(clamped * Float(Int16.max)))
            }
            data = Data(bytes: int16Samples, count: int16Samples.count * 2)
            
        case 24:
            var bytes = [UInt8]()
            bytes.reserveCapacity(samples.count * 3)
            for sample in samples {
                let clamped = max(-1.0, min(1.0, sample))
                let int32Value = Int32(clamped * Float(Int32.max >> 8))
                bytes.append(UInt8(truncatingIfNeeded: int32Value))
                bytes.append(UInt8(truncatingIfNeeded: int32Value >> 8))
                bytes.append(UInt8(truncatingIfNeeded: int32Value >> 16))
            }
            data = Data(bytes)
            
        case 32:
            // Keep as float
            data = Data(bytes: samples, count: samples.count * 4)
            
        default:
            throw AudioEncoderError.invalidOutputFormat
        }
        
        let duration = CMTime(
            value: CMTimeValue(frameCount),
            timescale: CMTimeScale(settings.sampleRate)
        )
        
        let packet = EncodedAudioPacket(
            data: data,
            frameCount: frameCount,
            presentationTime: currentPresentationTime,
            duration: duration
        )
        
        // Update state
        currentPresentationTime = CMTimeAdd(currentPresentationTime, duration)
        totalFramesEncoded += Int64(frameCount)
        
        return packet
    }
    
    private func encodeCompressed(
        samples: [Float],
        frameCount: Int,
        converter: AudioConverterRef
    ) throws -> EncodedAudioPacket? {
        guard let outputBuffer = outputBuffer else {
            throw AudioEncoderError.bufferAllocationFailed
        }
        
        // Prepare input data
        var inputData = samples
        let inputDataSize = UInt32(samples.count * MemoryLayout<Float>.size)
        
        // Create input buffer list
        var inputBufferList = AudioBufferList()
        inputBufferList.mNumberBuffers = 1
        inputBufferList.mBuffers.mNumberChannels = UInt32(settings.channels)
        inputBufferList.mBuffers.mDataByteSize = inputDataSize
        
        // Create output buffer list
        var outputBufferList = AudioBufferList()
        outputBufferList.mNumberBuffers = 1
        outputBufferList.mBuffers.mNumberChannels = UInt32(settings.channels)
        outputBufferList.mBuffers.mDataByteSize = UInt32(outputBufferSize)
        outputBufferList.mBuffers.mData = UnsafeMutableRawPointer(outputBuffer)
        
        var outputPacketCount: UInt32 = 1
        
        // User data for callback
        struct ConverterUserData {
            var inputData: UnsafeMutablePointer<Float>
            var inputDataSize: UInt32
            var channels: Int
            var consumed: Bool
        }
        
        let status = inputData.withUnsafeMutableBufferPointer { inputBufferPtr -> OSStatus in
            guard let inputBaseAddress = inputBufferPtr.baseAddress else { return -50 /* paramErr */ }
            
            var userData = ConverterUserData(
                inputData: inputBaseAddress,
                inputDataSize: inputDataSize,
                channels: settings.channels,
                consumed: false
            )
            
            return withUnsafeMutablePointer(to: &userData) { userDataPtr in
                AudioConverterFillComplexBuffer(
                    converter,
                    { (_, ioNumberDataPackets, ioData, outDataPacketDescription, inUserData) -> OSStatus in
                        guard let userData = inUserData?.assumingMemoryBound(to: ConverterUserData.self).pointee else {
                            ioNumberDataPackets.pointee = 0
                            return noErr
                        }
                        
                        if userData.consumed {
                            ioNumberDataPackets.pointee = 0
                            return noErr
                        }
                        
                        ioData.pointee.mNumberBuffers = 1
                        ioData.pointee.mBuffers.mNumberChannels = UInt32(userData.channels)
                        ioData.pointee.mBuffers.mDataByteSize = userData.inputDataSize
                        ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer(userData.inputData)
                        
                        inUserData?.assumingMemoryBound(to: ConverterUserData.self).pointee.consumed = true
                        
                        return noErr
                    },
                    UnsafeMutableRawPointer(userDataPtr),
                    &outputPacketCount,
                    &outputBufferList,
                    nil
                )
            }
        }
        
        guard status == noErr || status == -37 else { // -37 is "end of data" for AudioConverter
            throw AudioEncoderError.encodingFailed(status)
        }
        
        // Check if we got output
        let outputSize = Int(outputBufferList.mBuffers.mDataByteSize)
        if outputSize > 0 {
            let data = Data(bytes: outputBuffer, count: outputSize)
            let duration = CMTime(
                value: CMTimeValue(frameCount),
                timescale: CMTimeScale(settings.sampleRate)
            )
            
            let packet = EncodedAudioPacket(
                data: data,
                frameCount: frameCount,
                presentationTime: currentPresentationTime,
                duration: duration
            )
            
            currentPresentationTime = CMTimeAdd(currentPresentationTime, duration)
            totalFramesEncoded += Int64(frameCount)
            
            return packet
        }
        
        // Buffering - no output yet
        return nil
    }
}

// MARK: - Audio File Encoder

/// Encodes audio directly to a file
public actor AudioFileEncoder {
    
    private let settings: AudioEncoderSettings
    private let outputURL: URL
    private var audioFile: ExtAudioFileRef?
    private var totalFramesWritten: Int64 = 0
    
    public init(settings: AudioEncoderSettings, outputURL: URL) throws {
        self.settings = settings
        self.outputURL = outputURL
        
        // Determine file type
        let fileType: AudioFileTypeID
        switch settings.codec {
        case .aac, .aacLC, .aacHE:
            fileType = kAudioFileM4AType
        case .alac:
            fileType = kAudioFileM4AType
        case .pcmS16LE, .pcmS24LE, .pcmS32LE, .pcmFloat:
            fileType = kAudioFileWAVEType
        case .flac:
            fileType = kAudioFileFLACType
        case .mp3:
            fileType = kAudioFileMP3Type
        case .opus, .ac3, .eac3, .unknown:
            fileType = kAudioFileM4AType // Fallback
        }
        
        // Create output format
        var outputFormat = try AudioEncoder.createOutputFormat(for: settings)
        
        // Create client (input) format - 32-bit float
        var clientFormat = AudioStreamBasicDescription(
            mSampleRate: settings.sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(settings.channels * 4),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(settings.channels * 4),
            mChannelsPerFrame: UInt32(settings.channels),
            mBitsPerChannel: 32,
            mReserved: 0
        )
        
        // Create audio file
        var audioFile: ExtAudioFileRef?
        let status = ExtAudioFileCreateWithURL(
            outputURL as CFURL,
            fileType,
            &outputFormat,
            nil,
            AudioFileFlags.eraseFile.rawValue,
            &audioFile
        )
        
        guard status == noErr, let file = audioFile else {
            throw AudioEncoderError.fileCreationFailed(status)
        }
        
        self.audioFile = file
        
        // Set client format
        let clientFormatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let clientStatus = ExtAudioFileSetProperty(
            file,
            kExtAudioFileProperty_ClientDataFormat,
            clientFormatSize,
            &clientFormat
        )
        
        if clientStatus != noErr {
            throw AudioEncoderError.encoderCreationFailed(clientStatus)
        }
    }
    
    deinit {
        if let audioFile = audioFile {
            ExtAudioFileDispose(audioFile)
        }
    }
    
    // MARK: - Public Methods
    
    /// Write audio samples to file
    public func write(samples: [Float], frameCount: Int) throws {
        guard let audioFile = audioFile else {
            throw AudioEncoderError.fileCreationFailed(0)
        }
        
        var mutableSamples = samples
        var bufferList = AudioBufferList()
        bufferList.mNumberBuffers = 1
        bufferList.mBuffers.mNumberChannels = UInt32(settings.channels)
        bufferList.mBuffers.mDataByteSize = UInt32(samples.count * MemoryLayout<Float>.size)
        
        let frameCountToWrite = UInt32(frameCount)
        let status = mutableSamples.withUnsafeMutableBytes { bytes in
            bufferList.mBuffers.mData = bytes.baseAddress
            return ExtAudioFileWrite(audioFile, frameCountToWrite, &bufferList)
        }
        
        guard status == noErr else {
            throw AudioEncoderError.writeError(status)
        }
        
        totalFramesWritten += Int64(frameCount)
    }
    
    /// Write from CMSampleBuffer
    public func write(sampleBuffer: CMSampleBuffer) throws {
        guard let audioFile = audioFile else {
            throw AudioEncoderError.fileCreationFailed(0)
        }
        
        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList()
        
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        
        guard status == noErr else {
            throw AudioEncoderError.invalidInputFormat
        }
        
        let frameCount = UInt32(CMSampleBufferGetNumSamples(sampleBuffer))
        let writeFrameCount = frameCount
        
        let writeStatus = ExtAudioFileWrite(audioFile, writeFrameCount, &audioBufferList)
        
        guard writeStatus == noErr else {
            throw AudioEncoderError.writeError(writeStatus)
        }
        
        totalFramesWritten += Int64(frameCount)
    }
    
    /// Finalize and close file
    public func finalize() throws {
        guard let audioFile = audioFile else { return }
        
        let status = ExtAudioFileDispose(audioFile)
        self.audioFile = nil
        
        if status != noErr {
            throw AudioEncoderError.writeError(status)
        }
    }
    
    /// Get total frames written
    public func getTotalFramesWritten() -> Int64 {
        return totalFramesWritten
    }
    
    // MARK: - Private Methods
    

    
    private static func createOutputFormat(for settings: AudioEncoderSettings) throws -> AudioStreamBasicDescription {
        switch settings.codec {
        case .aac, .aacLC, .aacHE:
            return AudioStreamBasicDescription(
                mSampleRate: settings.sampleRate,
                mFormatID: kAudioFormatMPEG4AAC,
                mFormatFlags: 0,
                mBytesPerPacket: 0,
                mFramesPerPacket: 1024,
                mBytesPerFrame: 0,
                mChannelsPerFrame: UInt32(settings.channels),
                mBitsPerChannel: 0,
                mReserved: 0
            )
            
        case .pcmS16LE, .pcmS24LE, .pcmS32LE, .pcmFloat:
            let bytesPerSample = UInt32(settings.bitDepth / 8)
            return AudioStreamBasicDescription(
                mSampleRate: settings.sampleRate,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                mBytesPerPacket: bytesPerSample * UInt32(settings.channels),
                mFramesPerPacket: 1,
                mBytesPerFrame: bytesPerSample * UInt32(settings.channels),
                mChannelsPerFrame: UInt32(settings.channels),
                mBitsPerChannel: UInt32(settings.bitDepth),
                mReserved: 0
            )
            
        case .alac:
            return AudioStreamBasicDescription(
                mSampleRate: settings.sampleRate,
                mFormatID: kAudioFormatAppleLossless,
                mFormatFlags: 0,
                mBytesPerPacket: 0,
                mFramesPerPacket: 4096,
                mBytesPerFrame: 0,
                mChannelsPerFrame: UInt32(settings.channels),
                mBitsPerChannel: UInt32(settings.bitDepth),
                mReserved: 0
            )
            
        case .flac:
            return AudioStreamBasicDescription(
                mSampleRate: settings.sampleRate,
                mFormatID: kAudioFormatFLAC,
                mFormatFlags: 0,
                mBytesPerPacket: 0,
                mFramesPerPacket: 0,
                mBytesPerFrame: 0,
                mChannelsPerFrame: UInt32(settings.channels),
                mBitsPerChannel: UInt32(settings.bitDepth),
                mReserved: 0
            )
            
        case .mp3, .opus, .ac3, .eac3, .unknown:
            // MP3/Opus encoding not natively supported, fallback to AAC
            return AudioStreamBasicDescription(
                mSampleRate: settings.sampleRate,
                mFormatID: kAudioFormatMPEG4AAC,
                mFormatFlags: 0,
                mBytesPerPacket: 0,
                mFramesPerPacket: 1024,
                mBytesPerFrame: 0,
                mChannelsPerFrame: UInt32(settings.channels),
                mBitsPerChannel: 0,
                mReserved: 0
            )
        }
    }
}
