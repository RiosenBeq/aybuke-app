import Foundation

// MARK: - Cues

/// One word of a caption and when it's said, for the Karaoke highlight.
public struct CaptionWord: Equatable, Hashable, Codable, Sendable {
    public var text: String
    public var start: Double
    public var end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// One caption on screen: its text from `start` to `end`, in seconds.
public struct CaptionCue: Identifiable, Equatable, Hashable, Codable, Sendable {
    public var id: UUID
    public var start: Double
    public var end: Double
    public var text: String
    /// Word times, when the recognizer gave them and the text still matches.
    public var words: [CaptionWord]?

    public init(id: UUID = UUID(), start: Double, end: Double, text: String, words: [CaptionWord]? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.words = words
    }

    public var isBlank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The word being said at `time`: each word stays lit until the next one
    /// starts. Nil without word times.
    public func activeWordIndex(at time: Double) -> Int? {
        guard let words, !words.isEmpty else { return nil }
        var index = 0
        for (position, word) in words.enumerated() where word.start <= time {
            index = position
        }
        return index
    }

    /// The cue with new text. Word times survive a fix that keeps the same
    /// number of words (a typo); other edits drop them, and Karaoke shows
    /// that cue like Pop.
    public func withText(_ newText: String) -> CaptionCue {
        var cue = self
        cue.text = newText
        guard let words else { return cue }
        let old = Self.tokens(text)
        let new = Self.tokens(newText)
        if old.count == words.count, new.count == words.count {
            cue.words = zip(new, words).map { CaptionWord(text: $0, start: $1.start, end: $1.end) }
        } else {
            cue.words = nil
        }
        return cue
    }

    /// UTF-16 ranges of the words in `text`, in order; nil when any is missing.
    public var wordRanges: [Range<Int>]? {
        guard let words, !words.isEmpty else { return nil }
        var ranges: [Range<Int>] = []
        var cursor = text.startIndex
        for word in words {
            let token = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty, cursor < text.endIndex,
                  let found = text.range(of: token, range: cursor..<text.endIndex) else { return nil }
            ranges.append(found.lowerBound.utf16Offset(in: text)..<found.upperBound.utf16Offset(in: text))
            cursor = found.upperBound
        }
        return ranges
    }

    static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }
}

// MARK: - Line breaking

/// Caption lines: about 32 characters each (CJK characters and emoji count
/// double), as few lines as fit, balanced so no line is a stub, and broken
/// after punctuation when that's nearly as even.
public enum CaptionLayout {
    public static let lineWidth = 32
    public static let maxLines = 2

    /// A run of text that stays on one line: a word, or one Han or kana
    /// character with the punctuation that clings to it.
    struct Atom {
        var range: Range<String.Index>
        var width: Int
        /// Separated from the atom before by a space (dropped at a break).
        var spaceBefore: Bool
        /// Ends with punctuation: a natural place for a break.
        var endsClause: Bool
    }

    /// The lines of `text` as UTF-16 ranges; the spaces at breaks are left out.
    public static func lineRanges(for text: String, width: Int = lineWidth) -> [Range<Int>] {
        let atoms = atoms(in: text)
        return partition(atoms, limit: width).map { line in
            atoms[line.lowerBound].range.lowerBound.utf16Offset(in: text)
                ..< atoms[line.upperBound - 1].range.upperBound.utf16Offset(in: text)
        }
    }

    public static func lines(for text: String, width: Int = lineWidth) -> [String] {
        let utf16 = text.utf16
        return lineRanges(for: text, width: width).map { range in
            let lower = utf16.index(utf16.startIndex, offsetBy: range.lowerBound)
            let upper = utf16.index(utf16.startIndex, offsetBy: range.upperBound)
            return String(text[lower..<upper])
        }
    }

    /// How many lines `text` needs.
    public static func lineCount(for text: String, width: Int = lineWidth) -> Int {
        let atoms = atoms(in: text)
        let widths = Widths(atoms)
        return widths.fewestLines(limit: width)
    }

