import Foundation

// The live makeup tint's geometry, from Vision's face landmarks: the lips' own
// outline and a soft blush spot on each cheek, smoothed between Vision's looks
// and paced so the camera stays smooth. Colour goes on inside the lip line and
// as a soft wash on the cheeks; nothing here moves or reshapes a feature.

/// A point with y up (Core Image's way), in pixels or in fractions of a frame.
public struct FacePoint: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    static func + (a: FacePoint, b: FacePoint) -> FacePoint { FacePoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: FacePoint, b: FacePoint) -> FacePoint { FacePoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: FacePoint, k: Double) -> FacePoint { FacePoint(x: a.x * k, y: a.y * k) }
    static prefix func - (a: FacePoint) -> FacePoint { FacePoint(x: -a.x, y: -a.y) }

    func dot(_ other: FacePoint) -> Double { x * other.x + y * other.y }
    var length: Double { (x * x + y * y).squareRoot() }
    func distance(to other: FacePoint) -> Double { (self - other).length }
}

/// What the tint needs of one face: Vision's landmark regions.
public struct FaceLandmarks: Equatable, Sendable {
    public var outerLips: [FacePoint]
    public var innerLips: [FacePoint]
    public var leftEye: [FacePoint]
    public var rightEye: [FacePoint]
    public var nose: [FacePoint]
    public var faceContour: [FacePoint]
    /// Only Soft skin uses the brows (kept sharp); empty when Vision has none.
    public var leftEyebrow: [FacePoint]
    public var rightEyebrow: [FacePoint]

    public init(outerLips: [FacePoint], innerLips: [FacePoint] = [], leftEye: [FacePoint], rightEye: [FacePoint],
                nose: [FacePoint] = [], faceContour: [FacePoint] = [], leftEyebrow: [FacePoint] = [], rightEyebrow: [FacePoint] = []) {
        self.outerLips = outerLips
        self.innerLips = innerLips
        self.leftEye = leftEye
        self.rightEye = rightEye
        self.nose = nose
        self.faceContour = faceContour
        self.leftEyebrow = leftEyebrow
        self.rightEyebrow = rightEyebrow
    }

    /// Halfway between the eyes and the mouth.
    public var center: FacePoint? {
        guard let left = FaceTintGeometry.centroid(leftEye), let right = FaceTintGeometry.centroid(rightEye),
              let mouth = FaceTintGeometry.centroid(outerLips) else { return nil }
        return ((left + right) * 0.5 + mouth) * 0.5
    }

    /// Between the eyes' centres: how big the face is.
    public var eyeDistance: Double {
        guard let left = FaceTintGeometry.centroid(leftEye), let right = FaceTintGeometry.centroid(rightEye) else { return 0 }
        return left.distance(to: right)
    }

    /// Every point through `transform` (from fractions of a frame into pixels, say).
    public func mapped(_ transform: (FacePoint) -> FacePoint) -> FaceLandmarks {
        FaceLandmarks(outerLips: outerLips.map(transform), innerLips: innerLips.map(transform),
                      leftEye: leftEye.map(transform), rightEye: rightEye.map(transform),
                      nose: nose.map(transform), faceContour: faceContour.map(transform),
                      leftEyebrow: leftEyebrow.map(transform), rightEyebrow: rightEyebrow.map(transform))
    }

    /// `fraction` of the way to `target`, point by point; `target` itself when
    /// the regions don't have the same points.
    public func moved(toward target: FaceLandmarks, by fraction: Double) -> FaceLandmarks {
        let parts = [(outerLips, target.outerLips), (innerLips, target.innerLips), (leftEye, target.leftEye),
                     (rightEye, target.rightEye), (nose, target.nose), (faceContour, target.faceContour)]
        guard parts.allSatisfy({ $0.0.count == $0.1.count }) else { return target }
        let k = min(max(fraction.isFinite ? fraction : 1, 0), 1)
        func blend(_ from: [FacePoint], _ to: [FacePoint]) -> [FacePoint] {
            zip(from, to).map { $0 + ($1 - $0) * k }
        }
        return FaceLandmarks(outerLips: blend(outerLips, target.outerLips), innerLips: blend(innerLips, target.innerLips),
                             leftEye: blend(leftEye, target.leftEye), rightEye: blend(rightEye, target.rightEye),
                             nose: blend(nose, target.nose), faceContour: blend(faceContour, target.faceContour))
    }
}

