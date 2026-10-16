import Foundation

// Auto edit in the video editor: one tap turns a clip into a vertical cut
// (9:16, 1080 × 1920) for TikTok, Instagram Reels or YouTube Shorts, all on
// the device. Which parts stay, how the 9:16 window follows her, where the
// crossfades go, where captions may sit, the free one a day and the words to
// post with it live here, so they're tested; the app only reads the clip
// (loudness, Vision, motion) and renders it.

// MARK: - Platforms

/// Where an Auto edit is going. The names are brands, shown as they are in
/// every language.
public enum SocialPlatform: String, CaseIterable, Identifiable, Codable, Sendable {
    case tiktok
    case reels
    case shorts

    public var id: String { rawValue }

    /// All three take 9:16 video at 1080 × 1920.
    public static let frameWidth = 1080.0
    public static let frameHeight = 1920.0
    public static var frameAspect: Double { frameWidth / frameHeight }

    /// Lengths she can aim for, in seconds; Reels also takes 90 s.
    public var lengths: [Double] {
        self == .reels ? [15, 30, 60, 90] : [15, 30, 60]
    }

    public static let defaultLength = 30.0

    /// Where the app's own buttons and text sit once it's posted, as shares
    /// of the frame: TikTok's column of buttons on the right and its caption,
    /// sound and tab bar along the bottom; the caption and sound lines at the
    /// bottom of Reels and Shorts, with their narrower button column. Captions
    /// stay inside the rest.
    public var safeArea: SafeArea {
        switch self {
        case .tiktok: return SafeArea(top: 0.08, left: 0.06, bottom: 0.25, right: 0.15)
        case .reels: return SafeArea(top: 0.08, left: 0.05, bottom: 0.22, right: 0.12)
        case .shorts: return SafeArea(top: 0.08, left: 0.05, bottom: 0.21, right: 0.12)
        }
    }

    /// `context.format` for the caption writer (`AssistContext`).
    public var assistFormat: String { rawValue }

    /// Shorts have a title (at most `PostText.titleLimit` characters);
    /// TikTok and Reels only a caption.
    public var hasTitle: Bool { self == .shorts }
}

/// Margins of a frame, as shares of its width (left, right) and height (top, bottom).
public struct SafeArea: Hashable, Sendable {
    public var top: Double
    public var left: Double
    public var bottom: Double
    public var right: Double

    public init(top: Double = 0, left: Double = 0, bottom: Double = 0, right: Double = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    public static let zero = SafeArea()

    /// The free part of a `width` × `height` frame, measured from its top left corner.
    public func frame(width: Double, height: Double) -> FrameRect {
        FrameRect(x: width * left, y: height * top,
                  width: max(0, width * (1 - left - right)), height: max(0, height * (1 - top - bottom)))
    }
}

/// A rectangle in a frame, from its top left corner.
public struct FrameRect: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var maxY: Double { y + height }
}

// MARK: - The free one a day

/// Auto edit is part of Pro; free members get one a day on this device,
/// counted by local calendar day, so the next one is ready at local midnight.
public struct AutoEditAllowance: Codable, Equatable, Sendable {
    public static let freePerDay = 1

    /// The local day (yyyy-MM-dd) the uses were counted on.
    public var day: String?
    public var used: Int

    public init(day: String? = nil, used: Int = 0) {
        self.day = day
        self.used = used
    }

    /// Free auto edits left today.
    public func remaining(at date: Date, calendar: Calendar = .current) -> Int {
        let today = Self.dayKey(for: date, calendar: calendar)
        return max(0, Self.freePerDay - (day == today ? used : 0))
    }

    public func allows(at date: Date, isPro: Bool, calendar: Calendar = .current) -> Bool {
        isPro || remaining(at: date, calendar: calendar) > 0
    }

    public mutating func recordUse(at date: Date, calendar: Calendar = .current) {
        let today = Self.dayKey(for: date, calendar: calendar)
        if day != today {
            day = today
            used = 0
        }
        used += 1
    }