    /// Display width: 1 per character, 2 for CJK characters and emoji.
    public static func width(of text: String) -> Int {
        text.reduce(0) { $0 + width(of: $1) }
    }

    static func width(of character: Character) -> Int {
        guard let scalar = character.unicodeScalars.first else { return 0 }
        if isWide(scalar) { return 2 }
        if scalar.properties.isEmojiPresentation || (character.unicodeScalars.count > 1 && scalar.properties.isEmoji) { return 2 }
        return 1
    }

    static func atoms(in text: String) -> [Atom] {
        var atoms: [Atom] = []
        var pendingSpace = false
        var previous: Character?
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if character.isWhitespace {
                pendingSpace = true
                previous = nil
                index = next
                continue
            }
            let joins: Bool
            if atoms.isEmpty || pendingSpace {
                joins = false
            } else if let previous {
                let breakable = breaksAnywhere(previous) || breaksAnywhere(character)
                joins = !breakable || noBreakBefore.contains(character) || noBreakAfter.contains(previous)
            } else {
                joins = false
            }
            if joins {
                atoms[atoms.count - 1].range = atoms[atoms.count - 1].range.lowerBound..<next
                atoms[atoms.count - 1].width += width(of: character)
            } else {
                atoms.append(Atom(range: index..<next, width: width(of: character), spaceBefore: pendingSpace && !atoms.isEmpty, endsClause: false))
            }
            atoms[atoms.count - 1].endsClause = clauseEnds.contains(character)
            pendingSpace = false
            previous = character
            index = next
        }
        return atoms
    }

    /// Prefix sums for line widths over a run of atoms.
    struct Widths {
        let sums: [Int]
        let spaces: [Int]

        init(_ atoms: [Atom]) {
            var sums = [0], spaces = [0]
            for atom in atoms {
                sums.append(sums[sums.count - 1] + atom.width)
                spaces.append(spaces[spaces.count - 1] + (atom.spaceBefore ? 1 : 0))
            }
            self.sums = sums
            self.spaces = spaces
        }

        var count: Int { sums.count - 1 }

        /// Width of atoms `i..<j` on one line (the space before `i` doesn't count).
        func line(_ i: Int, _ j: Int) -> Int {
            sums[j] - sums[i] + spaces[j] - spaces[min(i + 1, j)]
        }

        func fewestLines(limit: Int) -> Int {
            var lines = 0, i = 0
            while i < count {
                var j = i + 1
                while j < count, line(i, j + 1) <= limit { j += 1 }
                lines += 1
                i = j
            }
            return lines
        }
    }

    /// The fewest lines that fit, balanced: each line close to the average
    /// width, breaks after punctuation preferred, and the top line not wider
    /// than it must be. A word longer than a line gets a line of its own.
    static func partition(_ atoms: [Atom], limit: Int) -> [Range<Int>] {
        let widths = Widths(atoms)
        let m = widths.count
        guard m > 0 else { return [] }
        let lines = widths.fewestLines(limit: limit)
        guard lines > 1 else { return [0..<m] }
        let target = Double(widths.line(0, m) - (lines - 1)) / Double(lines)
        var cost = Array(repeating: Array(repeating: Double.infinity, count: m + 1), count: lines + 1)
        var from = Array(repeating: Array(repeating: 0, count: m + 1), count: lines + 1)
        cost[0][0] = 0
        for k in 1...lines {
            for j in k...m {
                for i in (k - 1)..<j where cost[k - 1][i] < .infinity {
                    let width = widths.line(i, j)
                    if width > limit, j - i > 1 { continue }
                    var total = cost[k - 1][i] + abs(Double(width) - target)
                    if j < m {
                        if !atoms[j - 1].endsClause { total += 6 }
                        if Double(width) > target { total += 0.5 }
                    }
                    if total < cost[k][j] {
                        cost[k][j] = total
                        from[k][j] = i
                    }
                }
            }
        }
        guard cost[lines][m] < .infinity else { return [0..<m] }
        var ranges: [Range<Int>] = []
        var end = m
        for k in stride(from: lines, to: 0, by: -1) {
            let start = from[k][end]
            ranges.insert(start..<end, at: 0)
            end = start
        }
        return ranges
    }

    /// Chinese and Japanese break between characters; Korean, like Latin
    /// scripts, only at spaces.
    static func breaksAnywhere(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3040...0x30FF, 0x31F0...0x31FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
             0x3000...0x303F, 0xFF00...0xFF60, 0x20000...0x2FA1F:
            return true
        default:
            return false
        }
    }

    static func isWide(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x115F, 0x2E80...0x303E, 0x3040...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
             0xA960...0xA97F, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60,
             0xFFE0...0xFFE6, 0x20000...0x2FA1F:
            return true
        default:
            return false
        }
    }

    /// Never at the start of a line (kinsoku): closing marks and small kana.
    static let noBreakBefore: Set<Character> = Set("、。，．・：；？！）」』】〉》〕］｝ー…‥ぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮヵヶ々,.!?;:)]}%’”")
    /// Never at the end of a line: opening marks.
    static let noBreakAfter: Set<Character> = Set("（「『【〈《〔［｛([{‘“¿¡")
    static let clauseEnds: Set<Character> = Set(",.!?;:…、。，．！？；：")
}

