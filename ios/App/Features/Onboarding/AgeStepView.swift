import SwiftUI
import AppCore
#if canImport(DeclaredAgeRange)
import DeclaredAgeRange
#endif

/// The neutral age question. Apple's Declared Age Range first where it
/// exists (iOS 26+), otherwise month and year menus with nothing preselected
/// and no hint of a cutoff. Only the band is kept (`AgeRecord`), on this
/// device; the month and year are discarded.
struct AgeStepView: View {
    enum Mode {
        /// A page of onboarding (the parent supplies the background).
        case onboarding
        /// Once, for people who finished onboarding before this step existed.
        case returning
        /// Settings › Age range.
        case update
    }

    let mode: Mode
    /// Returns false when the answer may not replace the current one.
    let onAnswer: (AgeRecord) -> Bool

    @State private var month: Int?
    @State private var year: Int?
    @State private var usesMenus: Bool
    /// Apple's age range is required here and she declined to share it.
    @State private var appleDeclined = false
    @State private var isAsking = false
    @State private var rejected = false

    init(mode: Mode, onAnswer: @escaping (AgeRecord) -> Bool) {
        self.mode = mode
        self.onAnswer = onAnswer
        var usesMenus = !Self.appleAgeRangeExists
        #if DEBUG
        // -GLAgeMenus YES: the fallback question, for screenshots and QA.
        if UserDefaults.standard.bool(forKey: "GLAgeMenus") { usesMenus = true }
        #endif
        _usesMenus = State(initialValue: usesMenus)
    }

    private static var appleAgeRangeExists: Bool {
        #if canImport(DeclaredAgeRange)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 8)
            Text(styled: title, size: 30)
                .foregroundStyle(Palette.textPrimary)
            Group {
                if usesMenus {
                    Text("We only keep your age range on this device, never your birthday.")
                } else {
                    Text("\(Brand.name) asks Apple for your age range, never your birthday. It stays on this device.")
                }
            }
                .font(.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if appleDeclined {
                appleDeclinedNote
            } else if usesMenus {
                HStack(spacing: 12) {
                    monthMenu
                    yearMenu
                }
            }

            if mode == .update {
                Text("You can enter a younger age anytime. An older one can be entered once a year.")
                    .font(.legibleFootnote)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if rejected {
                Text("That's older than the age range you entered before. You can change it once a year.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
            primaryButton
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, mode == .onboarding ? 8 : 24)
        .animation(.snappy, value: usesMenus)
        .animation(.snappy, value: appleDeclined)
    }

    private var title: String {
        if mode == .update { return String(localized: "Update your *age*") }
        return usesMenus ? String(localized: "When were you *born?*") : String(localized: "Your *age range*")
    }

    // MARK: Apple's age range

    @ViewBuilder
    private var primaryButton: some View {
        if usesMenus {
            Button("Continue") { submitMenus() }
                .buttonStyle(.primary)
                .disabled(month == nil || year == nil)
        } else {
            appleButton
        }
    }

    @ViewBuilder
    private var appleButton: some View {
        #if canImport(DeclaredAgeRange)
        if #available(iOS 26.0, *) {
            AppleAgeRangeButton(title: appleDeclined ? "Share age range" : "Continue", isAsking: $isAsking) { outcome in
                handle(outcome)
            }
        }
        #endif
    }

    private var appleDeclinedNote: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where you live, \(Brand.name) needs your age range from Apple for anything beyond the free tools on your device. You can share it anytime.")
                .font(.subheadline)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if mode != .update {
                Button("Continue with free tools") {
                    finish(AgeRecord(band: .unknown, source: .declined, setAt: Date()))
                }
                .buttonStyle(.secondary)
            }
        }
        .padding(16)
        .glassPanel()
    }

    private func handle(_ outcome: AppleAgeOutcome) {
        switch outcome {
        case .shared(let band, let source):
            appleDeclined = false
            finish(AgeRecord(band: band, source: source, setAt: Date()))
        case .declinedWhereRequired:
            appleDeclined = true
        case .declined, .unavailable:
            // Everywhere else: the neutral question instead.
            usesMenus = true
        }
    }

    // MARK: Month and year