public enum FaceTintGeometry {
    /// A soft blush spot, `radiusX` along the eye line and `radiusY` across it.
    public struct Ellipse: Equatable, Sendable {
        public var center: FacePoint
        public var radiusX: Double
        public var radiusY: Double
        /// The eye line's angle, radians counterclockwise from +x.
        public var angle: Double
    }

    /// The lips' mask: their outline with the mouth's opening cut out, pulled
    /// in so a soft edge `feather` wide (a blur radius) ends at the lip line
    /// instead of going over it.
    public struct LipPlan: Equatable, Sendable {
        public var outline: [FacePoint]
        public var opening: [FacePoint]
        public var feather: Double
    }

    /// Blush on the apples of the cheeks: below each eye, a little above the
    /// bottom of the nose and a little outward, inside the face and clear of
    /// the mouth. Worked out in the face's own frame, so it follows a tilted
    /// head; needs units with the same scale across and up (pixels).
    public static func cheeks(of face: FaceLandmarks) -> [Ellipse] {
        guard let left = centroid(face.leftEye), let right = centroid(face.rightEye) else { return [] }
        let across = right - left
        let eyeDistance = across.length
        guard eyeDistance > 0 else { return [] }
        let unitAcross = across * (1 / eyeDistance)
        let eyes = (left + right) * 0.5
        // Down the face, toward the mouth, whichever way the head is turned.
        var down = FacePoint(x: unitAcross.y, y: -unitAcross.x)
        if let mouth = centroid(face.outerLips), (mouth - eyes).dot(down) < 0 { down = -down }
        let radiusX = 0.38 * eyeDistance
        let radiusY = 0.28 * eyeDistance
        // How far the nose reaches below the eye line (a typical face when Vision has no nose).
        let noseDrop = face.nose.map { ($0 - eyes).dot(down) }.max() ?? 0.7 * eyeDistance
        var depth = 0.8 * min(max(noseDrop, 0.45 * eyeDistance), eyeDistance)
        if let mouthTop = face.outerLips.map({ ($0 - eyes).dot(down) }).min() {
            depth = min(depth, mouthTop - 0.6 * radiusY)
        }
        depth = max(depth, 0.3 * eyeDistance)
        let angle = atan2(unitAcross.y, unitAcross.x)
        return [(left, -unitAcross), (right, unitAcross)].map { eye, outward in
            var center = eye + down * depth + outward * (0.1 * eyeDistance)
            // The soft edge stays inside the face's outline (the far cheek of a turned head).
            if let edge = face.faceContour.map({ ($0 - eyes).dot(outward) }).max(), edge > 0 {
                let reach = (center - eyes).dot(outward) + 0.8 * radiusX
                if reach > edge { center = center - outward * min(reach - edge, 0.5 * eyeDistance) }
            }
            return Ellipse(center: center, radiusX: radiusX, radiusY: radiusY, angle: angle)
        }
    }

    /// The lips' mask, or nil without enough of their outline.
    public static func lips(of face: FaceLandmarks) -> LipPlan? {
        guard face.outerLips.count >= 6 else { return nil }
        let width = span(of: face.outerLips)
        guard width > 0 else { return nil }
        let feather = 0.035 * width
        // The opening grows a little, so teeth keep their own colour.
        let opening = face.innerLips.count >= 3 ? inset(smoothOutline(face.innerLips), by: -0.6 * feather) : []
        return LipPlan(outline: inset(smoothOutline(face.outerLips), by: feather), opening: opening, feather: feather)
    }

    /// A smooth closed curve through `points` (centripetal Catmull–Rom, which
    /// never loops or overshoots wildly at the mouth's corners):
    /// `samplesPerSegment` points per side, the first of each an original point.
    public static func smoothOutline(_ points: [FacePoint], samplesPerSegment: Int = 4) -> [FacePoint] {
        let count = points.count
        guard count >= 3, samplesPerSegment > 1 else { return points }
        var curve: [FacePoint] = []
        curve.reserveCapacity(count * samplesPerSegment)
        for index in 0..<count {
            let p0 = points[(index + count - 1) % count], p1 = points[index]
            let p2 = points[(index + 1) % count], p3 = points[(index + 2) % count]
            for step in 0..<samplesPerSegment {
                curve.append(catmullRom(p0, p1, p2, p3, t: Double(step) / Double(samplesPerSegment)))
            }
        }
        return curve
    }

