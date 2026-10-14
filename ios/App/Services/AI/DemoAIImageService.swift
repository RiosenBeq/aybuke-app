import UIKit
import CoreImage
import AppCore

/// Offline stand-in for the backend so the whole app can be run, designed and
/// reviewed without API keys. Results are clearly labelled "Demo" and are
/// local Core Image approximations — not real AI output.
final class DemoAIImageService: AIImageService {
    func perform(_ job: AIJob) async throws -> AIJobResult {
        try await Task.sleep(for: .milliseconds(Self.simulatedDelayMilliseconds))
        try Task.checkCancellation()

        let images: [UIImage] = try await Task.detached(priority: .userInitiated) {
            try Self.render(job)
        }.value
        return AIJobResult(images: images, creditsRemaining: nil, requestID: "demo-\(UUID().uuidString)")
    }

    /// 1.6–2.8 s. DEBUG builds accept `-GLDemoDelaySeconds 15` to demo the
    /// Live Activity in the Dynamic Island.
    private static var simulatedDelayMilliseconds: Int {
        #if DEBUG
        let override = UserDefaults.standard.double(forKey: "GLDemoDelaySeconds")
        if override > 0 { return Int(override * 1000) }
        #endif
        return Int.random(in: 1600...2800)
    }

    private static func render(_ job: AIJob) throws -> [UIImage] {
        switch job.operation {
        case .textToImage:
            let size = job.aspectRatio.pixelSize(longEdge: 1024)
            let style = job.style ?? StyleCatalog.auto
            return (0..<max(1, job.numOutputs)).map { variant in
                DemoArt.render(prompt: job.prompt ?? "", style: style, size: size, variant: variant)
            }
        case .enhance:
            return [try transform(job.sourceImage) { ImageFilters.upscale(ImageFilters.autoEnhance($0), factor: 1.5) }]
        case .magicEdit:
            return [try transform(job.sourceImage) { ImageFilters.cinematicGrade($0) }]
        case .restyle:
            let seed = job.template.map { DemoArt.stableHash($0.id) } ?? 0
            return [try transform(job.sourceImage) { ImageFilters.stylize($0, seed: seed) }]
        case .eraseObject:
            guard let maskImage = job.mask, let mask = ImageFilters.ciImage(maskImage) else {
                throw AIServiceError.invalidRequest(String(localized: "Brush over the area you want to erase."))
            }
            return [try transform(job.sourceImage) { ImageFilters.blurInpaint($0, mask: mask) }]
        case .removeBackground:
            guard let source = job.sourceImage else { throw AIServiceError.invalidRequest(String(localized: "Pick a photo first.")) }
            return [try OnDeviceImageService.removeBackground(from: source)]
        }
    }

    private static func transform(_ image: UIImage?, _ body: (CIImage) -> CIImage) throws -> UIImage {
        guard let image, let input = ImageFilters.ciImage(image) else {
            throw AIServiceError.invalidRequest(String(localized: "Pick a photo first."))
        }
        let output = body(input)
        let extent = output.extent.isInfinite ? input.extent : output.extent.integral
        guard let rendered = ImageFilters.render(output, extent: extent) else {
            throw AIServiceError.invalidResponse
        }
        return DemoArt.stamp(rendered)
    }
}

/// Procedural "art" for demo text-to-image results.
enum DemoArt {
    /// `stamped: false` is for brand art (the invite card, screenshots), never for results.
    static func render(prompt: String, style: ImageStyle, size: PixelSize, variant: Int, stamped: Bool = true) -> UIImage {
        var generator = SplitMix64(seed: UInt64(truncatingIfNeeded: stableHash(prompt + style.id)) &+ UInt64(variant) &* 7919)
        let swatch = style.swatch.compactMap { UIColor(hexString: $0) }
        let accents: [UIColor] = [.brandBlush, .brandPetal, .white]
        let colors = swatch + accents
        let canvas = CGSize(width: size.width, height: size.height)

        let image = ImageUtilities.draw(size: canvas, opaque: true, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) { cg in
            let space = CGColorSpaceCreateDeviceRGB()
            let base = colors.first ?? .darkGray
            let baseEnd = colors.dropFirst().first ?? .black
            if let gradient = CGGradient(colorsSpace: space, colors: [base.cgColor, baseEnd.cgColor] as CFArray, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: canvas.width, y: canvas.height), options: [])
            }
            for _ in 0..<9 {
                let color = colors.randomElement(using: &generator) ?? base
                let center = CGPoint(
                    x: CGFloat.random(in: 0...canvas.width, using: &generator),
                    y: CGFloat.random(in: 0...canvas.height, using: &generator)
                )
                let radius = CGFloat.random(in: canvas.width * 0.18...canvas.width * 0.6, using: &generator)
                let stops = [color.withAlphaComponent(0.85).cgColor, color.withAlphaComponent(0).cgColor] as CFArray
                if let glow = CGGradient(colorsSpace: space, colors: stops, locations: [0, 1]) {
                    cg.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
                }
            }
        }
        return stamped ? stamp(image) : image
    }

    /// Adds a small "DEMO" label so simulated results are never mistaken for real output.
    static func stamp(_ image: UIImage) -> UIImage {
        ImageUtilities.draw(size: image.size, scale: image.scale, opaque: !ImageUtilities.hasAlpha(image),
                            colorSpace: image.cgImage?.colorSpace) { _ in
            image.draw(at: .zero)
            let fontSize = max(14, image.size.width * 0.028)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .heavy),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85),
            ]
            let label = "DEMO PREVIEW" as NSString
            let textSize = label.size(withAttributes: attributes)
            let padding = fontSize * 0.8
            let rect = CGRect(
                x: padding,
                y: image.size.height - textSize.height - padding * 1.5,
                width: textSize.width + padding,
                height: textSize.height + padding * 0.6
            )
            UIColor.black.withAlphaComponent(0.4).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2).fill()
            label.draw(at: CGPoint(x: rect.minX + padding / 2, y: rect.minY + padding * 0.3), withAttributes: attributes)
        }
    }

    /// djb2 — stable across launches, unlike `String.hashValue`.
    static func stableHash(_ string: String) -> Int {
        var hash: UInt64 = 5381
        for byte in string.utf8 {
            hash = (hash &<< 5) &+ hash &+ UInt64(byte)
        }
        return Int(truncatingIfNeeded: hash)
    }
}

/// Deterministic RNG so the same prompt renders the same demo art.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
