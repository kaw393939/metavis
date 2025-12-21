import CoreGraphics
import Foundation
import Shared
import simd

public enum RenderUtils {
    public static func calculateLayoutPosition(
        layout: LayoutConfig,
        imageSize: CGSize,
        screenSize: CGSize
    ) -> CGPoint {
        var margin = layout.margin ?? 0.0

        // Add safe area
        if layout.safeArea == "Title Safe" {
            margin += min(screenSize.width, screenSize.height) * 0.05
        } else if layout.safeArea == "Action Safe" {
            margin += min(screenSize.width, screenSize.height) * 0.025
        }

        let anchor = layout.anchor ?? "Center"
        var x: Double = 0
        var y: Double = 0

        let halfW = screenSize.width / 2
        let halfH = screenSize.height / 2
        let halfImgW = imageSize.width / 2
        let halfImgH = imageSize.height / 2

        if anchor.contains("Left") {
            x = -halfW + margin + halfImgW
        } else if anchor.contains("Right") {
            x = halfW - margin - halfImgW
        } else {
            x = 0
        }

        if anchor.contains("Upper") || anchor.contains("Top") {
            y = -halfH + margin + halfImgH
        } else if anchor.contains("Lower") || anchor.contains("Bottom") {
            y = halfH - margin - halfImgH
        } else {
            y = 0
        }

        return CGPoint(x: x, y: y)
    }

    public static func parseColor(_ hex: String?) -> SIMD4<Float>? {
        guard let hex = hex, hex.hasPrefix("#") else { return nil }
        let hexString = String(hex.dropFirst())
        guard let val = Int(hexString, radix: 16) else { return nil }

        let r = Float((val >> 16) & 0xFF) / 255.0
        let g = Float((val >> 8) & 0xFF) / 255.0
        let b = Float(val & 0xFF) / 255.0
        return SIMD4<Float>(r, g, b, 1.0)
    }
}
