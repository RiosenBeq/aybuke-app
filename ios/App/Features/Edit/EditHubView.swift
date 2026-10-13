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
                        Text(styled: "Edit & *glow up*", size: 28)
                            .foregroundStyle(Palette.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text("Choose a tool, then a photo.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                    }

                    Button {
                        Haptics.tap()
                        app.startEditing()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(Palette.blush)
                                .frame(width: 54, height: 54)
                                .background(Palette.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

                    Button {
                        Haptics.tap()
                        app.isBestShotPresented = true
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "photo.stack")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                                .frame(width: 54, height: 54)
                                .background(Palette.petal, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text("Find your best shot")
                                        .font(.cardTitle)
                                        .foregroundStyle(Palette.textPrimary)
                                    NewBadge()
                                }
                                Text("Ranks your selfies · free, on-device")
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

                    Button {
                        Haptics.tap()
                        app.isVideoPickerPresented = true
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "video.fill")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Palette.blush)
                                .frame(width: 54, height: 54)
                                .background(Palette.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text("Edit a video")
                                        .font(.cardTitle)
                                        .foregroundStyle(Palette.textPrimary)
                                    NewBadge()
                                }
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
                    .reveal(2)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(EditorTool.allCases.enumerated()), id: \.element) { index, tool in
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
                                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                        Text("Background removal and adjustments run on your iPhone. Cloud edits are never used to train AI and are deleted from our servers within \(app.config.retentionPhrase).")
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
}
