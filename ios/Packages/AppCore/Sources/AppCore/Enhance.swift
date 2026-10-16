import Foundation

// The editor's Enhance tool: a free Quick fix on the device (noise reduction,
// sharpening, local contrast, a gentle exposure and white balance, and an
// optional upscale), and four AI fixes in the cloud. Every AI fix keeps the
// same skin and identity guard as the original "AI Enhance": nothing here
// smooths skin, reshapes anyone or changes who they are.
//
// The server owns the AI prompts (catalog.json's "enhanceModes", exported
// from `EnhanceMode.prompt` by scripts/export-catalog.sh): the app only names
// a mode, so a modified client can't send its own words with an Enhance.

/// What the server's Enhance does. The raw value is the wire format
/// (`enhance_mode` in the ai-image request).
public enum EnhanceMode: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Today's "AI Enhance": sharper, less blur and noise, faces restored.
    case unblur
    /// An old print: scratches, dust, creases and fading; black and white stays so.
    case restore
    /// The same restoration with natural colours for a black-and-white print.
    case restoreColor = "restore_color"
    /// A photo taken in low light, brightened naturally (no added glow).
    case lowLight = "low_light"
    /// Finer, natural detail; the app returns it at up to twice the size.
    case hd

    public var id: String { rawValue }

    /// Kept word for word in every mode: real skin, nobody reshaped.
    public static let skinGuard = "Keep real skin texture, freckles, moles, pores and blemishes; don't retouch or smooth the skin, and don't reshape the face or body."
    /// Composition, colours and every person stay as they are.
    public static let identityGuard = "Keep the composition, colors, every person and their identity exactly the same."
    /// Colourising changes the colours, so it keeps everything but them.
    static let identityGuardWithoutColors = "Keep the composition, every person and their identity exactly the same."

    /// The instruction the image model gets. Never asks for smoothing.
    public var prompt: String {
        switch self {
        case .unblur:
            return "Enhance this photo: make it sharper and more detailed, reduce blur and noise, restore faces naturally and gently improve the lighting. "
                + Self.skinGuard + " " + Self.identityGuard
        case .restore:
            return "Restore this old photo: remove scratches, dust, spots, creases and tears, bring back faded contrast and detail, and restore faces naturally. If it is black and white, keep it black and white. "
                + Self.skinGuard + " " + Self.identityGuard
        case .restoreColor:
            return "Restore this old photo and add natural, true-to-life color to it: remove scratches, dust, spots, creases and tears, bring back faded detail and restore faces naturally. Keep every skin tone natural and true to the person. "
                + Self.skinGuard + " " + Self.identityGuardWithoutColors
        case .lowLight:
            return "Brighten this photo taken in low light: lift the exposure and shadows naturally, reduce the noise and recover detail, with realistic light and no added glow, haze or bloom. "
                + Self.skinGuard + " " + Self.identityGuard
        case .hd:
            return "Make this photo crisp and high-definition: recover fine, natural detail and clean edges, and remove compression artifacts and noise, so it still looks like a real photo. "
                + Self.skinGuard + " " + Self.identityGuard
        }
    }
}

/// The Enhance panel's choices, in its order.
public enum EnhanceOption: String, CaseIterable, Sendable, Identifiable {
    /// Free, on the device, no consent or credits; works offline and under 13.
    case quickFix
    case unblur
    case restore
    case lowLight
    case hd

    public var id: String { rawValue }

    /// An AI fix: cloud, consent and credits.
    public var isCloud: Bool { self != .quickFix }

    /// What the server is asked for; "Add color" only changes Restore.
    public func mode(addingColor: Bool = false) -> EnhanceMode? {
        switch self {
        case .quickFix: return nil
        case .unblur: return .unblur
        case .restore: return addingColor ? .restoreColor : .restore
        case .lowLight: return .lowLight
        case .hd: return .hd
        }
    }

    /// The options she can use: Quick fix only without cloud AI (under 13).
    public static func available(cloudAI: Bool) -> [EnhanceOption] {
        cloudAI ? allCases : [.quickFix]
    }
}

// MARK: - Sizes

public enum EnhanceSizing {
    /// The editor works at this size, so nothing grows past it.
    public static let maxLongEdge = 2048.0

    /// Quick fix's "Upscale": twice the size, up to the editor's limit.
    public static func upscaleFactor(longEdge: Double) -> Double {
        guard longEdge > 0 else { return 1 }
        return min(2, max(1, maxLongEdge / longEdge))
    }

    /// Worth offering: the photo grows by at least a quarter.
    public static func canUpscale(longEdge: Double) -> Bool {
        upscaleFactor(longEdge: longEdge) >= 1.25
    }

