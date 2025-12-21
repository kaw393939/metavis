import Foundation

public enum FITSError: Error {
    case fileNotFound
    case invalidHeader
    case unsupportedBitpix(Int)
    case missingEndKeyword
    case dataReadFailed
}

/// A specialized reader for FITS (Flexible Image Transport System) files.
/// Focusing on the subset required for JWST (Float32, standard headers).
public struct FITSReader {
    
    public init() {}
    
    /// Reads a FITS file and returns a generic FITSAsset.
    /// Scans HDUs until a valid image extension is found.
    public func read(url: URL) throws -> FITSAsset {
        // 1. Read Data
        let data = try Data(contentsOf: url)
        var cursor = 0
        
        while cursor < data.count {
            // 2. Parse Header of current HDU
            let (metadata, dataOffset) = try parseHeaderBlocks(data: data, startOffset: cursor)
            
            let bitpix = Int(metadata["BITPIX"] ?? "") ?? 0
            let naxis = Int(metadata["NAXIS"] ?? "") ?? 0
            let naxis1 = Int(metadata["NAXIS1"] ?? "") ?? 0
            let naxis2 = Int(metadata["NAXIS2"] ?? "") ?? 0
            
            // Calculate Data Size
            var dataSize = 0
            if naxis1 > 0 && naxis2 > 0 && bitpix != 0 {
                let bytesPerPixel = abs(bitpix) / 8
                let pixelCount = naxis1 * naxis2
                dataSize = pixelCount * bytesPerPixel
            }
            
            // FITS data blocks are padded to 2880 bytes
            let paddedDataSize = ((dataSize + 2879) / 2880) * 2880
            
            // Check if this is a valid image extension we want to load
            // We look for 2D images with valid dimensions and known bit depth
            if naxis >= 2 && naxis1 > 0 && naxis2 > 0 && bitpix != 0 {
                // Found a candidate!
                
                guard dataOffset + dataSize <= data.count else {
                    throw FITSError.dataReadFailed
                }
                
                // Extract Data Buffer
                let rawData = data.subdata(in: dataOffset..<dataOffset + dataSize)
                
                // Handle Endianness and Compute Stats
                let convertedData = try convertEndianness(data: rawData, bitpix: bitpix)
                let stats = computeStats(data: convertedData, bitpix: bitpix)
                
                return FITSAsset(
                    url: url,
                    width: naxis1,
                    height: naxis2,
                    bitpix: bitpix,
                    metadata: metadata,
                    statistics: stats,
                    rawData: convertedData
                )
            }
            
            // Move to next HDU
            cursor = dataOffset + paddedDataSize
        }
        
        throw FITSError.fileNotFound // Or a more specific "NoImageFound" error
    }
    
    // MARK: - Helpers
    
    private func parseHeaderBlocks(data: Data, startOffset: Int) throws -> ([String: String], Int) {
        var cursor = startOffset
        var metadata: [String: String] = [:]
        var endFound = false
        
        // Process in 2880 byte blocks
        while cursor < data.count {
            let blockSize = 2880
            if cursor + blockSize > data.count { break }
            
            // Scan the block 80 bytes at a time
            for i in 0..<(blockSize / 80) {
                let cardStart = cursor + (i * 80)
                let cardData = data.subdata(in: cardStart..<cardStart+80)
                guard let cardString = String(data: cardData, encoding: .ascii) else { continue }
                
                let keyword = String(cardString.prefix(8)).trimmingCharacters(in: .whitespaces)
                
                if keyword == "END" {
                    endFound = true
                    // The data begins after this 2880 block finishes.
                    return (metadata, cursor + blockSize)
                }
                
                if cardString.contains("=") {
                    let parts = cardString.split(separator: "=", maxSplits: 1)
                    if parts.count == 2 {
                        let valuePart = parts[1]
                        // Remove comments starting with /
                        let val = valuePart.split(separator: "/").first ?? ""
                        // Remove quotes and whitespace
                        let cleanVal = val.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "'", with: "")
                        metadata[keyword] = cleanVal
                    }
                }
            }
            cursor += blockSize
        }
        
        if !endFound { throw FITSError.missingEndKeyword }
        return (metadata, cursor)
    }
    
    private func convertEndianness(data: Data, bitpix: Int) throws -> Data {
        var buffer = data // Copy
        
        buffer.withUnsafeMutableBytes { ptr in
            if bitpix == -32 {
                // Float32
                let count = ptr.count / 4
                // Ensure alignment
                let baseAddress = ptr.baseAddress!
                // We shouldn't bind directly if alignment is off, but Data is usually aligned?
                // Safest to load/swap/store or use generic copy. 
                // However, for speed and simplicity in this context:
                let floatPtr = ptr.bindMemory(to: UInt32.self)
                for i in 0..<count {
                    floatPtr[i] = UInt32(bigEndian: floatPtr[i])
                }
            } else if bitpix == 16 {
                // Int16
                let count = ptr.count / 2
                let intPtr = ptr.bindMemory(to: UInt16.self)
                for i in 0..<count {
                    intPtr[i] = UInt16(bigEndian: intPtr[i])
                }
            }
        }
        
        return buffer
    }
    
    private func computeStats(data: Data, bitpix: Int) -> FITSStatistics {
        guard bitpix == -32 else {
            return FITSStatistics(min: 0, max: 0, mean: 0)
        }
        
        var minVal: Float = .greatestFiniteMagnitude
        var maxVal: Float = -.greatestFiniteMagnitude
        var sum: Double = 0
        var count = 0
        
        // First pass: Min, Max, Mean
        data.withUnsafeBytes { ptr in
            // Assuming data is now Little Endian Float32
            let floats = ptr.bindMemory(to: Float.self)
            count = floats.count
            
            for val in floats {
                if val.isFinite {
                    if val < minVal { minVal = val }
                    if val > maxVal { maxVal = val }
                    sum += Double(val)
                }
            }
        }
        
        let mean = count > 0 ? Float(sum / Double(count)) : 0
        
        // Second pass: Histogram for Percentiles
        // We'll use 10,000 bins for reasonable precision
        let numBins = 10000
        var histogram = [Int](repeating: 0, count: numBins)
        let range = maxVal - minVal
        
        if range > 0 {
             data.withUnsafeBytes { ptr in
                let floats = ptr.bindMemory(to: Float.self)
                for val in floats {
                    if val.isFinite {
                        let normalized = (val - minVal) / range
                        let bin = Int(normalized * Float(numBins - 1))
                        // Clamp just in case
                        let safeBin = min(max(bin, 0), numBins - 1)
                        histogram[safeBin] += 1
                    }
                }
            }
        }
        
        // Calculate Percentiles from Histogram
        func valueAtPercentile(_ p: Float) -> Float {
            let targetCount = Int(Float(count) * p)
            var currentCount = 0
            for i in 0..<numBins {
                currentCount += histogram[i]
                if currentCount >= targetCount {
                    let fraction = Float(i) / Float(numBins - 1)
                    return minVal + (fraction * range)
                }
            }
            return maxVal
        }
        
        let median = valueAtPercentile(0.50)
        let p90 = valueAtPercentile(0.90)
        let p99 = valueAtPercentile(0.99)
        
        return FITSStatistics(
            min: minVal, 
            max: maxVal, 
            mean: mean, 
            median: median, 
            percentiles: [90: p90, 99: p99]
        )
    }
}