    /// Every point of a closed outline moved `distance` inward, square to the
    /// outline (outward when negative). Meant for small distances next to
    /// the shape's size, like a mask's soft edge.
    public static func inset(_ points: [FacePoint], by distance: Double) -> [FacePoint] {
        let count = points.count
        guard count >= 3 else { return points }
        // Inside is on the left of a counterclockwise outline.
        let turn: Double = signedArea(points) >= 0 ? 1 : -1
        return points.indices.map { index in
            let tangent = points[(index + 1) % count] - points[(index + count - 1) % count]
            let length = tangent.length
            guard length > 0 else { return points[index] }
            return points[index] + FacePoint(x: -tangent.y, y: tangent.x) * (turn * distance / length)
        }
    }

    /// Positive for a counterclockwise outline (shoelace formula).
    static func signedArea(_ points: [FacePoint]) -> Double {
        var area = 0.0
        for index in points.indices {
            let a = points[index], b = points[(index + 1) % points.count]
            area += a.x * b.y - b.x * a.y
        }
        return area / 2
    }

    /// The longest distance between two of `points`: a mouth's width, however the head tilts.
    public static func span(of points: [FacePoint]) -> Double {
        var longest = 0.0
        for i in points.indices {
            for j in points.indices where j > i {
                longest = max(longest, points[i].distance(to: points[j]))
            }
        }
        return longest
    }

    public static func centroid(_ points: [FacePoint]) -> FacePoint? {
        guard !points.isEmpty else { return nil }
        return points.reduce(FacePoint(x: 0, y: 0), +) * (1 / Double(points.count))
    }

    static func catmullRom(_ p0: FacePoint, _ p1: FacePoint, _ p2: FacePoint, _ p3: FacePoint, t: Double) -> FacePoint {
        // Knots spaced by the square root of each side's length.
        func knot(_ a: FacePoint, _ b: FacePoint) -> Double { max(a.distance(to: b).squareRoot(), 1e-9) }
        let t0 = 0.0
        let t1 = t0 + knot(p0, p1)
        let t2 = t1 + knot(p1, p2)
        let t3 = t2 + knot(p2, p3)
        let u = t1 + (t2 - t1) * t
        func lerp(_ a: FacePoint, _ b: FacePoint, _ ta: Double, _ tb: Double) -> FacePoint {
            a * ((tb - u) / (tb - ta)) + b * ((u - ta) / (tb - ta))
        }
        let a1 = lerp(p0, p1, t0, t1), a2 = lerp(p1, p2, t1, t2), a3 = lerp(p2, p3, t2, t3)
        return lerp(lerp(a1, a2, t0, t2), lerp(a2, a3, t1, t3), t1, t2)
    }
}

// MARK: - Smoothing

/// Keeps the tint steady on moving faces between Vision's looks (a few a
/// second): every frame each face glides toward its latest landmarks instead
/// of jumping, fades in when found and out a moment after it's gone. Faces are
/// matched from look to look by where they are, so several can wear a tint.
public struct FaceTrackSmoother: Sendable {
    public struct Face: Equatable, Sendable {
        public var id: Int
        public var landmarks: FaceLandmarks
        /// 0…1: how much of the tint it gets.
        public var opacity: Double
    }

    public static let maxFaces = 4
    /// Time constant of the glide, in seconds.
    public var glide = 0.07
    public var fadeIn = 0.2
    public var fadeOut = 0.3
    /// A face missing from one look keeps its tint this long (Vision misses one now and then).
    public var grace = 0.35

    private struct Track: Sendable {
        var id: Int
        var shown: FaceLandmarks
        var target: FaceLandmarks
        var opacity: Double
        var lastSeen: Double
    }

    private var tracks: [Track] = []
    private var nextID = 0
    private var clock: Double?

    public init() {}

    public var isEmpty: Bool { tracks.isEmpty }

    /// Vision's faces, as of `time` (seconds on the frames' clock).
    public mutating func update(_ detections: [FaceLandmarks], at time: Double) {
        var open = Array(tracks.indices)
        var fresh: [Track] = []
        let faces = detections.filter { $0.center != nil && $0.eyeDistance > 0 }
            .sorted { $0.eyeDistance > $1.eyeDistance }
            .prefix(Self.maxFaces)
        for face in faces {
            guard let center = face.center else { continue }
            func gap(_ index: Int) -> Double { tracks[index].target.center?.distance(to: center) ?? .infinity }
            if let best = open.min(by: { gap($0) < gap($1) }),
               gap(best) < 1.2 * max(face.eyeDistance, tracks[best].target.eyeDistance) {
                open.removeAll { $0 == best }
                // A big jump (someone new in the same spot, a quick turn) snaps instead of smearing.
                if gap(best) > 0.6 * face.eyeDistance { tracks[best].shown = face }
                tracks[best].target = face
                tracks[best].lastSeen = time
            } else {
                fresh.append(Track(id: nextID, shown: face, target: face, opacity: 0, lastSeen: time))
                nextID += 1
            }
        }
        tracks += fresh
        // Room for the faces in view: the faintest of those gone make way.
        while tracks.count > Self.maxFaces {
            let gone = tracks.indices.filter { tracks[$0].lastSeen < time }
            guard let faintest = (gone.isEmpty ? Array(tracks.indices) : gone).min(by: { tracks[$0].opacity < tracks[$1].opacity }) else { break }
            tracks.remove(at: faintest)
        }
    }

