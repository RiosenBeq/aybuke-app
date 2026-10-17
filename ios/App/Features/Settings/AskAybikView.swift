import SwiftUI
import AppCore

/// Settings › Help: Ask Aybik. She asks how something in the app works, and
/// Aybik answers from the server's facts about the app when writing help is
/// on (`AppModel.askAybik`); otherwise, or when it can't, the closest common
/// questions answer on the device. Under 13 only the common questions show
/// (the app never asks the server). Nothing is stored: the question and the
/// answer last as long as the screen.
struct AskAybikView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var question = ""
    /// The question the shown outcome answers.
    @State private var asked = ""
    @State private var outcome: HelpOutcome?
    @State private var asking: Task<Void, Never>?
    /// The wait has lasted long enough to show a placeholder answer.
    @State private var showsWriting = false
    @FocusState private var isFocused: Bool

    /// Long enough for a question, short of the server's 400.
    private static let maxLength = 300
    /// Example questions under the field.
    private static let examples = ["credits", "polls", "cancel", "training"]

    private var isAsking: Bool { asking != nil }

    private var canAsk: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isAsking
    }

    private var topics: [HelpTopic] { HelpTopic.topics(cloudAI: app.allowsCloudAI) }

    var body: some View {
        List {
            if app.allowsCloudAI {
                askSection
                if isAsking {
                    if showsWriting { writingSection }
                } else if let outcome {
                    answerSection(outcome)
                }
            }
            commonQuestions
            supportSection
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle(app.allowsCloudAI ? Text("Ask Aybik", comment: "Settings › Help: the screen where she asks the app's AI helper about the app. Aybik is the app's AI helper: keep the name Aybik.")
                                           : Text("Common questions", comment: "Settings › Help: the list of common questions about the app"))
        .navigationBarTitleDisplayMode(.inline)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : Motion.appear, value: outcome)
        .animation(.easeInOut(duration: 0.2), value: showsWriting)
        // A placeholder answer only for a wait worth showing: the questions on the device answer at once.
        .task(id: isAsking) {
            guard isAsking else { return showsWriting = false }
            try? await Task.sleep(for: .milliseconds(250))
            if !Task.isCancelled { showsWriting = true }
        }
        // Nothing waits for an answer she left.
        .onDisappear(perform: cancel)
        #if DEBUG
        // Screenshot QA: -GLAskAybik "<question>" types it and asks once.
        .task {
            guard ScreenshotScene.current != nil, outcome == nil,
                  let words = UserDefaults.standard.string(forKey: "GLAskAybik"), words.lowercased() != "yes" else { return }
            question = words
            ask()
        }
        #endif
    }

    // MARK: Asking

    private var askSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text(styled: LocalizedStringResource("Ask *Aybik*", comment: "Settings › Help › Ask Aybik: the title; the words between asterisks are set in the accent font. Aybik is the app's AI helper: keep the name Aybik."), size: 27)
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("Ask how something in \(Brand.name) works: credits, Pro, polls, privacy or a tool.",
                     comment: "Settings › Help › Ask Aybik: the line under the title. The placeholder is the app's name.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                field
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(Self.examples.compactMap { id in topics.first { $0.id == id } }) { topic in
                        SelectableChip(verbatim: L10n.core(topic.question), isSelected: false) {
                            Haptics.selection()
                            cancel()
                            question = L10n.core(topic.question)
                            ask()
                        }
                        .accessibilityHint(Text("Asks this question", comment: "Accessibility hint of an example question in Ask Aybik"))
                    }
                }
                (app.usesCloudWriter
                     ? Text("Aybik, our AI helper, gets only your question. The app doesn't keep it.",
                            comment: "Settings › Help › Ask Aybik: what the app's AI helper receives. Aybik is the app's AI helper: keep the name Aybik.")
                     : Text("Aybik can't answer right now. The common questions below answer on your device.",
                            comment: "Settings › Help › Ask Aybik when the AI helper is off (no cloud AI opt-in or account yet, offline or paused). Aybik is the app's AI helper: keep the name Aybik."))
                    .font(.legibleCaption)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 6)
        }
        .listRowBackground(Palette.surface)
    }

    private var field: some View {
        HStack(alignment: .center, spacing: 6) {
            TextField(text: $question, axis: .vertical) {
                Text("Type your question", comment: "Settings › Help › Ask Aybik: the placeholder of the question field")
            }
            .lineLimit(1...4)
            .font(.subheadline)
            .foregroundStyle(Palette.textPrimary)
            .focused($isFocused)
            .submitLabel(.send)
            .padding(.leading, 14)
            .padding(.vertical, 11)
            .accessibilityLabel(Text("Type your question", comment: "Settings › Help › Ask Aybik: the placeholder of the question field"))
            .onChange(of: question) { _, newText in
                // A multi-line field turns Send (Return) into a newline, so a trailing one asks.
                var cleaned = newText
                let pressedSend = cleaned.hasSuffix("\n")
                if cleaned.contains("\n") {
                    cleaned = cleaned.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
                }
                if cleaned.count > Self.maxLength { cleaned = String(cleaned.prefix(Self.maxLength)) }
                if cleaned != newText { question = cleaned }
                if pressedSend {
                    ask()
                } else if isAsking, cleaned != asked {
                    // She's changing the question: the answer to the old one isn't wanted.
                    cancel()
                }
            }
            .onSubmit(ask)
            Button(action: ask) {
                ZStack {
                    if isAsking {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Palette.onAccent)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.subheadline.weight(.bold))
                    }
                }
                .foregroundStyle(canAsk || isAsking ? Palette.onAccent : Palette.textTertiary)
                .frame(width: 34, height: 34)
                .background(canAsk || isAsking ? Palette.accent : Palette.strokeStrong, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Circle())
            }
            .buttonStyle(.pressable)
            .disabled(!canAsk)
            .accessibilityLabel(Text("Ask", comment: "Settings › Help › Ask Aybik: the button that sends her question"))
            .accessibilityValue(isAsking ? Text("Writing…") : Text(verbatim: ""))
            .macHelp(Text("Ask", comment: "Settings › Help › Ask Aybik: the button that sends her question"))
            .padding(.trailing, 2)
        }
        .background(Palette.background, in: .card)
        .overlay(
            RoundedRectangle.card
                .strokeBorder(isFocused ? Palette.accent : Palette.strokeStrong, lineWidth: isFocused ? 1.5 : 1)
        )
    }

    private func ask() {
        guard canAsk else { return }
        isFocused = false
        let words = question.trimmingCharacters(in: .whitespacesAndNewlines)
        asked = question
        asking = Task {
            let found = await app.askAybik(words)
            guard !Task.isCancelled else { return }
            if case .blocked = found { Haptics.error() } else { Haptics.success() }
            outcome = found
            asking = nil
            AccessibilityNotification.Announcement(announcement(for: found)).post()
        }
    }

    /// What VoiceOver says when the outcome arrives: focus stays on Ask, so
    /// she hears the answer, the refusal or the closest questions.
    private func announcement(for outcome: HelpOutcome) -> String {
        switch outcome {
        case .answer(let answer, _):
            return answer
        case .blocked(let message):
            return message
        case .topics(let closest) where closest.isEmpty:
            return app.usesCloudWriter
                ? String(localized: "Aybik can't answer right now, and none of the common questions match. Try the list below or Help & Support.",
                         comment: "Settings › Help › Ask Aybik: the AI helper didn't answer and nothing on the device matched her question. Aybik is the app's AI helper: keep the name Aybik.")
                : String(localized: "None of the common questions match. Try the list below or Help & Support.",
                         comment: "Settings › Help › Ask Aybik: nothing on the device matched her question (the AI helper is off)")
        case .topics(let closest):
            let questions = closest.map { L10n.core($0.question) }.formatted(.list(type: .and))
            if app.usesCloudWriter {
                let header = String(localized: "Aybik can't answer right now. These might help:",
                                    comment: "Settings › Help › Ask Aybik: the AI helper didn't answer; the closest common questions follow. Aybik is the app's AI helper: keep the name Aybik.")
                return "\(header) \(questions)"
            }
            return String(localized: "Closest answers: \(questions)",
                          comment: "VoiceOver, Settings › Help › Ask Aybik: the common questions closest to hers, found on the device, as a list")
        }
    }

    private func cancel() {
        asking?.cancel()
        asking = nil
    }

    // MARK: The answer

    /// Lines shaped like an answer, glinting while Aybik writes it.
    private var writingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text(verbatim: "Aybik")
                        .font(.legibleFootnote.weight(.bold))
                        .foregroundStyle(Palette.textSecondary)
                } icon: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Palette.accent)
                }
                VStack(alignment: .leading, spacing: 8) {
                    SkeletonLine()
                    SkeletonLine()
                    SkeletonLine(width: 150)
                }
                .padding(.vertical, 2)
                .shimmering()
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Writing…"))
        }
        .listRowBackground(Palette.surface)
    }

    @ViewBuilder
    private func answerSection(_ outcome: HelpOutcome) -> some View {
        switch outcome {
        case .answer(let answer, let support):
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label {
                        Text(verbatim: "Aybik")
                            .font(.legibleFootnote.weight(.bold))
                            .foregroundStyle(Palette.textSecondary)
                    } icon: {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Palette.accent)
                    }
                    .accessibilityAddTraits(.isHeader)
                    Text(verbatim: answer)
                        .font(.subheadline)
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if support { contactButton }
                    canBeWrongNote
                }
                .padding(.vertical, 6)
                .arrival()
            }
            .listRowBackground(Palette.surface)
        case .blocked(let message):
            Section {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(.legibleFootnote.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Palette.surface)
        case .topics(let closest):
            Section {
                if closest.isEmpty {
                    Group {
                        if app.usesCloudWriter {
                            Text("Aybik can't answer right now, and none of the common questions match. Try the list below or Help & Support.",
                                 comment: "Settings › Help › Ask Aybik: the AI helper didn't answer and nothing on the device matched her question. Aybik is the app's AI helper: keep the name Aybik.")
                        } else {
                            Text("None of the common questions match. Try the list below or Help & Support.",
                                 comment: "Settings › Help › Ask Aybik: nothing on the device matched her question (the AI helper is off)")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(closest) { topic in
                        TopicRow(topic: topic, startsOpen: closest.count == 1)
                    }
                }
            } header: {
                if !closest.isEmpty {
                    if app.usesCloudWriter {
                        Text("Aybik can't answer right now. These might help:",
                             comment: "Settings › Help › Ask Aybik: the AI helper didn't answer; the closest common questions follow. Aybik is the app's AI helper: keep the name Aybik.")
                    } else {
                        Text("Closest answers", comment: "Settings › Help › Ask Aybik: the common questions closest to hers, found on the device")
                    }
                }
            }
            .listRowBackground(Palette.surface)
        }
    }

    private var canBeWrongNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Answers can be wrong. If something doesn't add up, see Help & Support.",
                 comment: "Settings › Help › Ask Aybik: the small note under the AI helper's answer; Help & Support is the support page on the website")
                .font(.legibleCaption)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if let page = app.config.supportPageURL {
                Button {
                    openURL(page)
                } label: {
                    Text("Help & Support", comment: "Settings › Help: opens the support page on the website in the browser")
                        .font(.legibleCaption.weight(.bold))
                        .foregroundStyle(Palette.accent)
                        .frame(minHeight: 32)
                }
                .buttonStyle(.borderless)
                .accessibilityHint(Text("Opens in your browser", comment: "Accessibility hint of a link that opens a web page"))
            }
        }
    }

    private var contactButton: some View {
        Group {
            if let support = app.config.supportURL {
                Button {
                    openURL(support)
                } label: {
                    Label("Contact support", systemImage: "envelope")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 32)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: Common questions

    private var commonQuestions: some View {
        Section {
            ForEach(topics) { topic in
                TopicRow(topic: topic, startsOpen: false)
            }
        } header: {
            Text("Common questions", comment: "Settings › Help: the list of common questions about the app")
        }
        .listRowBackground(Palette.surface)
    }

    private var supportSection: some View {
        Section {
            if let page = app.config.supportPageURL {
                Button {
                    openURL(page)
                } label: {
                    Label {
                        Text("Help & Support", comment: "Settings › Help: opens the support page on the website in the browser")
                    } icon: {
                        Image(systemName: "questionmark.circle")
                    }
                }
                .accessibilityHint(Text("Opens in your browser", comment: "Accessibility hint of a link that opens a web page"))
            }
            if let support = app.config.supportURL {
                Button {
                    openURL(support)
                } label: {
                    Label("Contact support", systemImage: "envelope")
                }
            }
        } footer: {
            Text("Still stuck? We're happy to help.", comment: "Settings › Help: under the support links")
        }
        .listRowBackground(Palette.surface)
    }
}

/// A common question that opens to its answer.
private struct TopicRow: View {
    let topic: HelpTopic
    @State private var isOpen: Bool

    init(topic: HelpTopic, startsOpen: Bool) {
        self.topic = topic
        _isOpen = State(initialValue: startsOpen)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isOpen) {
            Text(verbatim: L10n.core(topic.answer))
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
                .textSelection(.enabled)
        } label: {
            Text(verbatim: L10n.core(topic.question))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
