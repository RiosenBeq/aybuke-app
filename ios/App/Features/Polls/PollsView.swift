import SwiftUI
import AppCore

/// "Your polls": each poll's question, its two pictures (the small copies
/// kept here), the votes with gentle bars, the time left, Share again and
/// Delete. Read on open, on pull to refresh and every minute while it's on
/// screen; an ended poll keeps its last counts for a day. Counts only, never
/// a winner: friends picked a vibe, nobody lost.
struct PollsView: View {
    var focus: String?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var now = Date()
    @State private var pendingDelete: PollRecord?
    @State private var deleting: Set<String> = []
    @State private var shareItems: ActivityItems?
    @State private var notice: String?

    private var polls: PollsModel { app.polls }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        if let notice {
                            PollNotice(text: notice)
                                .transition(.opacity)
                        }
                        if polls.records.isEmpty {
                            empty
                        }
                        ForEach(polls.records) { record in
                            PollCard(record: record, now: now, isFocused: record.id == focus,
                                     isDeleting: deleting.contains(record.id),
                                     share: { share(record) }, delete: { pendingDelete = record })
                                .id(record.id)
                        }
                        Text("Polls end after 24 hours. Then the pictures, the question and the votes are deleted from our servers; this device keeps the last counts for a day.")
                            .font(.legibleCaption)
                            .foregroundStyle(Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.vertical, 16)
                    .readableWidth(Metrics.compactWidth)
                    .animation(.snappy, value: polls.records.map(\.id))
                    .animation(.snappy, value: notice)
                }
                .refreshable { await polls.refresh() }
                .task {
                    guard let focus else { return }
                    try? await Task.sleep(for: .milliseconds(300))
                    withAnimation(.snappy) { proxy.scrollTo(focus, anchor: .top) }
                }
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle(Text("Your polls"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(Palette.accent)
        // On open, then every minute while it's on screen.
        .task {
            while !Task.isCancelled {
                now = Date()
                await polls.refresh()
                now = Date()
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .confirmationDialog("Delete this poll?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible, presenting: pendingDelete) { record in
            Button("Delete", role: .destructive) { delete(record) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The link stops working, and the pictures, the question and the votes are deleted.")
        }
        .shareSheet(item: $shareItems)
    }

    @ViewBuilder
    private var header: some View {
        let live = polls.shelf.live(at: now).count
        if live > 0 || polls.remainingToday != nil || polls.refreshFailed {
            VStack(alignment: .leading, spacing: 4) {
                if live > 0 {
                    Text("\(live) live polls")
                        .font(.cardTitle)
                        .foregroundStyle(Palette.textPrimary)
                }
                if let left = polls.remainingToday {
                    Text("\(left) polls left today")
                        .font(.legibleFootnote)
                        .foregroundStyle(Palette.textSecondary)
                }
                if polls.refreshFailed {
                    Label("Couldn't update just now. These are the last counts.", systemImage: "wifi.exclamationmark")
                        .font(.legibleFootnote)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 72, height: 72)
                .background(Palette.blush, in: Circle())
                .accessibilityHidden(true)
            Text("No polls right now")
                .font(.sectionTitle)
                .foregroundStyle(Palette.textPrimary)
            Text("Pick two creations in My Works, or open “Which vibe?” when you share, then choose Ask friends.")
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func share(_ record: PollRecord) {
        Haptics.tap()
        shareItems = ActivityItems(items: [PollShareText.message(question: record.question), record.shareURL])
    }

    private func delete(_ record: PollRecord) {
        let id = record.id
        deleting.insert(id)
        notice = nil
        Task {
            defer { deleting.remove(id) }
            do {
                try await polls.delete(id)
                app.notePollDeleted(id)
                Haptics.success()
            } catch {
                Haptics.error()
                notice = polls.message(for: error)
            }
        }
    }
}

/// One poll: question, time left, the two pictures with their votes, and what she can do with it.
struct PollCard: View {
    let record: PollRecord
    let now: Date
    var isFocused = false
    var isDeleting = false
    let share: () -> Void
    let delete: () -> Void

    @Environment(AppModel.self) private var app
    @State private var images: [PollSide: UIImage] = [:]

    private var isRemoved: Bool { record.status == .takenDown }
    private var hasEnded: Bool { record.hasEnded(at: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Group {
                    if let question = record.question {
                        Text(verbatim: question)
                    } else {
                        Text("Which vibe?")
                    }
                }
                .font(.cardTitle)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                statusChip
            }
            if isRemoved {
                removed
            } else {
                HStack(alignment: .top, spacing: 12) {
                    side(.a)
                    side(.b)
                }
                if record.votes.total == 0 && !hasEnded {
                    Text("No votes yet. Share the link with your friends.")
                        .font(.legibleFootnote)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            actions
        }
        .padding(16)
        .cardStyle()
        .overlay {
            if isFocused {
                RoundedRectangle.card.strokeBorder(Palette.accent.opacity(0.45), lineWidth: 1.5)
            }
        }
        .opacity(isDeleting ? 0.5 : 1)
        .task(id: record.id) {
            for side in PollSide.allCases {
                if let image = await app.polls.thumbnail(record.id, side) { images[side] = image }
            }
        }
    }

    private var statusChip: some View {
        Group {
            if isRemoved {
                Text("Closed")
            } else {
                switch PollTimeLeft(expiresAt: record.expiresAt, now: now) {
                case .hours(let hours): Text("\(hours) h left")
                case .minutes(let minutes): Text("\(minutes) min left")
                case .ended: Text("Ended")
                }
            }
        }
        .font(.legibleCaption.weight(.semibold))
        .foregroundStyle(hasEnded || isRemoved ? Palette.textSecondary : Palette.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(hasEnded || isRemoved ? Palette.surfaceRaised : Palette.blush, in: Capsule())
        .accessibilityLabel(timeAccessibility)
    }

    private var timeAccessibility: Text {
        if isRemoved { return Text("Closed after a report") }
        if hasEnded { return Text("Ended") }
        return Text("Ends \(record.expiresAt.formatted(.relative(presentation: .named)))")
    }

    private func side(_ side: PollSide) -> some View {
        let votes = record.votes[side]
        let share = record.votes.percentages.map { side == .a ? $0.a : $0.b }
        return VStack(alignment: .leading, spacing: 8) {
            PollSideTile(image: images[side], side: side, madeWithAI: record.ai[side])
            HStack(alignment: .firstTextBaseline) {
                Text("\(votes) votes")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 4)
                if let share {
                    Text(verbatim: share.formatted(.percent))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            PollBar(fraction: share.map { Double($0) / 100 } ?? 0, side: side)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(side == .a ? Text("Picture A") : Text("Picture B"))
        .accessibilityValue(Text("\(votes) votes") + Text(verbatim: share.map { ", " + $0.formatted(.percent) } ?? ""))
    }

    private var removed: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "eye.slash")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 32, height: 32)
                .background(Palette.surfaceRaised, in: Circle())
                .accessibilityHidden(true)
            Text("This poll was closed after a report, so nobody can open it. It's deleted when its 24 hours end.")
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            if !isRemoved && !hasEnded {
                Button(action: share) {
                    Label("Share again", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(role: .destructive, action: delete) {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.secondary)
            .disabled(isDeleting)
            .tint(Palette.danger)
        }
    }
}

/// A soft bar for one side's share of the votes.
struct PollBar: View {
    let fraction: Double
    let side: PollSide
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.surfaceRaised)
                Capsule()
                    .fill(side == .a ? Palette.blush : Palette.auraLilac.opacity(0.7))
                    .frame(width: max(fraction > 0 ? 8 : 0, proxy.size.width * fraction))
            }
        }
        .frame(height: 8)
        .animation(reduceMotion ? nil : Motion.appear, value: fraction)
        .accessibilityHidden(true)
    }
}

/// "Your polls" at the top of My Works while she has some.
struct PollsEntryRow: View {
    @Environment(AppModel.self) private var app
    @State private var now = Date()

    var body: some View {
        let live = app.polls.shelf.live(at: now)
        Button {
            Haptics.tap()
            app.presentPolls()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 40, height: 40)
                    .background(Palette.blush, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your polls")
                        .font(.cardTitle)
                        .foregroundStyle(Palette.textPrimary)
                    Group {
                        if live.isEmpty {
                            Text("See how your friends voted")
                        } else {
                            Text("\(live.count) live polls")
                        }
                    }
                    .font(.legibleFootnote)
                    .foregroundStyle(Palette.textSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.legibleFootnote.weight(.semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Palette.surface, in: .card)
            .overlay(RoundedRectangle.card.strokeBorder(Palette.stroke))
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .task {
            // The counts here come from the last read; a fresh one when My Works opens.
            await app.polls.refreshIfStale()
            now = Date()
        }
    }
}