// MARK: - From speech to cues

/// A word as the recognizer gave it, with the spaces before it, so a
/// phrase's words concatenate to its text.
public struct TranscriptWord: Equatable, Sendable {
    public var text: String
    public var start: Double
    public var end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// A piece of a recognizer result: a word with its time, or spaces and
/// punctuation that may have none.
public struct TranscriptPiece: Equatable, Sendable {
    public var text: String
    public var start: Double?
    public var end: Double?

    public init(text: String, start: Double? = nil, end: Double? = nil) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// One recognizer result (about a sentence) as timed words.
public struct TranscriptPhrase: Equatable, Sendable {
    public var words: [TranscriptWord]
    /// False when the recognizer gave no word times and they were estimated.
    public var hasWordTimes: Bool

    public init(words: [TranscriptWord]) {
        self.words = words
        hasWordTimes = true
    }

    /// From pieces that concatenate to the result's text. Punctuation joins
    /// the word before it and spaces the word after, so "today" + ". " +
    /// "I" reads "today." and " I".
    public init(pieces: [TranscriptPiece]) {
        var words: [TranscriptWord] = []
        var lead = ""
        for piece in pieces {
            let isWord = piece.text.contains { $0.isLetter || $0.isNumber }
            if isWord, let start = piece.start, let end = piece.end {
                words.append(TranscriptWord(text: lead + piece.text, start: start, end: max(end, start)))
                lead = ""
            } else if words.isEmpty || !lead.isEmpty {
                lead += piece.text
            } else if let space = piece.text.firstIndex(where: \.isWhitespace) {
                words[words.count - 1].text += piece.text[..<space]
                lead = String(piece.text[space...])
            } else {
                words[words.count - 1].text += piece.text
            }
        }
        if !lead.isEmpty, !words.isEmpty { words[words.count - 1].text += lead }
        self.init(words: words)
    }

    /// From a transcription and its timed words as UTF-16 ranges, the way
    /// SFSpeechRecognizer reports them.
    public init(text: String, segments: [(range: Range<Int>, start: Double, end: Double)]) {
        let utf16 = text.utf16
        func slice(_ lower: Int, _ upper: Int) -> String {
            let from = utf16.index(utf16.startIndex, offsetBy: lower)
            let to = utf16.index(utf16.startIndex, offsetBy: upper)
            return String(utf16[from..<to]) ?? ""
        }
        var pieces: [TranscriptPiece] = []
        var cursor = 0
        for segment in segments.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
            guard segment.range.lowerBound >= cursor, segment.range.upperBound <= utf16.count, !segment.range.isEmpty else { continue }
            if segment.range.lowerBound > cursor { pieces.append(TranscriptPiece(text: slice(cursor, segment.range.lowerBound))) }
            pieces.append(TranscriptPiece(text: slice(segment.range.lowerBound, segment.range.upperBound), start: segment.start, end: segment.end))
            cursor = segment.range.upperBound
        }
        if cursor < utf16.count { pieces.append(TranscriptPiece(text: slice(cursor, utf16.count))) }
        self.init(pieces: pieces)
    }

