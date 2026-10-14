import UIKit
#if !targetEnvironment(macCatalyst)
import ActivityKit
#endif
import WidgetKit
import AppCore

#if !targetEnvironment(macCatalyst)
/// Starts, updates and ends the generation Live Activity (Dynamic Island and
/// Lock Screen) for cloud AI jobs.
@MainActor
final class GlowActivityController {
    private var activity: Activity<GlowActivityAttributes>?
    private var overtime: Task<Void, Never>?

    /// Returns false when Live Activities are off or couldn't start.
    @discardableResult
    func start(title: String, symbolName: String, expectedSeconds: TimeInterval) -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
        endImmediately()
        let now = Date()
        let state = GlowActivityAttributes.ContentState(stage: .creating, startedAt: now, expectedEnd: now.addingTimeInterval(expectedSeconds))
        activity = try? Activity.request(
            attributes: GlowActivityAttributes(title: title, symbolName: symbolName),
            content: ActivityContent(state: state, staleDate: now.addingTimeInterval(600)),
            pushType: nil
        )
        guard let started = activity else { return false }
        // Running long: once the bar is full, say "Adding the final sparkle…"
        // so a full bar never looks stuck.
        overtime = Task { [weak self] in
            try? await Task.sleep(for: .seconds(expectedSeconds))
            guard !Task.isCancelled, self?.activity?.id == started.id else { return }
            var finishing = state
            finishing.stage = .finishing
            await started.update(ActivityContent(state: finishing, staleDate: now.addingTimeInterval(600)))
        }
        return true
    }

    /// Shows "ready" (or "didn't work"). In the foreground it clears after a
    /// few seconds; if she's away it stays on the Lock Screen for an hour.
    func finish(success: Bool, lingers: Bool) {
        overtime?.cancel()
        overtime = nil
        guard let activity else { return }
        self.activity = nil
        let started = activity.content.state.startedAt
        let state = GlowActivityAttributes.ContentState(stage: success ? .ready : .failed, startedAt: started, expectedEnd: Date())
        Task {
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .after(Date().addingTimeInterval(lingers ? 3600 : success ? 8 : 5))
            )
        }
    }

    /// Ends activities left over from an earlier launch (say the app was
    /// closed mid-job), so the Lock Screen never shows a job that's stuck.
    func endLeftovers() {
        for leftover in Activity<GlowActivityAttributes>.activities where leftover.id != activity?.id {
            Task { await leftover.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// She cancelled: no "didn't work" state, just go.
    func cancel() {
        endImmediately()
    }

    /// "Delete my data": activity titles are her prompts.
    func endAll() {
        endImmediately()
        endLeftovers()
    }

    private func endImmediately() {
        overtime?.cancel()
        overtime = nil
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
#else
/// Macs have no Live Activities: `start` reports false, so a finished job is
/// announced with a notification instead (if she opted in).
@MainActor
final class GlowActivityController {
    @discardableResult
    func start(title: String, symbolName: String, expectedSeconds: TimeInterval) -> Bool { false }
    func finish(success: Bool, lingers: Bool) {}
    func endLeftovers() {}
    func cancel() {}
    func endAll() {}
}
#endif

extension GlowActivityController {
    /// Typical duration per operation, used for the self-animating progress bar.
    static func expectedSeconds(for operation: AIOperation, outputs: Int) -> TimeInterval {
        let base: TimeInterval
        switch operation {
        case .textToImage: base = 14
        case .magicEdit, .restyle: base = 12
        case .enhance: base = 10
        case .eraseObject: base = 8
        case .removeBackground: base = 3
        }
        return base + Double(max(0, outputs - 1)) * 4
    }
}

/// Keeps the widgets' App Group snapshot (credits, latest creation) current.
enum GlowWidgetBridge {
    /// File reads and writes in the App Group, the picture's JPEG and the
    /// WidgetKit reloads happen here, in order, off the main thread (a save
    /// used to wait for them).
    private static let queue = DispatchQueue(label: "app.glowlit.widgets", qos: .utility)

    static func update(
        credits: Int, isPro: Bool, nextRefill: Date?, latest: Creation?, creationsCount: Int,
        breakdown: CreditBreakdown? = nil, nextGrant: Date? = nil, cloudAIAllowed: Bool = true, allowance: Int? = nil
    ) {
        let snapshot = GlowWidgetSnapshot(
            credits: credits,
            isPro: isPro,
            nextRefill: isPro ? nil : nextRefill,
            latestTitle: latest.flatMap(widgetTitle(for:)),
            latestIsFavorite: latest?.isFavorite ?? false,
            creationsCount: creationsCount,
            daily: breakdown?.daily,
            monthly: breakdown?.monthly,
            packs: breakdown?.packs,
            nextGrant: isPro ? nextGrant : nil,
            cloudAIAllowed: cloudAIAllowed,
            allowance: allowance
        )
        queue.async {
            let previous = GlowSharedStore.load()
            var unchanged = snapshot
            unchanged.updatedAt = previous?.updatedAt ?? snapshot.updatedAt
            guard previous != unchanged else { return }
            GlowSharedStore.save(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
            if previous?.showsCloudAI != snapshot.showsCloudAI { reloadControls() }
        }
    }

    /// Only catalog text reaches the widget (it can show on the Lock Screen
    /// and in StandBy): a Magic Edit or Create title is her prompt, so those
    /// show "Your latest creation" instead.
    private static func widgetTitle(for creation: Creation) -> String? {
        switch creation.operation {
        case .magicEdit, .textToImage: return nil
        default: return creation.title
        }
    }

    /// The Magic Edit control turns into Cut out under 13.
    private static func reloadControls() {
        #if !targetEnvironment(macCatalyst) || compiler(>=6.2)
        if #available(iOS 18.0, *) { ControlCenter.shared.reloadAllControls() }
        #endif
    }

    /// A ~600 px thumbnail of the newest creation for the "My glow" widget.
    static func updateLatestImage(_ image: UIImage?) {
        queue.async {
            let jpeg = image.flatMap { ImageUtilities.jpegData($0, maxLongEdge: 600, quality: 0.85) }
            GlowSharedStore.saveLatestImage(jpeg)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