    private var monthNames: [String] {
        let formatter = DateFormatter()
        formatter.locale = .current
        return formatter.standaloneMonthSymbols ?? Calendar.current.monthSymbols
    }

    private var years: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return Array(stride(from: current, through: current - 100, by: -1))
    }

    private var monthMenu: some View {
        Menu {
            ForEach(Array(monthNames.enumerated()), id: \.offset) { index, name in
                Button(name) { month = index + 1 }
            }
        } label: {
            menuLabel(month.map { monthNames[$0 - 1] }, placeholder: "Month")
        }
        .accessibilityLabel("Month")
    }

    private var yearMenu: some View {
        Menu {
            ForEach(years, id: \.self) { value in
                Button { year = value } label: { Text(verbatim: String(value)) }
            }
        } label: {
            menuLabel(year.map { String($0) }, placeholder: "Year")
        }
        .accessibilityLabel("Year")
    }

    private func menuLabel(_ value: String?, placeholder: LocalizedStringKey) -> some View {
        HStack {
            if let value {
                Text(verbatim: value)
                    .foregroundStyle(Palette.textPrimary)
            } else {
                Text(placeholder)
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
        }
        .font(.body.weight(.semibold))
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(Palette.surface, in: .control)
        .overlay(
            RoundedRectangle.control
                .strokeBorder(Palette.stroke, lineWidth: 1)
        )
    }

    private func submitMenus() {
        guard let month, let year else { return }
        finish(AgeRecord(band: AgeBand(birthMonth: month, birthYear: year, now: Date(), calendar: .current), source: .selfDeclared, setAt: Date()))
        // Nothing of the date is kept, not even in this view.
        self.month = nil
        self.year = nil
    }

    private func finish(_ record: AgeRecord) {
        Haptics.tap()
        rejected = !onAnswer(record)
    }
}

/// What Apple's Declared Age Range said, in the app's terms.
enum AppleAgeOutcome {
    case shared(AgeBand, AgeSource)
    /// Declined where the law requires Apple's age range (no fallback).
    case declinedWhereRequired
    case declined
    case unavailable
}

#if canImport(DeclaredAgeRange)
/// Asks Apple for her age range with the gates that matter here (13, 16, 18).
/// No timeout: it's a system sheet she answers herself.
@available(iOS 26.0, *)
private struct AppleAgeRangeButton: View {
    let title: LocalizedStringKey
    @Binding var isAsking: Bool
    let onOutcome: (AppleAgeOutcome) -> Void
    @Environment(\.requestAgeRange) private var requestAgeRange

    var body: some View {
        Button {
            Task { await ask() }
        } label: {
            if isAsking { ProgressView().tint(Palette.onPrimary) } else { Text(title) }
        }
        .buttonStyle(.primary)
        .disabled(isAsking)
    }

    private func ask() async {
        isAsking = true
        defer { isAsking = false }
        do {
            switch try await requestAgeRange(ageGates: 13, 16, 18) {
            case .sharing(let range):
                let source: AgeSource = range.ageRangeDeclaration == .selfDeclared ? .appleSelfDeclared : .apple
                onOutcome(.shared(AgeBand(appleLowerBound: range.lowerBound), source))
            case .declinedSharing:
                onOutcome(await Self.isRequired() ? .declinedWhereRequired : .declined)
            @unknown default:
                onOutcome(.unavailable)
            }
        } catch {
            onOutcome(.unavailable)
        }
    }

    /// Where the law requires it (Texas, Utah, Louisiana…), Apple's answer
    /// is the only one that counts.
    private static func isRequired() async -> Bool {
        if #available(iOS 26.4, *),
           let features = try? await AgeRangeService.shared.requiredRegulatoryFeatures {
            return features.contains(.declaredAgeRangeRequired)
        }
        if #available(iOS 26.2, *) {
            return (try? await AgeRangeService.shared.isEligibleForAgeFeatures) ?? false
        }
        return false
    }
}
#endif

extension AgeBand {
    /// Settings › Age range.
    var title: String {
        switch self {
        case .under13: return String(localized: "Under 13")
        case .teen13to15: return String(localized: "13 to 15")
        case .teen16to17: return String(localized: "16 to 17")
        case .adult: return String(localized: "18 or older")
        case .unknown: return String(localized: "Not shared")
        }
    }
}
