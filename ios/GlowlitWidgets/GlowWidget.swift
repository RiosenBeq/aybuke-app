import SwiftUI
import UIKit
import WidgetKit
import AppCore

/// "My glow": the newest creation, credits left and quick actions.
struct GlowEntry: TimelineEntry {
    let date: Date
    let snapshot: GlowWidgetSnapshot
    let latestImage: UIImage?
}

struct GlowProvider: TimelineProvider {
    func placeholder(in context: Context) -> GlowEntry {
        GlowEntry(date: Date(), snapshot: .placeholder, latestImage: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (GlowEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlowEntry>) -> Void) {
        let entry = currentEntry()
        // The app reloads this widget whenever credits or the library change;
        // otherwise refresh when free credits refill.
        let refresh = entry.snapshot.nextRefill ?? Date().addingTimeInterval(6 * 3600)
        completion(Timeline(entries: [entry], policy: .after(max(refresh, Date().addingTimeInterval(900)))))
    }

    private func currentEntry() -> GlowEntry {
        let snapshot = GlowSharedStore.load() ?? .placeholder
        let image = GlowSharedStore.latestImageURL.flatMap { UIImage(contentsOfFile: $0.path) }
        return GlowEntry(date: Date(), snapshot: snapshot, latestImage: image)
    }
}

struct GlowWidgetView: View {
    let entry: GlowEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: GlowWidgetSnapshot { entry.snapshot }

    var body: some View {
        switch family {
        case .accessoryCircular:
            if snapshot.showsCloudAI { circular } else { circularEffects }
        case .systemMedium:
            medium
        default:
            small
        }
    }

    // MARK: Pieces

    private var creditsPill: some View {
        HStack(spacing: 4) {
            Image(systemName: snapshot.isPro ? "crown.fill" : "bolt.fill")
            Text("\(snapshot.credits)")
                .monospacedDigit()
        }
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .foregroundStyle(WidgetPalette.blush)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(WidgetPalette.ink, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var artwork: some View {
        if let image = entry.latestImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                GlowWash()
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(WidgetPalette.ink)
                    .frame(width: 66, height: 66)
                    .background(.white, in: Circle())
            }
        }
    }

    private var small: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
            if entry.latestImage != nil {
                LinearGradient(colors: [.clear, WidgetPalette.ink.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.latestImage == nil ? "Make your first" : "Your latest")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                (entry.latestImage == nil ? Text("glow ✨") : Text(L10n.core(snapshot.latestTitle ?? String(localized: "creation"))))
                    .font(entry.latestImage == nil ? .widgetAccent(20) : .widgetTitle(15))
                    .lineLimit(2)
                    // Hidden while locked (StandBy, the iPad Lock Screen).
                    .privacySensitive()
            }
            .foregroundStyle(entry.latestImage == nil ? WidgetPalette.ink : .white)
        }
        .overlay(alignment: .topLeading) {
            // Under 13 there are no credits to count.
            if snapshot.showsCloudAI { creditsPill }
        }
        .overlay(alignment: .topTrailing) {
            if snapshot.latestIsFavorite && entry.latestImage != nil {
                Image(systemName: "heart.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WidgetPalette.blush)
                    .padding(6)
                    .background(WidgetPalette.ink.opacity(0.55), in: Circle())
            }
        }
        .containerBackground(for: .widget) { artwork }
        .widgetURL(entry.latestImage == nil ? firstTool.url : GlowDeepLink.library.url)
    }

    private var medium: some View {
        HStack(spacing: 14) {
            Link(destination: GlowDeepLink.library.url) {
                artwork
                    .frame(width: 118, height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.white.opacity(0.8), lineWidth: 2)
                    )
                    .shadow(color: WidgetPalette.ink.opacity(0.15), radius: 8, y: 4)
                    .privacySensitive()
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("Make it")
                        .font(.widgetTitle(17))
                    Text("glow.")
                        .font(.widgetAccent(19))
                }
                .foregroundStyle(WidgetPalette.ink)
                if snapshot.showsCloudAI {
                    creditsLine
                } else {
                    Text("Free, on your device")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(WidgetPalette.inkSoft)
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    if snapshot.showsCloudAI {
                        action("wand.and.stars", "Magic", .magicEdit)
                    } else {
                        action("scissors", "Cut out", .removeBackground)
                    }
                    action("camera.filters", "Effects", .effects)
                    action("video.fill", "Video", .video)
                }
            }
            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) { GlowWash() }
    }

    @ViewBuilder
    private var creditsLine: some View {
        let refill = snapshot.isPro ? snapshot.nextGrant : snapshot.nextRefill
        Group {
            if let refill, snapshot.credits == 0 {
                Text("New credits in \(Text(refill, style: .relative))")
            } else {
                switch snapshot.balanceKind {
                case .daily:
                    Label("\(snapshot.credits) free credits today", systemImage: "bolt.fill")
                case .monthly:
                    Label("\(snapshot.credits) Pro credits", systemImage: "crown.fill")
                case .mixed:
                    // Pack credits are neither free nor monthly.
                    Label("\(snapshot.credits) credits left", systemImage: snapshot.isPro ? "crown.fill" : "bolt.fill")
                }
            }
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(WidgetPalette.inkSoft)
    }

    private func action(_ symbol: String, _ title: LocalizedStringKey, _ link: GlowDeepLink) -> some View {
        Link(destination: link.url) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WidgetPalette.blush)
                    .frame(width: 36, height: 36)
                    .background(WidgetPalette.ink, in: Circle())
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetPalette.ink)
                    .lineLimit(1)
            }
        }
    }

    /// Magic Edit, or the free effects under 13 (no cloud AI entry points).
    private var firstTool: GlowDeepLink { snapshot.showsCloudAI ? .magicEdit : .effects }

    private var circularEffects: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "camera.filters")
                .font(.system(size: 22, weight: .semibold))
        }
        .widgetAccentable()
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(GlowDeepLink.effects.url)
        .accessibilityLabel(Text("Retro effects"))
    }

    private var circular: some View {
        let range = snapshot.gaugeRange()
        return Gauge(value: Double(snapshot.gaugeValue()), in: Double(range.lowerBound)...Double(range.upperBound)) {
            Image(systemName: snapshot.isPro ? "crown.fill" : "bolt.fill")
        } currentValueLabel: {
            Text("\(snapshot.credits)")
                .font(.system(.title3, design: .rounded).weight(.bold))
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(GlowDeepLink.magicEdit.url)
    }
}

struct GlowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.glowlit.glow", provider: GlowProvider()) { entry in
            GlowWidgetView(entry: entry)
        }
        .configurationDisplayName("My glow")
        .description("Your latest creation, credits left and quick actions.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}