    /// The faces to tint at `time`, each a step closer to its latest landmarks.
    public mutating func advance(to time: Double) -> [Face] {
        let step = clock.map { min(max(time - $0, 0), 0.25) } ?? 0
        clock = time
        let pull = glide > 0 ? 1 - exp(-step / glide) : 1
        for index in tracks.indices {
            tracks[index].shown = tracks[index].shown.moved(toward: tracks[index].target, by: pull)
            let isSeen = time - tracks[index].lastSeen <= grace
            let change = isSeen ? step / max(fadeIn, 1e-6) : -step / max(fadeOut, 1e-6)
            tracks[index].opacity = min(max(tracks[index].opacity + change, 0), 1)
        }
        tracks.removeAll { $0.opacity <= 0 && time - $0.lastSeen > grace }
        return tracks.filter { $0.opacity > 0 }.map { Face(id: $0.id, landmarks: $0.shown, opacity: $0.opacity) }
    }

    public mutating func reset() {
        tracks = []
        clock = nil
    }
}

// MARK: - Pacing

/// When to look for faces again, and when the tint should pause to keep the
/// camera smooth. Vision runs a few times a second, never twice at once, and
/// less often when it's slow; when frames keep falling behind (or Vision
/// can't keep up) for a couple of seconds, the tint turns itself off.
public struct MakeupTintPacing: Sendable {
    public static let fastestInterval = 1.0 / 12
    public static let slowestInterval = 0.5
    /// Average time a frame with the tint may take (drawing, waiting for the GPU).
    public static let frameBudget = 1.0 / 22
    /// Average Vision time above which the tint would trail behind her face.
    public static let detectionBudget = 0.35
    /// Seconds before judging (the first frames are always slow).
    public static let warmUp = 1.5
    /// Seconds over budget before the tint pauses.
    public static let patience = 2.0

    public private(set) var interval = 1.0 / 10
    public private(set) var isPaused = false
    private var lastStart: Double?
    private var isDetecting = false
    private var averageDetection: Double?
    private var averageFrame: Double?
    private var firstFrame: Double?
    private var overSince: Double?

    public init() {}

    /// Whether to start a look now; when true, it counts as started.
    public mutating func shouldDetect(at time: Double) -> Bool {
        guard !isPaused, !isDetecting else { return false }
        if let lastStart, time >= lastStart, time - lastStart < interval { return false }
        lastStart = time
        isDetecting = true
        return true
    }

    /// The look took `duration` seconds; the next one waits about twice that.
    public mutating func detectionFinished(duration: Double) {
        isDetecting = false
        let average = Self.blend(averageDetection, Self.clean(duration), weight: 0.3)
        averageDetection = average
        interval = min(max(2 * average, Self.fastestInterval), Self.slowestInterval)
    }

    /// A frame with the tint took `duration` seconds, drawn at `time`.
    public mutating func frameDrawn(at time: Double, duration: Double) {
        let start = firstFrame ?? time
        firstFrame = start
        averageFrame = Self.blend(averageFrame, Self.clean(duration), weight: 0.1)
        guard time - start >= Self.warmUp else { return }
        let isOver = (averageFrame ?? 0) > Self.frameBudget || (averageDetection ?? 0) > Self.detectionBudget
        guard isOver else {
            overSince = nil
            return
        }
        let since = overSince ?? time
        overSince = since
        if time - since >= Self.patience { isPaused = true }
    }

    /// The device is running hot: the tint pauses at once.
    public mutating func pause() {
        isPaused = true
    }

    static func blend(_ average: Double?, _ value: Double, weight: Double) -> Double {
        guard let average else { return value }
        return average + (value - average) * weight
    }

    static func clean(_ seconds: Double) -> Double {
        seconds.isFinite ? max(seconds, 0) : 0
    }
}
