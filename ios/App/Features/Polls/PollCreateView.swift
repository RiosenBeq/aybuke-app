import SwiftUI
import AppCore

/// "Ask friends": her two pictures and an optional question become a private
/// link where friends vote A or B for 24 hours, no app needed. The first
/// time, a short explainer says what happens to the pictures.
///
/// Gates, in order: her age range (13+), the question against the edit
/// rules (as the server checks it), AI consent (the usual sheet), her
/// session (made like the first consented cloud job's), the connection;
/// then the upload, where both pictures are checked for safety before
/// anyone can see them. Polls cost no credits.
struct PollCreateView: View {
    let draft: PollDraft

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step
    @State private var question = ""
    @State private var notice: String?
    @State private var showsConsent = false
    @State private var shareItems: ActivityItems?
    @State private var hasGroup = false
    @State private var copied = false
    /// "Ideas from Aybik": its questions, and whether it's writing or couldn't.
    @State private var aybikIdeas: [String] = []
    /// The request for ideas, and the question it was asked with: changing
    /// the question or leaving cancels it.
    @State private var writingIdeas: Task<Void, Never>?
    @State private var ideasAskedWith = ""
    @State private var ideasUnavailable = false
    @FocusState private var isQuestionFocused: Bool

    enum Step: Equatable {
        case explainer
        case compose
        case sending
        case ready(PollRecord)
    }

