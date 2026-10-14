import Foundation

/// Block-level structure of the bundled legal documents (legal/*.md). Only
/// the small Markdown subset those files use: headings, paragraphs, bullet
/// and numbered lists, block quotes and rules. Inline styling (bold, italics,
/// links) stays in the text and is rendered by the app.
public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(String)
    case numbered(marker: String, text: String)
    case quote([MarkdownBlock])
    case rule

    public static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph.removeAll()
        }
        func flushQuote() {
            guard !quote.isEmpty else { return }
            blocks.append(.quote(parse(quote.joined(separator: "\n"))))
            quote.removeAll()
        }

        for rawLine in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix(">") {
                flushParagraph()
                quote.append(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }
            flushQuote()

            if line.isEmpty {
                flushParagraph()
            } else if let heading = Self.heading(line) {
                flushParagraph()
                blocks.append(heading)
            } else if line == "---" || line == "***" || line == "___" {
                flushParagraph()
                blocks.append(.rule)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                blocks.append(.bullet(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)))
            } else if let numbered = Self.numbered(line) {
                flushParagraph()
                blocks.append(numbered)
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        flushQuote()
        return blocks
    }

    private static func heading(_ line: String) -> MarkdownBlock? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return .heading(level: hashes, text: String(line.dropFirst(hashes + 1)).trimmingCharacters(in: .whitespaces))
    }

    private static func numbered(_ line: String) -> MarkdownBlock? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return .numbered(marker: "\(digits).", text: String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces))
    }
}