    /// The local calendar day of `date`.
    public static func dayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// When the next free one is ready: the next local midnight.
    public static func nextReset(after date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? date.addingTimeInterval(86_400)
    }
}

// MARK: - Choosing the parts

/// Picks what stays: the clip without dead air (silences, a still start or
/// end, the tap on the record button) and, when that's still longer than the
/// target, its liveliest moments in their order. Liveliness is speech
/// (loudness against the clip's own quiet and loud), motion (how much the
/// picture changes) and whether she's in the frame.
public enum AutoEditPlanner {
    /// A measurement over the clip: how much the picture changed, or 1 where
    /// a face or person was found and 0 where not.
    public struct Sample: Equatable, Sendable {
        public var time: Double
        public var value: Double

        public init(time: Double, value: Double) {
            self.time = time
            self.value = value
        }
    }

    public struct Input: Sendable {
        public var duration: Double
        /// Loudness per `window` in dBFS (`SilenceCutter`'s input); empty without sound.
        public var levels: [Double]
        public var window: Double
        /// Picture change between looks, any scale (0 = still).
        public var motion: [Sample]
        public var presence: [Sample]
        /// The part of the clip she trimmed to, if any: nothing outside it stays.
        public var bounds: ClosedRange<Double>?

        public init(duration: Double, levels: [Double] = [], window: Double = 0.05, motion: [Sample] = [], presence: [Sample] = [],
                    bounds: ClosedRange<Double>? = nil) {
            self.duration = duration
            self.levels = levels
            self.window = window
            self.motion = motion
            self.presence = presence
            self.bounds = bounds
        }
    }

    public struct Settings: Sendable {
        /// Trimmed at the very start and end of clips of 4 s or more: the tap
        /// on the record button.
        public var lead = 0.2
        public var tail = 0.3
        /// Moments to choose from are at most about this long, so the
        /// liveliest parts can be picked.
        public var longestMoment = 6.0
        /// No part shorter than this (a flash isn't a moment).
        public var shortestPart = 1.0
        /// Without sound, a still start or end this long is dead air.
        public var stillness = 0.8
        /// Picture change below this (the mean difference of 8-bit greys
        /// between looks, 0…1) is a still frame.
        public var stillMotion = 0.012

        public init() {}
    }