    /// Text without word times: words spread over the span by their width.
    public init(text: String, start: Double, end: Double) {
        let atoms = CaptionLayout.atoms(in: text)
        let total = Double(max(atoms.reduce(0) { $0 + $1.width }, 1))
        var words: [TranscriptWord] = []
        var time = start
        for atom in atoms {
            let length = (end - start) * Double(atom.width) / total
            words.append(TranscriptWord(text: (atom.spaceBefore ? " " : "") + text[atom.range], start: time, end: time + length))
            time += length
        }
        self.words = words
        hasWordTimes = false
    }
}

/// Splits recognized speech into readable captions: up to ~7 words, ~3.5 s
/// and two lines each, a new caption after a pause, and breaks placed after
/// punctuation where possible.
public enum CaptionChunker {
    public struct Limits: Sendable {
        public var maxWords = 7
        public var maxDuration = 3.5
        public var lineWidth = CaptionLayout.lineWidth
        public var maxLines = CaptionLayout.maxLines
        /// A pause this long always starts a new caption.
        public var pause = 0.8
        /// Shortest time a caption stays up, and extra reading time after the words.
        public var minimumDuration = 0.8
        public var linger = 0.3
        /// Smaller gaps between captions are closed, so they don't blink.
        public var bridge = 0.35

        public init() {}
    }

    public static func cues(from phrases: [TranscriptPhrase], limits: Limits = Limits()) -> [CaptionCue] {
        var cues: [CaptionCue] = []
        for phrase in phrases {
            let words = phrase.words.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            var group: [TranscriptWord] = []
            for word in words {
                if let last = group.last, word.start - last.end >= limits.pause {
                    cues += split(group, limits: limits).map { cue(from: $0, timed: phrase.hasWordTimes) }
                    group = []
                }
                group.append(word)
            }
            cues += split(group, limits: limits).map { cue(from: $0, timed: phrase.hasWordTimes) }
        }
        return settle(cues.sorted { $0.start < $1.start }, limits: limits)
    }

    static func cue(from words: ArraySlice<TranscriptWord>, timed: Bool) -> CaptionCue {
        let text = words.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        let start = words.first?.start ?? 0
        let end = max(words.last?.end ?? start, start)
        let timings = words.map { CaptionWord(text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines), start: $0.start, end: $0.end) }
        return CaptionCue(start: start, end: end, text: text, words: timed ? timings : nil)
    }

    /// The best split of one stretch of speech: fewest, fullest captions,
    /// with breaks after punctuation or a short pause where possible.
    static func split(_ words: [TranscriptWord], limits: Limits) -> [ArraySlice<TranscriptWord>] {
        let n = words.count
        guard n > 0 else { return [] }
        var best = Array(repeating: Double.infinity, count: n + 1)
        var from = Array(repeating: 0, count: n + 1)
        best[0] = 0
        for j in 1...n {
            // Longer chunks only get worse, so stop at the first that doesn't fit.
            for i in stride(from: j - 1, through: 0, by: -1) where best[i] < .infinity {
                let chunk = words[i..<j]
                if j - i > 1, !fits(chunk, limits: limits) { break }
                var cost = best[i] + 0.5
                if j < n {
                    if endsSentence(words[j - 1]) {
                        cost += 0
                    } else if endsClause(words[j - 1]) {
                        cost += 0.3
                    } else if words[j].start - words[j - 1].end >= 0.25 {
                        cost += 0.5
                    } else {
                        cost += 1.2
                    }
                }
                // A sentence ending inside a caption, worst with a stub after it.
                if let inner = chunk.dropLast().lastIndex(where: endsSentence) {
                    cost += j - 1 - inner < 3 ? 0.8 : 0.3
                }
                if n > 2 { cost += j - i == 1 ? 0.6 : (j - i == 2 ? 0.2 : 0) }
                if cost < best[j] {
                    best[j] = cost
                    from[j] = i
                }
            }
        }
        var chunks: [ArraySlice<TranscriptWord>] = []
        var end = n
        while end > 0 {
            let start = from[end]
            chunks.insert(words[start..<end], at: 0)
            end = start
        }
        return chunks
    }

