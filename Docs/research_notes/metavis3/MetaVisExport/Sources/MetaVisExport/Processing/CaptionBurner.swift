// CaptionBurner.swift
// MetaVisRender
//
// Renders captions/subtitles directly into video frames

import Foundation
import CoreGraphics
import CoreImage
import CoreText
import Metal
import simd

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - Caption Entry

/// Represents a single caption/subtitle entry for export
public struct ExportCaptionEntry: Sendable, Codable {
    /// Unique identifier
    public let id: String
    
    /// Start time in seconds
    public let startTime: Double
    
    /// End time in seconds
    public let endTime: Double
    
    /// Caption text content
    public let text: String
    
    /// Speaker name (optional)
    public let speaker: String?
    
    /// Position override (0-1 normalized)
    public let position: CGPoint?
    
    /// Style override
    public let styleOverride: CaptionStyleOverride?
    
    public init(
        id: String = UUID().uuidString,
        startTime: Double,
        endTime: Double,
        text: String,
        speaker: String? = nil,
        position: CGPoint? = nil,
        styleOverride: CaptionStyleOverride? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.speaker = speaker
        self.position = position
        self.styleOverride = styleOverride
    }
    
    /// Duration in seconds
    public var duration: Double {
        return endTime - startTime
    }
}

// MARK: - Caption Style Override

/// Style overrides for individual captions
public struct CaptionStyleOverride: Sendable, Codable {
    public let fontName: String?
    public let fontSize: CGFloat?
    public let textColor: CodableColor?
    public let backgroundColor: CodableColor?
    public let outlineColor: CodableColor?
    public let outlineWidth: CGFloat?
    public let alignment: TextAlignment?
    
    public init(
        fontName: String? = nil,
        fontSize: CGFloat? = nil,
        textColor: CodableColor? = nil,
        backgroundColor: CodableColor? = nil,
        outlineColor: CodableColor? = nil,
        outlineWidth: CGFloat? = nil,
        alignment: TextAlignment? = nil
    ) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.outlineColor = outlineColor
        self.outlineWidth = outlineWidth
        self.alignment = alignment
    }
    
    public enum TextAlignment: String, Sendable, Codable {
        case left
        case center
        case right
    }
}

// MARK: - Codable Color

/// A codable color representation
public struct CodableColor: Sendable, Codable {
    public let red: CGFloat
    public let green: CGFloat
    public let blue: CGFloat
    public let alpha: CGFloat
    
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
    
    public static let white = CodableColor(red: 1, green: 1, blue: 1)
    public static let black = CodableColor(red: 0, green: 0, blue: 0)
    public static let yellow = CodableColor(red: 1, green: 1, blue: 0)
    public static let clear = CodableColor(red: 0, green: 0, blue: 0, alpha: 0)
    