    /// Source time ranges to keep, in order, not overlapping; at most
    /// `target` seconds in all (everything without dead air when that fits).
    public static func plan(_ input: Input, target: Double, settings: Settings = Settings()) -> [ClosedRange<Double>] {
        guard input.duration > 0.1 else { return [] }
        let parts = cleaned(input, settings: settings)
        guard target > 0, total(parts) > target else { return parts }

        let curve = Liveliness(input)
        let moments = parts.flatMap { split($0, longest: settings.longestMoment, input: input) }
        let scores = moments.enumerated().map { index, moment in
            // How she starts sets up the rest.
            curve.mean(over: moment) * (index == 0 ? 1.1 : 1)
        }
        let order = moments.indices.sorted { scores[$0] != scores[$1] ? scores[$0] > scores[$1] : $0 < $1 }
        var chosen = Set<Int>()
        var used = 0.0
        for index in order where used + length(moments[index]) <= target + 1e-9 {
            chosen.insert(index)
            used += length(moments[index])
        }
        var picked = chosen.map { moments[$0] }
        // The time left goes to the beginning of the next best moment,
        // ending where it's quiet.
        let room = target - used
        if room >= settings.shortestPart, let next = order.first(where: { !chosen.contains($0) }) {
            let start = moments[next].lowerBound
            let end = quietEnd(of: start...min(start + room, moments[next].upperBound), input: input)
            if end - start >= settings.shortestPart { picked.append(start...end) }
        }
        picked.sort { $0.lowerBound < $1.lowerBound }
        var merged: [ClosedRange<Double>] = []
        for range in picked {
            if let last = merged.last, range.lowerBound - last.upperBound < 0.01 {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        let lasting = merged.filter { length($0) >= settings.shortestPart }
        return lasting.isEmpty ? merged : lasting
    }

    /// The clip without its dead air: silences when it has sound, a still
    /// start or end when it hasn't, and the record button's tap at either end.
    static func cleaned(_ input: Input, settings: Settings) -> [ClosedRange<Double>] {
        let duration = input.duration
        var parts: [ClosedRange<Double>]
        if !input.levels.isEmpty, input.window > 0 {
            parts = SilenceCutter.plan(levels: input.levels, window: input.window).keep.compactMap { clip($0, to: 0...duration) }
            if parts.isEmpty { parts = [0...duration] }
        } else {
            parts = [stillTrimmed(input, settings: settings)]
        }
        if duration >= 4 {
            parts = parts.compactMap { clip($0, to: settings.lead...(duration - settings.tail)) }
        }
        if let bounds = input.bounds {
            let inside = parts.compactMap { clip($0, to: bounds) }
            parts = inside.isEmpty ? (clip(bounds, to: 0...duration).map { [$0] } ?? []) : inside
        }
        let lasting = parts.filter { length($0) >= 0.3 }
        return lasting.isEmpty ? parts : lasting
    }

    /// Without sound, a start or end where nothing moves is dead air; at
    /// most 40% of the clip goes at either end.
    static func stillTrimmed(_ input: Input, settings: Settings) -> ClosedRange<Double> {
        let duration = input.duration
        let samples = input.motion.filter { $0.time >= 0 && $0.time <= duration }.sorted { $0.time < $1.time }
        // A clip where nothing moves at all (a slideshow) keeps everything.
        let moving = samples.filter { $0.value >= settings.stillMotion }
        guard samples.count >= 4, let first = moving.first, let last = moving.last else { return 0...duration }
        // A sample measures the change since the look before it.
        let spacing = (samples[samples.count - 1].time - samples[0].time) / Double(samples.count - 1)
        var start = 0.0
        var end = duration
        if first.time - spacing >= settings.stillness { start = min(first.time - spacing, duration * 0.4) }
        if duration - last.time >= settings.stillness { end = max(last.time + 0.25, duration * 0.6) }
        return start...max(end, start + 0.1)
    }

    /// A long part as moments of about `longest` seconds, cut at the
    /// quietest moment near each even split, so no word is cut in two.
    static func split(_ range: ClosedRange<Double>, longest: Double, input: Input) -> [ClosedRange<Double>] {
        let span = length(range)
        guard longest > 0, span > longest else { return [range] }
        let count = Int((span / longest).rounded(.up))
        let cuts = (1..<count).map { k in
            quietest(near: range.lowerBound + span * Double(k) / Double(count), spread: 0.75, within: range, input: input)
        }
        var moments: [ClosedRange<Double>] = []
        var start = range.lowerBound
        for cut in cuts.sorted() where cut > start + 0.2 && cut < range.upperBound - 0.2 {
            moments.append(start...cut)
            start = cut
        }
        moments.append(start...range.upperBound)
        return moments
    }

    /// The middle of the quietest loudness window within `spread` of `time`;
    /// `time` itself without sound.
    static func quietest(near time: Double, spread: Double, within range: ClosedRange<Double>, input: Input) -> Double {
        guard !input.levels.isEmpty, input.window > 0 else { return time }
        let from = max(range.lowerBound, time - spread)
        let to = min(range.upperBound, time + spread)
        let first = max(0, Int(from / input.window))
        let last = min(input.levels.count - 1, Int(to / input.window) - 1)
        guard first <= last else { return time }
        var best = first
        for index in first...last where input.levels[index] < input.levels[best] {
            best = index
        }
        return min(max((Double(best) + 0.5) * input.window, from), to)
    }

    /// Where a shortened moment should end: the quietest window in its last 40%.
    static func quietEnd(of range: ClosedRange<Double>, input: Input) -> Double {
        let span = length(range)
        guard !input.levels.isEmpty, span > 0 else { return range.upperBound }
        let tail = (range.upperBound - span * 0.4)...range.upperBound
        return quietest(near: (tail.lowerBound + tail.upperBound) / 2, spread: span * 0.2, within: tail, input: input)
    }

    /// How lively the clip is at any time, 0…1.
    struct Liveliness {
        let input: Input
        let floor: Double?
        let loud: Double?
        let motionPeak: Double?
        let motion: [Sample]
        let presence: [Sample]

        init(_ input: Input) {
            self.input = input
            floor = percentile(input.levels, 0.1)
            loud = percentile(input.levels, 0.9)
            motion = input.motion.sorted { $0.time < $1.time }
            presence = input.presence.sorted { $0.time < $1.time }
            let peak = percentile(motion.map(\.value), 0.9)
            motionPeak = (peak ?? 0) > 0 ? peak : nil
        }

        func value(at time: Double) -> Double {
            let speech = speechLevel(at: time)
            let moving = motionPeak.map { min(1, max(0, interpolate(motion, at: time) / $0)) }
            let there = presence.isEmpty ? nil : nearest(presence, at: time)
            switch (speech, moving) {
            case let (speech?, moving?): return 0.55 * speech + 0.3 * moving + 0.15 * (there ?? 0.5)
            case let (speech?, nil): return 0.85 * speech + 0.15 * (there ?? 0.5)
            case let (nil, moving?): return 0.75 * moving + 0.25 * (there ?? 0.5)
            case (nil, nil): return there ?? 0.5
            }
        }

        func mean(over range: ClosedRange<Double>) -> Double {
            let step = 0.1
            let count = max(1, Int((length(range) / step).rounded(.up)))
            var sum = 0.0
            for index in 0..<count {
                sum += value(at: min(range.lowerBound + (Double(index) + 0.5) * step, range.upperBound))
            }
            return sum / Double(count)
        }

        private func speechLevel(at time: Double) -> Double? {
            guard let floor, let loud, input.window > 0, !input.levels.isEmpty else { return nil }
            let index = min(max(0, Int(time / input.window)), input.levels.count - 1)
            return min(1, max(0, (input.levels[index] - floor) / max(loud - floor, 6)))
        }

        private func interpolate(_ samples: [Sample], at time: Double) -> Double {
            guard let first = samples.first, let last = samples.last else { return 0 }
            if time <= first.time { return first.value }
            if time >= last.time { return last.value }
            let after = samples.firstIndex { $0.time > time } ?? samples.count - 1
            let a = samples[after - 1], b = samples[after]
            let fraction = b.time > a.time ? (time - a.time) / (b.time - a.time) : 0
            return a.value + (b.value - a.value) * fraction
        }

        private func nearest(_ samples: [Sample], at time: Double) -> Double {
            samples.min { abs($0.time - time) < abs($1.time - time) }?.value ?? 0
        }
    }

    static func length(_ range: ClosedRange<Double>) -> Double { range.upperBound - range.lowerBound }

    static func total(_ ranges: [ClosedRange<Double>]) -> Double { ranges.reduce(0) { $0 + length($1) } }

    static func clip(_ range: ClosedRange<Double>, to bounds: ClosedRange<Double>) -> ClosedRange<Double>? {
        let lower = max(range.lowerBound, bounds.lowerBound)
        let upper = min(range.upperBound, bounds.upperBound)
        return upper - lower > 0.05 ? lower...upper : nil
    }

    static func percentile(_ values: [Double], _ fraction: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[Int(Double(sorted.count - 1) * fraction)]
    }
}

// MARK: - Framing her

/// One look at the clip for the vertical window: the centre of her face
/// (or, without one, her upper body) across the frame, 0 (left) … 1 (right),
/// or nil when nobody was found.
public struct FramingSample: Equatable, Sendable {
    public var time: Double
    public var center: Double?

    public init(time: Double, center: Double?) {
        self.time = time
        self.center = center
    }
}

/// Where the 9:16 window sits over the clip: its centre across the source
/// frame (0…1) at source times. Between keys it moves in a straight line.
public struct FramingPath: Equatable, Sendable {
    public struct Key: Equatable, Sendable {
        public var time: Double
        public var center: Double

        public init(time: Double, center: Double) {
            self.time = time
            self.center = center
        }
    }

    public var keys: [Key]
    /// The window's width as a share of the source's width (1: all of it).
    public var windowWidth: Double

    public init(keys: [Key], windowWidth: Double) {
        self.keys = keys
        self.windowWidth = windowWidth
    }

    /// A plain centre crop.
    public static func centered(windowWidth: Double = 1) -> FramingPath {
        FramingPath(keys: [], windowWidth: windowWidth)
    }

    public var isCentered: Bool { keys.allSatisfy { abs($0.center - 0.5) < 1e-9 } }

    /// The window's centre at `time` (source seconds), always inside the frame.
    public func center(at time: Double) -> Double {
        let half = min(max(windowWidth, 0), 1) / 2
        guard let first = keys.first, let last = keys.last else { return 0.5 }
        let value: Double
        if time <= first.time {
            value = first.center
        } else if time >= last.time {
            value = last.center
        } else {
            var low = 0, high = keys.count - 1
            while high - low > 1 {
                let middle = (low + high) / 2
                if keys[middle].time <= time { low = middle } else { high = middle }
            }
            let a = keys[low], b = keys[high]
            let fraction = b.time > a.time ? (time - a.time) / (b.time - a.time) : 0
            value = a.center + (b.center - a.center) * fraction
        }
        return min(max(value, half), 1 - half)
    }
}

/// Keeps her in the middle of a vertical cut: the window follows where she
/// was found, but calmly. Small moves inside a dead zone don't move it, the
/// path is smoothed both ways (no lag) and its speed is limited, so it never
/// jitters or whips; when she's gone for a moment it holds, then drifts back
/// to the centre. Without anyone found, it's a plain centre crop.
public enum AutoFraming {
    /// The largest window of `aspect` (width / height) inside a source of
    /// `sourceWidth` × `sourceHeight`, as shares of its width and height.
    public static func window(sourceWidth: Double, sourceHeight: Double,
                              aspect: Double = SocialPlatform.frameAspect) -> (width: Double, height: Double) {
        guard sourceWidth > 0, sourceHeight > 0, aspect > 0 else { return (1, 1) }
        let sourceAspect = sourceWidth / sourceHeight
        return sourceAspect > aspect ? (aspect / sourceAspect, 1) : (1, sourceAspect / aspect)
    }

    public struct Settings: Sendable {
        /// Seconds between the path's keys.
        public var step = 0.2
        /// A lost subject keeps her place this long before the window drifts to the centre.
        public var hold = 1.5
        /// How far (share of the source's width) she may move before the window follows.
        public var deadZone = 0.05
        /// The smoothing's time constant, in seconds.
        public var smoothing = 0.45
        /// The window moves at most this share of the source's width per second.
        public var maxSpeed = 0.3

        public init() {}
    }

    public static func path(_ samples: [FramingSample], duration: Double, windowWidth: Double,
                            settings: Settings = Settings()) -> FramingPath {
        let width = min(max(windowWidth, 0), 1)
        let sorted = samples.sorted { $0.time < $1.time }
        guard width < 0.999, duration > 0, settings.step > 0, let firstSeen = sorted.first(where: { $0.center != nil }) else {
            return .centered(windowWidth: width)
        }
        let half = width / 2
        func inside(_ center: Double) -> Double { min(max(center, half), 1 - half) }

        // Where she is at `time`: the last look at or before it; after a look
        // that found nobody, where she was last seen for `hold`, then the middle.
        func target(at time: Double) -> Double {
            var low = 0, high = sorted.count
            while low < high {
                let middle = (low + high) / 2
                if sorted[middle].time <= time { low = middle + 1 } else { high = middle }
            }
            let index = low - 1
            guard index >= 0 else {
                return firstSeen.time - time <= settings.hold ? firstSeen.center ?? 0.5 : 0.5
            }
            if let center = sorted[index].center { return center }
            if let seen = sorted[...index].last(where: { $0.center != nil }), let center = seen.center,
               time - seen.time <= settings.hold {
                return center
            }
            return 0.5
        }

        let steps = max(1, Int((duration / settings.step).rounded(.up)))
        let times = (0...steps).map { min(Double($0) * settings.step, duration) }
        var anchor = inside(target(at: 0))
        var centers: [Double] = []
        for time in times {
            let goal = inside(target(at: time))
            if abs(goal - anchor) > settings.deadZone { anchor = goal }
            centers.append(anchor)
        }
        // Forward and backward, so the window doesn't trail behind her.
        let alpha = 1 - exp(-settings.step / max(settings.smoothing, 0.001))
        for index in centers.indices.dropFirst() {
            centers[index] = centers[index - 1] + alpha * (centers[index] - centers[index - 1])
        }
        for index in centers.indices.dropLast().reversed() {
            centers[index] = centers[index + 1] + alpha * (centers[index] - centers[index + 1])
        }
        let maxStep = settings.maxSpeed * settings.step
        for index in centers.indices.dropFirst() {
            centers[index] = centers[index - 1] + min(max(centers[index] - centers[index - 1], -maxStep), maxStep)
        }
        let keys = zip(times, centers).map { FramingPath.Key(time: $0, center: inside($1)) }
        return FramingPath(keys: keys, windowWidth: width)
    }
}

// MARK: - Crossfades

/// A short crossfade where the cut jumps ahead in the clip. The edited
/// timeline stays back to back: the crossfade borrows a moment from just
/// before the incoming part and just after the outgoing one (both cut
/// anyway), like the handles of a film edit, so trimming and captions map
/// exactly as with plain cuts.
public struct AutoEditTransition: Equatable, Sendable {
    /// Where the cut is on the edited timeline, in seconds.
    public var cut: Double
    /// Half the crossfade: it runs from `cut - half` to `cut + half`.
    public var half: Double
    /// End of the outgoing part and start of the incoming one, in source seconds.
    public var outgoingEnd: Double
    public var incomingStart: Double

    public init(cut: Double, half: Double, outgoingEnd: Double, incomingStart: Double) {
        self.cut = cut
        self.half = half
        self.outgoingEnd = outgoingEnd
        self.incomingStart = incomingStart
    }

    public var start: Double { cut - half }
    public var end: Double { cut + half }

    /// How far the picture has gone from the outgoing part to the incoming one, 0…1.
    public func progress(at time: Double) -> Double {
        guard half > 0 else { return time < cut ? 0 : 1 }
        return min(max((time - start) / (2 * half), 0), 1)
    }

    /// Source time of the borrowed frame at `time` on the edited timeline:
    /// the incoming part's lead-in before the cut, the outgoing part's
    /// run-out after it.
    public func handleTime(at time: Double) -> Double {
        time < cut ? incomingStart - (cut - time) : outgoingEnd + (time - cut)
    }
}

public enum AutoEditTimeline {
    public static let crossfade = 0.3
    /// Cuts that skip at least this much of the clip get a crossfade;
    /// shorter ones (a pause taken out) stay jump cuts.
    public static let jumpGap = 2.0

    /// Crossfades for the kept parts (source seconds, in order): where the
    /// gap between two parts is at least `jumpGap`, the clip has a moment to
    /// borrow on both sides, and both parts are long enough to hold one.
    public static func transitions(keeping ranges: [ClosedRange<Double>], sourceDuration: Double,
                                   crossfade: Double = AutoEditTimeline.crossfade,
                                   jumpGap: Double = AutoEditTimeline.jumpGap) -> [AutoEditTransition] {
        let half = crossfade / 2
        guard half > 0, ranges.count > 1 else { return [] }
        var transitions: [AutoEditTransition] = []
        var offset = 0.0
        for index in 0..<(ranges.count - 1) {
            let outgoing = ranges[index]
            let incoming = ranges[index + 1]
            offset += outgoing.upperBound - outgoing.lowerBound
            guard incoming.lowerBound - outgoing.upperBound >= max(jumpGap, crossfade),
                  outgoing.upperBound + half <= sourceDuration,
                  incoming.lowerBound - half >= 0,
                  outgoing.upperBound - outgoing.lowerBound >= crossfade + 0.1,
                  incoming.upperBound - incoming.lowerBound >= crossfade + 0.1 else { continue }
            transitions.append(AutoEditTransition(cut: offset, half: half, outgoingEnd: outgoing.upperBound,
                                                  incomingStart: incoming.lowerBound))
        }
        return transitions
    }
}

// MARK: - Words to post

/// The words she posts an Auto edit with: captions, their hashtags and, for
/// Shorts, a title.
public enum PostText {
    /// YouTube's limit on a title.
    public static let titleLimit = 100
    public static let maxHashtags = 5

    /// A caption without the hashtags it ends with, and those hashtags.
    public static func split(_ line: String) -> (text: String, hashtags: [String]) {
        var words = line.split(whereSeparator: \.isWhitespace).map(String.init)
        var tags: [String] = []
        while let last = words.last, let tag = hashtag(last) {
            tags.insert(tag, at: 0)
            words.removeLast()
        }
        return (words.joined(separator: " "), tags)
    }

    /// "#glow" from "#glow," — a # with letters, digits or underscores; nil otherwise.
    static func hashtag(_ token: String) -> String? {
        let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:…"))
        guard trimmed.first == "#" else { return nil }
        let body = trimmed.dropFirst()
        guard !body.isEmpty, body.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }
        return "#" + body
    }

    /// The hashtags the captions end with, then `extra`, each once (any
    /// case), at most `limit`.
    public static func hashtags(in lines: [String], adding extra: [String] = [], limit: Int = maxHashtags) -> [String] {
        let more = extra.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }.filter { !$0.isEmpty }.map { "#" + $0 }
        var seen = Set<String>()
        var tags: [String] = []
        for tag in lines.flatMap({ split($0).hashtags }) + more where tags.count < limit {
            if seen.insert(tag.lowercased()).inserted { tags.append(tag) }
        }
        return tags
    }

    /// A title from a caption: without its hashtags, at most `titleLimit`
    /// characters, ending on a whole word.
    public static func title(from line: String) -> String {
        Assist.cut(split(line).text, to: titleLimit)
    }

    /// What Copy puts on the clipboard: the caption, then on a new line the
    /// hashtags it doesn't already end with.
    public static func clipboard(caption: String, hashtags: [String]) -> String {
        let own = Set(split(caption).hashtags.map { $0.lowercased() })
        let more = hashtags.filter { !own.contains($0.lowercased()) }
        return more.isEmpty ? caption : caption + "\n" + more.joined(separator: " ")
    }
}

extension Assist {
    /// What the caption writer hears about an Auto edit: what she says in
    /// it, from its captions (cut to the contract's limit), when that passes
    /// the policy as caption words; otherwise a plain line. English, never shown.
    public static func videoCaptionHint(transcript: String) -> String {
        let words = cut(PromptBuilder.sanitize(transcript), to: AssistRequest.maxTextLength)
        if !words.isEmpty, ContentPolicy.evaluate(words, operation: AssistTask.captions.screeningOperation).isAllowed {
            return words
        }
        return "A short video to share with friends"
    }
}
