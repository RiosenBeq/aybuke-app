import Foundation

// Adjust's "Soft skin" slider: an owner decision of 16 October 2026 for
// adults only (18+), off by default and gentle at its strongest. It's a
// manual, on-device edit (no AI marking), and it never reaches an AI prompt,
// a look or Glow Cam; the prompt policy still refuses smoothing requests.
//
// How it softens: frequency separation on the skin only. An edge-preserving
// filter evens out the middle frequencies (blotches and unevenness), the
// finest band (pores, freckles, fine texture) is put back on top, and the
// result is blended in at most `maxBlend`. The skin mask is Vision's person
// matte, narrowed to the face's own skin colour, minus the eyes, brows, lips
// and nostrils, so hair, eyes and lips stay sharp. The numbers live here so
// the 1200 px preview and the full-size Apply match.

public enum SoftSkin {
    /// The most of the softened skin ever blended in, at the slider's end.
    public static let maxBlend = 0.35
    /// Off until she moves it.
    public static let defaultAmount = 0.0

    /// Only adults see the slider: never 13–17, unknown ages or under 13.
    public static func isAvailable(for defaults: AgeDefaults) -> Bool { defaults.allowsSoftSkin }

    /// How much of the softened skin is blended in for a slider value (0…1).
    public static func blend(for amount: Double) -> Double {
        guard amount.isFinite, amount > 0 else { return 0 }
        return maxBlend * min(amount, 1)
    }

    /// Sizes for a photo of any size, in thousandths of its long edge.
    public struct Plan: Equatable, Sendable {
        /// Edge-preserving smoothing (a guided filter): radius in pixels and
        /// its edge threshold (variance, 0…1 values). Edges stronger than
        /// this keep their contrast.
        public var smoothingRadius: Double
        public var edgeThreshold: Double
        /// The finest band, put back on top: a Gaussian of this σ (pixels)
        /// separates it, so pores and freckles stay.
        public var textureSigma: Double
        /// The mask's edge is feathered by this σ (pixels).
        public var featherSigma: Double
        public var blend: Double
    }

    public static func plan(amount: Double, longEdge: Double) -> Plan? {
        let blend = blend(for: amount)
        guard blend > 0, longEdge > 0 else { return nil }
        let unit = AdjustRendering.unit(longEdge: longEdge)
        return Plan(smoothingRadius: max(2, 7 * unit), edgeThreshold: 0.0025, textureSigma: max(0.6, 0.8 * unit),
                    featherSigma: max(1, 2.5 * unit), blend: blend)
    }
}

// MARK: - Skin colour

/// A face's own skin colour, sampled on the cheeks and forehead, and how
/// close another pixel is to it. Hair, eyes, lips, clothes and the
/// background fall outside it. Values are gamma-encoded sRGB in 0…1.
public struct SkinTone: Equatable, Sendable {
    /// BT.601 chroma of the reference (centred on 0).
    public var cb: Double
    public var cr: Double
    /// The reference's luma, and how far from it skin still counts (shadows and highlights on a face).
    public var luma: Double

    public init(cb: Double, cr: Double, luma: Double) {
        self.cb = cb
        self.cr = cr
        self.luma = luma
    }

    static func chroma(r: Double, g: Double, b: Double) -> (y: Double, cb: Double, cr: Double) {
        let y = 0.299 * r + 0.587 * g + 0.114 * b
        return (y, -0.168736 * r - 0.331264 * g + 0.5 * b, 0.5 * r - 0.418688 * g - 0.081312 * b)
    }

    /// The median colour of the samples (robust to a stray hair or shadow);
    /// nil with too few to tell.
    public static func reference(samples: [(r: Double, g: Double, b: Double)]) -> SkinTone? {
        guard samples.count >= 12 else { return nil }
        let values = samples.map { chroma(r: $0.r, g: $0.g, b: $0.b) }
        func median(_ list: [Double]) -> Double {
            let sorted = list.sorted()
            return sorted[sorted.count / 2]
        }
        return SkinTone(cb: median(values.map(\.cb)), cr: median(values.map(\.cr)), luma: median(values.map(\.y)))
    }

    /// Chroma distance that still counts fully as skin, and where it stops.
    static let innerRadius = 0.035
    static let outerRadius = 0.07

    /// 1 for this skin's colour, falling to 0 a little away from it. Much
    /// darker than the face (hair, brows, deep shadow) or blown out doesn't
    /// count: dark hair has much the same hue as the skin it frames.
    public func likelihood(r: Double, g: Double, b: Double) -> Double {
        let value = Self.chroma(r: r, g: g, b: b)
        guard value.y > 0.06, value.y < 0.985 else { return 0 }
        let light = value.y / max(luma, 0.05)
        let brightness = Self.falloff(light, from: 0.62, to: 0.42) * Self.falloff(light, from: 1.45, to: 1.7)
        guard brightness > 0 else { return 0 }
        // Skin in shadow loses some chroma; scale the reference with the light.
        let scale = min(1, max(0.5, light))
        let dcb = value.cb - cb * scale
        let dcr = value.cr - cr * scale
        let distance = (dcb * dcb + dcr * dcr).squareRoot()
        return brightness * Self.falloff(distance, from: Self.innerRadius, to: Self.outerRadius)
    }

    /// 1 up to `from`, 0 past `to` (either direction), smooth between.
    static func falloff(_ value: Double, from: Double, to: Double) -> Double {
        let t = (value - from) / (to - from)
        if t <= 0 { return 1 }
        if t >= 1 { return 0 }
        return 1 - t * t * (3 - 2 * t)
    }
}

// MARK: - Features kept sharp