    public var cgColor: CGColor {
        return CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

// MARK: - Caption Burner Style

/// Style configuration for burned-in captions
public struct CaptionBurnerStyle: Sendable {
    /// Font name
    public let fontName: String
    
    /// Base font size (scaled based on video resolution)
    public let baseFontSize: CGFloat
    
    /// Text color
    public let textColor: CodableColor
    
    /// Background color (for background box)
    public let backgroundColor: CodableColor
    
    /// Background padding
    public let backgroundPadding: CGFloat
    
    /// Background corner radius
    public let backgroundCornerRadius: CGFloat
    
    /// Outline/stroke color
    public let outlineColor: CodableColor
    
    /// Outline width
    public let outlineWidth: CGFloat
    
    /// Shadow offset
    public let shadowOffset: CGSize
    
    /// Shadow blur radius
    public let shadowBlur: CGFloat
    
    /// Shadow color
    public let shadowColor: CodableColor
    
    /// Vertical position (0 = top, 1 = bottom)
    public let verticalPosition: CGFloat
    
    /// Maximum width as percentage of video width
    public let maxWidthRatio: CGFloat
    
    /// Line spacing multiplier
    public let lineSpacing: CGFloat
    
    /// Animation fade duration in seconds
    public let fadeDuration: Double
    
    public init(
        fontName: String = "Helvetica-Bold",
        baseFontSize: CGFloat = 48,
        textColor: CodableColor = .white,
        backgroundColor: CodableColor = CodableColor(red: 0, green: 0, blue: 0, alpha: 0.6),
        backgroundPadding: CGFloat = 12,
        backgroundCornerRadius: CGFloat = 8,
        outlineColor: CodableColor = .black,
        outlineWidth: CGFloat = 2,
        shadowOffset: CGSize = CGSize(width: 2, height: 2),
        shadowBlur: CGFloat = 4,
        shadowColor: CodableColor = CodableColor(red: 0, green: 0, blue: 0, alpha: 0.5),
        verticalPosition: CGFloat = 0.9,
        maxWidthRatio: CGFloat = 0.8,
        lineSpacing: CGFloat = 1.2,
        fadeDuration: Double = 0.15
    ) {
        self.fontName = fontName
        self.baseFontSize = baseFontSize
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.backgroundPadding = backgroundPadding
        self.backgroundCornerRadius = backgroundCornerRadius
        self.outlineColor = outlineColor
        self.outlineWidth = outlineWidth
        self.shadowOffset = shadowOffset
        self.shadowBlur = shadowBlur
        self.shadowColor = shadowColor
        self.verticalPosition = verticalPosition
        self.maxWidthRatio = maxWidthRatio
        self.lineSpacing = lineSpacing
        self.fadeDuration = fadeDuration
    }
    
    /// Preset styles
    public static let standard = CaptionBurnerStyle()
    
    public static let youtube = CaptionBurnerStyle(
        fontName: "Arial-BoldMT",
        baseFontSize: 42,
        textColor: .white,
        backgroundColor: CodableColor(red: 0, green: 0, blue: 0, alpha: 0.75),
        backgroundPadding: 8,
        outlineWidth: 0
    )
    
    public static let netflix = CaptionBurnerStyle(
        fontName: "Helvetica-Bold",
        baseFontSize: 40,
        textColor: .white,
        backgroundColor: .clear,
        outlineColor: .black,
        outlineWidth: 3,
        shadowBlur: 6
    )
    
    public static let instagram = CaptionBurnerStyle(
        fontName: "AvenirNext-Bold",
        baseFontSize: 36,
        textColor: .white,
        backgroundColor: CodableColor(red: 0, green: 0, blue: 0, alpha: 0.5),
        backgroundPadding: 10,
        backgroundCornerRadius: 12,
        verticalPosition: 0.85
    )
    
    public static let tiktok = CaptionBurnerStyle(
        fontName: "AvenirNext-Heavy",
        baseFontSize: 44,
        textColor: .white,
        backgroundColor: .clear,
        outlineColor: .black,
        outlineWidth: 4,
        verticalPosition: 0.5 // Center for TikTok style
    )
}

// MARK: - Caption Burner

/// Burns captions/subtitles directly into video frames
public actor CaptionBurner {
    
    // MARK: - Properties
    
    private let device: MTLDevice
    private let style: CaptionBurnerStyle
    private let captions: [ExportCaptionEntry]
    private let videoWidth: Int
    private let videoHeight: Int
    private var captionCache: [String: CachedCaption] = [:]
    private let ciContext: CIContext
    
    // MARK: - Cached Caption
    
    private struct CachedCaption {
        let image: CGImage
        let size: CGSize
        let bounds: CGRect
    }
    
    // MARK: - Initialization
    
    public init(
        device: MTLDevice,
        captions: [ExportCaptionEntry],
        style: CaptionBurnerStyle = .standard,
        videoWidth: Int,
        videoHeight: Int
    ) {
        self.device = device
        self.captions = captions.sorted { $0.startTime < $1.startTime }
        self.style = style
        self.videoWidth = videoWidth
        self.videoHeight = videoHeight
        self.ciContext = CIContext(mtlDevice: device, options: [
            .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
            .cacheIntermediates: false
        ])
    }
    
    // MARK: - Public Methods
    
    /// Get active captions at a given time
    public func activeCaptions(at time: Double) -> [ExportCaptionEntry] {
        return captions.filter { caption in
            time >= caption.startTime && time < caption.endTime
        }
    }
    
    /// Render captions onto a pixel buffer
    public func burn(onto pixelBuffer: CVPixelBuffer, at time: Double) throws {
        let activeCapts = activeCaptions(at: time)
        guard !activeCapts.isEmpty else { return }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        
        // Create CGContext from pixel buffer
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }
        
        // Render each caption
        for caption in activeCapts {
            try renderCaption(caption, in: context, at: time, width: width, height: height)
        }
    }
    
    /// Render captions onto a CIImage
    public func burn(onto image: CIImage, at time: Double) throws -> CIImage {
        let activeCapts = activeCaptions(at: time)
        guard !activeCapts.isEmpty else { return image }
        
        let width = Int(image.extent.width)
        let height = Int(image.extent.height)
        
        // Create caption overlay
        guard let overlayImage = createCaptionOverlay(
            captions: activeCapts,
            at: time,
            width: width,
            height: height
        ) else {
            return image
        }
        
        // Composite overlay onto image
        let ciOverlay = CIImage(cgImage: overlayImage)
        
        // Use source-over compositing
        guard let compositeFilter = CIFilter(name: "CISourceOverCompositing") else {
            return image
        }
        
        compositeFilter.setValue(ciOverlay, forKey: kCIInputImageKey)
        compositeFilter.setValue(image, forKey: kCIInputBackgroundImageKey)
        
        return compositeFilter.outputImage ?? image
    }
    
    /// Render captions onto a Metal texture
    public func burn(
        onto texture: MTLTexture,
        at time: Double,
        commandBuffer: MTLCommandBuffer
    ) throws {
        let activeCapts = activeCaptions(at: time)
        guard !activeCapts.isEmpty else { return }
        
        // Create caption overlay
        guard let overlayImage = createCaptionOverlay(
            captions: activeCapts,
            at: time,
            width: texture.width,
            height: texture.height
        ) else { return }
        
        // Convert to CIImage and render to texture
        let ciOverlay = CIImage(cgImage: overlayImage)
        
        // Create destination texture for overlay
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: texture.pixelFormat,
            width: texture.width,
            height: texture.height,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        
        guard let overlayTexture = device.makeTexture(descriptor: textureDescriptor) else { return }
        
        // Render overlay to texture
        ciContext.render(
            ciOverlay,
            to: overlayTexture,
            commandBuffer: commandBuffer,
            bounds: ciOverlay.extent,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        
        // Blend overlay onto target texture
        // This would require a compute shader for proper alpha blending
        // For now, use CIContext to composite
        let targetImage = CIImage(mtlTexture: texture, options: nil)!
        let composited = ciOverlay.composited(over: targetImage)
        
        ciContext.render(
            composited,
            to: texture,
            commandBuffer: commandBuffer,
            bounds: composited.extent,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
    }
    
    /// Clear caption cache
    public func clearCache() {
        captionCache.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func renderCaption(
        _ caption: ExportCaptionEntry,
        in context: CGContext,
        at time: Double,
        width: Int,
        height: Int
    ) throws {
        // Calculate fade alpha
        let alpha = calculateFadeAlpha(for: caption, at: time)
        guard alpha > 0 else { return }
        
        // Get or create cached caption image
        let cached = try getOrCreateCachedCaption(caption, width: width, height: height)
        
        // Calculate position
        let position = calculatePosition(
            for: caption,
            cachedSize: cached.size,
            width: width,
            height: height
        )
        
        // Save context state
        context.saveGState()
        
        // Apply alpha
        context.setAlpha(alpha)
        
        // Draw caption image (flip Y for CGContext)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        
        let drawRect = CGRect(
            x: position.x,
            y: CGFloat(height) - position.y - cached.size.height,
            width: cached.size.width,
            height: cached.size.height
        )
        
        context.draw(cached.image, in: drawRect)
        
        // Restore context state
        context.restoreGState()
    }
    
    private func createCaptionOverlay(
        captions: [ExportCaptionEntry],
        at time: Double,
        width: Int,
        height: Int
    ) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        // Clear with transparent
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        
        // Render each caption
        for caption in captions {
            do {
                try renderCaption(caption, in: context, at: time, width: width, height: height)
            } catch {
                // Skip failed captions
                continue
            }
        }
        
        return context.makeImage()
    }
    
    private func getOrCreateCachedCaption(
        _ caption: ExportCaptionEntry,
        width: Int,
        height: Int
    ) throws -> CachedCaption {
        let cacheKey = "\(caption.id)_\(width)x\(height)"
        
        if let cached = captionCache[cacheKey] {
            return cached
        }
        
        // Create caption image
        let cached = try createCaptionImage(caption, width: width, height: height)
        captionCache[cacheKey] = cached
        
        return cached
    }
    
    private func createCaptionImage(
        _ caption: ExportCaptionEntry,
        width: Int,
        height: Int
    ) throws -> CachedCaption {
        // Scale font size based on video height
        let scaleFactor = CGFloat(height) / 1080.0
        let fontSize = (caption.styleOverride?.fontSize ?? style.baseFontSize) * scaleFactor
        let fontName = caption.styleOverride?.fontName ?? style.fontName
        
        // Create font
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        
        // Create attributed string
        let textColor = caption.styleOverride?.textColor?.cgColor ?? style.textColor.cgColor
        
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        
        // Add paragraph style for alignment
        let paragraphStyle = NSMutableParagraphStyle()
        switch caption.styleOverride?.alignment ?? .center {
        case .left:
            paragraphStyle.alignment = .left
        case .center:
            paragraphStyle.alignment = .center
        case .right:
            paragraphStyle.alignment = .right
        }
        paragraphStyle.lineHeightMultiple = style.lineSpacing
        attributes[.paragraphStyle] = paragraphStyle
        
        // Prepare text with speaker if present
        var displayText = caption.text
        if let speaker = caption.speaker {
            displayText = "[\(speaker)] \(caption.text)"
        }
        
        let attributedString = NSAttributedString(string: displayText, attributes: attributes)
        
        // Calculate text bounds
        let maxWidth = CGFloat(width) * style.maxWidthRatio
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let textSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude),
            nil
        )
        
        // Add padding for background
        let padding = style.backgroundPadding * scaleFactor
        let imageWidth = textSize.width + padding * 2
        let imageHeight = textSize.height + padding * 2
        
        // Create context
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(ceil(imageWidth)),
            height: Int(ceil(imageHeight)),
            bitsPerComponent: 8,
            bytesPerRow: Int(ceil(imageWidth)) * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CaptionBurnerError.contextCreationFailed
        }
        
        // Draw background
        let bgColor = caption.styleOverride?.backgroundColor ?? style.backgroundColor
        if bgColor.alpha > 0 {
            context.setFillColor(bgColor.cgColor)
            let cornerRadius = style.backgroundCornerRadius * scaleFactor
            let bgRect = CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
            let bgPath = CGPath(roundedRect: bgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            context.addPath(bgPath)
            context.fillPath()
        }
        
        // Draw shadow
        if style.shadowColor.alpha > 0 {
            context.setShadow(
                offset: CGSize(
                    width: style.shadowOffset.width * scaleFactor,
                    height: style.shadowOffset.height * scaleFactor
                ),
                blur: style.shadowBlur * scaleFactor,
                color: style.shadowColor.cgColor
            )
        }
        
        // Draw text outline if needed
        let outlineWidth = caption.styleOverride?.outlineWidth ?? style.outlineWidth
        if outlineWidth > 0 {
            context.setTextDrawingMode(CGTextDrawingMode.stroke)
            context.setStrokeColor((caption.styleOverride?.outlineColor ?? style.outlineColor).cgColor)
            context.setLineWidth(outlineWidth * scaleFactor)
            
            // Draw outline
            let outlinePath = CGMutablePath()
            outlinePath.addRect(CGRect(x: padding, y: padding, width: textSize.width, height: textSize.height))
            let outlineFrame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), outlinePath, nil)
            
            context.saveGState()
            context.translateBy(x: padding, y: padding)
            CTFrameDraw(outlineFrame, context)
            context.restoreGState()
        }
        
