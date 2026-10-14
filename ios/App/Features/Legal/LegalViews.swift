import SwiftUI
import AppCore

/// Legal documents bundled with the app (generated from legal/*.md by
/// scripts/build-legal.py), readable offline in English or Turkish.
enum LegalDocument: String, CaseIterable, Identifiable, Hashable {
    case terms
    case privacy
    case acceptableUse
    case kvkk

    var id: String { rawValue }

    func title(in language: LegalLanguage) -> String {
        switch (self, language) {
        case (.terms, .en): return String(localized: "Terms of Use")
        case (.terms, .tr): return "Kullanım Koşulları"
        case (.privacy, .en): return String(localized: "Privacy Policy")
        case (.privacy, .tr): return "Gizlilik Politikası"
        case (.acceptableUse, .en): return String(localized: "Acceptable Use Policy")
        case (.acceptableUse, .tr): return "Kabul Edilebilir Kullanım"
        case (.kvkk, _): return "KVKK Aydınlatma Metni"
        }
    }

    var symbolName: String {
        switch self {
        case .terms: return "doc.text"
        case .privacy: return "hand.raised"
        case .acceptableUse: return "checkmark.shield"
        case .kvkk: return "building.columns"
        }
    }

    /// Bundle resource name; the KVKK notice exists in Turkish only.
    func resourceName(in language: LegalLanguage) -> String {
        switch (self, language) {
        case (.terms, .en): return "terms-of-use"
        case (.terms, .tr): return "kullanim-kosullari"
        case (.privacy, .en): return "privacy-policy"
        case (.privacy, .tr): return "gizlilik-politikasi"
        case (.acceptableUse, .en): return "acceptable-use-policy"
        case (.acceptableUse, .tr): return "kabul-edilebilir-kullanim-politikasi"
        case (.kvkk, _): return "kvkk-aydinlatma-metni"
        }
    }

    var languages: [LegalLanguage] { self == .kvkk ? [.tr] : LegalLanguage.allCases }

    /// In-document links between policies use this scheme (see build-legal.py).
    static let linkScheme = "glowlit-legal"

    /// `glowlit-legal://privacy` → `.privacy` (hosts may arrive lowercased).
    init?(link url: URL) {
        guard url.scheme?.lowercased() == Self.linkScheme, let host = url.host?.lowercased(),
              let document = Self.allCases.first(where: { $0.rawValue.lowercased() == host }) else { return nil }
        self = document
    }
}

enum LegalLanguage: String, CaseIterable, Identifiable {
    case en, tr

    var id: String { rawValue }
    var label: String { self == .en ? (Locale.current.localizedString(forLanguageCode: "en") ?? "English") : "Türkçe" }

    static var preferred: LegalLanguage {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("tr") == true ? .tr : .en
    }
}

/// Renders one bundled document. Works pushed in a NavigationStack or inside
/// `LegalSheet`; links to other policies push them.
struct LegalDocumentView: View {
    let document: LegalDocument
    @State private var language: LegalLanguage
    @State private var linked: LegalDocument?
    @Environment(\.openURL) private var openURL

    init(document: LegalDocument, language: LegalLanguage = .preferred) {
        self.document = document
        _language = State(initialValue: document.languages.contains(language) ? language : document.languages[0])
    }

    private var blocks: [MarkdownBlock] {
        guard let url = Bundle.main.url(forResource: document.resourceName(in: language), withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return MarkdownBlock.parse(text)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                let blocks = blocks
                if blocks.isEmpty {
                    Text("This document couldn't be loaded. Please contact support.")
                        .foregroundStyle(Palette.textSecondary)
                }
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    MarkdownBlockView(block: block)
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle(document.title(in: language))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if document.languages.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Language", selection: $language) {
                            ForEach(document.languages) { Text($0.label).tag($0) }
                        }
                    } label: {
                        Label(language.rawValue.uppercased(), systemImage: "globe")
                            .labelStyle(.titleAndIcon)
                    }
                    .accessibilityLabel("Language")
                }
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            if let target = LegalDocument(link: url) {
                linked = target
                return .handled
            }
            return .systemAction(url)
        })
        .navigationDestination(item: $linked) { target in
            LegalDocumentView(document: target, language: language)
        }
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(level == 1 ? .screenTitle : level == 2 ? .sectionTitle : .cardTitle)
                .foregroundStyle(Palette.textPrimary)
                .padding(.top, level == 1 ? 0 : 10)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            Text(inline(text))
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let text):
            listRow(marker: "•", text: text)
        case .numbered(let marker, let text):
            listRow(marker: marker, text: text)
        case .quote(let blocks):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    MarkdownBlockView(block: block)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.primary.opacity(0.35), in: .card)
            .overlay(
                RoundedRectangle.card
                    .strokeBorder(Palette.stroke, lineWidth: 1)
            )
        case .rule:
            Rectangle().fill(Palette.stroke).frame(height: 1).padding(.vertical, 6)
        }
    }

    private func listRow(marker: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(marker)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Palette.textPrimary)
                .frame(minWidth: 14, alignment: .leading)
            Text(inline(text))
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func inline(_ text: String) -> AttributedString {
        var string = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        for run in string.runs where run.link != nil {
            string[run.range].foregroundColor = Palette.accent
            string[run.range].underlineStyle = .single
        }
        return string
    }
}

/// A legal document presented modally (from onboarding, the paywall or the
/// AI consent screen).
struct LegalSheet: View {
    let document: LegalDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LegalDocumentView(document: document)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
        }
        .tint(Palette.accent)
    }
}

extension View {
    func legalSheet(_ document: Binding<LegalDocument?>) -> some View {
        sheet(item: document) { LegalSheet(document: $0) }
    }
}

/// Settings › Legal: every policy plus open-source notices.
struct LegalCenterView: View {
    private let language = LegalLanguage.preferred

    var body: some View {
        List {
            Section {
                ForEach(LegalDocument.allCases) { document in
                    NavigationLink {
                        LegalDocumentView(document: document, language: language)
                    } label: {
                        Label(document.title(in: language), systemImage: document.symbolName)
                    }
                }
            } footer: {
                Text("Available in English and Turkish. The KVKK notice applies to people in Türkiye.")
            }
            .listRowBackground(Palette.surface)
            Section {
                NavigationLink("Acknowledgements") { AcknowledgementsView() }
            }
            .listRowBackground(Palette.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Legal")
        .navigationBarTitleDisplayMode(.inline)
    }
}
