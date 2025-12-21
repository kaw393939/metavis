// Sources/MetaVisRender/Ingestion/Document/PageRenderer.swift
// Sprint 03: PDF page to texture rendering

import Foundation
import PDFKit
import Metal
import CoreGraphics

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

// MARK: - Page Renderer

/// Renders PDF pages to Metal textures or images
public actor PageRenderer {
    
    // MARK: - Configuration
    
    public struct Config: Sendable {
        /// Default DPI for rendering
        public let dpi: CGFloat
        /// Background color
        public let backgroundColor: CGColor
        /// Enable antialiasing
        public let antialiasing: Bool
        /// Cache rendered pages
        public let enableCache: Bool
        /// Maximum cache size in MB
        public let maxCacheSizeMB: Int
        
        public init(
            dpi: CGFloat = 150,
            backgroundColor: CGColor = CGColor(gray: 1.0, alpha: 1.0),
            antialiasing: Bool = true,
            enableCache: Bool = true,
            maxCacheSizeMB: Int = 100
        ) {
            self.dpi = dpi
            self.backgroundColor = backgroundColor
            self.antialiasing = antialiasing
            self.enableCache = enableCache
            self.maxCacheSizeMB = maxCacheSizeMB
        }
        
        public static let `default` = Config()
        
        public static let highQuality = Config(dpi: 300)
        
        public static let preview = Config(dpi: 72, enableCache: false)
    }
    
    private let config: Config
    private let device: MTLDevice?
    private var cache: [String: CachedPage] = [:]
    private var cacheSize: Int = 0
    
    private struct CachedPage {
        let texture: MTLTexture
        let size: Int
        let accessTime: Date
    }
    
    public init(config: Config = .default, device: MTLDevice? = nil) {
        self.config = config
        self.device = device ?? MTLCreateSystemDefaultDevice()
    }
    
    // MARK: - Public API
    
    /// Render PDF page to Metal texture
    public func renderToTexture(
        page: Int,
        from url: URL,
        resolution: CGSize? = nil
    ) async throws -> MTLTexture {
        guard let device = device else {
            throw DocumentError.renderFailed("Metal device not available")
        }
        
        // Check cache
        let cacheKey = "\(url.path)_\(page)_\(resolution?.width ?? 0)x\(resolution?.height ?? 0)"
        if config.enableCache, let cached = cache[cacheKey] {
            return cached.texture
        }
        
        // Render to CGImage
        let cgImage = try await renderToCGImage(page: page, from: url, resolution: resolution)
        
        // Create texture from CGImage
        let texture = try createTexture(from: cgImage, device: device)
        
        // Cache if enabled
        if config.enableCache {
            let estimatedSize = cgImage.width * cgImage.height * 4  // RGBA
            cacheTexture(texture, size: estimatedSize, key: cacheKey)
        }
        
        return texture
    }
    
    /// Render PDF page to CGImage
    public func renderToCGImage(
        page pageNumber: Int,
        from url: URL,
        resolution: CGSize? = nil
    ) async throws -> CGImage {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DocumentError.fileNotFound(url)
        }
        
        guard let document = PDFDocument(url: url) else {
            throw DocumentError.invalidDocument("Failed to open PDF")
        }
        
        guard pageNumber >= 1 && pageNumber <= document.pageCount else {
            throw DocumentError.pageOutOfRange(pageNumber, document.pageCount)
        }
        
        guard let page = document.page(at: pageNumber - 1) else {
            throw DocumentError.pageOutOfRange(pageNumber, document.pageCount)
        }
        
        let bounds = page.bounds(for: .mediaBox)
        
        // Calculate render size
        let renderSize: CGSize
        if let resolution = resolution {
            renderSize = resolution
        } else {
            let scale = config.dpi / 72.0  // PDF uses 72 DPI
            renderSize = CGSize(
                width: bounds.width * scale,
                height: bounds.height * scale
            )
        }
        
        // Create context and render
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let context = CGContext(
            data: nil,
            width: Int(renderSize.width),
            height: Int(renderSize.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(renderSize.width) * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            throw DocumentError.renderFailed("Failed to create graphics context")
        }
        
        // Fill background
        context.setFillColor(config.backgroundColor)
        context.fill(CGRect(origin: .zero, size: renderSize))
        
        // Scale and render
        let scaleX = renderSize.width / bounds.width
        let scaleY = renderSize.height / bounds.height
        
        context.scaleBy(x: scaleX, y: scaleY)
        
        if config.antialiasing {
            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)
        }
        
        // PDFPage draws with origin at bottom-left
        #if os(macOS)
        let nsGraphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsGraphicsContext
        page.draw(with: .mediaBox, to: context)
        NSGraphicsContext.restoreGraphicsState()
        #else
        UIGraphicsPushContext(context)
        page.draw(with: .mediaBox, to: context)
        UIGraphicsPopContext()
        #endif
        
        guard let cgImage = context.makeImage() else {
            throw DocumentError.renderFailed("Failed to create image")
        }
        
        return cgImage
    }
    
    /// Render page with text highlighting
    public func renderWithHighlight(
        page pageNumber: Int,
        from url: URL,
        highlightText: [String],
        highlightColor: CGColor = CGColor(red: 1, green: 1, blue: 0, alpha: 0.5),
        resolution: CGSize? = nil
    ) async throws -> CGImage {
        guard let document = PDFDocument(url: url) else {
            throw DocumentError.invalidDocument("Failed to open PDF")
        }
        
        guard let page = document.page(at: pageNumber - 1) else {
            throw DocumentError.pageOutOfRange(pageNumber, document.pageCount)
        }
        
        // Find text locations
        var highlightRects: [CGRect] = []
        
        for text in highlightText {
            let selections = document.findString(text, withOptions: .caseInsensitive)
            for selection in selections {
                if selection.pages.contains(page) {
                    // Get selection bounds on this page
                    let bounds = selection.bounds(for: page)
                    highlightRects.append(bounds)
                }
            }
        }
        
        // Render base page
        let baseImage = try await renderToCGImage(page: pageNumber, from: url, resolution: resolution)
        
        guard !highlightRects.isEmpty else {
            return baseImage
        }
        
        // Add highlights
        let pageBounds = page.bounds(for: .mediaBox)
        let scaleX = CGFloat(baseImage.width) / pageBounds.width
        let scaleY = CGFloat(baseImage.height) / pageBounds.height
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: baseImage.width,
            height: baseImage.height,
            bitsPerComponent: 8,
            bytesPerRow: baseImage.width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw DocumentError.renderFailed("Failed to create context for highlights")
        }
        
        // Draw base image
        context.draw(baseImage, in: CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height))
        
        // Draw highlights
        context.setFillColor(highlightColor)
        context.setBlendMode(.multiply)
        
        for rect in highlightRects {
            let scaledRect = CGRect(
                x: rect.minX * scaleX,
                y: rect.minY * scaleY,
                width: rect.width * scaleX,
                height: rect.height * scaleY
            )
            context.fill(scaledRect)
        }
        
        guard let highlightedImage = context.makeImage() else {
            throw DocumentError.renderFailed("Failed to create highlighted image")
        }
        
        return highlightedImage
    }
    
    /// Render page to file
    public func renderToFile(
        page: Int,
        from url: URL,
        output: URL,
        format: ImageFormat = .png,
        resolution: CGSize? = nil
    ) async throws {
        let cgImage = try await renderToCGImage(page: page, from: url, resolution: resolution)
        
        #if os(macOS)
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            throw DocumentError.renderFailed("Failed to create bitmap")
        }
        
        let imageData: Data?
        switch format {
        case .png:
            imageData = bitmap.representation(using: .png, properties: [:])
        case .jpeg:
            imageData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        case .tiff:
            imageData = bitmap.representation(using: .tiff, properties: [:])
        }
        
        guard let data = imageData else {
            throw DocumentError.renderFailed("Failed to encode image")
        }
        
        try data.write(to: output)
        #else
        let uiImage = UIImage(cgImage: cgImage)
        
        let imageData: Data?
        switch format {
        case .png:
            imageData = uiImage.pngData()
        case .jpeg:
            imageData = uiImage.jpegData(compressionQuality: 0.9)
        case .tiff:
            // iOS doesn't support TIFF directly, use PNG
            imageData = uiImage.pngData()
        }
        
        guard let data = imageData else {
            throw DocumentError.renderFailed("Failed to encode image")
        }
        
        try data.write(to: output)
        #endif
    }
    
    /// Render all pages to directory
    public func renderAllPages(
        from url: URL,
        outputDir: URL,
        format: ImageFormat = .png,
        resolution: CGSize? = nil,
        progress: ((Int, Int) -> Void)? = nil
    ) async throws -> [URL] {
        guard let document = PDFDocument(url: url) else {
            throw DocumentError.invalidDocument("Failed to open PDF")
        }
        
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        
        var outputURLs: [URL] = []
        let pageCount = document.pageCount
        
        for i in 1...pageCount {
            let filename = String(format: "page_%03d.\(format.fileExtension)", i)
            let outputURL = outputDir.appendingPathComponent(filename)
            
            try await renderToFile(page: i, from: url, output: outputURL, format: format, resolution: resolution)
            outputURLs.append(outputURL)
            
            progress?(i, pageCount)
        }
        
        return outputURLs
    }
    
    /// Clear render cache
    public func clearCache() {
        cache.removeAll()
        cacheSize = 0
    }
    
    // MARK: - Private Methods
    
    private func createTexture(from cgImage: CGImage, device: MTLDevice) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: cgImage.width,
            height: cgImage.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw DocumentError.renderFailed("Failed to create Metal texture")
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = cgImage.width * 4
        
        guard let context = CGContext(
            data: nil,
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw DocumentError.renderFailed("Failed to create context for texture")
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        
        guard let data = context.data else {
            throw DocumentError.renderFailed("Failed to get context data")
        }
        
        texture.replace(
            region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                            size: MTLSize(width: cgImage.width, height: cgImage.height, depth: 1)),
            mipmapLevel: 0,
            withBytes: data,
            bytesPerRow: bytesPerRow
        )
        
        return texture
    }
    
    private func cacheTexture(_ texture: MTLTexture, size: Int, key: String) {
        // Evict old entries if cache is too large
        let maxSize = config.maxCacheSizeMB * 1024 * 1024
        
        while cacheSize + size > maxSize && !cache.isEmpty {
            // Remove oldest entry
            if let oldest = cache.min(by: { $0.value.accessTime < $1.value.accessTime }) {
                cacheSize -= oldest.value.size
                cache.removeValue(forKey: oldest.key)
            }
        }
        
        cache[key] = CachedPage(texture: texture, size: size, accessTime: Date())
        cacheSize += size
    }
}

// MARK: - Image Format

public enum ImageFormat: String, Sendable {
    case png
    case jpeg
    case tiff
    
    public var fileExtension: String {
        rawValue
    }
    
    public var mimeType: String {
        switch self {
        case .png: return "image/png"
        case .jpeg: return "image/jpeg"
        case .tiff: return "image/tiff"
        }
    }
}
