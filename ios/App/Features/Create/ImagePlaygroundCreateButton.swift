import SwiftUI
import AppCore
#if canImport(ImagePlayground)
import ImagePlayground
#endif

#if canImport(ImagePlayground)
/// "Create with Image Playground": Apple's own image maker, offered as an extra
/// in Create on devices that support it. No Aybuke credits or cloud consent:
/// Apple makes the picture under its own terms and limits, and Aybuke only
/// receives the finished image.
///
/// iOS 18.4 is the floor because locking the styles and turning off people
/// from her library both start there.
@available(iOS 18.4, *)
struct ImagePlaygroundCreateButton: View {
    let prompt: String
    let onImage: (UIImage) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground
    @AppStorage("imagePlayground.appleNotice.v1") private var hasSeenAppleNotice = false
    @State private var isSheetPresented = false
    @State private var isNoticePresented = false

    /// From iOS 27, Apple may make the image on Private Cloud Compute, so she
    /// hears that once before her description leaves the device.
    private var mayUseAppleCloud: Bool {
        if #available(iOS 27.0, *) { return true }
        return false
    }

    var body: some View {
        if supportsImagePlayground {
            VStack(alignment: .leading, spacing: 8) {
                Button(action: start) {
                    Label("Create with Image Playground", systemImage: "apple.image.playground")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.secondary)
                Text("Apple's image maker · no Aybuke credits. Style, size and count here don't apply.")
                    .font(.legibleCaption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .imagePlaygroundSheet(
                isPresented: $isSheetPresented,
                concepts: concepts,
                sourceImage: nil,
                onCompletion: finish
            )
            // Apple's own cartoon styles only: never photorealistic or
            // third-party (ChatGPT) styles.
            .imagePlaygroundGenerationStyle(.illustration, in: [.animation, .illustration, .sketch])
            .modifier(NoPersonalization())
            .alert("Image Playground is Apple's", isPresented: $isNoticePresented) {
                Button("Continue") {
                    hasSeenAppleNotice = true
                    isSheetPresented = true
                }
                Button("Not now", role: .cancel) {}
            } message: {
                Text("Apple creates the image on its Private Cloud Compute servers, under Apple's terms and daily limits. Aybuke only gets the finished picture.")
            }
        }
    }

    private var concepts: [ImagePlaygroundConcept] {
        let text = PromptBuilder.sanitize(prompt)
        return text.isEmpty ? [] : [.text(text)]
    }

    private func start() {
        if case .blocked(let reason, _) = ContentPolicy.evaluate(prompt, operation: .textToImage) {
            app.showToast(verbatim: L10n.core(reason), style: .error)
            Haptics.error()
            return
        }
        Haptics.tap()
        if mayUseAppleCloud && !hasSeenAppleNotice {
            isNoticePresented = true
        } else {
            isSheetPresented = true
        }
    }

    /// The URL is temporary: read it right away, off the main actor.
    private func finish(_ url: URL) {
        Task {
            guard let image = await Self.decode(url) else {
                app.showToast("Couldn't open that image. Please try again.", style: .error)
                return
            }
            onImage(image)
        }
    }

    /// Reads and decodes Apple's file in the background (ImageIO, one plain
    /// upright copy), never on the main actor.
    private static func decode(_ url: URL) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return ImageUtilities.decodedImage(from: data)
        }.value
    }
}

/// Keeps people from her photo library out of the sheet.
@available(iOS 18.4, *)
private struct NoPersonalization: ViewModifier {
    func body(content: Content) -> some View {
        // ImagePlaygroundOptions arrived with the iOS 26.4 SDK (Swift 6.3);
        // older toolchains, such as CI's, only know the policy modifier.
        #if compiler(>=6.3)
        if #available(iOS 26.4, *) {
            var options = ImagePlaygroundOptions()
            options.personalization = .disabled
            return AnyView(content.imagePlaygroundOptions(options))
        }
        #endif
        return AnyView(content.imagePlaygroundPersonalizationPolicy(.disabled))
    }
}
#endif
