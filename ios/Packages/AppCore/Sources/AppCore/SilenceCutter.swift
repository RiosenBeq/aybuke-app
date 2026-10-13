import Foundation

/// "Auto-cut silences" for the video editor: finds the quiet stretches in a
/// clip's loudness and returns the parts worth keeping, like a jump cut.
/// The threshold adapts to each clip (a whisper vlog and a loud room both
/// work), and short pauses are kept so speech doesn't sound chopped.
public enum SilenceCutter {
    public struct Plan: Equatable, Sendable {
        /// Time ranges to keep, in seconds, in order.
        public let keep: [ClosedRange<Double>]
        public let duration: Double

        public var removedSeconds: Double {
            duration - keep.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
        }

        public var cutsSomething: Bool { removedSeconds > 0.05 }
    }

    /// - Parameters:
    ///   - levels: loudness per window in dBFS (silence ≈ -60, speech ≈ -20).
    ///   - window: length of each window in seconds.
    ///   - minSilence: quiet stretches shorter than this stay (natural pauses).
    ///   - padding: kept on each side of a cut, so words aren't clipped.
    public static func plan(levels: [Double], window: Double, minSilence: Double = 0.7, padding: Double = 0.15) -> Plan {
        let duration = Double(levels.count) * window
        let everything = Plan(keep: duration > 0 ? [0...duration] : [], duration: duration)
        guard levels.count >= 4, window > 0, let threshold = threshold(for: levels) else { return everything }

        // Quiet runs → cut ranges (shrunk by the padding).
        var cuts: [ClosedRange<Double>] = []
        var runStart: Int?
        // A loud sentinel at the end closes a trailing quiet run.
        for (index, level) in (levels + [Double.greatestFiniteMagnitude]).enumerated() {
            if level < threshold {
                if runStart == nil { runStart = index }
            } else if let start = runStart {
                let from = Double(start) * window
                let to = Double(index) * window
                if to - from >= minSilence {
                    // Leading and trailing silence can be cut right to the edge.
                    let cutFrom = start == 0 ? 0 : from + padding
                    let cutTo = index == levels.count ? duration : to - padding
                    if cutTo - cutFrom > 0.05 { cuts.append(cutFrom...cutTo) }
                }
                runStart = nil
            }
        }
        guard !cuts.isEmpty else { return everything }

        // Keep = the gaps between cuts; drop slivers.
        var keep: [ClosedRange<Double>] = []
        var cursor = 0.0
        for cut in cuts {
            if cut.lowerBound - cursor > 0.1 { keep.append(cursor...cut.lowerBound) }
            cursor = cut.upperBound
        }
        if duration - cursor > 0.1 { keep.append(cursor...duration) }
        // A clip that's all silence keeps everything rather than nothing.
        return keep.isEmpty ? everything : Plan(keep: keep, duration: duration)
    }

    /// Between the clip's noise floor and its speech level; nil when the clip
    /// has no clear quiet parts (music, constant noise).
    static func threshold(for levels: [Double]) -> Double? {
        let sorted = levels.sorted()
        let floor = sorted[Int(Double(sorted.count - 1) * 0.1)]
        let loud = sorted[Int(Double(sorted.count - 1) * 0.9)]
        guard loud - floor >= 10 else { return nil }
        return min(max(floor + (loud - floor) * 0.3, -55), -26)
    }
}
