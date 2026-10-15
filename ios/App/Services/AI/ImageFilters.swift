import UIKit
import Metal
import CoreImage
import CoreImage.CIFilterBuiltins
import AppCore

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

    /// The Adjust tool's sliders (`AdjustmentSettings`). Every size, radius and
    /// colour map comes from AppCore (`AdjustRendering`, `ToneMap`) and scales
    /// with the photo, so the 1200 px preview and the full-size render match.
    /// Neutral sliders skip their filter, so photos without the vibe sliders
    /// render as they always have.
    static func adjust(_ input: CIImage, with settings: AdjustmentSettings) -> CIImage {
        guard !settings.isNeutral else { return input }
        let extent = input.extent
        let longEdge = Double(max(extent.width, extent.height))
        var image = input

        if settings.brightness != 0 || settings.contrast != 1 || settings.saturation != 1 {
            let colors = CIFilter.colorControls()
            colors.inputImage = image
            colors.brightness = Float(settings.brightness)
            colors.contrast = Float(settings.contrast)
            colors.saturation = Float(settings.saturation)
            image = colors.outputImage ?? image
        }

        if settings.warmth != 0 {
            let temperature = CIFilter.temperatureAndTint()
            temperature.inputImage = image
            temperature.neutral = CIVector(x: 6500, y: 0)
            // A higher target temperature renders the photo warmer.
            temperature.targetNeutral = CIVector(x: 6500 + CGFloat(settings.warmth) * 2500, y: 0)
            image = temperature.outputImage ?? image
        }

        if settings.hasToneMap {
            image = toneMap(image, settings: settings)
        }

        if settings.sharpness > 0 {
            let sharpen = CIFilter.sharpenLuminance()
            sharpen.inputImage = image
            sharpen.sharpness = Float(settings.sharpness)
            image = sharpen.outputImage ?? image
        }

        if let glow = AdjustRendering.glow(settings.glow, longEdge: longEdge) {
            image = self.glow(image, glow)
        }

        if let plan = AdjustRendering.vignette(settings.vignette, width: Double(extent.width), height: Double(extent.height)) {
            let vignette = CIFilter.vignetteEffect()
            vignette.inputImage = image
            vignette.center = CGPoint(x: extent.midX, y: extent.midY)
            vignette.radius = Float(plan.radius)
            vignette.intensity = Float(plan.intensity)
            vignette.falloff = Float(plan.falloff)
            image = vignette.outputImage ?? image
        }

        // Last, so nothing blurs or sharpens it.
        if let grain = AdjustRendering.grain(settings.grain, longEdge: longEdge) {
            image = filmGrain(over: image.cropped(to: extent), amount: grain.amount, scale: grain.scale)
        }
        return image.cropped(to: extent)
    }

    /// Fade, highlights, shadows and tint as one colour cube on gamma-encoded
    /// sRGB values (`ToneMap`).
    private static func toneMap(_ image: CIImage, settings: AdjustmentSettings) -> CIImage {
        let dimension = 32
        let key = [settings.fade, settings.highlights, settings.shadows, settings.tint]
        // The preview and Apply ask for the same cube; making one takes a moment.
        let data: Data = cubeLock.withLock {
            if let cached = cachedCube, cached.key == key { return cached.data }
            let floats = ToneMap.cube(for: settings, dimension: dimension)
            let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
            cachedCube = (key, data)
            return data
        }
        let cube = CIFilter.colorCubeWithColorSpace()
        cube.inputImage = image
        cube.cubeDimension = Float(dimension)
        cube.cubeData = data
        cube.colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        return cube.outputImage ?? image
    }

    private static let cubeLock = NSLock()
    nonisolated(unsafe) private static var cachedCube: (key: [Double], data: Data)?

    /// Soft light: the tones above the threshold, blurred wide and screened
    /// back over the photo (gamma-encoded, as an artist would blend it). Light
    /// is only added on top, so skin keeps its texture.
    private static func glow(_ image: CIImage, _ plan: AdjustRendering.Glow) -> CIImage {
        let extent = image.extent
        let encoded = image.applyingFilter("CILinearToSRGBToneCurve")
        let threshold = CGFloat(plan.threshold)
        let gain = 1 / (1 - threshold)
        let lights = encoded
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: gain, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: gain, w: 0),
                "inputBiasVector": CIVector(x: -threshold * gain, y: -threshold * gain, z: -threshold * gain, w: 0),
            ])
            .applyingFilter("CIColorClamp")
        let strength = CGFloat(plan.strength)
        let glow = lights
            .clampedToExtent()
            .applyingGaussianBlur(sigma: plan.radius)
            .cropped(to: extent)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: strength, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: strength, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: strength, w: 0),
            ])
        return glow
            .applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: encoded])
            .applyingFilter("CISRGBToneCurveToLinear")
            .cropped(to: extent)
    }

    /// Film grain: grey noise centred on 50% (neutral for soft light), so it
    /// adds texture without darkening. `scale` is the noise cell in pixels:
    /// grow it with the photo and previews and full-size renders look alike.
    static func filmGrain(over image: CIImage, amount: CGFloat, scale: CGFloat) -> CIImage {
        guard let noise = CIFilter.randomGenerator().outputImage else { return image }
        let spread = amount * 2
        let offset = 0.5 - spread / 2
        // The generator's alpha is random too; fix it at 1 first, or the colour
        // matrix (which un-premultiplies) would blow the values up.
        let gray = noise
            .settingAlphaOne(in: CGRect(x: -1e6, y: -1e6, width: 2e6, height: 2e6))
            .transformed(by: CGAffineTransform(scaleX: max(scale, 1), y: max(scale, 1)))
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: spread, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: spread, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: spread, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: offset, y: offset, z: offset, w: 1),
            ])
            .cropped(to: image.extent)
        return gray.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: image])
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
