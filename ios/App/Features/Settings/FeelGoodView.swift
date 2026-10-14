import SwiftUI

/// Settings › Feel good: a short, kind note and where to find support
/// (ICO Children's Code standard 13: signpost ages 13–17 to trusted adults
/// and services). Signposting only: no tracking, no prompts, no triggers.
struct FeelGoodView: View {
    @Environment(\.openURL) private var openURL

    private static let helplineURL = URL(string: "https://findahelpline.com")!

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(styled: "Feel *good*", size: 27)
                        .foregroundStyle(Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("Our looks are made to keep your face, skin tone and body as they are.")
                    Text("Some days, scrolling can feel heavy. That's normal, and you don't have to carry it alone.")
                }
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
                .padding(.vertical, 6)
            }
            .listRowBackground(Palette.surface)

            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Talk to someone you trust")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.textPrimary)
                        Text("A parent, a friend, a teacher or a school counselor can help.")
                            .font(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                    }
                } icon: {
                    Image(systemName: "heart.text.square")
                        .foregroundStyle(Palette.accent)
                }
                .padding(.vertical, 4)
                Button {
                    openURL(Self.helplineURL)
                } label: {
                    Label("Find a helpline near you", systemImage: "phone.bubble")
                }
            } footer: {
                Text("findahelpline.com lists free helplines in many countries. It opens in your browser.")
            }
            .listRowBackground(Palette.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Feel good")
        .navigationBarTitleDisplayMode(.inline)
    }
}
