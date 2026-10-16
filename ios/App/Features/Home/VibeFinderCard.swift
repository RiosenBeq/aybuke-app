import SwiftUI
import AppCore

/// Explore's "Describe your vibe": she says the moment ("birthday picnic by
/// the sea"), and up to three things the app has come back, each opening in
/// one tap: a one-tap look, a Create style, a retro effect, an Enhance fix or
/// a Glow look in Retro Cam. Aybik picks them when writing help is on
/// (`AppModel.findLooks`); otherwise, and always under 13, the device
/// matches her words against the catalog's names. Nothing is made or charged
/// until she uses one, through its usual gates.
struct VibeFinderCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var text = ""
    @State private var isWorking = false
    @State private var outcome: LookFinderOutcome?
    /// What the picks are called, read when they came.
    @State private var items: [String: LookFinder.Item] = [:]
    @FocusState private var isFocused: Bool

    /// Long enough for a moment, short of the server's limit.
    private static let maxLength = 200
    private static let placeholder: LocalizedStringKey = "A birthday picnic by the sea, a rainy day in…"

    private var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isWorking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "wand.and.stars")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44)
                    .background(AuraFill(palette: .lilac).clipShape(.control))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Describe your vibe")
                        .font(.cardTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("Say the moment, and find looks and effects to match.",
                         comment: "Explore: under “Describe your vibe”, a field where she describes an occasion or a mood and gets matching looks, styles and effects")
                        .font(.legibleFootnote)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            field
            if let outcome {
                results(outcome)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
            if app.usesCloudWriter && outcome == nil {
                Text("Aybik, our AI helper, gets only your words.",
                     comment: "Explore, under “Describe your vibe”: what the app's AI helper receives. Aybik is the app's AI helper: keep the name Aybik.")
                    .font(.legibleCaption)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .cardStyle()
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : Motion.appear, value: outcome)
        #if DEBUG
        // Screenshot QA: -GLVibeFinder "<words>" types them and asks once.
        .task {
            guard ScreenshotScene.current != nil, text.isEmpty, outcome == nil,
                  let words = UserDefaults.standard.string(forKey: "GLVibeFinder"), words.lowercased() != "yes" else { return }
            text = words
            try? await Task.sleep(for: .milliseconds(300))
            submit()
        }
        #endif
    }

    // MARK: Field

    private var field: some View {
        HStack(alignment: .center, spacing: 6) {
            ZStack(alignment: .topLeading) {
                // A field's own placeholder stays on one line and cuts the
                // example short in longer languages; this one wraps.
                if text.isEmpty {
                    Text(Self.placeholder)
                        .font(.subheadline)
                        .foregroundStyle(Color(uiColor: .placeholderText))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                TextField("", text: $text, axis: .vertical)
                    .lineLimit(1...3)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textPrimary)
                    .focused($isFocused)
                    .submitLabel(.go)
                    .accessibilityLabel(Text("Describe your vibe"))
                    .accessibilityHint(Text(Self.placeholder))
                    // A multi-line field turns Go (Return) into a newline
                    // instead of submitting, so a trailing one sends.
                    .onChange(of: text) { _, newText in
                        var cleaned = newText
                        let pressedGo = cleaned.hasSuffix("\n")
                        if cleaned.contains("\n") {
                            cleaned = cleaned.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
                        }
                        if cleaned.count > Self.maxLength { cleaned = String(cleaned.prefix(Self.maxLength)) }
                        if cleaned != newText { text = cleaned }
                        if pressedGo { submit() }
                    }
                    .onSubmit(submit)
            }
            .padding(.leading, 14)
            .padding(.vertical, 11)
            Button(action: submit) {
                ZStack {
                    if isWorking {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Palette.onAccent)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.subheadline.weight(.bold))
                    }
                }
                .foregroundStyle(canSubmit || isWorking ? Palette.onAccent : Palette.textTertiary)
                .frame(width: 34, height: 34)
                .background(canSubmit || isWorking ? Palette.accent : Palette.strokeStrong, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Circle())
            }
            .buttonStyle(.pressable)
            .disabled(!canSubmit)
            .accessibilityLabel(Text("Find looks for my vibe", comment: "Explore: the button that searches looks, styles and effects for what she described"))
            .macHelp(Text("Find looks for my vibe", comment: "Explore: the button that searches looks, styles and effects for what she described"))
            .padding(.trailing, 2)
        }
        .background(Palette.background, in: .card)
        .overlay(
            RoundedRectangle.card
                .strokeBorder(isFocused ? Palette.accent : Palette.strokeStrong, lineWidth: isFocused ? 1.5 : 1)
        )
    }

    // MARK: Results

    @ViewBuilder
    private func results(_ outcome: LookFinderOutcome) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            switch outcome {
            case .blocked(let message):
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(.legibleFootnote.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    .fixedSize(horizontal: false, vertical: true)
            case .picks(let picks, let writtenBy):
                ForEach(picks, id: \.key) { pick in
                    row(pick)
                }
                footnote(writtenBy == .cloud
                         ? Text("Picked by Aybik, our AI helper.", comment: "Explore, under the looks found for her vibe. Aybik is the app's AI helper: keep the name Aybik.")
                         : Text("Matched on your device.", comment: "Explore, under the looks found for her vibe by a word match on the device"))
            case .favorites(let picks):
                Text("No match for those words yet. Some favorites to try:",
                     comment: "Explore: nothing in the app matched her described vibe; a few popular looks and effects follow")
                    .font(.legibleFootnote)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(picks, id: \.key) { pick in
                    row(pick)
                }
            }
            Button {
                Haptics.tap()
                text = ""
                self.outcome = nil
            } label: {
                Text("Clear")
                    .font(.legibleFootnote.weight(.bold))
                    .foregroundStyle(Palette.accent)
                    .frame(minHeight: 32)
            }
            .buttonStyle(.pressable)
        }
    }

    private func footnote(_ text: Text) -> some View {
        text
            .font(.legibleCaption)
            .foregroundStyle(Palette.textTertiary)
    }

    private func row(_ pick: LookFinder.Pick) -> some View {
        let item = items[pick.key]
        let isLocked = item?.isPro == true && !app.purchases.isPro
        return Button {
            Haptics.tap()
            isFocused = false
            app.open(pick)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: symbol(for: pick))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44)
                    .background(AuraFill(palette: palette(for: pick.kind)).clipShape(.control))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    kindLabel(pick.kind)
                        .font(.legibleCaption2.weight(.bold))
                        .foregroundStyle(Palette.textTertiary)
                        .textCase(.uppercase)
                    HStack(spacing: 4) {
                        Text(verbatim: item?.name ?? pick.id)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Palette.textPrimary)
                        if isLocked {
                            Image(systemName: "lock.fill")
                                .font(.legibleCaption2)
                                .foregroundStyle(Palette.textSecondary)
                                .accessibilityHidden(true)
                        }
                    }
                    Text(verbatim: pick.reason)
                        .font(.legibleFootnote)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.legibleFootnote.weight(.semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(10)
            .background(Palette.background, in: .control)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .macHoverLift()
        .accessibilityElement(children: .combine)
        .accessibilityHint(isLocked ? Text("Pro. Opens it.", comment: "Accessibility hint of a Pro item found for her vibe on Explore")
                                    : Text("Opens it.", comment: "Accessibility hint of an item found for her vibe on Explore"))
    }

    private func kindLabel(_ kind: LookFinder.Kind) -> Text {
        switch kind {
        case .look: return Text("One-tap look", comment: "Explore, vibe finder: the kind of a suggestion (a one-tap look for her photo)")
        case .style: return Text("Create style", comment: "Explore, vibe finder: the kind of a suggestion (an art style for a new picture in Create)")
        case .effect: return Text("Free effect", comment: "Explore, vibe finder: the kind of a suggestion (a free retro effect in the editor)")
        case .enhance: return Text("Enhance")
        case .glow: return Text("Retro Cam Glow", comment: "Explore, vibe finder: the kind of a suggestion (a Glow look in Retro Cam). Keep Retro Cam as it is.")
        }
    }

    private func symbol(for pick: LookFinder.Pick) -> String {
        switch pick.kind {
        case .look: return TemplateCatalog.template(id: pick.id)?.symbolName ?? "sparkles"
        case .style: return StyleCatalog.style(id: pick.id).symbolName
        case .effect: return "camera.filters"
        case .enhance: return EnhanceOption(rawValue: pick.id)?.symbolName ?? "wand.and.sparkles"
        case .glow: return AdjustVibes.preset(id: pick.id)?.symbolName ?? "sun.min"
        }
    }

    private func palette(for kind: LookFinder.Kind) -> AuraPalette {
        switch kind {
        case .look: return .bubblegum
        case .style: return .lilac
        case .effect: return .sunset
        case .enhance: return .mint
        case .glow: return .butter
        }
    }

    // MARK: Asking

    private func submit() {
        guard canSubmit else { return }
        isFocused = false
        isWorking = true
        let words = text
        Task {
            let found = await app.findLooks(for: words)
            items = Dictionary(app.finderItems.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
            isWorking = false
            if case .blocked = found { Haptics.error() } else { Haptics.success() }
            outcome = found
        }
    }
}

extension VibeFinderCard {
    /// Explore shows it everywhere but in screenshot scenes, which keep their
    /// picture unless `-GLVibeFinder` asks for it. Always true in Release.
    static var isShown: Bool {
        #if DEBUG
        return ScreenshotScene.current == nil || UserDefaults.standard.string(forKey: "GLVibeFinder") != nil
        #else
        return true
        #endif
    }
}