        // Draw fill text
        context.setTextDrawingMode(CGTextDrawingMode.fill)
        context.setShadow(offset: CGSize.zero, blur: 0)
        
        let textPath = CGMutablePath()
        textPath.addRect(CGRect(x: padding, y: padding, width: textSize.width, height: textSize.height))
        let textFrame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), textPath, nil)
        
        context.saveGState()
        context.translateBy(x: padding, y: padding)
        CTFrameDraw(textFrame, context)
        context.restoreGState()
        
        guard let image = context.makeImage() else {
            throw CaptionBurnerError.imageCreationFailed
        }
        
        return CachedCaption(
            image: image,
            size: CGSize(width: imageWidth, height: imageHeight),
            bounds: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
        )
    }
    
    private func calculatePosition(
        for caption: ExportCaptionEntry,
        cachedSize: CGSize,
        width: Int,
        height: Int
    ) -> CGPoint {
        // Use caption position if specified
        if let position = caption.position {
            return CGPoint(
                x: position.x * CGFloat(width) - cachedSize.width / 2,
                y: position.y * CGFloat(height) - cachedSize.height / 2
            )
        }
        
        // Use style vertical position
        let x = (CGFloat(width) - cachedSize.width) / 2
        let y = style.verticalPosition * CGFloat(height) - cachedSize.height / 2
        
        return CGPoint(x: x, y: y)
    }
    
    private func calculateFadeAlpha(for caption: ExportCaptionEntry, at time: Double) -> CGFloat {
        let fadeIn = style.fadeDuration
        let fadeOut = style.fadeDuration
        
        // Fade in
        if time < caption.startTime + fadeIn {
            return CGFloat((time - caption.startTime) / fadeIn)
        }
        
        // Fade out
        if time > caption.endTime - fadeOut {
            return CGFloat((caption.endTime - time) / fadeOut)
        }
        
        // Full opacity
        return 1.0
    }
}