    static func endsSentence(_ word: TranscriptWord) -> Bool {
        guard let last = word.text.trimmingCharacters(in: .whitespacesAndNewlines).last else { return false }
        return ".!?…。！？".contains(last)
    }

    static func endsClause(_ word: TranscriptWord) -> Bool {
        guard let last = word.text.trimmingCharacters(in: .whitespacesAndNewlines).last else { return false }
        return CaptionLayout.clauseEnds.contains(last)
    }

    static func fits(_ chunk: ArraySlice<TranscriptWord>, limits: Limits) -> Bool {
        guard let first = chunk.first, let last = chunk.last else { return true }
        guard last.end - first.start <= limits.maxDuration else { return false }
        let text = chunk.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        // Words between spaces: Chinese and Japanese are limited by width instead.
        guard CaptionCue.tokens(text).count <= limits.maxWords else { return false }
        return CaptionLayout.lineCount(for: text, width: limits.lineWidth) <= limits.maxLines
    }

    /// Reading time: each caption stays at least `minimumDuration` and a
    /// little past its last word, small gaps close, and none overlap.
    static func settle(_ cues: [CaptionCue], limits: Limits) -> [CaptionCue] {
        var result = cues
        for index in result.indices {
            let next = index + 1 < result.count ? result[index + 1].start : .infinity
            var end = max(result[index].end + limits.linger, result[index].start + limits.minimumDuration)
            if next - end < limits.bridge { end = next }
            result[index].end = max(min(end, next), result[index].start + 0.05)
        }
        return result
    }
}

// MARK: - Edited timeline

/// Captions are made from the whole clip; trimming and "Auto-cut silences"
/// change which parts play. These map times through the kept parts (in
/// source seconds, sorted, not overlapping).
public enum CaptionTimeline {
    /// Captions shorter than this after cutting are dropped.
    public static let shortestKept = 0.1

    /// When `source` plays in the edited video; nil when it was cut.
    public static func outputTime(_ source: Double, keeping ranges: [ClosedRange<Double>]) -> Double? {
        var offset = 0.0
        for range in ranges {
            if range.contains(source) { return offset + source - range.lowerBound }
            offset += range.upperBound - range.lowerBound
        }
        return nil
    }

    /// Like `outputTime`, but a cut moment lands where the cut is.
    static func collapsedTime(_ source: Double, keeping ranges: [ClosedRange<Double>]) -> Double {
        var offset = 0.0
        for range in ranges {
            if source < range.lowerBound { return offset }
            if source <= range.upperBound { return offset + source - range.lowerBound }
            offset += range.upperBound - range.lowerBound
        }
        return offset
    }

    /// The source time that plays at `output` in the edited video.
    public static func sourceTime(_ output: Double, keeping ranges: [ClosedRange<Double>]) -> Double {
        var offset = 0.0
        for range in ranges {
            let length = range.upperBound - range.lowerBound
            if output < offset + length { return range.lowerBound + max(0, output - offset) }
            offset += length
        }
        return ranges.last?.upperBound ?? output
    }

    /// Cues on the edited timeline, sorted: a cue inside a removed part is
    /// dropped, one across a cut keeps the parts that play (they're
    /// back to back once the cut is closed), and word times move along.
    public static func remap(_ cues: [CaptionCue], keeping ranges: [ClosedRange<Double>]) -> [CaptionCue] {
        var result: [CaptionCue] = []
        for cue in cues where !cue.isBlank {
            var offset = 0.0
            var start: Double?
            var end: Double?
            for range in ranges {
                let lower = max(cue.start, range.lowerBound)
                let upper = min(cue.end, range.upperBound)
                if upper > lower {
                    if start == nil { start = offset + lower - range.lowerBound }
                    end = offset + upper - range.lowerBound
                }
                offset += range.upperBound - range.lowerBound
            }
            guard let start, let end, end - start >= shortestKept else { continue }
            var moved = cue
            moved.start = start
            moved.end = end
            moved.words = cue.words?.map { word in
                CaptionWord(text: word.text,
                            start: min(max(collapsedTime(word.start, keeping: ranges), start), end),
                            end: min(max(collapsedTime(word.end, keeping: ranges), start), end))
            }
            result.append(moved)
        }
        return result.sorted { $0.start < $1.start }
    }

