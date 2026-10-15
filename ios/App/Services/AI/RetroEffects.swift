import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import AppCore

/// On-device "special effects" with an era: VHS tapes, disposable cameras,
/// Y2K digicams, instant film, 90s glamour shots, glitter, 2016 phone
/// photos, a 2006 camcorder, a 2009 toy camera, 2017's rainbow prism light,
/// 2012's DSLR portrait blur and film stills, plus a tilt-shift "tiny
/// world". Pure Core Image plus a little UIKit drawing (date stamps, frames,
/// sparkles, camera chrome) and, for DSLR '12, Vision's subject masks, so
/// they're free for everyone and never leave the device.
enum RetroEffect: String, CaseIterable, Identifiable {
    case vhs
    case disposable
    case kira
    case digicam
    case instant
    case glamour
    case neon
    case throwback16
    case camcorder06
    case toyCam
    case rainbow
    case dslr12
    case filmStill
    case tinyWorld

    var id: String { rawValue }

    /// Effect names are kept as they are in every language.
    var title: String {
        switch self {
        case .vhs: return "VHS '86"
        case .disposable: return "Disposable '98"
        case .kira: return "Kira Kira"
        case .digicam: return "Digicam '04"
        case .instant: return "Instant '82"
        case .glamour: return "Glamour '92"
        case .neon: return "Neon '84"
        case .throwback16: return "Throwback '16"
        case .camcorder06: return "Camcorder '06"
        case .toyCam: return "Toy Cam '09"
        case .rainbow: return "Rainbow '17"
        case .dslr12: return "DSLR '12"
        case .filmStill: return "Film Still"
        case .tinyWorld: return "Tiny World"
        }
    }

    var era: String {
        switch self {
        case .vhs, .instant, .neon: return "80s"
        case .disposable, .glamour: return "90s"
        case .digicam, .camcorder06, .toyCam: return "Y2K"
        case .throwback16, .rainbow, .dslr12: return "2010s"
        case .kira: return String(localized: "Sparkle")
        case .filmStill: return String(localized: "Film", comment: "Era tag of the Film Still effect: the look of a movie frame")
        case .tinyWorld: return String(localized: "Mini", comment: "Tag of the Tiny World effect: a tilt-shift photo that looks like a miniature model")
        }
    }

    /// The one switch an effect offers under the strip.
    enum Option {
        case dateStamp, border, letterbox, cameraInfo

        var label: LocalizedStringResource {
            switch self {
            case .dateStamp: return "Date stamp"
            case .border: return LocalizedStringResource("Border", comment: "Effect switch: a white square border around the photo")
            case .letterbox: return LocalizedStringResource("Letterbox", comment: "Effect switch: black cinema bars at the top and bottom")
            case .cameraInfo: return LocalizedStringResource("Camera info", comment: "Effect switch: the camcorder's REC, battery and time display")
            }
        }

        var symbolName: String {
            switch self {
            case .dateStamp: return "calendar"
            case .border: return "square.dashed"
            case .letterbox: return "rectangle.ratio.16.to.9"
            case .cameraInfo: return "record.circle"
            }
        }

        /// On when the effect is picked. The border changes the photo's shape,
        /// so she opts in.
        var isOnByDefault: Bool { self != .border }

        /// The border makes a bigger canvas, which a video frame can't do.
        var worksOnVideo: Bool { self != .border }
    }

    var option: Option? {
        switch self {
        case .vhs, .disposable, .digicam: return .dateStamp
        case .throwback16: return .border
        case .camcorder06: return .cameraInfo
        case .filmStill: return .letterbox
        default: return nil
        }
    }

    /// Effects that print a date on the photo, like the real thing did.
    var hasDateStamp: Bool { option == .dateStamp }

    /// Film Still can carry one line of subtitle (photos only).
    var takesSubtitle: Bool { self == .filmStill }

    /// DSLR '12 offers three lenses (85, 50 and 35 mm).
    var takesLens: Bool { self == .dslr12 }

    /// What she chose under the strip: the effect's switch, Film Still's
    /// subtitle (already through the content policy) and DSLR '12's lens.
    struct Options: Equatable, Sendable {
        var extra = true
        var subtitle = ""
        var lens = DSLRLens.standard

        static let plain = Options(extra: false)
    }

    /// Where DSLR '12 gets the photo's subjects: found here with Vision, or
    /// already known (the editor finds them once per step; nil: none).
    enum Subjects {
        case find
        case known(SubjectMasks?)
    }

