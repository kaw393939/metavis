import Foundation
import MetaVisCore

public enum FITSError: Error, Sendable {
    case invalidHeader
    case unsupportedBitpix(Int)
    case missingEndKeyword
    case dataReadFailed
    case noImageHDUFound
}

/// FITS (Flexible Image Transport System) reader.
/// Focused on the subset we need for scientific raster ingest (JWST-style 2D images).
public struct FITSReader: Sendable {

    private struct HDUInfo: Sendable {
        let metadata: [String: String]
        let dataOffset: UInt64
        let bitpix: Int
        let naxis: Int
        let naxis1: Int
        let naxis2: Int
        let dataSize: Int
        let paddedDataSize: Int
    }

    #if DEBUG
    public enum Diagnostics {
        private static let lock = NSLock()
        public private(set) static var lastBytesRead: Int = 0

        public static func reset() {
            lock.lock()
            defer { lock.unlock() }
            lastBytesRead = 0
        }

        static func addBytesRead(_ n: Int) {
            lock.lock()
            defer { lock.unlock() }
            lastBytesRead += max(0, n)
        }
    }
    #endif

    public init() {}

    /// Reads a FITS file and returns the first 2D image HDU encountered.
    ///
    /// - Note: FITS stores numeric payload big-endian. Returned `FITSAsset.rawData` is converted to little-endian.
    public func read(url: URL) throws -> FITSAsset {
        let fileSize: Int = {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            return values?.fileSize ?? 0
        }()
        guard fileSize > 0 else {
            throw FITSError.dataReadFailed
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        #if DEBUG
        Diagnostics.reset()
        #endif

        var cursor: UInt64 = 0

        while cursor < UInt64(fileSize) {
            let hdu = try readHDUInfo(handle: handle, startOffset: cursor, fileSize: UInt64(fileSize))

            if hdu.naxis >= 2 && hdu.naxis1 > 0 && hdu.naxis2 > 0 && hdu.bitpix != 0 {
                guard hdu.dataSize > 0 else { throw FITSError.dataReadFailed }
                guard hdu.dataOffset + UInt64(hdu.dataSize) <= UInt64(fileSize) else { throw FITSError.dataReadFailed }

                var payload = try readExact(handle: handle, offset: hdu.dataOffset, byteCount: hdu.dataSize)
                try convertEndiannessInPlace(data: &payload, bitpix: hdu.bitpix)
                let stats = computeStats(data: payload, bitpix: hdu.bitpix)

                return FITSAsset(
                    url: url,
                    width: hdu.naxis1,
                    height: hdu.naxis2,
                    bitpix: hdu.bitpix,
                    metadata: hdu.metadata,
                    statistics: stats,
                    rawData: payload
                )
            }

            cursor = hdu.dataOffset + UInt64(hdu.paddedDataSize)
        }

        throw FITSError.noImageHDUFound
    }

    /// Reads a single Float32 scanline from the first 2D image HDU without allocating the full payload.
    /// Returned values are little-endian `Float` values.
    ///
    /// - Note: Intended for tests/validation and incremental pipelines.
    internal func readFloat32Scanline(url: URL, row: Int) throws -> [Float] {
        let fileSize: Int = {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            return values?.fileSize ?? 0
        }()
        guard fileSize > 0 else { throw FITSError.dataReadFailed }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        #if DEBUG
        Diagnostics.reset()
        #endif

        var cursor: UInt64 = 0
        while cursor < UInt64(fileSize) {
            let hdu = try readHDUInfo(handle: handle, startOffset: cursor, fileSize: UInt64(fileSize))
            if hdu.naxis >= 2 && hdu.naxis1 > 0 && hdu.naxis2 > 0 && hdu.bitpix == -32 {
                guard row >= 0, row < hdu.naxis2 else { throw FITSError.dataReadFailed }
                let rowByteCount = hdu.naxis1 * 4
                let rowOffset = hdu.dataOffset + UInt64(row * rowByteCount)
                guard rowOffset + UInt64(rowByteCount) <= UInt64(fileSize) else { throw FITSError.dataReadFailed }

                var rowData = try readExact(handle: handle, offset: rowOffset, byteCount: rowByteCount)
                try convertEndiannessInPlace(data: &rowData, bitpix: hdu.bitpix)

                return rowData.withUnsafeBytes { raw in
                    Array(raw.bindMemory(to: Float.self))
                }
            }

            cursor = hdu.dataOffset + UInt64(hdu.paddedDataSize)
        }

        throw FITSError.noImageHDUFound
    }

    // MARK: - Header parsing

    private func parseHeaderBlocks(handle: FileHandle, startOffset: UInt64, fileSize: UInt64) throws -> ([String: String], UInt64) {
        var cursor = startOffset
        var metadata: [String: String] = [:]

        try handle.seek(toOffset: startOffset)

        while cursor < fileSize {
            let blockSize = 2880
            if cursor + UInt64(blockSize) > fileSize { break }

            guard let block = try handle.read(upToCount: blockSize), block.count == blockSize else {
                throw FITSError.dataReadFailed
            }

            #if DEBUG
            Diagnostics.addBytesRead(block.count)
            #endif

            for i in 0..<(blockSize / 80) {
                let cardStart = i * 80
                let cardData = block.subdata(in: cardStart..<(cardStart + 80))
                guard let cardString = String(data: cardData, encoding: .ascii) else { continue }

                let keyword = String(cardString.prefix(8)).trimmingCharacters(in: .whitespaces)
                if keyword == "END" {
                    return (metadata, cursor + UInt64(blockSize))
                }

                guard cardString.contains("=") else { continue }
                let parts = cardString.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }

                let valuePart = parts[1]
                let val = valuePart.split(separator: "/").first ?? ""
                let cleanVal = val.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "'", with: "")
                if !keyword.isEmpty {
                    metadata[keyword] = cleanVal
                }
            }

            cursor += UInt64(blockSize)
        }