    /// The cue showing at `time` in cues sorted by start; when two overlap,
    /// the later one.
    public static func index(at time: Double, in cues: [CaptionCue]) -> Int? {
        var low = 0, high = cues.count
        while low < high {
            let middle = (low + high) / 2
            if cues[middle].start <= time { low = middle + 1 } else { high = middle }
        }
        var index = low - 1
        while index >= 0, index >= low - 4 {
            if cues[index].end > time, cues[index].start <= time { return index }
            index -= 1
        }
        return nil
    }
}

// MARK: - SubRip

/// "Copy captions": the captions as SubRip (.srt) text, which video apps
/// and sites import.
public enum CaptionSRT {
    public static func text(for cues: [CaptionCue]) -> String {
        cues.filter { !$0.isBlank }
            .sorted { $0.start < $1.start }
            .enumerated()
            .map { index, cue in
                let lines = CaptionLayout.lines(for: cue.text).joined(separator: "\n")
                return "\(index + 1)\n\(timestamp(cue.start)) --> \(timestamp(cue.end))\n\(lines)\n"
            }
            .joined(separator: "\n")
    }

    static func timestamp(_ seconds: Double) -> String {
        let total = Int((max(0, seconds) * 1000).rounded())
        return String(format: "%02d:%02d:%02d,%03d", total / 3_600_000, total / 60000 % 60, total / 1000 % 60, total % 1000)
    }
}

// MARK: - Language

/// Picks a recognizer language for the app or device language.
public enum CaptionLanguage {
    /// Regions to try when the preferred language names none.
    static let usualRegion = [
        "en": "US", "es": "ES", "pt": "BR", "fr": "FR", "de": "DE", "it": "IT", "ru": "RU",
        "tr": "TR", "ja": "JP", "ko": "KR", "id": "ID", "zh": "CN",
    ]

    struct Parts: Equatable {
        var language: String
        var script: String?
        var region: String?
    }

    /// "pt-BR", "zh_Hans_CN" or "en" → language, script and region. Chinese
    /// gets its script from the region when it names none.
    static func parts(_ identifier: String) -> Parts {
        let pieces = identifier.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
        var parts = Parts(language: pieces.first?.lowercased() ?? "")
        for piece in pieces.dropFirst() {
            if piece.count == 4, piece.allSatisfy(\.isLetter) {
                parts.script = piece.prefix(1).uppercased() + piece.dropFirst().lowercased()
            } else if parts.region == nil, piece.count == 2 || (piece.count == 3 && piece.allSatisfy(\.isNumber)) {
                parts.region = piece.uppercased()
            }
        }
        if parts.language == "zh", parts.script == nil {
            parts.script = ["TW", "HK", "MO"].contains(parts.region ?? "") ? "Hant" : "Hans"
        }
        return parts
    }

    /// The best of `available` for the first of `preferred` that has a
    /// match: the same language (and script, for Chinese), in the preferred
    /// region, else `region`, else the usual one, else any.
    public static func bestMatch(preferred: [String], available: [String], region: String?) -> String? {
        let candidates = available.map { ($0, parts($0)) }
        for identifier in preferred {
            let wanted = parts(identifier)
            let same = candidates.filter { $0.1.language == wanted.language && ($0.1.script == wanted.script || wanted.language != "zh") }
            guard !same.isEmpty else { continue }
            let regions = [wanted.region, region?.uppercased(), usualRegion[wanted.language]].compactMap { $0 }
            for wantedRegion in regions {
                if let match = same.first(where: { $0.1.region == wantedRegion }) { return match.0 }
            }
            return same.map(\.0).sorted().first
        }
        return nil
    }
}