    init(draft: PollDraft, startsWithExplainer: Bool) {
        self.draft = draft
        _step = State(initialValue: startsWithExplainer ? .explainer : .compose)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .explainer:
                    explainer
                        .transition(.opacity)
                case .compose, .sending:
                    compose
                        .transition(.opacity)
                case .ready(let record):
                    ready(record)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
                }
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : Motion.appear, value: step)
            .background(AuroraBackground(intensity: 0.4))
            .navigationTitle(Text("Ask friends"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if case .ready = step {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    } else {
                        Button("Cancel") { dismiss() }
                            .disabled(step == .sending)
                    }
                }
            }
        }
        .tint(Palette.accent)
        .interactiveDismissDisabled(step == .sending)
        .onDisappear(perform: cancelIdeas)
        .sheet(isPresented: $showsConsent) {
            AIConsentView(
                processors: app.config.consentProcessors,
                retention: app.config.retentionPhrase,
                asksGuardian: app.ageDefaults.requiresGuardianStep,
                onAccept: { guardianConfirmed in
                    showsConsent = false
                    app.grantAIConsent(guardianConfirmed: guardianConfirmed)
                    askFriends()
                },
                onDecline: { showsConsent = false }
            )
            .environment(app)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Palette.background)
            .formSheetOnMacPageOnPad()
        }
        .shareSheet(item: $shareItems)
        .task { hasGroup = await Self.showsAGroup(draft) }
        #if DEBUG
        .onAppear(perform: applyScreenshotState)
        #endif
    }

    // MARK: Explainer

    private var explainer: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 68, height: 68)
                    .background(Palette.blush, in: Circle())
                    .floating(distance: 3)
                    .accessibilityHidden(true)
                Text(styled: "Let your friends *pick*", size: 25)
                    .foregroundStyle(Palette.textPrimary)
                Text("Share a link, and friends vote A or B in their browser. Here's what happens:")
                    .font(.body)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 14) {
                    PollPoint(symbol: "checkmark.shield",
                              text: "Your two pictures go to our servers. Before anyone sees them, a third-party AI provider checks them for safety.")
                    PollPoint(symbol: "link", text: "Anyone with the link can see them and vote for 24 hours.")
                    PollPoint(symbol: "trash", text: "Then the pictures, your question and the votes are deleted. You can delete your poll sooner.")
                    PollPoint(symbol: "eye.slash", text: "Votes are anonymous: no names, no comments.")
                    PollPoint(symbol: "heart", text: "Only share pictures of other people with their OK.")
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .readableWidth(Metrics.compactWidth)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            Button("Got it") {
                Haptics.tap()
                app.polls.hasSeenExplainer = true
                step = .compose
            }
            .buttonStyle(.primary)
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .readableWidth(Metrics.compactWidth, alignment: .center)
            .background(Palette.background.opacity(0.92))
        }
    }

    // MARK: Compose

    private var compose: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    PollSideTile(image: draft.a, side: .a, madeWithAI: draft.aiLabels.a)
                    PollSideTile(image: draft.b, side: .b, madeWithAI: draft.aiLabels.b)
                }
                questionCard
                if hasGroup {
                    Label("Friends in these pictures? Ask them before you share 💗", systemImage: "heart")
                        .font(.legibleFootnote)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
                if let notice {
                    PollNotice(text: notice)
                        .transition(.opacity)
                }
                Text("Anyone with the link can see both pictures and vote for 24 hours. Then everything is deleted.")
                    .font(.legibleCaption)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 16)
            .readableWidth(Metrics.compactWidth)
            .animation(.snappy, value: notice)
            .animation(.snappy, value: hasGroup)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { sendBar }
    }

    private var questionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your question")
                    .font(.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Text(verbatim: "\(question.count)/\(PollQuestion.maxLength)")
                    .font(.legibleCaption.monospacedDigit())
                    .foregroundStyle(Palette.textTertiary)
                    .accessibilityLabel(Text("\(PollQuestion.maxLength - question.count) characters left"))
            }
            TextField("Ask something (optional)", text: $question, axis: .vertical)
                .lineLimit(1...3)
                .font(.body)
                .focused($isQuestionFocused)
                .submitLabel(.done)
                .onSubmit { isQuestionFocused = false }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Palette.background, in: .control)
                .onChange(of: question) { _, typed in
                    let clipped = PollQuestion.clipped(typed)
                    if clipped != typed { question = clipped }
                    notice = nil
                    if isWritingIdeas, clipped != ideasAskedWith { cancelIdeas() }
                }
            FlowLayout {
                ForEach(PollQuestion.presets, id: \.self) { preset in
                    let text = L10n.core(preset)
                    SelectableChip(verbatim: text, isSelected: question == text) {
                        Haptics.selection()
                        question = question == text ? "" : text
                    }
                }
                ForEach(aybikIdeas, id: \.self) { idea in
                    SelectableChip(verbatim: idea, symbolName: "sparkles", isSelected: question == idea) {
                        Haptics.selection()
                        question = question == idea ? "" : idea
                    }
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9)))
                    .accessibilityHint(Text("Written by Aybik, our AI helper.", comment: "Under suggested words in the share composer. Aybik is the app's AI helper: keep the name Aybik."))
                }
            }
            if app.usesCloudWriter {
                aybikIdeasButton
            }
        }
        .padding(16)
        .cardStyle()
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : Motion.appear, value: aybikIdeas)
    }

    /// Aybik writes question ideas only when she asks; the note says what it gets.
    private var aybikIdeasButton: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                writeIdeas()
            } label: {
                HStack(spacing: 6) {
                    if isWritingIdeas {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                            .accessibilityHidden(true)
                    }
                    Text("Ideas from Aybik", comment: "Ask friends sheet: a button that asks the app's AI helper for poll questions. Aybik is the app's AI helper: keep the name Aybik.")
                }
            }
            .buttonStyle(.secondary)
            .disabled(isWritingIdeas || step == .sending)
            Group {
                if ideasUnavailable {
                    Text("Aybik can't write ideas right now. Try one of these.",
                         comment: "Ask friends sheet: the AI helper didn't answer; the ready-made questions stay. Aybik is the app's AI helper: keep the name Aybik.")
                } else {
                    Text("Aybik, our AI helper, gets what you typed and your pictures' titles, never the pictures.",
                         comment: "Ask friends sheet, under “Ideas from Aybik”: what the app's AI helper receives. Aybik is the app's AI helper: keep the name Aybik.")
                }
            }
            .font(.legibleCaption)
            .foregroundStyle(Palette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }

    private var isWritingIdeas: Bool { writingIdeas != nil }

    private func writeIdeas() {
        guard !isWritingIdeas else { return }
        Haptics.tap()
        ideasUnavailable = false
        let typed = question
        ideasAskedWith = typed
        writingIdeas = Task {
            let ideas = await app.pollQuestionIdeas(typed: typed, draft: draft)
            guard !Task.isCancelled else { return }
            writingIdeas = nil
            let fresh = ideas.filter { idea in !PollQuestion.presets.contains { L10n.core($0) == idea } }
            if fresh.isEmpty {
                ideasUnavailable = true
            } else {
                aybikIdeas = fresh
                AccessibilityNotification.Announcement(fresh.joined(separator: ", ")).post()
            }
        }
    }

    private func cancelIdeas() {
        writingIdeas?.cancel()
        writingIdeas = nil
    }

    private var sendBar: some View {
        VStack(spacing: 8) {
            Button {
                askFriends()
            } label: {
                if step == .sending {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Checking your pictures…")
                    }
                } else {
                    Label("Ask friends", systemImage: "paperplane.fill")
                }
            }
            .buttonStyle(.primary)
            .disabled(step == .sending)
            if let left = app.polls.remainingToday {
                Text("\(left) polls left today")
                    .font(.legibleCaption)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .readableWidth(Metrics.compactWidth, alignment: .center)
        .background(Palette.background.opacity(0.92))
    }

    // MARK: Ready

    private func ready(_ record: PollRecord) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 68, height: 68)
                    .background(Palette.blush, in: Circle())
                    .accessibilityHidden(true)
                Text(styled: "Your poll is *ready*", size: 25)
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Share the link with your friends. They vote in their browser, no app needed.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    PollSideTile(image: draft.a, side: .a, madeWithAI: draft.aiLabels.a)
                    PollSideTile(image: draft.b, side: .b, madeWithAI: draft.aiLabels.b)
                }
                .frame(maxWidth: 300)
                if let question = record.question {
                    Text(verbatim: question)
                        .font(.cardTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .multilineTextAlignment(.center)
                }
                Text(verbatim: record.shareURL.absoluteString.replacingOccurrences(of: "https://", with: ""))
                    .font(.subheadline.monospaced())
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Palette.surface, in: .control)
                    .overlay(RoundedRectangle.control.strokeBorder(Palette.stroke))
                    .accessibilityLabel(Text("Poll link"))
                    .accessibilityValue(Text(verbatim: record.shareURL.absoluteString))
                VStack(spacing: 10) {
                    Button {
                        share(record)
                    } label: {
                        Label("Share link", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.primary)
                    Button {
                        copy(record)
                    } label: {
                        Label(copied ? "Copied" : "Copy link", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .contentTransition(.opacity)
                    }
                    .buttonStyle(.secondaryFull)
                }
                if let left = app.polls.remainingToday {
                    Text("\(left) polls left today")
                        .font(.legibleCaption)
                        .foregroundStyle(Palette.textSecondary)
                }
                Text("The votes show up in My Works, under Your polls. The poll ends in 24 hours.")
                    .font(.legibleCaption)
                    .foregroundStyle(Palette.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .readableWidth(Metrics.compactWidth, alignment: .center)
        }
    }

    // MARK: Actions

    private func askFriends() {
        isQuestionFocused = false
        notice = nil
        // Under 13 there are no polls (the server can't know her age).
        guard app.offersPolls else { return dismiss() }
        let checked: String?
        switch PollQuestion.check(question) {
        case .tooLong:
            return refuse(String(localized: "That's a long question. Try a shorter one."))
        case .blocked(let reason, let category):
            return refuse(PollsModel.questionMessage(reason: reason, category: category))
        case .ok(let cleaned):
            checked = cleaned
        }
        guard app.hasAIConsent else {
            showsConsent = true
            return
        }
        if let pause = app.cloudPause, pause.isActive() {
            return refuse(app.message(for: pause))
        }
        step = .sending
        Task {
            do {
                try await app.polls.ensureSession()
                guard !app.isCloudOffline else { throw AIServiceError.offline }
                let record = try await app.polls.create(draft, question: checked, isPro: app.purchases.isPro)
                Haptics.success()
                app.notePollMade(record)
                step = .ready(record)
            } catch {
                step = .compose
                if !AppModel.isCancellation(error) { refuse(app.polls.message(for: error)) }
            }
        }
    }

    private func refuse(_ message: String) {
        Haptics.error()
        notice = message
    }

    private func share(_ record: PollRecord) {
        Haptics.tap()
        shareItems = ActivityItems(items: [PollShareText.message(question: record.question), record.shareURL])
    }

    private func copy(_ record: PollRecord) {
        UIPasteboard.general.url = record.shareURL
        Haptics.success()
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    /// A group photo: the kindness line asks her to check with her friends.
    private static func showsAGroup(_ draft: PollDraft) async -> Bool {
        for image in [draft.a, draft.b] where await FaceAnalysis.faceRects(in: image).count >= 2 {
            return true
        }
        return false
    }

    #if DEBUG
    /// `-GLPollsQuestion "<words>"` fills the question; `-GLPollsCreate send`
    /// (or `ready`) sends it to the fixtures, and the `limit` and `blocked`
    /// fixtures send it straight away to show their message.
    private func applyScreenshotState() {
        guard ScreenshotScene.current != nil, step != .sending else { return }
        let defaults = UserDefaults.standard
        if let words = defaults.string(forKey: "GLPollsQuestion") { question = PollQuestion.clipped(words) }
        let sends = ["send", "ready"].contains(defaults.string(forKey: "GLPollsCreate") ?? "")
        if sends || app.polls.fixture.flatMap(PollsModel.fixtureError) != nil, step == .compose {
            askFriends()
        }
    }
    #endif
}

/// What the share sheet sends with the link.
enum PollShareText {
    static func message(question: String?) -> String {
        guard let question else { return String(localized: "Help me pick! Tap A or B to vote 💗") }
        return question + "\n" + String(localized: "Tap A or B to vote 💗")
    }
}

/// One of the poll's two pictures, with its letter.
struct PollSideTile: View {
    let image: UIImage?
    let side: PollSide
    var madeWithAI = false
    var dimmed = false

    var body: some View {
        Color.clear
            .aspectRatio(4 / 5, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .saturation(dimmed ? 0 : 1)
                        .opacity(dimmed ? 0.45 : 1)
                } else {
                    Palette.surfaceRaised
                }
            }
            .clipShape(.control)
            .overlay(RoundedRectangle.control.strokeBorder(Palette.stroke))
            .overlay(alignment: .topLeading) {
                PollSideBadge(side: side)
                    .padding(8)
            }
            .overlay(alignment: .bottomLeading) {
                if madeWithAI {
                    Text("Edited with AI")
                        .font(.legibleCaption2.weight(.semibold))
                        .foregroundStyle(Palette.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(8)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.accessibilityName(side, madeWithAI: madeWithAI))
            .accessibilityAddTraits(.isImage)
    }

    /// "Picture A", and ", Edited with AI" when the label shows on it.
    static func accessibilityName(_ side: PollSide, madeWithAI: Bool) -> Text {
        let name = side == .a ? Text("Picture A") : Text("Picture B")
        return madeWithAI ? name + Text(verbatim: ", ") + Text("Edited with AI") : name
    }
}

struct PollSideBadge: View {
    let side: PollSide
    /// Grows with Dynamic Type, so the letter never clips.
    @ScaledMetric(relativeTo: .subheadline) private var diameter: CGFloat = 28

    var body: some View {
        Text(verbatim: side.rawValue.uppercased())
            .font(.system(.subheadline, design: .rounded).weight(.heavy))
            .foregroundStyle(Palette.ink)
            .frame(width: diameter, height: diameter)
            .background(side == .a ? Palette.blush : Palette.auraLilac.opacity(0.85), in: Circle())
            .overlay(Circle().strokeBorder(Palette.white.opacity(0.8), lineWidth: 1.5))
            .accessibilityHidden(true)
    }
}

/// A short message in the sheet: why something didn't work, kindly.
struct PollNotice: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .font(.subheadline)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .card)
        .overlay(RoundedRectangle.card.strokeBorder(Palette.strokeStrong))
        .accessibilityElement(children: .combine)
    }
}

private struct PollPoint: View {
    let symbol: String
    let text: LocalizedStringKey
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !typeSize.isAccessibilitySize {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 32, height: 32)
                    .background(Palette.blush, in: Circle())
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, typeSize.isAccessibilitySize ? 0 : 6)
        }
    }
}
