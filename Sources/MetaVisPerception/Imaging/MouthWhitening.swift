import Foundation
import CoreImage
import CoreVideo
import CoreGraphics

public enum MouthWhitening {

    public enum MouthWhiteningError: Error, Sendable, Equatable {
        case unsupportedPixelFormat
        case invalidROI
        case unableToCreateOutput
    }

    /// Apply a conservative whitening pass inside the provided mouth ROI.
    ///
    /// - Parameters:
    ///   - pixelBuffer: Input frame. Must be `kCVPixelFormatType_32BGRA`.
    ///   - mouthRectTopLeft: Normalized mouth ROI in top-left origin coordinates.
    ///   - strength: [0,1].
    /// - Returns: New 32BGRA pixel buffer with whitening applied inside ROI.
    public static func apply(
        in pixelBuffer: CVPixelBuffer,
        mouthRectTopLeft: CGRect,
        strength: Double
    ) throws -> CVPixelBuffer {
        let fmt = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard fmt == kCVPixelFormatType_32BGRA else {
            throw MouthWhiteningError.unsupportedPixelFormat
        }

        let s = max(0.0, min(1.0, strength.isFinite ? strength : 0.0))
        if s <= 0.00001 {
            return pixelBuffer
        }

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = image.extent

        guard let mouthRectPx = pixelRectInCICoordinates(extent: extent, normalizedTopLeftRect: mouthRectTopLeft) else {
            throw MouthWhiteningError.invalidROI
        }

        // Crop to ROI and apply conservative adjustments.
        let roi = image.cropped(to: mouthRectPx)

        let vibrance = roi.applyingFilter(
            "CIVibrance",
            parameters: [
                kCIInputAmountKey: NSNumber(value: -0.55 * s)
            ]
        )

        let colorControls = vibrance.applyingFilter(
            "CIColorControls",
            parameters: [
                kCIInputSaturationKey: NSNumber(value: 1.0 - 0.25 * s),
                kCIInputBrightnessKey: NSNumber(value: 0.05 * s),
                kCIInputContrastKey: NSNumber(value: 1.0 + 0.06 * s)
            ]
        )

        // Very slight cooling to counter yellowing.
        let temp = colorControls.applyingFilter(
            "CITemperatureAndTint",
            parameters: [
                "inputNeutral": CIVector(x: 6500.0, y: 0.0),
                "inputTargetNeutral": CIVector(x: 6500.0 - CGFloat(450.0 * s), y: 0.0)
            ]
        )

        var out: CVPixelBuffer?
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let attrs: [String: Any] = [
            kCVPixelBufferWidthKey as String: w,
            kCVPixelBufferHeightKey as String: h,
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &out)
        guard status == kCVReturnSuccess, let outPB = out else {
            throw MouthWhiteningError.unableToCreateOutput
        }

        // Strict locality: start by copying input bytes, then render only the ROI crop back into place.
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(outPB, [])
        defer {
            CVPixelBufferUnlockBaseAddress(outPB, [])
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }

        guard let src = CVPixelBufferGetBaseAddress(pixelBuffer),
              let dst = CVPixelBufferGetBaseAddress(outPB) else {
            throw MouthWhiteningError.unableToCreateOutput
        }

        let srcBpr = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let dstBpr = CVPixelBufferGetBytesPerRow(outPB)
        let rowBytes = min(srcBpr, dstBpr)
        for y in 0..<h {
            memcpy(dst.advanced(by: y * dstBpr), src.advanced(by: y * srcBpr), rowBytes)
        }

        // Render only within the ROI bounds.
        let context = CIContext(options: [.useSoftwareRenderer: false, .workingColorSpace: NSNull()])
        context.render(temp, to: outPB, bounds: mouthRectPx, colorSpace: nil)
        return outPB
    }

    /// Convert a normalized top-left rect into a pixel rect in CI coordinate space (origin bottom-left).
    static func pixelRectInCICoordinates(extent: CGRect, normalizedTopLeftRect: CGRect) -> CGRect? {
        let r = normalizedTopLeftRect
            .standardized
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))

        guard r.width > 0.0001, r.height > 0.0001 else { return nil }

        let w = extent.width
        let h = extent.height

        let x = extent.origin.x + r.minX * w
        let yTop = r.minY * h
        let rectH = r.height * h

        // Convert top-left y to CI bottom-left y.
        let y = extent.origin.y + (h - (yTop + rectH))

        let pxRect = CGRect(x: x, y: y, width: r.width * w, height: rectH).integral
        guard pxRect.width >= 2, pxRect.height >= 2 else { return nil }
        return pxRect
    }
}