/// The parts of a face the smoothing never touches, as ellipses in the
/// landmarks' own coordinates: the eyes with their lashes, the brows, the
/// lips and the nostrils. Brows come from Vision when it has them, else
/// from the eyes.
public struct FaceFeatureEllipse: Equatable, Sendable {
    public var center: FacePoint
    public var radiusX: Double
    public var radiusY: Double
    /// Radians, counter-clockwise from the x axis (the face's tilt).
    public var angle: Double

    public init(center: FacePoint, radiusX: Double, radiusY: Double, angle: Double) {
        self.center = center
        self.radiusX = radiusX
        self.radiusY = radiusY
        self.angle = angle
    }
}

public enum FaceFeatureMask {
    public static func ellipses(for face: FaceLandmarks) -> [FaceFeatureEllipse] {
        guard let left = FaceTintGeometry.centroid(face.leftEye), let right = FaceTintGeometry.centroid(face.rightEye) else { return [] }
        let eyeDistance = left.distance(to: right)
        guard eyeDistance > 0 else { return [] }
        let across = (right - left) * (1 / eyeDistance)
        let angle = atan2(across.y, across.x)
        // "Up" the face, from the mouth towards the eyes (y up).
        var up = FacePoint(x: -across.y, y: across.x)
        if let mouth = FaceTintGeometry.centroid(face.outerLips), ((left + right) * 0.5 - mouth).dot(up) < 0 {
            up = -up
        }
        var result: [FaceFeatureEllipse] = []
        for (eye, points, brow) in [(left, face.leftEye, face.leftEyebrow), (right, face.rightEye, face.rightEyebrow)] {
            let width = max(spread(points, along: across), 0.3 * eyeDistance)
            result.append(FaceFeatureEllipse(center: eye, radiusX: 0.75 * width, radiusY: 0.32 * eyeDistance, angle: angle))
            if let browCenter = FaceTintGeometry.centroid(brow), brow.count >= 3 {
                let browWidth = max(spread(brow, along: across), 0.35 * eyeDistance)
                result.append(FaceFeatureEllipse(center: browCenter, radiusX: 0.62 * browWidth, radiusY: 0.13 * eyeDistance, angle: angle))
            } else {
                result.append(FaceFeatureEllipse(center: eye + up * (0.33 * eyeDistance), radiusX: 0.42 * eyeDistance,
                                                 radiusY: 0.14 * eyeDistance, angle: angle))
            }
        }
        if let mouth = FaceTintGeometry.centroid(face.outerLips), face.outerLips.count >= 3 {
            let width = max(spread(face.outerLips, along: across), 0.5 * eyeDistance)
            let height = max(spread(face.outerLips, along: up), 0.18 * eyeDistance)
            result.append(FaceFeatureEllipse(center: mouth, radiusX: 0.62 * width, radiusY: 0.68 * height, angle: angle))
        }
        // The nostrils: the bottom of the nose, or under the eyes' middle.
        // On the face's midline, at the lowest point of the nose.
        let mid = (left + right) * 0.5
        let drop = face.nose.count >= 3 ? (face.nose.map { ($0 - mid).dot(up) }.min() ?? -0.62 * eyeDistance) : -0.62 * eyeDistance
        let noseTip = mid + up * drop
        result.append(FaceFeatureEllipse(center: noseTip + up * (0.06 * eyeDistance), radiusX: 0.3 * eyeDistance,
                                         radiusY: 0.14 * eyeDistance, angle: angle))
        return result
    }

    /// Where on the cheeks and forehead the skin colour is sampled.
    public static func skinSamplePoints(for face: FaceLandmarks) -> [FacePoint] {
        guard let left = FaceTintGeometry.centroid(face.leftEye), let right = FaceTintGeometry.centroid(face.rightEye) else { return [] }
        let eyeDistance = left.distance(to: right)
        guard eyeDistance > 0 else { return [] }
        let across = (right - left) * (1 / eyeDistance)
        var up = FacePoint(x: -across.y, y: across.x)
        if let mouth = FaceTintGeometry.centroid(face.outerLips), ((left + right) * 0.5 - mouth).dot(up) < 0 {
            up = -up
        }
        let mid = (left + right) * 0.5
        var points: [FacePoint] = []
        // A small grid on each cheek, below and outside the eyes, and one on the forehead.
        for eye in [left, right] {
            let outward = (eye - mid).dot(across) < 0 ? -across : across
            for i in 0..<3 {
                for j in 0..<3 {
                    let center = eye - up * (0.5 * eyeDistance) + outward * (0.16 * eyeDistance)
                    points.append(center + across * (Double(i - 1) * 0.09 * eyeDistance) + up * (Double(j - 1) * 0.09 * eyeDistance))
                }
            }
        }
        for i in 0..<3 {
            points.append(mid + up * (0.7 * eyeDistance) + across * (Double(i - 1) * 0.15 * eyeDistance))
        }
        return points
    }

    private static func spread(_ points: [FacePoint], along axis: FacePoint) -> Double {
        let values = points.map { $0.dot(axis) }
        guard let low = values.min(), let high = values.max() else { return 0 }
        return high - low
    }
}

extension FaceFeatureEllipse {
    /// Inside (≤ 1) or outside (> 1), in units of the ellipse's radii.
    public func normalizedDistance(to point: FacePoint) -> Double {
        let d = point - center
        let c = cos(angle), s = sin(angle)
        let x = (d.x * c + d.y * s) / max(radiusX, 1e-9)
        let y = (-d.x * s + d.y * c) / max(radiusY, 1e-9)
        return (x * x + y * y).squareRoot()
    }
}
