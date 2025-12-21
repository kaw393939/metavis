// Sources/MetaVisRender/Ingestion/Document/DocumentAnalysisEngine.swift
// Sprint 03: PDF OCR, text extraction, and layout analysis

import Foundation
import PDFKit
import Vision
import NaturalLanguage

// MARK: - Document Analysis Engine

/// Performs OCR, text extraction, and layout analysis on PDF documents
public actor DocumentAnalysisEngine {
    
    // MARK: - Configuration
    
    public struct Config: Sendable {
        /// Force OCR even if text is extractable
        public let forceOCR: Bool
        /// Recognition language hint
        public let languageHint: String?
        /// Minimum confidence for OCR results
        public let minConfidence: Float
        /// Detect tables in documents
        public let detectTables: Bool
        /// Detect images in documents
        public let detectImages: Bool
        /// Maximum pages to analyze (nil = all)
        public let maxPages: Int?
        
        public init(
            forceOCR: Bool = false,
            languageHint: String? = nil,
            minConfidence: Float = 0.5,
            detectTables: Bool = true,
            detectImages: Bool = true,
            maxPages: Int? = nil
        ) {
            self.forceOCR = forceOCR
            self.languageHint = languageHint
            self.minConfidence = minConfidence
            self.detectTables = detectTables
            self.detectImages = detectImages
            self.maxPages = maxPages
        }
        
        public static let `default` = Config()
        
        public static let ocrOnly = Config(forceOCR: true)
        
        public static let quick = Config(
            detectTables: false,
            detectImages: false,
            maxPages: 5
        )
    }
    
    private let config: Config
    
    public init(config: Config = .default) {
        self.config = config
    }
    
    // MARK: - Public API
    
    /// Analyze PDF document with OCR and layout extraction
    public func analyze(_ url: URL, pageRange: Range<Int>? = nil) async throws -> DocumentAnalysis {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DocumentError.fileNotFound(url)
        }
        
        guard let document = PDFDocument(url: url) else {
            throw DocumentError.invalidDocument("Failed to open PDF")
        }
        
        if document.isLocked {
            throw DocumentError.encryptedDocument
        }
        
        let totalPages = document.pageCount
        let startPage = pageRange?.lowerBound ?? 0
        let endPage = min(pageRange?.upperBound ?? totalPages, config.maxPages ?? totalPages, totalPages)
        
        var pages: [PageAnalysis] = []
        var allText = ""
        
        for pageIndex in startPage..<endPage {
            let pageAnalysis = try await analyzePage(document: document, pageIndex: pageIndex)
            pages.append(pageAnalysis)
            allText += pageAnalysis.textContent + "\n\n"
        }
        
        // Detect language
        let detectedLanguage = detectLanguage(text: allText)
        
        // Check for structured content
        let hasStructuredContent = pages.contains { !$0.tables.isEmpty || $0.layout != .unknown }
        
        // Calculate overall confidence
        let avgConfidence = pages.isEmpty ? 0 : pages.reduce(0) { $0 + $1.averageConfidence } / Float(pages.count)
        
        return DocumentAnalysis(
            pageCount: totalPages,
            analyzedPages: pages.count,
            pages: pages,
            textContent: allText.trimmingCharacters(in: .whitespacesAndNewlines),
            detectedLanguage: detectedLanguage,
            hasStructuredContent: hasStructuredContent,
            averageConfidence: avgConfidence
        )
    }
    
    /// Extract text only (fast path)
    public func extractText(_ url: URL) async throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw DocumentError.invalidDocument("Failed to open PDF")
        }
        
        if document.isLocked {
            throw DocumentError.encryptedDocument
        }
        
        var allText = ""
        
        for i in 0..<document.pageCount {
            if let page = document.page(at: i),
               let text = page.string {
                allText += text + "\n\n"
            }
        }
        
        // If no text extracted and not empty document, try OCR on first page
        if allText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && document.pageCount > 0 {
            let analysis = try await analyzePage(document: document, pageIndex: 0)
            return analysis.textContent
        }
        
        return allText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Page Analysis
    
    private func analyzePage(document: PDFDocument, pageIndex: Int) async throws -> PageAnalysis {
        guard let page = document.page(at: pageIndex) else {
            throw DocumentError.pageOutOfRange(pageIndex + 1, document.pageCount)
        }
        
        let bounds = page.bounds(for: .mediaBox)
        
        // Try to extract embedded text first
        var textContent = ""
        var textBlocks: [TextBlock] = []
        var useOCR = config.forceOCR
        
        if !config.forceOCR {
            let embeddedText = page.string ?? ""
            if !embeddedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                textContent = embeddedText
                // Create a single text block for embedded text
                textBlocks = [TextBlock(
                    text: embeddedText,
                    boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1),
                    confidence: 1.0,
                    fontSize: nil,
                    isBold: false,
                    isItalic: false
                )]
            } else {
                useOCR = true
            }
        }
        
        // Perform OCR if needed
        if useOCR {
            let ocrResults = try await performOCR(on: page)
            textBlocks = ocrResults.blocks
            textContent = ocrResults.blocks.map { $0.text }.joined(separator: "\n")
        }
        
        // Detect layout
        let layout = detectLayout(textBlocks: textBlocks, pageSize: bounds.size)
        
        // Detect tables (if enabled)
        var tables: [TableRegion] = []
        if config.detectTables {
            tables = detectTables(in: textBlocks, pageSize: bounds.size)
        }
        
        // Detect images (if enabled)
        var images: [ImageRegion] = []
        if config.detectImages {
            images = detectImages(on: page)
        }
        
        let avgConfidence = textBlocks.isEmpty ? 0 : textBlocks.reduce(0) { $0 + $1.confidence } / Float(textBlocks.count)
        
        return PageAnalysis(
            pageNumber: pageIndex + 1,
            pageSize: bounds.size,
            textBlocks: textBlocks,
            tables: tables,
            images: images,
            layout: layout,
            textContent: textContent,
            averageConfidence: avgConfidence
        )
    }
    
    // MARK: - OCR
    
    private func performOCR(on page: PDFPage) async throws -> (blocks: [TextBlock], confidence: Float) {
        // Render page to image for OCR
        let scale: CGFloat = 2.0  // 2x for better OCR
        let bounds = page.bounds(for: .mediaBox)
        let imageSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        
        let image = page.thumbnail(of: imageSize, for: .mediaBox)
        
        #if os(macOS)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw DocumentError.ocrFailed("Failed to get CGImage from thumbnail")
        }
        #else
        guard let cgImage = image.cgImage else {
            throw DocumentError.ocrFailed("Failed to get CGImage from thumbnail")
        }
        #endif
        
        // Perform text recognition
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        if let language = config.languageHint {
            request.recognitionLanguages = [language]
        }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try handler.perform([request])
                
                guard let observations = request.results else {
                    continuation.resume(returning: ([], 0))
                    return
                }
                
                var blocks: [TextBlock] = []
                var totalConfidence: Float = 0
                
                for observation in observations {
                    guard let topCandidate = observation.topCandidates(1).first else { continue }
                    
                    let confidence = topCandidate.confidence
                    if confidence < self.config.minConfidence { continue }
                    
                    // Convert bounding box (Vision uses bottom-left origin, normalized)
                    let bbox = observation.boundingBox
                    let normalizedBox = CGRect(
                        x: bbox.origin.x,
                        y: 1.0 - bbox.origin.y - bbox.height,  // Flip Y
                        width: bbox.width,
                        height: bbox.height
                    )
                    
                    let block = TextBlock(
                        text: topCandidate.string,
                        boundingBox: normalizedBox,
                        confidence: confidence,
                        fontSize: nil,
                        isBold: false,
                        isItalic: false
                    )
                    blocks.append(block)
                    totalConfidence += confidence
                }
                
                let avgConfidence = blocks.isEmpty ? 0 : totalConfidence / Float(blocks.count)
                
                // Sort blocks top-to-bottom, left-to-right
                blocks.sort { a, b in
                    if abs(a.boundingBox.minY - b.boundingBox.minY) < 0.02 {
                        return a.boundingBox.minX < b.boundingBox.minX
                    }
                    return a.boundingBox.minY < b.boundingBox.minY
                }
                
                continuation.resume(returning: (blocks, avgConfidence))
            } catch {
                continuation.resume(throwing: DocumentError.ocrFailed(error.localizedDescription))
            }
        }
    }
    
    // MARK: - Layout Detection
    
    private func detectLayout(textBlocks: [TextBlock], pageSize: CGSize) -> LayoutType {
        guard textBlocks.count > 3 else { return .unknown }
        
        // Analyze X positions of text blocks
        let leftMargin: CGFloat = 0.15
        let centerX: CGFloat = 0.5
        let rightMargin: CGFloat = 0.85
        
        var leftBlocks = 0
        var rightBlocks = 0
        var centeredBlocks = 0
        var indentedBlocks = 0
        
        for block in textBlocks {
            let centerOfBlock = block.boundingBox.midX
            
            if centerOfBlock < leftMargin + 0.2 {
                leftBlocks += 1
            } else if centerOfBlock > rightMargin - 0.2 {
                rightBlocks += 1
            } else if abs(centerOfBlock - centerX) < 0.15 {
                centeredBlocks += 1
            }
            
            // Check for screenplay-style indentation
            if block.boundingBox.minX > 0.3 && block.boundingBox.minX < 0.5 {
                indentedBlocks += 1
            }
        }
        
        let total = textBlocks.count
        
        // Screenplay detection: lots of centered and indented text
        if Float(centeredBlocks + indentedBlocks) / Float(total) > 0.5 {
            return .screenplay
        }
        
        // Two-column detection: roughly equal left and right blocks
        if Float(leftBlocks) / Float(total) > 0.3 && Float(rightBlocks) / Float(total) > 0.3 {
            return .twoColumn
        }
        
        // Presentation: mostly centered
        if Float(centeredBlocks) / Float(total) > 0.6 {
            return .presentation
        }
        
        // Default to single column
        if Float(leftBlocks) / Float(total) > 0.5 {
            return .singleColumn
        }
        
        return .unknown
    }
    
    // MARK: - Table Detection
    
    private func detectTables(in textBlocks: [TextBlock], pageSize: CGSize) -> [TableRegion] {
        // Simplified table detection based on aligned text blocks
        // Real implementation would use more sophisticated grid detection
        
        var tables: [TableRegion] = []
        
        // Group blocks by Y position (rows)
        var rows: [[TextBlock]] = []
        var currentRow: [TextBlock] = []
        var lastY: CGFloat = -1
        
        for block in textBlocks {
            if lastY < 0 || abs(block.boundingBox.minY - lastY) < 0.02 {
                currentRow.append(block)
            } else {
                if currentRow.count >= 2 {
                    rows.append(currentRow)
                }
                currentRow = [block]
            }
            lastY = block.boundingBox.minY
        }
        
        if currentRow.count >= 2 {
            rows.append(currentRow)
        }
        
        // Detect table-like regions (multiple rows with similar column structure)
        if rows.count >= 3 {
            let columnCounts = rows.map { $0.count }
            let modeColumnCount = columnCounts.max() ?? 0
            
            if modeColumnCount >= 2 {
                // Find bounding box of table-like region
                let tableRows = rows.filter { $0.count >= modeColumnCount - 1 }
                if tableRows.count >= 3 {
                    var minX: CGFloat = 1, maxX: CGFloat = 0
                    var minY: CGFloat = 1, maxY: CGFloat = 0
                    
                    for row in tableRows {
                        for block in row {
                            minX = min(minX, block.boundingBox.minX)
                            maxX = max(maxX, block.boundingBox.maxX)
                            minY = min(minY, block.boundingBox.minY)
                            maxY = max(maxY, block.boundingBox.maxY)
                        }
                    }
                    
                    let table = TableRegion(
                        boundingBox: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
                        rowCount: tableRows.count,
                        columnCount: modeColumnCount,
                        confidence: 0.7
                    )
                    tables.append(table)
                }
            }
        }
        
        return tables
    }
    
    // MARK: - Image Detection
    
    private func detectImages(on page: PDFPage) -> [ImageRegion] {
        // PDFKit doesn't directly expose image annotations
        // This is a simplified implementation
        var images: [ImageRegion] = []
        
        // Check for annotations that might be images
        for annotation in page.annotations {
            if annotation.type == "Stamp" || annotation.type == "FileAttachment" {
                let bounds = page.bounds(for: .mediaBox)
                let annotBounds = annotation.bounds
                
                // Normalize to 0-1
                let normalizedBox = CGRect(
                    x: annotBounds.minX / bounds.width,
                    y: 1.0 - (annotBounds.maxY / bounds.height),
                    width: annotBounds.width / bounds.width,
                    height: annotBounds.height / bounds.height
                )
                
                images.append(ImageRegion(
                    boundingBox: normalizedBox,
                    type: .embedded
                ))
            }
        }
        
        return images
    }
    
    // MARK: - Language Detection
    
    private func detectLanguage(text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        
        if let language = recognizer.dominantLanguage {
            return language.rawValue
        }
        
        return "unknown"
    }
}