    /// The long edge an AI fix comes back at: never smaller than her photo
    /// (the model answers at about 1k), and for HD twice her photo, both up
    /// to the editor's limit. The result's own shape is kept.
    public static func resultLongEdge(source: Double, result: Double, mode: EnhanceMode) -> Double {
        let wanted = mode == .hd ? 2 * source : source
        return max(result, min(wanted, maxLongEdge)).rounded()
    }
}

// MARK: - Measuring a photo

/// Cheap measures of one photo, read from a small copy (at most 1024 px) on
/// the device, for Enhance's suggestion and Quick fix's noise reduction.
public struct PhotoQuality: Equatable, Sendable {
    /// Detail in the sharpest parts: the Laplacian variance of the second
    /// sharpest of 4×4 tiles (0–255 grey), less what noise adds to it.
    public var sharpness: Double
    /// Noise in the flattest parts: Immerkær's estimate of σ (0–255 grey),
    /// the median of the flatter half of the tiles.
    public var noise: Double
    /// Mean luma, 0…1.
    public var meanLuma: Double
    /// 2nd and 98th percentile luma, 0…1.
    public var lowLuma: Double
    public var highLuma: Double
    /// Mean chroma (max − min of r, g, b), 0…1.
    public var chroma: Double
    /// Share of pixels whose colour runs red ≥ green ≥ blue (sepia, warm prints).
    public var warmShare: Double
    /// Long edge of the copy it was measured on.
    public var longEdge: Int

    public init(sharpness: Double = 500, noise: Double = 1, meanLuma: Double = 0.45, lowLuma: Double = 0.03, highLuma: Double = 0.9,
                chroma: Double = 0.15, warmShare: Double = 0.5, longEdge: Int = 1024) {
        self.sharpness = sharpness
        self.noise = noise
        self.meanLuma = meanLuma
        self.lowLuma = lowLuma
        self.highLuma = highLuma
        self.chroma = chroma
        self.warmShare = warmShare
        self.longEdge = longEdge
    }

    /// The copy the app measures: at most this on its long edge.
    public static let measuredLongEdge = 1024

    public var isBlurry: Bool { sharpness < 80 }
    public var isNoisy: Bool { noise > 3 }
    public var isLowLight: Bool { meanLuma < 0.2 && highLuma < 0.6 }
    /// Black and white (or nearly: a scan's faint cast).
    public var isMonochrome: Bool { chroma < 0.025 }
    /// Lifted blacks and a narrow range, like a print that has faded.
    public var isFaded: Bool { lowLuma > 0.1 && highLuma - lowLuma < 0.62 }
    /// An old print: black and white or sepia, and faded or soft. A crisp,
    /// contrasty black-and-white photo of today isn't one.
    public var looksOld: Bool {
        if isMonochrome { return isFaded || sharpness < 200 }
        let sepia = warmShare > 0.95 && chroma < 0.25
        return sepia && isFaded && highLuma - lowLuma < 0.56
    }

    /// Measures RGBA8 pixels (row by row, any row order).
    public static func measure(rgba: [UInt8], width: Int, height: Int) -> PhotoQuality {
        guard width >= 8, height >= 8, rgba.count >= width * height * 4 else { return PhotoQuality() }
        let count = width * height
        var gray = [Double](repeating: 0, count: count)
        var lumaHistogram = [Int](repeating: 0, count: 256)
        var chromaSum = 0.0
        var warm = 0
        for i in 0..<count {
            let r = Double(rgba[4 * i]), g = Double(rgba[4 * i + 1]), b = Double(rgba[4 * i + 2])
            let y = 0.299 * r + 0.587 * g + 0.114 * b
            gray[i] = y
            lumaHistogram[min(255, Int(y.rounded()))] += 1
            chromaSum += (max(r, g, b) - min(r, g, b)) / 255
            if r >= g && g >= b { warm += 1 }
        }
        func percentile(_ p: Double) -> Double {
            let target = Int(Double(count - 1) * p)
            var seen = 0
            for (value, n) in lumaHistogram.enumerated() {
                seen += n
                if seen > target { return Double(value) / 255 }
            }
            return 1
        }
        let mean = gray.reduce(0, +) / Double(count) / 255

        // 4×4 tiles: Laplacian variance (detail) and Immerkær's noise σ.
        var variances: [Double] = []
        var noises: [Double] = []
        let tiles = 4
        for ty in 0..<tiles {
            for tx in 0..<tiles {
                let x0 = 1 + tx * (width - 2) / tiles, x1 = 1 + (tx + 1) * (width - 2) / tiles
                let y0 = 1 + ty * (height - 2) / tiles, y1 = 1 + (ty + 1) * (height - 2) / tiles
                var sum = 0.0, sumSquares = 0.0, absNoise = 0.0
                var n = 0
                for y in y0..<y1 {
                    let row = y * width, up = row - width, down = row + width
                    for x in x0..<x1 {
                        let c = gray[row + x]
                        let lap = gray[row + x - 1] + gray[row + x + 1] + gray[up + x] + gray[down + x] - 4 * c
                        sum += lap
                        sumSquares += lap * lap
                        let k = gray[up + x - 1] - 2 * gray[up + x] + gray[up + x + 1]
                            - 2 * gray[row + x - 1] + 4 * c - 2 * gray[row + x + 1]
                            + gray[down + x - 1] - 2 * gray[down + x] + gray[down + x + 1]
                        absNoise += abs(k)
                        n += 1
                    }
                }
                guard n > 0 else { continue }
                let average = sum / Double(n)
                variances.append(sumSquares / Double(n) - average * average)
                noises.append((Double.pi / 2).squareRoot() / 6 * absNoise / Double(n))
            }
        }
        variances.sort()
        noises.sort()
        let noise = noises.isEmpty ? 0 : median(Array(noises.prefix(max(1, noises.count / 2))))
        let raw = variances.count >= 2 ? variances[variances.count - 2] : variances.last ?? 0
        // White noise of σ adds 20σ² to the Laplacian's variance.
        let sharpness = max(0, raw - 20 * noise * noise)
        return PhotoQuality(sharpness: sharpness, noise: noise, meanLuma: mean, lowLuma: percentile(0.02), highLuma: percentile(0.98),
                            chroma: chromaSum / Double(count), warmShare: Double(warm) / Double(count), longEdge: max(width, height))
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }
}

