import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Instagram Stories sharing through the documented pasteboard handoff.
/// Instagram requires a Meta (Facebook) App ID (`AppConfig.instagramAppID`);
/// without one the composer falls back to the system share sheet.
enum InstagramStories {
    @MainActor
    static func isAvailable(appID: String) -> Bool {
        guard !appID.isEmpty, let url = URL(string: "instagram-stories://share") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// A 9:16 card goes in as the background; any other image becomes a
    /// movable sticker on a blush-to-petal background.
    @MainActor
    static func share(_ image: UIImage, asBackground: Bool, appID: String) async -> Bool {
        guard let url = URL(string: "instagram-stories://share?source_application=\(appID)"),
              let data = asBackground ? image.jpegData(compressionQuality: 0.92) : image.pngData() else { return false }
        var item: [String: Any] = [:]
        if asBackground {
            item["com.instagram.sharedSticker.backgroundImage"] = data
        } else {
            item["com.instagram.sharedSticker.stickerImage"] = data
            item["com.instagram.sharedSticker.backgroundTopColor"] = "#F7C1D9"
            item["com.instagram.sharedSticker.backgroundBottomColor"] = "#F8E0EA"
        }
        UIPasteboard.general.setItems([item], options: [.expirationDate: Date().addingTimeInterval(5 * 60)])
        return await UIApplication.shared.open(url)
    }
}

/// UIKit share sheet (lets us share files that carry provenance metadata).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Adds the caption only where text travels with an image (Messages, Mail,
/// X, WhatsApp, Telegram…); photo-first apps such as Instagram get the image
/// alone, and the composer copies the caption for them.
final class CaptionActivityItem: NSObject, UIActivityItemSource {
    private let caption: String

    private static let textFriendly: Set<String> = [
        UIActivity.ActivityType.message.rawValue,
        UIActivity.ActivityType.mail.rawValue,
        UIActivity.ActivityType.postToTwitter.rawValue,
        UIActivity.ActivityType.postToFacebook.rawValue,
        "net.whatsapp.WhatsApp.ShareExtension",
        "ph.telegra.Telegraph.Share",
        "com.atebits.Tweetie2.ShareExtension",
        "com.burbn.barcelona.ShareExtension",
    ]

    init(caption: String) {
        self.caption = caption
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        caption
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        guard let activityType, Self.textFriendly.contains(activityType.rawValue) else { return nil }
        return caption
    }
}

struct ActivityItems: Identifiable {
    let id = UUID()
    let items: [Any]
}

extension View {
    /// The system share sheet for `item`: a sheet on iPhone and iPad. The Mac
    /// shows a share popover instead of a sheet, so there it's presented from
    /// an invisible view behind this one and `item` is cleared when it closes.
    func shareSheet(item: Binding<ActivityItems?>) -> some View {
        #if targetEnvironment(macCatalyst)
        background(MacSharePresenter(item: item))
        #else
        sheet(item: item) { item in
            ShareSheet(items: item.items)
                .presentationDetents([.medium, .large])
        }
        #endif
    }
}

#if targetEnvironment(macCatalyst)
/// Presents the share popover once per request; the request is cleared when
/// she picks an app or closes it.
private struct MacSharePresenter: UIViewControllerRepresentable {
    @Binding var item: ActivityItems?

    final class Coordinator {
        var shownID: UUID?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIViewController {
        let anchor = UIViewController()
        anchor.view.isUserInteractionEnabled = false
        return anchor
    }

    func updateUIViewController(_ anchor: UIViewController, context: Context) {
        guard let request = item, request.id != context.coordinator.shownID, anchor.view.window != nil else { return }
        context.coordinator.shownID = request.id
        let share = UIActivityViewController(activityItems: request.items, applicationActivities: nil)
        share.completionWithItemsHandler = { _, _, _, _ in
            if item?.id == request.id { item = nil }
        }
        if let popover = share.popoverPresentationController {
            let bounds = anchor.view.bounds
            popover.sourceView = anchor.view
            popover.sourceRect = CGRect(x: bounds.midX, y: bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        anchor.present(share, animated: true)
    }
}
#endif