// MARK: - Caption Burner Error

public enum CaptionBurnerError: Error, LocalizedError {
    case contextCreationFailed
    case imageCreationFailed
    case renderingFailed
    
    public var errorDescription: String? {
        switch self {
        case .contextCreationFailed:
            return "Failed to create graphics context"
        case .imageCreationFailed:
            return "Failed to create caption image"
        case .renderingFailed:
            return "Failed to render captions"
        }
    }
}

// MARK: - SRT Parser

/// Parses SRT subtitle files
public struct SRTParser {
    
    public init() {}
    
    /// Parse SRT content into caption entries
    public func parse(_ content: String) -> [ExportCaptionEntry] {
        var captions: [ExportCaptionEntry] = []
        
        // Split into blocks
        let blocks = content.components(separatedBy: "\n\n")
        
        for block in blocks {
            let lines = block.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            guard lines.count >= 3 else { continue }
            
            // Parse timecode (line 1 is index, line 2 is timecode)
            let timecodeLine = lines[1]
            guard let times = parseTimecode(timecodeLine) else { continue }
            
            // Join remaining lines as text
            let text = lines[2...].joined(separator: "\n")
            
            let caption = ExportCaptionEntry(
                startTime: times.start,
                endTime: times.end,
                text: text
            )
            captions.append(caption)
        }
        
        return captions
    }
    
