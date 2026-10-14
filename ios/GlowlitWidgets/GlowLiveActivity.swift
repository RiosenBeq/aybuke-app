// Live Activities are iPhone and iPad only (ActivityKit is unavailable in Mac Catalyst).
#if !targetEnvironment(macCatalyst)
import ActivityKit
import SwiftUI
import WidgetKit
import AppCore

/// Live Activity for a cloud AI job: Dynamic Island + Lock Screen. The
/// progress bar animates on its own from `startedAt` to `expectedEnd`, so it
/// keeps moving while the app is in the background.
struct GlowLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GlowActivityAttributes.self) { context in
            GlowLockScreenView(context: context)
                .activityBackgroundTint(WidgetPalette.petal)
                .activitySystemActionForegroundColor(WidgetPalette.ink)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ToolBadge(symbol: context.attributes.symbolName, stage: state.stage, size: 44)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StageTrailing(state: state)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(L10n.core(state.stage.headline))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(context.attributes.title)
                            .font(.widgetAccent(15))
                            .foregroundStyle(WidgetPalette.blush)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        GlowProgressBar(state: state, track: .white.opacity(0.15))
                        Text(L10n.core(state.stage.detail))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 2)
                }
            } compactLeading: {
                Image(systemName: state.stage == .failed ? "exclamationmark" : "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WidgetPalette.blush)
                    .symbolEffect(.pulse, isActive: state.stage == .creating || state.stage == .finishing)
            } compactTrailing: {
                CompactTrailing(state: state)
            } minimal: {
                Image(systemName: state.stage == .ready ? "checkmark" : "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WidgetPalette.blush)
            }
            .keylineTint(WidgetPalette.blush)
        }
    }
}

// MARK: - Lock Screen

private struct GlowLockScreenView: View {
    let context: ActivityViewContext<GlowActivityAttributes>

    var body: some View {
        let state = context.state
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ToolBadge(symbol: context.attributes.symbolName, stage: state.stage, size: 46)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.core(state.stage.headline))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(WidgetPalette.ink)
                    Text(context.attributes.title)
                        .font(.widgetAccent(16))
                        .foregroundStyle(WidgetPalette.ink.opacity(0.75))
                        .lineLimit(1)
                }
                Spacer()
                StageTrailing(state: state, onDark: false)
            }
            GlowProgressBar(state: state, fill: WidgetPalette.ink, track: WidgetPalette.ink.opacity(0.1))
            HStack {
                Text(L10n.core(state.stage.detail))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(WidgetPalette.inkSoft)
                Spacer()
                HStack(spacing: 4) {
                    SparkleShape().fill(WidgetPalette.ink).frame(width: 10, height: 10)
                    Text("Glowlit")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(WidgetPalette.ink)
                }
            }
        }
        .padding(16)
    }
}

// MARK: - Pieces

private struct ToolBadge: View {
    let symbol: String
    let stage: GlowJobStage
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(WidgetPalette.blush)
            Image(systemName: stage == .ready ? "checkmark" : stage == .failed ? "arrow.clockwise" : symbol)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(WidgetPalette.ink)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: size, height: size)
        .overlay(alignment: .topTrailing) {
            SparkleShape().fill(.white).frame(width: size * 0.32, height: size * 0.32).offset(x: size * 0.08, y: -size * 0.08)
        }
    }
}

private struct StageTrailing: View {
    let state: GlowActivityAttributes.ContentState
    var onDark = true

    var body: some View {
        switch state.stage {
        case .creating, .finishing:
            Text(timerInterval: state.startedAt...Date.distantFuture, countsDown: false)
                .monospacedDigit()
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(onDark ? .white : WidgetPalette.ink)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 56)
        case .ready:
            Image(systemName: "heart.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(onDark ? WidgetPalette.blush : WidgetPalette.ink)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(onDark ? .white.opacity(0.8) : WidgetPalette.inkSoft)
        }
    }
}

private struct CompactTrailing: View {
    let state: GlowActivityAttributes.ContentState

    var body: some View {
        switch state.stage {
        case .creating, .finishing:
            ProgressView(timerInterval: state.startedAt...max(state.expectedEnd, state.startedAt.addingTimeInterval(1)), countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.circular)
            .tint(WidgetPalette.blush)
            .frame(width: 20, height: 20)
        case .ready:
            Image(systemName: "heart.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WidgetPalette.blush)
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

/// Bar that fills by itself between the start and the expected end.
private struct GlowProgressBar: View {
    let state: GlowActivityAttributes.ContentState
    var fill: Color = WidgetPalette.blush
    let track: Color

    var body: some View {
        Group {
            switch state.stage {
            case .creating, .finishing:
                ProgressView(timerInterval: state.startedAt...max(state.expectedEnd, state.startedAt.addingTimeInterval(1)), countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(fill)
            case .ready:
                Capsule().fill(fill).frame(height: 4)
            case .failed:
                Capsule().fill(track).frame(height: 4)
            }
        }
        .background(Capsule().fill(track).frame(height: 4))
    }
}
#endif