/// Why Enhance is suggested for a photo.
public enum EnhanceReason: String, Sendable, CaseIterable {
    case oldPrint, lowLight, blurry, noisy
}

/// The Enhance option that fits a photo, if it needs one.
public struct EnhanceSuggestion: Equatable, Sendable {
    public var option: EnhanceOption
    public var reason: EnhanceReason

    public init(option: EnhanceOption, reason: EnhanceReason) {
        self.option = option
        self.reason = reason
    }
}

public enum EnhanceAdvisor {
    /// Old prints first (they're often soft and dark too), then low light,
    /// blur and noise. Without cloud AI (under 13) the free Quick fix is
    /// offered for all of them.
    public static func suggestion(for quality: PhotoQuality?, cloudAI: Bool) -> EnhanceSuggestion? {
        guard let quality else { return nil }
        let reason: EnhanceReason
        let option: EnhanceOption
        if quality.looksOld {
            (reason, option) = (.oldPrint, .restore)
        } else if quality.isLowLight {
            (reason, option) = (.lowLight, .lowLight)
        } else if quality.isBlurry {
            (reason, option) = (.blurry, .unblur)
        } else if quality.isNoisy {
            (reason, option) = (.noisy, .quickFix)
        } else {
            return nil
        }
        return EnhanceSuggestion(option: cloudAI ? option : .quickFix, reason: reason)
    }
}

// MARK: - Quick fix

/// Quick fix's numbers for a photo of any size. Radii are in thousandths of
/// the long edge, so the preview and the full-size render match; noise
/// reduction follows the noise each size really has (a smaller copy has
/// averaged some of it away) and is off for clean photos, so their skin and
/// texture are untouched.
public struct QuickFixPlan: Equatable, Sendable {
    /// Exposure, contrast, colour and white balance ("Auto", gentle).
    public var light: AutoAdjustment
    /// Core Image noise reduction level, 0 = off.
    public var noiseLevel: Double
    /// Local contrast: an unsharp mask with a wide radius (pixels).
    public var clarityRadius: Double
    public var clarityIntensity: Double
    /// Luminance sharpening radius (pixels) and amount.
    public var sharpenRadius: Double
    public var sharpness: Double
    /// 1, or up to 2 with "Upscale".
    public var scale: Double
}

public enum QuickFix {
    /// Below this noise (σ on the measured copy) nothing is denoised.
    static let noiseFloor = 1.6

    /// `light`: Auto's plan for the photo; `noise`: `PhotoQuality.noise`;
    /// `longEdge`: the size being rendered (preview or full).
    public static func plan(light: AutoAdjustment, noise: Double, longEdge: Double, upscale: Bool = false) -> QuickFixPlan {
        let unit = AdjustRendering.unit(longEdge: longEdge)
        // σ at this size: a copy k times smaller averages noise down about k times.
        let scaleToMeasured = max(1, longEdge / Double(PhotoQuality.measuredLongEdge))
        let noiseHere = noise * scaleToMeasured
        let noiseLevel = noise > noiseFloor ? min(0.06, noiseHere / 255 * 1.4) : 0
        // Auto's light and colour as they are; its sharpening is done here.
        var gentle = light
        gentle.sharpness = 0
        return QuickFixPlan(
            light: gentle,
            noiseLevel: noiseLevel,
            clarityRadius: 18 * unit,
            clarityIntensity: 0.22,
            sharpenRadius: max(0.5, 0.9 * unit),
            sharpness: 0.5,
            scale: upscale ? EnhanceSizing.upscaleFactor(longEdge: longEdge) : 1
        )
    }
}
