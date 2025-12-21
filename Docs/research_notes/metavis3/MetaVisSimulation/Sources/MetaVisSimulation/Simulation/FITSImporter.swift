import Foundation
import Metal

public enum FITSError: Error {
    case fileNotFound
    case invalidHeader
    case unsupportedFormat
    case dataReadFailed
}

/// Importer for FITS (Flexible Image Transport System) files.
/// Converts scientific data into Metal 3D Textures.
public class FITSImporter {
    
    public init() {}
    
    /// Loads a FITS file and returns a 3D Texture.
    /// - Parameters:
    ///   - url: Path to the .fits file.
    ///   - device: Metal device to create the texture.
    /// - Returns: A single-channel float texture (R32Float).
    public func loadVolume(url: URL, device: MTLDevice) throws -> MTLTexture {
        let data = try Data(contentsOf: url)
        
        // FITS Block Size is 2880 bytes
        let blockSize = 2880
        var offset = 0
        
        // 1. Scan Headers to find the Image Extension
        // The primary header might be empty (NAXIS=0), so we look for the first valid image.
        
        var width = 0
        var height = 0
        var depth = 1
        var bitpix = 0
        var dataOffset = 0
        
        while offset < data.count {
            // 1. Read Header (one or more blocks)
            var headerString = ""
            var headerBlocks = 0
            var foundEnd = false
            
            var searchOffset = offset
            while searchOffset + blockSize <= data.count {
                let blockData = data.subdata(in: searchOffset..<searchOffset+blockSize)
                headerBlocks += 1
                searchOffset += blockSize
                
                // Parse 80-byte cards to find END
                var blockHasEnd = false
                for i in 0..<(blockSize / 80) {
                    let cardStart = i * 80
                    let cardData = blockData.subdata(in: cardStart..<cardStart+80)
                    let cardStr = String(data: cardData, encoding: .ascii) ?? ""
                    
                    headerString += cardStr
                    
                    // Strict check for END keyword
                    if cardStr.hasPrefix("END ") || cardStr.trimmingCharacters(in: .whitespaces) == "END" {
                        blockHasEnd = true
                        break
                    }
                }
                
                if blockHasEnd {
                    foundEnd = true
                    break
                }
            }
            
            guard foundEnd else {
                print("⚠️ FITS: Header END not found or file truncated.")
                break 
            }
            
            // 2. Parse Header
            let currentBitpix = extractHeaderValue(header: headerString, key: "BITPIX")
            let currentNaxis = extractHeaderValue(header: headerString, key: "NAXIS")
            let currentNaxis1 = extractHeaderValue(header: headerString, key: "NAXIS1")
            let currentNaxis2 = extractHeaderValue(header: headerString, key: "NAXIS2")
            let currentNaxis3 = extractHeaderValue(header: headerString, key: "NAXIS3")
            
            // 3. Calculate Data Size
            var dataSize = 0
            if let b = currentBitpix, let naxis = currentNaxis {
                if naxis > 0 {
                    let w = currentNaxis1 ?? 1
                    let h = currentNaxis2 ?? 1
                    let d = currentNaxis3 ?? 1
                    let pixelCount = w * h * d
                    let bytesPerPixel = abs(b) / 8
                    let totalBytes = pixelCount * bytesPerPixel
                    dataSize = ((totalBytes + blockSize - 1) / blockSize) * blockSize
                }
            }
            
            // 4. Check if this is the image we want
            // We want a 2D or 3D image with valid dimensions
            if let w = currentNaxis1, let h = currentNaxis2, w > 0 && h > 0 && (currentNaxis ?? 0) >= 2 {
                width = w
                height = h
                depth = currentNaxis3 ?? 1
                bitpix = currentBitpix ?? -32
                dataOffset = offset + (headerBlocks * blockSize)
                
                print("✅ FITS: Found Image Extension. Size: \(width)x\(height), Bitpix: \(bitpix)")
                break // Found it!
            }
            
            // 5. Advance to next HDU
            print("ℹ️ FITS: Skipping HDU (NAXIS=\(currentNaxis ?? 0)). HeaderBlocks: \(headerBlocks), DataSize: \(dataSize)")
            offset += (headerBlocks * blockSize) + dataSize
        }
        
        // Fallback if the loop logic failed (FITS is tricky without a full library)
        // Let's hardcode for the specific JWST file structure if generic fails, 
        // but let's try to be generic enough.
        // If we found dimensions, proceed.
        
        guard width > 0 && height > 0 && dataOffset > 0 else {
            throw FITSError.unsupportedFormat
        }
        
        // 2. Create Texture Descriptor
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = depth > 1 ? .type3D : .type2D
        descriptor.pixelFormat = .r32Float
        descriptor.width = width
        descriptor.height = height
        descriptor.depth = depth
        descriptor.usage = [.shaderRead]
        
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw FITSError.dataReadFailed
        }
        
        // 3. Process Data (Byte Swapping)
        // FITS is Big Endian. Metal/Swift (on Apple Silicon) is Little Endian.
        // We need to read the bytes, swap them, and upload.
        
        guard bitpix == -32 else {
            print("❌ FITS: Unsupported BITPIX: \(bitpix). Only -32 (Float32) is supported.")
            throw FITSError.unsupportedFormat
        }
        
        let pixelCount = width * height * depth
        let bytesToRead = pixelCount * 4 // 32-bit float
        
