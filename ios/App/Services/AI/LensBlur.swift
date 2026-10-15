import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import AppCore

/// DSLR '12's fast lens on a photo: the subject stays crisp and the
/// background gets a real lens blur, with round bokeh where there were small
/// lights. Pure Core Image, safe off the main thread; the numbers are in
/// AppCore (`DSLRLens`).
enum LensBlur {
    /// `image` with its background blurred. `matte` (white = subject, any
    /// size: it's scaled to the photo) stays sharp; without one, the middle
    /// of the photo stays sharp and the blur grows toward the edges.
    static func render(_ image: CIImage, matte: CIImage?, lens: DSLRLens) -> CIImage {
        let extent = image.extent
        let long = max(extent.width, extent.height)
        guard long >= 8 else { return image }
        let unit = long / 1000
        let subject = matte.map { Matte.scaled($0, to: extent) }

        // The background without her: the hole she leaves filled from around
        // it, so the blur never smears her colours into a dark halo.
        var plate = image
        if let subject {
            let hole = Matte.blur(Matte.dilate(Matte.ramp(subject, 0.05, 0.5), 5 * unit), 2 * unit)
            plate = Matte.fill(image, known: Matte.invert(hole))
        }

        // The blur runs on a copy about 1024 px long: the same look for a
        // preview and a full-size photo, at the same cost.
        let scale = min(1, DSLRLens.workingLongEdge / long)
        let work = CGRect(x: 0, y: 0, width: max(1, (extent.width * scale).rounded()), height: max(1, (extent.height * scale).rounded()))
        let small = Matte.scaled(plate, to: work)
        let workLong = max(work.width, work.height)
        let radius = CGFloat(lens.blurRadius) * workLong

        let far = bokeh(small, radius: radius)
        let near = bokeh(small, radius: radius * CGFloat(DSLRLens.nearBlurShare))

        // How far from the plane of focus each spot is: right around her the
        // background is nearer and less blurred; with no subject, the middle.
        let depth: CIImage
        if let subject {
            let around = Matte.dilate(Matte.ramp(Matte.scaled(subject, to: work), 0.3, 0.6), 0.01 * workLong)
            depth = Matte.invert(Matte.ramp(Matte.blur(around, 0.08 * workLong), 0.05, 0.75))
        } else {
            let gradient = CIFilter.radialGradient()
            gradient.center = CGPoint(x: work.midX, y: work.midY)
            gradient.radius0 = Float(0.18 * workLong)
            gradient.radius1 = Float(0.62 * workLong)
            gradient.color0 = CIColor(red: 0, green: 0, blue: 0)
            gradient.color1 = CIColor(red: 1, green: 1, blue: 1)
            depth = gradient.outputImage?.cropped(to: work) ?? Matte.gray(1, work)
        }
        var background = far.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: near, kCIInputMaskImageKey: depth])
        if subject == nil {
            background = background.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: small, kCIInputMaskImageKey: Matte.ramp(depth, 0, 0.35),
            ])
        }

        // Bokeh balls: small bright lights (not bright areas like the sky)
        // blurred on their own and screened back, brighter where it's blurrier.
        let lightness = Matte.ramp(Matte.lightness(small), 0.72, 0.98)
        let spots = Matte.multiply(lightness, Matte.invert(Matte.blur(lightness, 0.03 * workLong)))
        let lights = Matte.multiply(small, Matte.multiply(spots, spots))
        let glow = Matte.multiply(gain(bokeh(lights, radius: radius), 5), depth)
        background = glow.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: background]).cropped(to: work)

        // Clamped first, so the scaled-up edges don't fade into transparency.
        let blurred = background.clampedToExtent()
            .transformed(by: CGAffineTransform(scaleX: extent.width / work.width, y: extent.height / work.height))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .cropped(to: extent)
        guard let subject else { return blurred }
        return Matte.foreground(of: image, matte: subject)
            .applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: blurred, kCIInputMaskImageKey: subject])
            .cropped(to: extent)
    }

    /// A disc-shaped lens blur with a faint bright rim, like a real aperture.
    private static func bokeh(_ image: CIImage, radius: CGFloat) -> CIImage {
        let blur = CIFilter.bokehBlur()
        blur.inputImage = image.clampedToExtent()
        blur.radius = Float(radius)
        blur.ringAmount = 0.1
        blur.ringSize = 0.12
        blur.softness = 1
        return blur.outputImage?.cropped(to: image.extent) ?? image
    }

    private static func gain(_ image: CIImage, _ amount: CGFloat) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: amount, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: amount, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: amount, w: 0),
        ]).applyingFilter("CIColorClamp")
    }
}
