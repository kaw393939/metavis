// Sources/MetaVisRender/Ingestion/Metadata/XMPParser.swift
// Sprint 03_cleanup: XMP metadata extraction for keywords, ratings, copyright

import Foundation

/// Actor for extracting XMP metadata from image files and sidecar files
public actor XMPParser {
    
    /// Result type containing extracted XMP data
    public struct XMPResult: Sendable {
        public let keywords: [String]?
        public let description: String?
        public let rating: Int?
        public let copyright: String?
        public let creator: String?
        public let usageTerms: String?
        
        public static let empty = XMPResult(
            keywords: nil,
            description: nil,
            rating: nil,
            copyright: nil,
            creator: nil,
            usageTerms: nil
        )
        
        public var hasData: Bool {
            (keywords?.isEmpty == false) || rating != nil || description != nil ||
            copyright != nil || creator != nil
        }
        
        /// Convert to CurationMetadata type
        public func toCurationMetadata() -> CurationMetadata {
            CurationMetadata(
                keywords: keywords,
                description: description,
                rating: rating,
                copyright: copyright,
                creator: creator,
                usageTerms: usageTerms
            )
        }
        
        /// Merge with another result, preferring non-nil values from other
        public func merging(with other: XMPResult) -> XMPResult {
            XMPResult(
                keywords: other.keywords ?? keywords,
                description: other.description ?? description,
                rating: other.rating ?? rating,
                copyright: other.copyright ?? copyright,
                creator: other.creator ?? creator,
                usageTerms: other.usageTerms ?? usageTerms
            )
        }
    }
    
    public init() {}
    
    /// Extract XMP metadata from a media file
    /// Checks both embedded XMP and sidecar .xmp files
    /// - Parameter url: URL to the media file
    /// - Returns: Extracted XMP data
    public func extractXMP(from url: URL) async throws -> XMPResult {
        var result = XMPResult.empty
        
        // Try embedded XMP first (if ImageIO supports it)
        if let embeddedXMP = try? await extractEmbeddedXMP(from: url) {
            result = embeddedXMP
        }
        
        // Try sidecar XMP file (takes priority)
        let sidecarURL = url.deletingPathExtension().appendingPathExtension("xmp")
        if FileManager.default.fileExists(atPath: sidecarURL.path) {
            if let sidecarXMP = try? await parseXMPFile(sidecarURL) {
                result = result.merging(with: sidecarXMP)
            }
        }
        
        return result
    }
    
    // MARK: - Private Methods
    
    private func extractEmbeddedXMP(from url: URL) async throws -> XMPResult? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        
        // Read file and look for XMP packet
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return nil
        }
        
        // XMP packets are marked with <?xpacket begin or <x:xmpmeta
        guard let xmpData = extractXMPPacket(from: data) else {
            return nil
        }
        
        return try parseXMP(data: xmpData)
    }
    
    private func extractXMPPacket(from data: Data) -> Data? {
        guard let content = String(data: data, encoding: .utf8) else {
            // Try ASCII for binary files with embedded XMP
            guard let asciiContent = String(data: data, encoding: .ascii) else {
                return nil
            }
            return extractXMPFromString(asciiContent)
        }
        return extractXMPFromString(content)
    }
    
    private func extractXMPFromString(_ content: String) -> Data? {
        // Look for XMP packet markers
        let xmpMetaStart = "<x:xmpmeta"
        let xmpMetaEnd = "</x:xmpmeta>"
        
        guard let startRange = content.range(of: xmpMetaStart),
              let endRange = content.range(of: xmpMetaEnd) else {
            return nil
        }
        
        let xmpString = String(content[startRange.lowerBound..<endRange.upperBound])
        return xmpString.data(using: .utf8)
    }
    
    private func parseXMPFile(_ url: URL) async throws -> XMPResult {
        let data = try Data(contentsOf: url)
        return try parseXMP(data: data)
    }
    
    private func parseXMP(data: Data) throws -> XMPResult {
        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw MetadataError.invalidXMP
        }
        
        // Parse using simple regex-based extraction
        // (A full XML parser would be more robust but adds complexity)
        
        let keywords = extractKeywords(from: xmlString)
        let rating = extractRating(from: xmlString)
        let description = extractDescription(from: xmlString)
        let creator = extractCreator(from: xmlString)
        let copyright = extractCopyright(from: xmlString)
        let usageTerms = extractUsageTerms(from: xmlString)
        
        return XMPResult(
            keywords: keywords,
            description: description,
            rating: rating,
            copyright: copyright,
            creator: creator,
            usageTerms: usageTerms
        )
    }
    
    // MARK: - Field Extraction
    
    private func extractKeywords(from xml: String) -> [String]? {
        // Look for dc:subject containing rdf:Bag with rdf:li items
        guard let subjectRange = xml.range(of: "<dc:subject>"),
              let subjectEndRange = xml.range(of: "</dc:subject>") else {
            return nil
        }
        
        let subjectContent = String(xml[subjectRange.upperBound..<subjectEndRange.lowerBound])
        
        // Extract all rdf:li values
        var keywords: [String] = []
        let liPattern = #"<rdf:li[^>]*>([^<]+)</rdf:li>"#
        
        if let regex = try? NSRegularExpression(pattern: liPattern, options: []) {
            let matches = regex.matches(in: subjectContent, options: [], range: NSRange(subjectContent.startIndex..., in: subjectContent))
            for match in matches {
                if let range = Range(match.range(at: 1), in: subjectContent) {
                    keywords.append(String(subjectContent[range]).trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
        
        return keywords.isEmpty ? nil : keywords
    }
    
    private func extractRating(from xml: String) -> Int? {
        // Look for xmp:Rating
        let pattern = #"<xmp:Rating>(\d+)</xmp:Rating>"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: xml, options: [], range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else {
            return nil
        }
        
        return Int(xml[range])
    }
    
    private func extractDescription(from xml: String) -> String? {
        return extractLocalizedValue(from: xml, tag: "dc:description")
    }
    
    private func extractCreator(from xml: String) -> String? {
        // Creator is in dc:creator/rdf:Seq/rdf:li
        guard let creatorRange = xml.range(of: "<dc:creator>"),
              let creatorEndRange = xml.range(of: "</dc:creator>") else {
            return nil
        }
        
        let creatorContent = String(xml[creatorRange.upperBound..<creatorEndRange.lowerBound])
        
        // Extract first rdf:li value
        let liPattern = #"<rdf:li[^>]*>([^<]+)</rdf:li>"#
        
        if let regex = try? NSRegularExpression(pattern: liPattern, options: []),
           let match = regex.firstMatch(in: creatorContent, options: [], range: NSRange(creatorContent.startIndex..., in: creatorContent)),
           let range = Range(match.range(at: 1), in: creatorContent) {
            return String(creatorContent[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return nil
    }
    
    private func extractCopyright(from xml: String) -> String? {
        return extractLocalizedValue(from: xml, tag: "dc:rights")
    }
    
    private func extractUsageTerms(from xml: String) -> String? {
        return extractLocalizedValue(from: xml, tag: "xmpRights:UsageTerms")
    }
    
    /// Extract a localized value from rdf:Alt structure
    private func extractLocalizedValue(from xml: String, tag: String) -> String? {
        guard let startRange = xml.range(of: "<\(tag)>"),
              let endRange = xml.range(of: "</\(tag)>") else {
            return nil
        }
        
        let content = String(xml[startRange.upperBound..<endRange.lowerBound])
        
        // Extract value from rdf:li (prefer x-default)
        let liPattern = #"<rdf:li[^>]*>([^<]+)</rdf:li>"#
        
        if let regex = try? NSRegularExpression(pattern: liPattern, options: []),
           let match = regex.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)),
           let range = Range(match.range(at: 1), in: content) {
            return String(content[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return nil
    }
}