    // MARK: Rendering

    /// Renders the effect at the image's own size (the instant frame and the
    /// 2016 border add a canvas around it). DSLR '12 uses `subjects` when the
    /// editor has them for this photo, and finds them itself otherwise (in
    /// Shortcuts, say); a photo without any gets a centre-weighted blur.
    func apply(to image: UIImage, options: Options = Options(), date: Date = Date(), subjects: Subjects = .find) -> UIImage {
        let source = ImageUtilities.normalized(image, maxLongEdge: 4096)
        guard var input = ImageFilters.ciImage(source) else { return image }
        // A cut-out has no background left to blur: it only gets the grade.
        if self == .dslr12, !ImageUtilities.hasTransparentPixels(source) {
            let masks: SubjectMasks?
            switch subjects {
            case .find: masks = try? SubjectMasks.analyze(source)
            case .known(let known): masks = known
            }
            let matte = masks.flatMap { $0.allIDs.isEmpty ? nil : $0.matte(for: $0.allIDs) }
            input = LensBlur.render(input, matte: matte, lens: options.lens)
        }
        var graded = grade(input)
        // A photo comes out opaque (a JPEG when saved); a cut-out keeps its
        // transparency.
        if !ImageUtilities.hasAlpha(source) { graded = graded.settingAlphaOne(in: input.extent) }
        guard var output = ImageFilters.render(graded, extent: input.extent) else { return image }
        switch self {
        case .kira:
            output = RetroEffect.sparkles(on: output)
        case .instant:
            output = RetroEffect.instantFrame(around: output)
        default:
            break
        }
        if let layer = photoOverlay(size: output.size, options: options, date: date) {
            output = RetroEffect.draw(layer, over: output)
        }
        if options.extra, option == .border {
            output = RetroEffect.squareBorder(around: output)
        }
        return output
    }

    /// `effects`, each with its switch at its default, on a small copy of
    /// `image` for the Effects strip. At this size each one is mostly fixed
    /// overhead, so they render side by side. Call it off the main actor.
    static func thumbnails(of image: UIImage, maxLongEdge: Int = 240, effects: [RetroEffect] = allCases,
                           subjects: Subjects = .find) -> [RetroEffect: UIImage] {
        let source = ImageUtilities.normalized(image, maxLongEdge: maxLongEdge)
        var rendered = [UIImage?](repeating: nil, count: effects.count)
        rendered.withUnsafeMutableBufferPointer { slots in
            DispatchQueue.concurrentPerform(iterations: effects.count) { index in
                let effect = effects[index]
                slots[index] = effect.apply(to: source, options: Options(extra: effect.option?.isOnByDefault ?? true), subjects: subjects)
            }
        }
        return Dictionary(uniqueKeysWithValues: zip(effects, rendered).compactMap { effect, image in image.map { (effect, $0) } })
    }

    /// Effects that also work on video frames (no frames or per-frame sparkles;
    /// DSLR '12 needs Vision's subject masks, too slow for every frame).
    static let videoEffects: [RetroEffect] = [.vhs, .disposable, .digicam, .glamour, .neon, .throwback16, .camcorder06, .toyCam, .rainbow,
                                              .filmStill, .tinyWorld]

