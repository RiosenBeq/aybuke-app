import UIKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import AppCore

/// "Auto": the best light and colour for a photo, picked on the device.
/// RAW photos (ProRAW, DNG) are developed automatically when opened, since
/// they look flat straight from the camera.
enum AutoDevelop {
    /// Settings for the Adjust sliders, from a 64 px sample of the photo.
    static func settings(for image: UIImage) -> AdjustmentSettings {
        let plan = AutoAdjust.plan(pixels: pixels(of: image))
        return AdjustmentSettings(
            brightness: plan.brightness,
            contrast: plan.contrast,
            saturation: plan.saturation,
            warmth: plan.warmth,
            sharpness: plan.sharpness,
            vignette: 0
        )
    }

    static func isRAW(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) as String?,
              let type = UTType(identifier) else { return false }
        return type.conforms(to: .rawImage)
    }

    /// Develops a RAW file with the camera's own rendering, capped at 4096 px,
    /// then applies Auto. Nil if Core Image can't read it.
    static func developRAW(_ data: Data) -> UIImage? {
        guard let raw = CIRAWFilter(imageData: data, identifierHint: nil) else { return nil }
        let native = raw.nativeSize
        let longEdge = max(native.width, native.height)
        if longEdge > 4096 { raw.scaleFactor = Float(4096 / longEdge) }
        raw.isLensCorrectionEnabled = true
        guard let developed = raw.outputImage,
              let rendered = ImageFilters.render(developed, extent: developed.extent) else { return nil }
        let settings = settings(for: rendered)
        guard let input = ImageFilters.ciImage(rendered) else { return rendered }
        return ImageFilters.render(ImageFilters.adjust(input, with: settings), extent: input.extent) ?? rendered
    }

    private static func pixels(of image: UIImage, side: Int = 64) -> [AutoAdjust.Pixel] {
        let thumb = ImageUtilities.normalized(image, maxLongEdge: side)
        guard let cgImage = thumb.cgImage else { return [] }
        let width = cgImage.width, height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 0, to: bytes.count, by: 4).compactMap { i in
            guard bytes[i + 3] > 0 else { return nil } // skip transparent cut-outs
            return AutoAdjust.Pixel(r: Double(bytes[i]) / 255, g: Double(bytes[i + 1]) / 255, b: Double(bytes[i + 2]) / 255)
        }
    }
}
