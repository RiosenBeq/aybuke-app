import SwiftUI
import AppCore

/// Enhance in one panel: the free Quick fix (on the device, previewed on the
/// photo, works offline and under 13) and the AI fixes (Unblur, Restore old
/// photo with an optional "Add color", Brighten low light and HD 2×), which
/// go through the usual gates and credits. The fix that suits the photo, if
/// any, carries a "Suggested" mark.
struct EnhancePanel: View {
    let options: [EnhanceOption]
    let selected: EnhanceOption?
    let suggested: EnhanceOption?
    @Binding var addsColor: Bool
    @Binding var upscales: Bool
    /// The photo is small enough for "Upscale" to make it bigger.
    let canUpscale: Bool
    let cost: Int
    let onSelect: (EnhanceOption) -> Void
    let onReset: () -> Void
    let onApplyQuickFix: () -> Void
    let onRunAI: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChipRow {
                ForEach(options) { option in
                    chip(option)
                }
            }
            details
        }
        .animation(.snappy, value: selected)
    }

    private func chip(_ option: EnhanceOption) -> some View {
        SelectableChip(verbatim: option.title, symbolName: option.symbolName, isSelected: selected == option) {
            onSelect(option)
        }
        .overlay(alignment: .topTrailing) {
            if option == suggested && selected != option {
                Image(systemName: "sparkle")
                    .font(.legibleCaption2.weight(.bold))
                    .foregroundStyle(Palette.onAccent)
                    .padding(4)
                    .background(Palette.accent, in: Circle())
                    .offset(x: 4, y: -4)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityValue(option == suggested ? Text("Suggested", comment: "Enhance: VoiceOver value of the fix that suits this photo") : Text(verbatim: ""))
    }

    @ViewBuilder
    private var details: some View {
        switch selected {
        case nil:
            Text("Pick a fix. Quick fix is free and stays on your device.",
                 comment: "Enhance panel before a fix is picked")
                .font(.legibleFootnote)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .quickFix?:
            caption(.quickFix)
            if canUpscale {
                Toggle(isOn: $upscales) {
                    Label {
                        Text("Upscale up to 2×", comment: "Enhance › Quick fix switch: makes a small photo up to twice as big")
                    } icon: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .tint(Palette.accent)
            }
            ButtonRow {
                Button("Reset", action: onReset)
                    .buttonStyle(.secondary)
            } primary: {
                Button("Apply", action: onApplyQuickFix)
                    .buttonStyle(.primary)
            }
        case let option?:
            caption(option)
            if option == .restore {
                Toggle(isOn: $addsColor) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add color", comment: "Enhance › Restore old photo switch: colors a black-and-white print")
                            Text("For black-and-white prints", comment: "Under Enhance's Add color switch")
                                .font(.legibleCaption)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    } icon: {
                        Image(systemName: "paintpalette")
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .tint(Palette.accent)
            }
            Button(action: onRunAI) {
                CostLabel(title: "Enhance", cost: cost)
            }
            .buttonStyle(.primary)
            Text("Made to keep your skin, face and features as they are.",
                 comment: "Under the AI Enhance button: the AI fixes keep skin texture, faces and features")
                .font(.legibleCaption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func caption(_ option: EnhanceOption) -> some View {
        Text(verbatim: option.caption)
            .font(.legibleFootnote)
            .foregroundStyle(Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A one-time hint under the photo when it looks blurry, grainy, dark or
/// like an old print: what's off and the fix for it.
struct EnhanceHintCard: View {
    let suggestion: EnhanceSuggestion
    let onTry: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: suggestion.option.symbolName)
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 40, height: 40)
                .background(Palette.blush, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: suggestion.reason.hint)
                    .font(.cardTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: "\(suggestion.option.title) · \(suggestion.option.caption)")
                    .font(.legibleFootnote)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onTry) {
                    Text("Try it")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.onAccent)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 36)
                        .background(Palette.accent, in: .pill)
                }
                .buttonStyle(.pressable)
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.legibleCaption.weight(.bold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(14)
        .cardStyle()
        .accessibilityElement(children: .contain)
    }
}

/// Shown once on this device, the first time a photo needs a fix.
enum EnhanceHint {
    /// Delete my data removes it (`AppModel.Keys.wiped`).
    static let key = "enhance.hintShown"

    static var wasShown: Bool { UserDefaults.standard.bool(forKey: key) }

    static func markShown() { UserDefaults.standard.set(true, forKey: key) }
}

extension EnhanceOption {
    var title: String {
        switch self {
        case .quickFix: return String(localized: "Quick fix", comment: "Enhance option: a free fix for noise, sharpness and light, on the device")
        case .unblur: return String(localized: "Unblur & sharpen", comment: "Enhance option (AI)")
        case .restore: return String(localized: "Restore old photo", comment: "Enhance option (AI): scratches, dust, creases and fading on old prints")
        case .lowLight: return String(localized: "Brighten low light", comment: "Enhance option (AI): a photo taken in the dark")
        case .hd: return String(localized: "HD 2×", comment: "Enhance option (AI): finer detail, up to twice the size")
        }
    }

    var caption: String {
        switch self {
        case .quickFix: return String(localized: "Less noise, crisper detail and balanced light. Free, on your device.")
        case .unblur: return String(localized: "Sharpens blurry shots and brings faces back into focus.")
        case .restore: return String(localized: "Removes scratches, dust, creases and fading from old prints.")
        case .lowLight: return String(localized: "Brightens dark shots naturally, without adding a glow.")
        case .hd: return String(localized: "Finer detail, up to twice the size.")
        }
    }

    var symbolName: String {
        switch self {
        case .quickFix: return "wand.and.sparkles"
        case .unblur: return "camera.metering.spot"
        case .restore: return "photo.artframe"
        case .lowLight: return "moon.stars"
        case .hd: return "sparkle.magnifyingglass"
        }
    }
}

extension EnhanceMode {
    /// The fix's name for My Works.
    var title: String {
        switch self {
        case .unblur: return EnhanceOption.unblur.title
        case .restore, .restoreColor: return EnhanceOption.restore.title
        case .lowLight: return EnhanceOption.lowLight.title
        case .hd: return EnhanceOption.hd.title
        }
    }
}

extension EnhanceReason {
    var hint: String {
        switch self {
        case .oldPrint: return String(localized: "This looks like an old print.", comment: "Enhance hint in the editor")
        case .lowLight: return String(localized: "This photo looks a little dark.", comment: "Enhance hint in the editor")
        case .blurry: return String(localized: "This photo looks a little blurry.", comment: "Enhance hint in the editor")
        case .noisy: return String(localized: "This photo looks a little grainy.", comment: "Enhance hint in the editor")
        }
    }
}