    /// The colour, grain and light of the effect, for photos and video frames.
    func grade(_ input: CIImage) -> CIImage {
        let extent = input.extent
        let unit = max(extent.width, extent.height) / 1000
        switch self {
        case .vhs:
            var image = input
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.25, kCIInputContrastKey: 1.08])
                .clampedToExtent().applyingGaussianBlur(sigma: 0.9 * unit).cropped(to: extent)
            image = RetroEffect.chromaticShift(image, offset: 3.5 * unit)
            image = RetroEffect.scanlines(over: image, spacing: max(2, 3 * unit), strength: 0.18)
            image = RetroEffect.grain(over: image, amount: 0.12, scale: unit)
            return RetroEffect.tint(image, red: 1.02, green: 0.99, blue: 1.02)
        case .disposable:
            var image = input
                .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.28])
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 8200, y: 12),
                ])
                .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.06, kCIInputSaturationKey: 1.12])
            image = RetroEffect.liftBlacks(image, amount: 0.06)
            image = RetroEffect.lightLeak(over: image, color: CIColor(red: 1, green: 0.45, blue: 0.2), at: CGPoint(x: extent.maxX, y: extent.maxY), radius: extent.width * 0.7)
            image = RetroEffect.grain(over: image, amount: 0.16, scale: unit * 1.4)
            return image.applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: 0.9, kCIInputRadiusKey: 1.4])
        case .kira:
            let bloom = input.applyingFilter("CIBloom", parameters: [kCIInputRadiusKey: 8 * unit, kCIInputIntensityKey: 0.45])
            return bloom.cropped(to: extent).applyingFilter("CIVibrance", parameters: ["inputAmount": 0.35])
        case .digicam:
            var image = input
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 5200, y: -8),
                ])
                .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.18, kCIInputSaturationKey: 1.1, kCIInputBrightnessKey: 0.02])
            // On-camera flash: a hot centre that falls off fast.
            image = RetroEffect.lightLeak(over: image, color: CIColor(red: 1, green: 1, blue: 1), at: CGPoint(x: extent.midX, y: extent.midY), radius: extent.width * 0.55, alpha: 0.28)
            image = image.clampedToExtent().applyingGaussianBlur(sigma: 0.6 * unit).cropped(to: extent)
            return RetroEffect.grain(over: image, amount: 0.06, scale: unit)
                .applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: 0.6, kCIInputRadiusKey: 1.8])
        case .instant:
            var image = input
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 7600, y: 18),
                ])
                .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 0.88, kCIInputSaturationKey: 0.82])
            image = RetroEffect.liftBlacks(image, amount: 0.12)
            image = RetroEffect.tint(image, red: 1.02, green: 0.99, blue: 0.93)
            return RetroEffect.grain(over: image, amount: 0.08, scale: unit)
        case .glamour:
            // Soft-focus 90s studio portrait: a dreamy glow and a blush cast.
            let soft = input.clampedToExtent().applyingGaussianBlur(sigma: 14 * unit).cropped(to: extent)
            var image = soft.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: input])
            image = image.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.06, kCIInputContrastKey: 1.04, kCIInputSaturationKey: 1.05])
            image = RetroEffect.tint(image, red: 1.04, green: 0.97, blue: 1.0)
            image = RetroEffect.liftBlacks(image, amount: 0.05)
            return image.applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: 0.5, kCIInputRadiusKey: 2])
        case .neon:
            let duotone = input.applyingFilter("CIFalseColor", parameters: [
                "inputColor0": CIColor(red: 0.12, green: 0.05, blue: 0.35),
                "inputColor1": CIColor(red: 1, green: 0.42, blue: 0.78),
            ])
            let mixed = duotone.applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: input, kCIInputTimeKey: 0.42,
            ])
            return mixed
                .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.15, kCIInputSaturationKey: 1.3])
                .applyingFilter("CIBloom", parameters: [kCIInputRadiusKey: 10 * unit, kCIInputIntensityKey: 0.5])
                .cropped(to: extent)
        case .throwback16:
            // Early-phone-camera 2016: bright, punchy and very saturated, with
            // only a hint of the matte fade.
            var image = input
                .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.18])
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.28, kCIInputContrastKey: 1.06])
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 7000, y: 4),
                ])
            image = RetroEffect.liftBlacks(image, amount: 0.03)
            return image.applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: 0.35, kCIInputRadiusKey: 2])
        case .camcorder06:
            // A MiniDV tape: cool and a little green, soft but over-sharpened,
            // clipped highlights and faint interlacing. Kept far lighter than
            // VHS '86 on purpose.
            var image = input
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 5400, y: -18),
                ])
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.92, kCIInputContrastKey: 1.1])
                .applyingFilter("CIToneCurve", parameters: [
                    "inputPoint0": CIVector(x: 0, y: 0.02),
                    "inputPoint1": CIVector(x: 0.25, y: 0.24),
                    "inputPoint2": CIVector(x: 0.5, y: 0.54),
                    "inputPoint3": CIVector(x: 0.75, y: 0.88),
                    "inputPoint4": CIVector(x: 0.9, y: 1),
                ])
            image = image.clampedToExtent().applyingGaussianBlur(sigma: 0.6 * unit).cropped(to: extent)
            image = image.applyingFilter("CIUnsharpMask", parameters: [kCIInputRadiusKey: 2.5 * unit, kCIInputIntensityKey: 0.6]).cropped(to: extent)
            image = RetroEffect.chromaticShift(image, offset: 0.8 * unit)
            image = RetroEffect.scanlines(over: image, spacing: max(2, 2 * unit), strength: 0.06)
            return RetroEffect.grain(over: image, amount: 0.05, scale: unit)
        case .toyCam:
            // A plastic toy camera with cross-processed film, the look 2009's
            // camera apps copied: punchy colour, teal shadows, warm yellow
            // highlights and dark corners. Colour and light only. The shift
            // is made on gamma-encoded values (the working space is linear),
            // so it tints the shadows without turning dark skin purple.
            var image = input
                .applyingFilter("CILinearToSRGBToneCurve")
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 1.05, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 1.02, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 0.84, w: 0),
                    "inputBiasVector": CIVector(x: -0.02, y: 0.025, z: 0.07, w: 0),
                ])
                .applyingFilter("CISRGBToneCurveToLinear")
                .applyingFilter("CIToneCurve", parameters: [
                    "inputPoint0": CIVector(x: 0, y: 0.02),
                    "inputPoint1": CIVector(x: 0.25, y: 0.21),
                    "inputPoint2": CIVector(x: 0.5, y: 0.53),
                    "inputPoint3": CIVector(x: 0.75, y: 0.83),
                    "inputPoint4": CIVector(x: 1, y: 1),
                ])
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.22])
            image = RetroEffect.grain(over: image, amount: 0.08, scale: unit * 1.2)
            return image.applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: 1, kCIInputRadiusKey: 1.25])
        case .rainbow:
            // A prism held at the lens, the 2017 trend: a band of rainbow
            // light across one corner and a slightly brighter photo. Light
            // only, so faces keep their shape and their own colours.
            let lifted = input.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: 0.02, kCIInputContrastKey: 1.03, kCIInputSaturationKey: 1.08,
            ])
            return RetroEffect.prismLight(over: lifted)
        case .filmStill:
            // A warm movie frame. Halation blooms only from the brightest
            // lights (a high threshold), so skin is never softened.
            var image = input
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 7400, y: 6),
                ])
                .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.05, kCIInputSaturationKey: 0.95])
            image = RetroEffect.liftBlacks(image, amount: 0.05)
            image = RetroEffect.halation(over: image, unit: unit)
            return RetroEffect.grain(over: image, amount: 0.07, scale: unit)
        case .tinyWorld:
            // A toy-like scene: a little more colour and snap, then the
            // tilt-shift blur.
            let lifted = input.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.22, kCIInputContrastKey: 1.07])
            return RetroEffect.tiltShift(lifted, unit: unit)
        case .dslr12:
            // A clean full-frame look over the lens blur (`apply`): a gentle
            // S-curve, warm highlights, slightly cool shadows, fine grain and
            // a mild vignette. Colour and light only; skin keeps its texture.
            let cube = CIFilter.colorCubeWithColorSpace()
            cube.inputImage = input
            cube.cubeDimension = Float(RetroEffect.dslrCubeDimension)
            cube.cubeData = RetroEffect.dslrCube
            cube.colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
            let graded = RetroEffect.grain(over: (cube.outputImage ?? input).cropped(to: extent), amount: CGFloat(DSLRGrade.grainAmount), scale: unit * 0.8)
            return graded.applyingFilter("CIVignette", parameters: [
                kCIInputIntensityKey: DSLRGrade.vignetteIntensity, kCIInputRadiusKey: DSLRGrade.vignetteRadius,
            ])
        }
    }

    private static let dslrCubeDimension = 32
    /// Made once: every preview and render of DSLR '12 uses the same cube.
    private static let dslrCube: Data = DSLRGrade.cube(dimension: dslrCubeDimension).withUnsafeBufferPointer { Data(buffer: $0) }

    // MARK: Overlays

    /// Everything drawn on top of a photo for the chosen options.
    private func photoOverlay(size: CGSize, options: Options, date: Date) -> UIImage? {
        let subtitle = takesSubtitle ? FilmSubtitle.clean(options.subtitle) : ""
        switch option {
        case .dateStamp? where options.extra:
            return RetroEffect.stampLayer(stampText(for: date), style: self, size: size)
        case .cameraInfo? where options.extra:
            return CamcorderChrome.layer(size: size, date: date, showsDot: true)
        case .letterbox?:
            guard options.extra || !subtitle.isEmpty else { return nil }
            return RetroEffect.filmLayer(size: size, letterbox: options.extra, subtitle: subtitle)
        default:
            return nil
        }
    }

    /// The static part of the overlay on a video frame (a date stamp, the
    /// camcorder chrome without its blinking dot, or letterbox bars).
    func videoOverlay(size: CGSize, date: Date = Date()) -> CIImage? {
        let layer: UIImage?
        switch option {
        case .dateStamp?: layer = RetroEffect.stampLayer(stampText(for: date), style: self, size: size)
        case .cameraInfo?: layer = CamcorderChrome.layer(size: size, date: date, showsDot: false)
        case .letterbox?: layer = RetroEffect.filmLayer(size: size, letterbox: true, subtitle: "")
        case .border?, nil: layer = nil
        }
        return layer.flatMap { CIImage(image: $0) }
    }

    private static func draw(_ layer: UIImage, over image: UIImage) -> UIImage {
        composite(image) { _ in layer.draw(at: .zero) }
    }

    /// `image` with more drawn on top, in its own colour space; opaque
    /// when `image` is.
    private static func composite(_ image: UIImage, opaque: Bool? = nil, size: CGSize? = nil, at origin: CGPoint = .zero,
                                  background: UIColor? = nil, _ drawOnTop: (CGContext) -> Void) -> UIImage {
        let canvas = size ?? image.size
        return ImageUtilities.draw(size: canvas, opaque: opaque ?? !ImageUtilities.hasAlpha(image), colorSpace: image.cgImage?.colorSpace) { context in
            if let background {
                // Every pixel, including the last part-pixel row and column
                // of a fractional canvas (they'd turn grey in a JPEG).
                background.setFill()
                context.fill(CGRect(x: 0, y: 0, width: canvas.width.rounded(.up), height: canvas.height.rounded(.up)))
            }
            image.draw(in: CGRect(origin: origin, size: image.size))
            drawOnTop(context)
        }
    }

    /// Black cinema bars and a one-line subtitle in the system font (it has
    /// glyphs for every app language, the brand fonts don't).
    private static func filmLayer(size: CGSize, letterbox: Bool, subtitle: String) -> UIImage {
        let unit = max(size.width, size.height) / 1000
        let bar = letterbox ? Letterbox.barHeight(width: size.width, height: size.height) : 0
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            if bar > 0 {
                UIColor.black.setFill()
                context.fill(CGRect(x: 0, y: 0, width: size.width, height: bar))
                context.fill(CGRect(x: 0, y: size.height - bar, width: size.width, height: bar))
            }
            guard !subtitle.isEmpty else { return }
            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.85)
            shadow.shadowBlurRadius = 6 * unit
            shadow.shadowOffset = CGSize(width: 0, height: 1.5 * unit)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byTruncatingTail
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 36 * unit, weight: .medium),
                .foregroundColor: UIColor(white: 1, alpha: 0.96),
                .shadow: shadow,
                .paragraphStyle: paragraph,
            ]
            let text = subtitle as NSString
            let margin = 40 * unit
            let height = ceil(text.boundingRect(with: CGSize(width: size.width - margin * 2, height: .greatestFiniteMagnitude),
                                                options: [.usesLineFragmentOrigin], attributes: attributes, context: nil).height)
            let lineHeight = min(height, 60 * unit)
            let bottom = size.height - max(bar, margin) - 18 * unit
            text.draw(with: CGRect(x: margin, y: bottom - lineHeight, width: size.width - margin * 2, height: lineHeight),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes, context: nil)
        }
    }

    /// 2016's "no crop" posts: the whole photo centred on a white square.
    private static func squareBorder(around image: UIImage) -> UIImage {
        let size = image.size
        let side = max(size.width, size.height) * 1.08
        return composite(image, opaque: true, size: CGSize(width: side, height: side),
                         at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2), background: .white) { _ in }
    }

    // MARK: Building blocks

    private static func tint(_ image: CIImage, red: CGFloat, green: CGFloat, blue: CGFloat) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: red, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: green, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: blue, w: 0),
        ])
    }

    /// Faded shadows, as on old prints.
    private static func liftBlacks(_ image: CIImage, amount: CGFloat) -> CIImage {
        image.applyingFilter("CIToneCurve", parameters: [
            "inputPoint0": CIVector(x: 0, y: amount),
            "inputPoint1": CIVector(x: 0.25, y: 0.25 + amount * 0.5),
            "inputPoint2": CIVector(x: 0.5, y: 0.5),
            "inputPoint3": CIVector(x: 0.75, y: 0.76),
            "inputPoint4": CIVector(x: 1, y: 0.98),
        ])
    }

    /// Red and blue channels drift apart, like a worn tape.
    private static func chromaticShift(_ image: CIImage, offset: CGFloat) -> CIImage {
        func channel(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CIImage {
            image.clampedToExtent().applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: r, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0),
            ])
        }
        let red = channel(1, 0, 0).transformed(by: CGAffineTransform(translationX: offset, y: 0))
        let green = channel(0, 1, 0)
        let blue = channel(0, 0, 1).transformed(by: CGAffineTransform(translationX: -offset, y: 0))
        // Adding three opaque layers sums their alpha too; reset it to 1.
        return red
            .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: green])
            .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: blue])
            .settingAlphaOne(in: image.extent)
            .cropped(to: image.extent)
    }

    private static func scanlines(over image: CIImage, spacing: CGFloat, strength: CGFloat) -> CIImage {
        let stripes = CIFilter.stripesGenerator()
        stripes.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: strength)
        stripes.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        stripes.width = Float(spacing)
        stripes.sharpness = 0.6
        guard let lines = stripes.outputImage?
            .transformed(by: CGAffineTransform(rotationAngle: .pi / 2))
            .cropped(to: image.extent) else { return image }
        return lines.composited(over: image)
    }

    /// Film grain, scaled with the photo, so previews and full-size renders look alike.
    private static func grain(over image: CIImage, amount: CGFloat, scale: CGFloat) -> CIImage {
        ImageFilters.filmGrain(over: image, amount: amount, scale: scale)
    }

    private static func lightLeak(over image: CIImage, color: CIColor, at point: CGPoint, radius: CGFloat, alpha: CGFloat = 0.55) -> CIImage {
        let gradient = CIFilter.radialGradient()
        gradient.center = point
        gradient.radius0 = 0
        gradient.radius1 = Float(radius)
        gradient.color0 = CIColor(red: color.red, green: color.green, blue: color.blue, alpha: alpha)
        gradient.color1 = CIColor(red: color.red, green: color.green, blue: color.blue, alpha: 0)
        guard let leak = gradient.outputImage?.cropped(to: image.extent) else { return image }
        return leak.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: image])
    }

    /// Tilt-shift: a sharp band a little below the middle and blur that grows
    /// toward the top and bottom, so the scene looks like a model. The mask
    /// is two gradients (white = blurred), so it costs no pixels to build.
    private static func tiltShift(_ image: CIImage, unit: CGFloat) -> CIImage {
        let extent = image.extent
        // Core Image's y runs up: 46% from the bottom is 54% from the top.
        let focus = extent.minY + extent.height * 0.46
        let halfBand = extent.height * 0.09
        let fade = extent.height * 0.3
        func ramp(from start: CGFloat, to end: CGFloat) -> CIImage? {
            let gradient = CIFilter.linearGradient()
            gradient.point0 = CGPoint(x: extent.midX, y: start)
            gradient.point1 = CGPoint(x: extent.midX, y: end)
            gradient.color0 = CIColor(red: 0, green: 0, blue: 0)
            gradient.color1 = CIColor(red: 1, green: 1, blue: 1)
            return gradient.outputImage
        }
        guard let above = ramp(from: focus + halfBand, to: focus + halfBand + fade),
              let below = ramp(from: focus - halfBand, to: focus - halfBand - fade) else { return image }
        let blur = CIFilter.maskedVariableBlur()
        blur.inputImage = image.clampedToExtent()
        blur.mask = above.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: below]).cropped(to: extent)
        blur.radius = Float(16 * unit)
        return blur.outputImage?.cropped(to: extent) ?? image
    }

    /// Red-orange glow around the brightest lights, like light scattering
    /// back through film.
    private static func halation(over image: CIImage, unit: CGFloat) -> CIImage {
        let extent = image.extent
        let glow = image
            // Threshold the brightness, not each channel, so warm skin tones
            // don't count as "lights".
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            .applyingFilter("CIColorThreshold", parameters: ["inputThreshold": 0.86])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.55, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0.2, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0.06, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 12 * unit)
            .cropped(to: extent)
        return glow.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: image]).cropped(to: extent)
    }

    /// One row of rainbow light, see-through at both ends: made once, then
    /// stretched over every photo, preview and video frame.
    private static let spectrum: CIImage? = {
        let width = 256
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let colors = [
            CGColor(srgbRed: 1, green: 0.3, blue: 0.45, alpha: 0),
            CGColor(srgbRed: 1, green: 0.3, blue: 0.45, alpha: 0.55),
            CGColor(srgbRed: 1, green: 0.62, blue: 0.25, alpha: 0.62),
            CGColor(srgbRed: 1, green: 0.92, blue: 0.35, alpha: 0.66),
            CGColor(srgbRed: 0.4, green: 0.92, blue: 0.55, alpha: 0.62),
            CGColor(srgbRed: 0.35, green: 0.7, blue: 1, alpha: 0.56),
            CGColor(srgbRed: 0.68, green: 0.45, blue: 1, alpha: 0.45),
            CGColor(srgbRed: 0.68, green: 0.45, blue: 1, alpha: 0),
        ]
        guard let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray,
                                        locations: [0, 0.14, 0.28, 0.42, 0.56, 0.7, 0.84, 1]) else { return nil }
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: 0), options: [])
        return context.makeImage().map { CIImage(cgImage: $0) }
    }()

    /// Rainbow light from a prism held at the lens: a band across the top
    /// left corner with a soft white glow, fading toward the middle and
    /// screened over the photo. The band is `spectrum` stretched and turned,
    /// so it costs no pixels to build.
    private static func prismLight(over image: CIImage) -> CIImage {
        guard let spectrum else { return image }
        let extent = image.extent
        let long = max(extent.width, extent.height)
        // Core Image's y runs up: this is near the top left corner.
        let corner = CGPoint(x: extent.minX + extent.width * 0.16, y: extent.maxY - extent.height * 0.1)
        let bandWidth = long * 0.34
        let band = spectrum
            .clampedToExtent()
            .transformed(by: CGAffineTransform(scaleX: bandWidth / spectrum.extent.width, y: 1))
            .transformed(by: CGAffineTransform(translationX: -bandWidth / 2, y: 0))
            .transformed(by: CGAffineTransform(rotationAngle: -0.49))
            .transformed(by: CGAffineTransform(translationX: corner.x, y: corner.y))
        let fade = CIFilter.radialGradient()
        fade.center = corner
        fade.radius0 = Float(long * 0.05)
        fade.radius1 = Float(long * 0.8)
        fade.color0 = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        fade.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: 0)
        let glow = CIFilter.radialGradient()
        glow.center = corner
        glow.radius0 = 0
        glow.radius1 = Float(long * 0.4)
        glow.color0 = CIColor(red: 1, green: 0.97, blue: 0.9, alpha: 0.25)
        glow.color1 = CIColor(red: 1, green: 0.97, blue: 0.9, alpha: 0)
        guard let mask = fade.outputImage, let haze = glow.outputImage else { return image }
        let light = band
            .applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: mask])
            .applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: haze])
            // Only over the picture: a cut-out keeps its see-through parts.
            .applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: image])
            .cropped(to: extent)
        return light.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: image]).cropped(to: extent)
    }

    // MARK: UIKit overlays

    private func stampText(for date: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let parts = calendar.dateComponents([.month, .day], from: date)
        let month = parts.month ?? 1
        let day = parts.day ?? 1
        switch self {
        case .vhs:
            let names = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
            return "PLAY ▶\n\(names[month - 1]) \(String(format: "%02d", day)) 1986"
        case .disposable:
            return String(format: "'98 %02d %02d", month, day)
        default:
            return String(format: "2004/%02d/%02d", month, day)
        }
    }

    private static func stampLayer(_ text: String, style: RetroEffect, size: CGSize) -> UIImage {
        let unit = max(size.width, size.height) / 1000
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let isVHS = style == .vhs
            let font = UIFont.monospacedSystemFont(ofSize: (isVHS ? 30 : 34) * unit, weight: isVHS ? .bold : .semibold)
            let color = isVHS ? UIColor.white : UIColor(red: 1, green: 0.55, blue: 0.18, alpha: 0.95)
            let shadow = NSShadow()
            shadow.shadowColor = isVHS ? UIColor(red: 0.3, green: 0.5, blue: 1, alpha: 0.9) : UIColor(red: 1, green: 0.3, blue: 0, alpha: 0.6)
            shadow.shadowBlurRadius = 6 * unit
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .shadow: shadow]
            let margin = 36 * unit
            if isVHS {
                let lines = text.components(separatedBy: "\n")
                (lines[0] as NSString).draw(at: CGPoint(x: margin, y: margin), withAttributes: attributes)
                let bottom = lines[1] as NSString
                let bottomSize = bottom.size(withAttributes: attributes)
                bottom.draw(at: CGPoint(x: margin, y: size.height - margin - bottomSize.height), withAttributes: attributes)
            } else {
                let label = text as NSString
                let textSize = label.size(withAttributes: attributes)
                label.draw(at: CGPoint(x: size.width - margin - textSize.width, y: size.height - margin - textSize.height), withAttributes: attributes)
            }
            _ = context
        }
    }

    /// White instant-film border with a deeper chin.
    private static func instantFrame(around image: UIImage) -> UIImage {
        let size = image.size
        let side = max(size.width, size.height) * 0.05
        let chin = max(size.width, size.height) * 0.17
        let canvas = CGSize(width: size.width + side * 2, height: size.height + side + chin)
        return composite(image, opaque: true, size: canvas, at: CGPoint(x: side, y: side),
                         background: UIColor(red: 0.985, green: 0.98, blue: 0.965, alpha: 1)) { _ in }
    }

    /// Glitter: four-point stars on the brightest spots, like Kira Kira
    /// cameras. Positions come from the photo itself, so previews match.
    private static func sparkles(on image: UIImage) -> UIImage {
        let points = highlights(in: image, count: 14)
        let size = image.size
        let unit = max(size.width, size.height) / 1000
        return composite(image) { cg in
            for (index, point) in points.enumerated() {
                let radius = (index % 3 == 0 ? 34 : index % 3 == 1 ? 22 : 14) * unit * (0.6 + point.strength * 0.6)
                let center = CGPoint(x: point.location.x * size.width, y: point.location.y * size.height)
                cg.setShadow(offset: .zero, blur: radius * 0.9, color: UIColor.white.withAlphaComponent(0.95).cgColor)
                UIColor.white.setFill()
                sparklePath(center: center, radius: radius).fill()
                if index % 2 == 0 {
                    // A smaller star turned 45° makes the eight-point twinkle.
                    let small = sparklePath(center: center, radius: radius * 0.5)
                    small.apply(CGAffineTransform(translationX: -center.x, y: -center.y)
                        .concatenating(CGAffineTransform(rotationAngle: .pi / 4))
                        .concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
                    small.fill()
                }
            }
        }
    }

    private static func sparklePath(center: CGPoint, radius: CGFloat) -> UIBezierPath {
        let inner = radius * 0.22
        let path = UIBezierPath()
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.addQuadCurve(to: CGPoint(x: center.x + radius, y: center.y), controlPoint: CGPoint(x: center.x + inner, y: center.y - inner))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + radius), controlPoint: CGPoint(x: center.x + inner, y: center.y + inner))
        path.addQuadCurve(to: CGPoint(x: center.x - radius, y: center.y), controlPoint: CGPoint(x: center.x - inner, y: center.y + inner))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y - radius), controlPoint: CGPoint(x: center.x - inner, y: center.y - inner))
        path.close()
        return path
    }

    /// The brightest, well-spaced spots (normalised 0…1, top-left origin).
    private static func highlights(in image: UIImage, count: Int) -> [(location: CGPoint, strength: CGFloat)] {
        let grid = 48
        let thumb = ImageUtilities.normalized(image, maxLongEdge: grid)
        guard let cgImage = thumb.cgImage else { return [] }
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var candidates: [(x: Int, y: Int, luma: CGFloat)] = []
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let luma = (0.299 * CGFloat(pixels[i]) + 0.587 * CGFloat(pixels[i + 1]) + 0.114 * CGFloat(pixels[i + 2])) / 255
                if luma > 0.62 { candidates.append((x, y, luma)) }
            }
        }
        candidates.sort { $0.luma > $1.luma }
        var picked: [(location: CGPoint, strength: CGFloat)] = []
        let minDistance = CGFloat(max(width, height)) * 0.12
        for candidate in candidates where picked.count < count {
            let point = CGPoint(x: (CGFloat(candidate.x) + 0.5) / CGFloat(width), y: (CGFloat(candidate.y) + 0.5) / CGFloat(height))
            let tooClose = picked.contains { hypot(($0.location.x - point.x) * CGFloat(width), ($0.location.y - point.y) * CGFloat(height)) < minDistance }
            if !tooClose { picked.append((point, (candidate.luma - 0.62) / 0.38)) }
        }
        return picked
    }
}