    private func parseTimecode(_ line: String) -> (start: Double, end: Double)? {
        // Format: 00:00:00,000 --> 00:00:00,000
        let parts = line.components(separatedBy: " --> ")
        guard parts.count == 2 else { return nil }
        
        guard let start = parseTime(parts[0]),
              let end = parseTime(parts[1]) else { return nil }
        
        return (start, end)
    }
    
    private func parseTime(_ timeString: String) -> Double? {
        // Format: 00:00:00,000
        let cleaned = timeString.replacingOccurrences(of: ",", with: ".")
        let parts = cleaned.components(separatedBy: ":")
        guard parts.count == 3 else { return nil }
        
        guard let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else { return nil }
        
        return hours * 3600 + minutes * 60 + seconds
    }
    
    /// Load and parse SRT file
    public func parse(fileAt url: URL) throws -> [ExportCaptionEntry] {
        let content = try String(contentsOf: url, encoding: .utf8)
        return parse(content)
    }
}

// MARK: - VTT Parser

/// Parses WebVTT subtitle files
public struct VTTParser {
    
    public init() {}
    
    /// Parse VTT content into caption entries
    public func parse(_ content: String) -> [ExportCaptionEntry] {
        var captions: [ExportCaptionEntry] = []
        
        // Skip WEBVTT header
        var lines = content.components(separatedBy: "\n")
        if lines.first?.hasPrefix("WEBVTT") == true {
            lines.removeFirst()
        }
        
        // Remove NOTE blocks and empty lines
        let blocks = lines.joined(separator: "\n").components(separatedBy: "\n\n")
        
        for block in blocks {
            let blockLines = block.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("NOTE") }
            
            guard blockLines.count >= 2 else { continue }
            
            // Find timecode line
            var timecodeIndex = 0
            if !blockLines[0].contains("-->") {
                timecodeIndex = 1 // Skip cue identifier
            }
            
            guard timecodeIndex < blockLines.count else { continue }
            
            let timecodeLine = blockLines[timecodeIndex]
            guard let times = parseTimecode(timecodeLine) else { continue }
            
            // Join remaining lines as text (remove VTT tags)
            let textLines = Array(blockLines[(timecodeIndex + 1)...])
            let text = textLines.joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            
            let caption = ExportCaptionEntry(
                startTime: times.start,
                endTime: times.end,
                text: text
            )
            captions.append(caption)
        }
        
