import Foundation

/// Pure maths behind the camcorder and film-still overlays, kept here so it
/// runs in the Linux tests (the drawing itself lives in the app).
public enum CamcorderClock {
    /// "HH:MM:SS:FF" for a time on the output timeline.
    public static func timecode(seconds: Double, fps: Double) -> String {
        let rate = max(1, Int(fps.rounded()))
        let time = seconds.isFinite ? max(0, seconds) : 0
        let whole = Int(time)
        let frame = min(rate - 1, Int(((time - Double(whole)) * Double(rate)).rounded(.down)))
        return String(format: "%02d:%02d:%02d:%02d", whole / 3600, whole / 60 % 60, whole % 60, frame)
    }

    /// The REC dot blinks at 1 Hz: on for the first half of every second.
    public static func isRecDotVisible(at seconds: Double) -> Bool {
        guard seconds.isFinite else { return true }
        return Int((max(0, seconds) * 2).rounded(.down)) % 2 == 0
    }

    /// Video tracks that don't report a frame rate count at 30 fps.
    public static func frameRate(_ nominal: Double) -> Double {
        nominal.isFinite && nominal >= 1 ? nominal : 30
    }
}

public enum Letterbox {
    /// Frames at least this wide get true 2.39:1 cinema bars.
    public static let wideAspect = 1.5
    /// Portrait and square frames get thinner bars so most of the picture stays.
    public static let tallBarFraction = 0.11

    /// Height of each of the two bars (top and bottom), in the frame's units.
    public static func barHeight(width: Double, height: Double) -> Double {
        guard width > 0, height > 0 else { return 0 }
        if width / height >= wideAspect {
            return max(0, (height - width / 2.39) / 2)
        }
        return height * tallBarFraction
    }

    /// Share of the frame's height left visible between the bars.
    public static func visibleFraction(width: Double, height: Double) -> Double {
        guard height > 0 else { return 0 }
        return 1 - 2 * barHeight(width: width, height: height) / height
    }
}

public enum FilmSubtitle {
    /// One short line, like a real subtitle.
    public static let maxLength = 60

    /// Trims, joins lines and caps the length of what she typed.
    public static func clean(_ text: String) -> String {
        let oneLine = text.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return String(oneLine.prefix(maxLength))
    }
}
