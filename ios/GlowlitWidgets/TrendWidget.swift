import SwiftUI
import WidgetKit
import AppCore

/// "Today's trend": one look per day, tap to try it on a photo. Free looks
/// unless she's Pro, so a tap never lands on the paywall; under 13 (no cloud
/// AI) it offers the free retro effects instead.
struct TrendEntry: TimelineEntry {
    let date: Date
    let template: PhotoTemplate
    var onDeviceOnly = false
}

struct TrendProvider: TimelineProvider {
    func placeholder(in context: Context) -> TrendEntry {
        TrendEntry(date: Date(), template: TemplateCatalog.pushPool(isPro: false).first ?? TemplateCatalog.all[0])
    }

    func getSnapshot(in context: Context, completion: @escaping (TrendEntry) -> Void) {
        completion(entry(on: Date()))
    }

    private func entry(on date: Date) -> TrendEntry {
        // Read defensively: no snapshot yet means a free member with cloud AI.
        let snapshot = GlowSharedStore.load()
        return TrendEntry(date: date, template: TemplateCatalog.trendOfTheDay(on: date, isPro: snapshot?.isPro ?? false),
                          onDeviceOnly: !(snapshot?.showsCloudAI ?? true))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrendEntry>) -> Void) {
        let calendar = Calendar.current
        let now = Date()
        let tomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400))
        let entries = [
            entry(on: now),
            entry(on: tomorrow),
        ]
        completion(Timeline(entries: entries, policy: .after(calendar.date(byAdding: .day, value: 1, to: tomorrow) ?? tomorrow)))
    }
}

struct TrendWidgetView: View {
    let entry: TrendEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.onDeviceOnly {
            freeEffects
        } else {
            trend
        }
    }

    /// Under 13: the free on-device effects, no AI looks.
    @ViewBuilder
    private var freeEffects: some View {
        switch family {
        case .accessoryInline:
            Label("Retro effects", systemImage: "camera.filters")
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(GlowDeepLink.effects.url)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Retro effects", systemImage: "camera.filters")
                    .font(.headline)
                    .widgetAccentable()
                Text("Free, on your device")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .containerBackground(for: .widget) { Color.clear }
            .widgetURL(GlowDeepLink.effects.url)
        default:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "camera.filters")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(WidgetPalette.blush)
                    .frame(width: 44, height: 44)
                    .background(WidgetPalette.ink, in: Circle())
                Spacer(minLength: 0)
                Text("Retro effects")
                    .font(.widgetTitle(17))
                    .foregroundStyle(WidgetPalette.ink)
                Text("Free, on your device")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetPalette.inkSoft)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { GlowWash() }
            .widgetURL(GlowDeepLink.effects.url)
        }
    }

    @ViewBuilder
    private var trend: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Today's trend", systemImage: "sparkles")
                    .font(.caption2.weight(.semibold))
                    .widgetAccentable()
                Text(L10n.core(entry.template.title))
                    .font(.headline)
                    .lineLimit(1)
                Text(L10n.core(entry.template.subtitle))
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .containerBackground(for: .widget) { Color.clear }
        case .accessoryInline:
            Label("Trend: \(L10n.core(entry.template.title))", systemImage: "sparkles")
                .containerBackground(for: .widget) { Color.clear }
        case .systemMedium:
            medium
        default:
            small
        }
    }

    private var eyebrow: some View {
        Text("TODAY'S TREND")
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .tracking(1.2)
            .foregroundStyle(WidgetPalette.ink.opacity(0.6))
    }

    private var badge: some View {
        Image(systemName: entry.template.symbolName)
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(WidgetPalette.ink)
            .frame(width: 52, height: 52)
            .background(.white, in: Circle())
            .shadow(color: WidgetPalette.ink.opacity(0.10), radius: 8, y: 4)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                badge
                Spacer()
                SparklePair(size: 18)
            }
            Spacer(minLength: 6)
            eyebrow
            Text(L10n.core(entry.template.title))
                .font(.widgetTitle(19))
                .foregroundStyle(WidgetPalette.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text("Try it on you")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(WidgetPalette.ink.opacity(0.75))
        }
        .containerBackground(for: .widget) { GlowWash() }
        .widgetURL(GlowDeepLink.template(entry.template.id).url)
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                eyebrow
                Text(L10n.core(entry.template.title))
                    .font(.widgetTitle(24))
                    .foregroundStyle(WidgetPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(L10n.core(entry.template.subtitle))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(WidgetPalette.inkSoft)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Link(destination: GlowDeepLink.template(entry.template.id).url) {
                    HStack(spacing: 5) {
                        Text("Try it")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetPalette.blush)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(WidgetPalette.ink, in: Capsule())
                }
            }
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .fill(.white.opacity(0.55))
                    .frame(width: 112, height: 112)
                Image(systemName: entry.template.symbolName)
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(WidgetPalette.ink)
                SparklePair(size: 22)
                    .offset(x: 46, y: -42)
                if entry.template.isNew {
                    Text("NEW")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(WidgetPalette.ink, in: Capsule())
                        .offset(x: -40, y: 46)
                }
            }
        }
        .containerBackground(for: .widget) { GlowWash() }
        .widgetURL(GlowDeepLink.template(entry.template.id).url)
    }
}

struct TrendWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.glowlit.trend", provider: TrendProvider()) { entry in
            TrendWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's trend")
        .description("A different one-tap look every day.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}