        guard dataOffset + bytesToRead <= data.count else {
            throw FITSError.dataReadFailed
        }
        
        // Unsafe processing for speed
        var floatData = [Float](repeating: 0, count: pixelCount)
        
        data.withUnsafeBytes { rawBuffer in
            let base = rawBuffer.baseAddress!.advanced(by: dataOffset)
            let bind = base.bindMemory(to: UInt32.self, capacity: pixelCount)
            
            for i in 0..<pixelCount {
                // Read UInt32, swap bytes, bitcast to Float
                let bigEndian = bind[i]
                let littleEndian = bigEndian.byteSwapped
                floatData[i] = Float(bitPattern: littleEndian)
            }
        }
        
        // CPU Validation
        var minVal: Float = .greatestFiniteMagnitude
        var maxVal: Float = -.greatestFiniteMagnitude
        var sum: Double = 0
        var nanCount = 0
        
        // Create a copy for sorting to get percentiles
        var sortedData = [Float]()
        sortedData.reserveCapacity(pixelCount)
        
        for val in floatData {
            if val.isNaN {
                nanCount += 1
            } else {
                if val < minVal { minVal = val }
                if val > maxVal { maxVal = val }
                sum += Double(val)
                sortedData.append(val)
            }
        }
        
        sortedData.sort()
        let count = sortedData.count
        let p50 = count > 0 ? sortedData[Int(Double(count) * 0.50)] : 0
        let p90 = count > 0 ? sortedData[Int(Double(count) * 0.90)] : 0
        let p99 = count > 0 ? sortedData[Int(Double(count) * 0.99)] : 0
        let p999 = count > 0 ? sortedData[Int(Double(count) * 0.999)] : 0
        
        let validCount = pixelCount - nanCount
        let mean = validCount > 0 ? sum / Double(validCount) : 0
        
        // Center 5 floats
        let centerIndex = pixelCount / 2
        let centerStart = max(0, centerIndex - 2)
        let centerEnd = min(pixelCount, centerIndex + 3)
        let centerFloats = Array(floatData[centerStart..<centerEnd])
        
        print("[CPU] Asset: \(url.lastPathComponent)")
        print("  Path: \(url.path)")
        print("  Data Count: \(data.count)")
        floatData.withUnsafeBufferPointer { buffer in
             print("  Buffer Address: \(String(describing: buffer.baseAddress))")
        }
        print("  First 5 floats: \(floatData.prefix(5))")
        print("  Center 5 floats: \(centerFloats)")
        print("  Stats:")
        print("    Min: \(minVal)")
        print("    Max: \(maxVal)")
        print("    Mean: \(mean)")
        print("    P50: \(p50)")
        print("    P90: \(p90)")
        print("    P99: \(p99)")
        print("    P99.9: \(p999)")
        print("    NaNs: \(nanCount) / \(pixelCount)")
        
        if maxVal == 0 && minVal == 0 {
             print("❌ WARNING: Data appears to be all zeros.")
        }
        
        // 4. Upload to Texture
        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0), size: MTLSize(width: width, height: height, depth: depth))
        
        if depth > 1 {
            for z in 0..<depth {
                let sliceSize = width * height
                let sliceOffset = z * sliceSize
                floatData.withUnsafeBufferPointer { buffer in
                    let ptr = buffer.baseAddress!.advanced(by: sliceOffset)
                    texture.replace(region: MTLRegion(origin: MTLOrigin(x:0,y:0,z:z), size: MTLSize(width:width,height:height,depth:1)),
                                    mipmapLevel: 0, slice: 0, withBytes: ptr, bytesPerRow: width * 4, bytesPerImage: width * height * 4)
                }
            }
        } else {
            texture.replace(region: region, mipmapLevel: 0, withBytes: floatData, bytesPerRow: width * 4)
        }
        
        #if os(macOS)
        if texture.storageMode == .managed {
            // texture.didModifyRange(0..<floatData.count * 4) // Compiler error?
            // Use Blit Synchronize instead (Robust & Explicit)
            if let queue = device.makeCommandQueue(),
               let buffer = queue.makeCommandBuffer(),
               let blit = buffer.makeBlitCommandEncoder() {
                blit.synchronize(resource: texture)
                blit.endEncoding()
                buffer.commit()
                buffer.waitUntilCompleted()
            }
        }
        #endif
        
        print("Loaded FITS: \(width)x\(height) (Offset: \(dataOffset))")
        
        return texture
    }
    
    private func extractHeaderValue(header: String, key: String) -> Int? {
        // FITS headers are 80-char cards. No newlines guaranteed.
        // We should iterate 80 chars at a time.
        
        var startIndex = header.startIndex
        while startIndex < header.endIndex {
            let endIndex = header.index(startIndex, offsetBy: 80, limitedBy: header.endIndex) ?? header.endIndex
            let line = String(header[startIndex..<endIndex])
            startIndex = endIndex
            
            // Check if key matches. Keys are usually left-aligned, up to 8 chars.
            // But we can just check prefix.
            if line.hasPrefix(key) {
                // Found it. Format: "KEY     = value / comment"
                let parts = line.components(separatedBy: "=")
                if parts.count > 1 {
                    let valuePart = parts[1].components(separatedBy: "/").first ?? ""
                    // Remove quotes if present (for strings), though we return Int here.
                    let trimmed = valuePart.trimmingCharacters(in: .whitespaces)
                    return Int(trimmed)
                }
            }
        }
        return nil
    }
}
