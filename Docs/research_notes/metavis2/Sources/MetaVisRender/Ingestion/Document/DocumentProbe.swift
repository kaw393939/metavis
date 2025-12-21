// Sources/MetaVisRender/Ingestion/Document/DocumentProbe.swift
// Sprint 03: PDF metadata extraction and probing

import Foundation
import PDFKit

// MARK: - Document Probe

/// Extracts metadata from PDF documents without full analysis
public actor DocumentProbe {
    
    public init() {}
    
    // MARK: - Public API
    
    /// Probe a PDF document for metadata
    public func probe(_ url: URL) async throws -> DocumentProfile {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DocumentError.fileNotFound(url)
        }
        
        guard let document = PDFDocument(url: url) else {
            throw DocumentError.invalidDocument("Failed to open PDF")
        }
        
        // Get file attributes
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        let creationDate = attributes[.creationDate] as? Date
        let modificationDate = attributes[.modificationDate] as? Date
        
        // Extract PDF metadata
        let metadata = document.documentAttributes ?? [:]
        let title = metadata[PDFDocumentAttribute.titleAttribute] as? String
        let author = metadata[PDFDocumentAttribute.authorAttribute] as? String
        let subject = metadata[PDFDocumentAttribute.subjectAttribute] as? String
        let creator = metadata[PDFDocumentAttribute.creatorAttribute] as? String
        let producer = metadata[PDFDocumentAttribute.producerAttribute] as? String
        let keywords = metadata[PDFDocumentAttribute.keywordsAttribute] as? [String]
        
        // Get page information
        let pageCount = document.pageCount
        var pageSizes: [CGSize] = []
        
        for i in 0..<pageCount {
            if let page = document.page(at: i) {
                let bounds = page.bounds(for: .mediaBox)
                pageSizes.append(bounds.size)
            }
        }
        
        // Check encryption
        let isEncrypted = document.isEncrypted
        let isLocked = document.isLocked
        
        // Check if text is extractable
        let hasExtractableText = checkTextExtractable(document)
        
        // Detect PDF version from file
        let pdfVersion = extractPDFVersion(from: url)
        
        return DocumentProfile(
            id: UUID(),
            path: url.path,
            filename: url.lastPathComponent,
            fileSize: fileSize,
            creationDate: creationDate,
            modificationDate: modificationDate,
            pageCount: pageCount,
            pageSizes: pageSizes,
            title: title,
            author: author,
            subject: subject,
            creator: creator,
            producer: producer,
            keywords: keywords ?? [],
            pdfVersion: pdfVersion,
            isEncrypted: isEncrypted,
            isLocked: isLocked,
            hasExtractableText: hasExtractableText
        )
    }
    
    /// Quick probe for essential info only
    public func quickProbe(_ url: URL) async throws -> QuickDocumentProfile {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DocumentError.fileNotFound(url)
        }
        
        guard let document = PDFDocument(url: url) else {
            throw DocumentError.invalidDocument("Failed to open PDF")
        }
        
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        
        return QuickDocumentProfile(
            filename: url.lastPathComponent,
            pageCount: document.pageCount,
            fileSize: fileSize,
            isEncrypted: document.isEncrypted
        )
    }
    
    // MARK: - Private Methods
    
    private func checkTextExtractable(_ document: PDFDocument) -> Bool {
        guard document.pageCount > 0,
              let firstPage = document.page(at: 0) else {
            return false
        }
        
        let text = firstPage.string ?? ""
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func extractPDFVersion(from url: URL) -> String {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              data.count > 8 else {
            return "unknown"
        }
        
        // PDF version is in the header: %PDF-1.x
        let header = String(data: data.prefix(20), encoding: .ascii) ?? ""
        
        if let range = header.range(of: "%PDF-") {
            let versionStart = range.upperBound
            let versionEnd = header.index(versionStart, offsetBy: 3, limitedBy: header.endIndex) ?? header.endIndex
            return String(header[versionStart..<versionEnd])
        }
        
        return "unknown"
    }
}

// MARK: - Document Profile

/// Complete metadata profile for a PDF document
public struct DocumentProfile: Codable, Sendable, Identifiable {
    public let id: UUID
    public let path: String
    public let filename: String
    public let fileSize: Int64
    public let creationDate: Date?
    public let modificationDate: Date?
    
    // Page information
    public let pageCount: Int
    public let pageSizes: [CGSize]
    
    // PDF metadata
    public let title: String?
    public let author: String?
    public let subject: String?
    public let creator: String?
    public let producer: String?
    public let keywords: [String]
    
    // Technical
    public let pdfVersion: String
    public let isEncrypted: Bool
    public let isLocked: Bool
    public let hasExtractableText: Bool
    
    // MARK: - Computed Properties
    
    /// Check if all pages have the same size
    public var isUniformSize: Bool {
        guard let first = pageSizes.first else { return true }
        return pageSizes.allSatisfy { $0 == first }
    }
    
    /// Primary page size (first page)
    public var primaryPageSize: CGSize? {
        pageSizes.first
    }
    
    /// Formatted file size
    public var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    /// Page size description
    public var pageSizeDescription: String {
        guard let size = primaryPageSize else { return "Unknown" }
        
        // Standard paper sizes (in points, 72 points per inch)
        let letterWidth: CGFloat = 612
        let letterHeight: CGFloat = 792
        let a4Width: CGFloat = 595
        let a4Height: CGFloat = 842
        
        let tolerance: CGFloat = 5
        
        if abs(size.width - letterWidth) < tolerance && abs(size.height - letterHeight) < tolerance {
            return "Letter (8.5\" × 11\")"
        } else if abs(size.width - a4Width) < tolerance && abs(size.height - a4Height) < tolerance {
            return "A4 (210mm × 297mm)"
        } else {
            return String(format: "%.0f × %.0f pts", size.width, size.height)
        }
    }
}

/// Quick document profile for fast probing
public struct QuickDocumentProfile: Codable, Sendable {
    public let filename: String
    public let pageCount: Int
    public let fileSize: Int64
    public let isEncrypted: Bool
    
    public var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

// MARK: - Document Errors

/// Errors during document processing
public enum DocumentError: Error, LocalizedError {
    case fileNotFound(URL)
    case invalidDocument(String)
    case encryptedDocument
    case ocrFailed(String)
    case renderFailed(String)
    case pageOutOfRange(Int, Int)
    case unsupportedFormat(String)
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "Document not found: \(url.lastPathComponent)"
        case .invalidDocument(let reason):
            return "Invalid document: \(reason)"
        case .encryptedDocument:
            return "Document is encrypted and locked"
        case .ocrFailed(let reason):
            return "OCR failed: \(reason)"
        case .renderFailed(let reason):
            return "Render failed: \(reason)"
        case .pageOutOfRange(let page, let total):
            return "Page \(page) out of range (1-\(total))"
        case .unsupportedFormat(let format):
            return "Unsupported format: \(format)"
        }
    }
}
