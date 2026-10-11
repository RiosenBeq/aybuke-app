import SwiftUI
import AppCore

/// The "Edit" tab: pick a tool, then a photo.
struct EditHubView: View {
    @Environment(AppModel.self) private var app

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Edit")
                            .font(.screenTitle)
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
                                .foregroundStyle(Palette.onPrimary)
                                .frame(width: 54, height: 54)
                                .background(Palette.brandGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Open a photo")
                                    .font(.cardTitle)
                                    .foregroundStyle(Palette.textPrimary)
                                Text("All tools in one editor")
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
                    .buttonStyle(.plain)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(EditorTool.allCases) { tool in
                            Button {
                                Haptics.tap()
                                app.startEditing(tool: tool)
                            } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    Image(systemName: tool.symbolName)
                                        .font(.title2.weight(.semibold))
                                        .foregroundStyle(Palette.brandGradient)
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
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(Palette.success)
                        Text("Background removal and adjustments run on your iPhone. Cloud edits are deleted from our servers within \(app.config.dataRetentionHours) hours.")
                            .font(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .background(Palette.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
