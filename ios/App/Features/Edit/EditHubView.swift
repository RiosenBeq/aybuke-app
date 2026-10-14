import SwiftUI
import AppCore

/// The "Edit" tab: pick a tool, then a photo.
struct EditHubView: View {
    @Environment(AppModel.self) private var app

    /// Two columns on iPhone, more on iPad.
    private let columns = [GridItem(.adaptive(minimum: 136), spacing: 12)]
    /// Light aura palettes only: tool icons stay ink on colour.
    private static let toolPalettes: [AuraPalette] = [.bubblegum, .lilac, .mint, .sunset, .butter]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(styled: "Edit & *glow up*", size: 25)
                            .foregroundStyle(Palette.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text("Choose a tool, then a photo.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .tipSlot(.editHub)

                    Button {
                        Haptics.tap()
                        app.startEditing()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(Palette.blush)
                                .frame(width: 54, height: 54)
                                .background(Palette.ink, in: .control)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Open a photo")
                                    .font(.cardTitle)
                                    .foregroundStyle(Palette.ink)
                                Text("All tools in one editor")
                                    .font(.footnote)
                                    .foregroundStyle(Palette.ink.opacity(0.7))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(Palette.ink.opacity(0.6))
                        }
                        .padding(14)
                        .cardStyle(fill: Palette.blush)
                        .glowSweep()
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.97))
                    .reveal(1)

                    // Cloud AI, so not under 13 (like Magic Edit).
                    if app.allowsCloudAI {
                        makeupStudioCard
                            .reveal(2)
                    }

                    if RetroCam.isAvailable {
                        RetroCamHubCard()
                            .reveal(2)
                    }

                    Button {
                        Haptics.tap()
                        app.isBestShotPresented = true
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "photo.stack")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                                .frame(width: 54, height: 54)
                                .background(Palette.petal, in: .control)
                            VStack(alignment: .leading, spacing: 3) {
                                TitleWithNewBadge(title: "Find your best shot")
                                Text("Finds the best light & focus · free, on-device")
                                    .font(.footnote)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(Palette.textTertiary)
                        }
                        .padding(14)
                        .cardStyle()
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.97))
                    .reveal(2)

                    CollageHubCard()
                        .reveal(2)

                    Button {
                        Haptics.tap()
                        app.isVideoPickerPresented = true
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "video.fill")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Palette.blush)
                                .frame(width: 54, height: 54)
                                .background(Palette.ink, in: .control)
                            VStack(alignment: .leading, spacing: 3) {
                                TitleWithNewBadge(title: "Edit a video")
                                Text("Cut silences, 80s & 90s effects · free")
                                    .font(.footnote)
                                    .foregroundStyle(Palette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(Palette.textTertiary)
                        }
                        .padding(14)
                        .cardStyle()
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.97))
                    .tourAnchor(.edit)
                    .reveal(2)

                    LazyVGrid(columns: columns, spacing: 12) {
                        // Makeup Studio has its own card above.
                        ForEach(Array(EditorTool.available(cloudAI: app.allowsCloudAI).filter { $0 != .makeup }.enumerated()), id: \.element) { index, tool in
                            Button {
                                Haptics.tap()
                                app.startEditing(tool: tool)
                            } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    Image(systemName: tool.symbolName)
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(Palette.ink)
                                        .frame(width: 40, height: 40)
                                        .background(
                                            AuraFill(palette: Self.toolPalettes[index % Self.toolPalettes.count])
                                                .clipShape(.chip)
                                        )
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(tool.title)
                                            .font(.cardTitle)
                                            .foregroundStyle(Palette.textPrimary)
                                        Text(tool.caption)
                                            .font(.caption)
                                            .foregroundStyle(Palette.textSecondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                                .padding(16)
                                .cardStyle()
                            }
                            .buttonStyle(.pressable)
                            .reveal(2 + index)
                        }
                    }

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(Palette.success)
                            .accessibilityHidden(true)
                        // Under 13 there are no cloud edits to mention.
                        Group {
                            if app.allowsCloudAI {
                                Text("Background removal and adjustments run on your device. Cloud edits are never used to train AI and are deleted from our servers within \(app.config.retentionPhrase).")
                            } else {
                                Text("Every tool here runs on your device. Your photos are never uploaded.")
                            }
                        }
                            .font(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 12)
                .readableWidth()
            }
            .scrollIndicators(.hidden)
            .background(AuroraBackground(intensity: 0.3))
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// Makeup Studio: pick a photo, then try looks on it.
    private var makeupStudioCard: some View {
        Button {
            Haptics.tap()
            app.startEditing(tool: .makeup)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: EditorTool.makeup.symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 54, height: 54)
                    .background(AuraFill(palette: .bubblegum).clipShape(.control))
                VStack(alignment: .leading, spacing: 3) {
                    TitleWithNewBadge(title: "Makeup Studio")
                    Text("Try lips, eyes, blush and sparkle on your photo")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(14)
            .cardStyle()
        }
        .buttonStyle(PressableButtonStyle(scale: 0.97))
    }
}
