import CoreGraphics
import Foundation
import Metal
import MetalKit
import Shared

/// Handles rendering of debug overlays like grids and safe zones
public class DebugOverlayRenderer {
    private let device: MTLDevice
    
    public init(device: MTLDevice) {
        self.device = device
    }
    
    public func renderGridOverlay(width: Int, height: Int, config: AnyCodable?) -> MTLTexture? {
        guard let configDict = config?.value as? [String: Any] else { return nil }

        let columns = configDict["columns"] as? Int ?? 12
        let gutter = configDict["gutter"] as? Double ?? 20.0
        let margin = configDict["margin"] as? Double ?? 40.0
        let colorHex = configDict["color"] as? String ?? "#FF00FF"
        let opacity = configDict["opacity"] as? Double ?? 0.5

        let color = ColorUtils.parseColor(colorHex) ?? SIMD4<Float>(1, 0, 1, 1)

        // Create a texture context using CG
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }

        // Draw Grid
        // Calculate column width
        let totalWidth = Double(width)
        let totalMargin = margin * 2
        let totalGutter = gutter * Double(columns - 1)
        let availableWidth = totalWidth - totalMargin - totalGutter
        let columnWidth = availableWidth / Double(columns)

        for i in 0 ..< columns {
            let x = margin + Double(i) * (columnWidth + gutter)
            let rect = CGRect(x: x, y: 0, width: columnWidth, height: Double(height))

            // Fill column with higher opacity for visibility
            context.setFillColor(red: CGFloat(color.x), green: CGFloat(color.y), blue: CGFloat(color.z), alpha: CGFloat(opacity * 0.4))
            context.fill(rect)

            // Stroke edges with thick lines
            context.setStrokeColor(red: CGFloat(color.x), green: CGFloat(color.y), blue: CGFloat(color.z), alpha: CGFloat(opacity))
            context.setLineWidth(4.0)
            context.stroke(rect)
        }

        // Create texture from image
        guard let cgImage = context.makeImage() else { return nil }

        let textureLoader = MTKTextureLoader(device: device)
        return try? textureLoader.newTexture(cgImage: cgImage, options: [.SRGB: false])
    }

    public func renderSafeZones(width: Int, height: Int, config: AnyCodable?) -> MTLTexture? {
        guard let configDict = config?.value as? [String: Any] else { return nil }

        let showActionSafe = configDict["showActionSafe"] as? Bool ?? true
        let showTitleSafe = configDict["showTitleSafe"] as? Bool ?? true
        let colorHex = configDict["color"] as? String ?? "#00FFFF"
        let opacity = configDict["opacity"] as? Double ?? 0.8

        let color = ColorUtils.parseColor(colorHex) ?? SIMD4<Float>(0, 1, 1, 1)

        // Create a texture context using CG
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }

        let w = Double(width)
        let h = Double(height)

        context.setStrokeColor(red: CGFloat(color.x), green: CGFloat(color.y), blue: CGFloat(color.z), alpha: CGFloat(opacity))
        context.setLineWidth(2.0)

        if showActionSafe {
            // Action Safe: 5% margin (90% width/height) - actually standard is 3.5% or 5% depending on standard.
            // Let's use 5% margin (so 10% total reduction)
            let marginW = w * 0.05
            let marginH = h * 0.05
            let rect = CGRect(x: marginW, y: marginH, width: w - marginW * 2, height: h - marginH * 2)
            context.stroke(rect)

            // Add label
            // (Simplified text drawing using CoreText or just lines for now)
        }

        if showTitleSafe {
            // Title Safe: 10% margin (80% width/height)
            let marginW = w * 0.10
            let marginH = h * 0.10
            let rect = CGRect(x: marginW, y: marginH, width: w - marginW * 2, height: h - marginH * 2)
            context.setLineDash(phase: 0, lengths: [10, 10])
            context.stroke(rect)
            context.setLineDash(phase: 0, lengths: [])
        }

        // Crosshair
        context.move(to: CGPoint(x: w / 2, y: h / 2 - 20))
        context.addLine(to: CGPoint(x: w / 2, y: h / 2 + 20))
        context.move(to: CGPoint(x: w / 2 - 20, y: h / 2))
        context.addLine(to: CGPoint(x: w / 2 + 20, y: h / 2))
        context.strokePath()

        // Create texture from image
        guard let cgImage = context.makeImage() else { return nil }

        let textureLoader = MTKTextureLoader(device: device)
        return try? textureLoader.newTexture(cgImage: cgImage, options: [.SRGB: false])
    }
}