        return captions
    }
    
    private func parseTimecode(_ line: String) -> (start: Double, end: Double)? {
        // Format: 00:00:00.000 --> 00:00:00.000 (optional settings after)
        let parts = line.components(separatedBy: " --> ")
        guard parts.count >= 2 else { return nil }
        
        let startStr = parts[0].trimmingCharacters(in: .whitespaces)
        let endStr = parts[1].components(separatedBy: " ")[0].trimmingCharacters(in: .whitespaces)
        
        guard let start = parseTime(startStr),
              let end = parseTime(endStr) else { return nil }
        
        return (start, end)
    }
    
    private func parseTime(_ timeString: String) -> Double? {
        // Format: 00:00:00.000 or 00:00.000
        let parts = timeString.components(separatedBy: ":")
        
        if parts.count == 2 {
            // MM:SS.mmm
            guard let minutes = Double(parts[0]),
                  let seconds = Double(parts[1]) else { return nil }
            return minutes * 60 + seconds
        } else if parts.count == 3 {
            // HH:MM:SS.mmm
            guard let hours = Double(parts[0]),
                  let minutes = Double(parts[1]),
                  let seconds = Double(parts[2]) else { return nil }
            return hours * 3600 + minutes * 60 + seconds
        }
        
        return nil
    }
    
    /// Load and parse VTT file
    public func parse(fileAt url: URL) throws -> [ExportCaptionEntry] {
        let content = try String(contentsOf: url, encoding: .utf8)
        return parse(content)
    }
}
