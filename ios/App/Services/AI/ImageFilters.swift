import UIKit
import Metal
import CoreImage
import CoreImage.CIFilterBuiltins

/// Manual adjustments offered in the editor's Adjust panel.
struct AdjustmentSettings: Equatable {
    var brightness: Double = 0      // -0.3 … 0.3
    var contrast: Double = 1        // 0.7 … 1.4
    var saturation: Double = 1      // 0 … 2
    var warmth: Double = 0          // -1 … 1
    var sharpness: Double = 0       // 0 … 1
    var vignette: Double = 0        // 0 … 1

    static let neutral = AdjustmentSettings()

    var isNeutral: Bool { self == .neutral }
}

/// Core Image building blocks shared by the on-device tools and the offline
/// demo engine. All functions are pure and safe to call off the main thread.
enum ImageFilters {
    static let metalDevice = MTLCreateSystemDefaultDevice()
    /// The app's shared context. Explicitly Metal-backed, so Retro Cam's live
    /// preview can render into a Metal layer with it as well.
    static let context: CIContext = metalDevice.map { CIContext(mtlDevice: $0, options: [.cacheIntermediates: false]) }
        ?? CIContext(options: [.cacheIntermediates: false])
    /// For measuring pixels as they are (averages, masks), without colour
    /// management: the Vision checks and the share designs. Contexts are
    /// expensive to make and each compiles its own kernels, so these two
    /// are the only ones.
    static let measuringContext: CIContext = metalDevice.map { CIContext(mtlDevice: $0, options: [.workingColorSpace: NSNull()]) }
        ?? CIContext(options: [.workingColorSpace: NSNull()])

    static func render(_ image: CIImage, extent: CGRect? = nil) -> UIImage? {
        let rect = extent ?? image.extent
        guard let cgImage = context.createCGImage(image, from: rect) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    static func ciImage(_ image: UIImage) -> CIImage? {
        if let cgImage = image.cgImage { return CIImage(cgImage: cgImage) }
        return CIImage(image: image)
    }

    // MARK: Enhance

    static func autoEnhance(_ input: CIImage) -> CIImage {
        var image = input
        for filter in input.autoAdjustmentFilters(options: [.redEye: false]) {
            filter.setValue(image, forKey: kCIInputImageKey)
            image = filter.outputImage ?? image
        }
        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = image
        sharpen.sharpness = 0.45
        return sharpen.outputImage ?? image
    }

    static func upscale(_ input: CIImage, factor: Float) -> CIImage {
        let lanczos = CIFilter.lanczosScaleTransform()
        lanczos.inputImage = input
        lanczos.scale = factor
        lanczos.aspectRatio = 1
        return lanczos.outputImage ?? input
    }

    // MARK: Adjust

    static func adjust(_ input: CIImage, with settings: AdjustmentSettings) -> CIImage {
        guard !settings.isNeutral else { return input }
        var image = input

        let colors = CIFilter.colorControls()
        colors.inputImage = image
        colors.brightness = Float(settings.brightness)
        colors.contrast = Float(settings.contrast)
        colors.saturation = Float(settings.saturation)
        image = colors.outputImage ?? image

        if settings.warmth != 0 {
            let temperature = CIFilter.temperatureAndTint()
            temperature.inputImage = image
            temperature.neutral = CIVector(x: 6500, y: 0)
            // A higher target temperature renders the photo warmer.
            temperature.targetNeutral = CIVector(x: 6500 + CGFloat(settings.warmth) * 2500, y: 0)
            image = temperature.outputImage ?? image
        }

        if settings.sharpness > 0 {
            let sharpen = CIFilter.sharpenLuminance()
            sharpen.inputImage = image
            sharpen.sharpness = Float(settings.sharpness)
            image = sharpen.outputImage ?? image
        }

        if settings.vignette > 0 {
            let vignette = CIFilter.vignette()
            vignette.inputImage = image
            vignette.intensity = Float(settings.vignette)
            vignette.radius = 1.6
            image = vignette.outputImage ?? image
        }
        return image.cropped(to: input.extent)
    }

    // MARK: Demo-only approximations

    /// Stylized look used by the demo engine in place of a real restyle.
    static func stylize(_ input: CIImage, seed: Int) -> CIImage {
        switch abs(seed) % 4 {
        case 0:
            let comic = CIFilter.comicEffect()
            comic.inputImage = input
            return comic.outputImage ?? input
        case 1:
            let posterize = CIFilter.colorPosterize()
            posterize.inputImage = input
            posterize.levels = 6
            let bloom = CIFilter.bloom()
            bloom.inputImage = posterize.outputImage
            bloom.radius = 12
            bloom.intensity = 0.8
            return (bloom.outputImage ?? input).cropped(to: input.extent)
        case 2:
            let chrome = CIFilter.photoEffectChrome()
            chrome.inputImage = input
            let vibrance = CIFilter.vibrance()
            vibrance.inputImage = chrome.outputImage
            vibrance.amount = 0.8
            return vibrance.outputImage ?? input
        default:
            let sepia = CIFilter.sepiaTone()
            sepia.inputImage = input
            sepia.intensity = 0.7
            return sepia.outputImage ?? input
        }
    }

    /// Fakes object removal by blending a heavily blurred copy into the mask.
    static func blurInpaint(_ input: CIImage, mask: CIImage) -> CIImage {
        let scaledMask = mask.transformed(by: CGAffineTransform(
            scaleX: input.extent.width / max(mask.extent.width, 1),
            y: input.extent.height / max(mask.extent.height, 1)
        ))
        let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: 28).cropped(to: input.extent)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = blurred
        blend.backgroundImage = input
        blend.maskImage = scaledMask.applyingGaussianBlur(sigma: 6).cropped(to: input.extent)
        return blend.outputImage ?? input
    }

    /// Warm, punchy grade used by the demo engine in place of a prompt edit.
    static func cinematicGrade(_ input: CIImage) -> CIImage {
        adjust(input, with: AdjustmentSettings(brightness: 0.02, contrast: 1.12, saturation: 1.2, warmth: 0.45, sharpness: 0.2, vignette: 0.5))
    }
}