// MARK: - Analysis Result Types

/// Complete document analysis result
public struct DocumentAnalysis: Codable, Sendable {
    public let pageCount: Int
    public let analyzedPages: Int
    public let pages: [PageAnalysis]
    public let textContent: String
    public let detectedLanguage: String
    public let hasStructuredContent: Bool
    public let averageConfidence: Float
    
    /// Word count
    public var wordCount: Int {
        textContent.split(separator: " ").count
    }
}

/// Analysis result for a single page
public struct PageAnalysis: Codable, Sendable {
    public let pageNumber: Int
    public let pageSize: CGSize
    public let textBlocks: [TextBlock]
    public let tables: [TableRegion]
    public let images: [ImageRegion]
    public let layout: LayoutType
    public let textContent: String
    public let averageConfidence: Float
}

/// A block of text with position and styling
public struct TextBlock: Codable, Sendable {
    public let text: String
    public let boundingBox: CGRect
    public let confidence: Float
    public let fontSize: Float?
    public let isBold: Bool
    public let isItalic: Bool
    
    public init(
        text: String,
        boundingBox: CGRect,
        confidence: Float,
        fontSize: Float?,
        isBold: Bool,
        isItalic: Bool
    ) {
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.fontSize = fontSize
        self.isBold = isBold
        self.isItalic = isItalic
    }
}

/// Detected table region
public struct TableRegion: Codable, Sendable {
    public let boundingBox: CGRect
    public let rowCount: Int
    public let columnCount: Int
    public let confidence: Float
}

/// Detected image region
public struct ImageRegion: Codable, Sendable {
    public let boundingBox: CGRect
    public let type: ImageType
    
    public enum ImageType: String, Codable, Sendable {
        case embedded
        case annotation
        case background
    }
}

/// Document layout type
public enum LayoutType: String, Codable, Sendable {
    case singleColumn
    case twoColumn
    case screenplay
    case presentation
    case unknown
}