        throw FITSError.missingEndKeyword
    }

    private func readHDUInfo(handle: FileHandle, startOffset: UInt64, fileSize: UInt64) throws -> HDUInfo {
        let (metadata, dataOffset) = try parseHeaderBlocks(handle: handle, startOffset: startOffset, fileSize: fileSize)

        let bitpix = Int(metadata["BITPIX"] ?? "") ?? 0
        let naxis = Int(metadata["NAXIS"] ?? "") ?? 0
        let naxis1 = Int(metadata["NAXIS1"] ?? "") ?? 0
        let naxis2 = Int(metadata["NAXIS2"] ?? "") ?? 0

        var dataSize = 0
        if naxis1 > 0 && naxis2 > 0 && bitpix != 0 {
            let bytesPerPixel = abs(bitpix) / 8
            let pixelCount = naxis1 * naxis2
            dataSize = pixelCount * bytesPerPixel
        }

        let paddedDataSize = ((dataSize + 2879) / 2880) * 2880

        return HDUInfo(
            metadata: metadata,
            dataOffset: dataOffset,
            bitpix: bitpix,
            naxis: naxis,
            naxis1: naxis1,
            naxis2: naxis2,
            dataSize: dataSize,
            paddedDataSize: paddedDataSize
        )
    }

    private func readExact(handle: FileHandle, offset: UInt64, byteCount: Int) throws -> Data {
        guard byteCount >= 0 else { throw FITSError.dataReadFailed }
        if byteCount == 0 { return Data() }

        try handle.seek(toOffset: offset)

        var out = Data(count: byteCount)
        var written = 0

        while written < byteCount {
            let remaining = byteCount - written
            let chunkSize = min(256 * 1024, remaining)
            guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else {
                throw FITSError.dataReadFailed
            }

            #if DEBUG
            Diagnostics.addBytesRead(chunk.count)
            #endif
            out.withUnsafeMutableBytes { dst in
                guard let base = dst.baseAddress else { return }
                chunk.withUnsafeBytes { src in
                    guard let srcBase = src.baseAddress else { return }
                    memcpy(base.advanced(by: written), srcBase, min(chunk.count, remaining))
                }
            }
            written += chunk.count
        }

        return out
    }

    // MARK: - Data conversion

    private func convertEndiannessInPlace(data: inout Data, bitpix: Int) throws {
        switch bitpix {
        case -32, 16:
            break
        default:
            throw FITSError.unsupportedBitpix(bitpix)
        }

        try data.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }

            if bitpix == -32 {
                let strideBytes = 4
                guard raw.count % strideBytes == 0 else { throw FITSError.dataReadFailed }
                for offset in stride(from: 0, to: raw.count, by: strideBytes) {
                    var value: UInt32 = 0
                    memcpy(&value, base.advanced(by: offset), strideBytes)
                    value = UInt32(bigEndian: value)
                    memcpy(base.advanced(by: offset), &value, strideBytes)
                }
            } else if bitpix == 16 {
                let strideBytes = 2
                guard raw.count % strideBytes == 0 else { throw FITSError.dataReadFailed }
                for offset in stride(from: 0, to: raw.count, by: strideBytes) {
                    var value: UInt16 = 0
                    memcpy(&value, base.advanced(by: offset), strideBytes)
                    value = UInt16(bigEndian: value)
                    memcpy(base.advanced(by: offset), &value, strideBytes)
                }
            }
        }
    }

    // MARK: - Stats

    private func computeStats(data: Data, bitpix: Int) -> FITSStatistics {
        guard bitpix == -32 else {
            return FITSStatistics(min: 0, max: 0, mean: 0)
        }

        var minVal: Float = .greatestFiniteMagnitude
        var maxVal: Float = -.greatestFiniteMagnitude
        var sum: Double = 0
        var finiteCount = 0

        data.withUnsafeBytes { raw in
            let floats = raw.bindMemory(to: Float.self)
            for v in floats {
                guard v.isFinite else { continue }
                if v < minVal { minVal = v }
                if v > maxVal { maxVal = v }
                sum += Double(v)
                finiteCount += 1
            }
        }

        guard finiteCount > 0, minVal.isFinite, maxVal.isFinite else {
            return FITSStatistics(min: 0, max: 0, mean: 0)
        }

        let mean = Float(sum / Double(finiteCount))

        // Histogram percentiles (approximate, deterministic)
        let numBins = 10_000
        var histogram = [Int](repeating: 0, count: numBins)
        let range = maxVal - minVal

        if range > 0 {
            data.withUnsafeBytes { raw in
                let floats = raw.bindMemory(to: Float.self)
                for v in floats {
                    guard v.isFinite else { continue }
                    let normalized = (v - minVal) / range
                    let bin = Int(normalized * Float(numBins - 1))
                    let safeBin = min(max(bin, 0), numBins - 1)
                    histogram[safeBin] += 1
                }
            }
        }

        func valueAtPercentile(_ p: Float) -> Float {
            let targetCount = max(1, Int(Float(finiteCount) * p))
            var current = 0
            for i in 0..<numBins {
                current += histogram[i]
                if current >= targetCount {
                    let fraction = Float(i) / Float(numBins - 1)
                    return minVal + fraction * range
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
            stdDev: nil,
            percentiles: [90: p90, 99: p99]
        )
    }
}
