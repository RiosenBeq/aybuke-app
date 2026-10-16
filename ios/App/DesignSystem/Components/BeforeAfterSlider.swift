import SwiftUI
import UIKit

/// Drag the handle to compare the original (left) with the result (right).
/// The single most-loved interaction in photo-enhancement apps. The first
/// time a result shows here (an AI job, an Enhance fix, the first run) it
/// wipes in from the right over her photo and the handle settles in the
/// middle, which also shows that it moves; a touch stops it at once, and
/// with Reduce Motion the handle simply starts in the middle.
struct BeforeAfterSlider: View {
    let before: UIImage
    let after: UIImage
    var showsTransparencyGrid = false

    @State private var position: CGFloat
    /// She took the handle: the reveal stops where it is.
    @State private var isTouched = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(before: UIImage, after: UIImage, showsTransparencyGrid: Bool = false) {
        self.before = before
        self.after = after
        self.showsTransparencyGrid = showsTransparencyGrid
        let reveals = !UIAccessibility.isReduceMotionEnabled && !CompareReveal.played.contains(after)
        _position = State(initialValue: reveals ? 1 : 0.5)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                if showsTransparencyGrid {
                    CheckerboardBackground()
                }
                Image(uiImage: after)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                Image(uiImage: before)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: max(0, width * position))
                    }

                handle
                    .position(x: width * position, y: proxy.size.height / 2)

                HStack {
                    tag(String(localized: "Before"))
                    Spacer()
                    tag(String(localized: "After"))
                }
                .padding(10)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isTouched = true
                        position = min(max(value.location.x / max(width, 1), 0), 1)
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Before and after comparison")
            .accessibilityValue("\(Int(position * 100)) percent original")
            .accessibilityAdjustableAction { direction in
                isTouched = true
                switch direction {
                case .increment: position = min(position + 0.1, 1)
                case .decrement: position = max(position - 0.1, 0)
                @unknown default: break
                }
            }
        }
        .aspectRatio(after.size.width / max(after.size.height, 1), contentMode: .fit)
        .task(id: ObjectIdentifier(after)) {
            // Once per result, also when a new one takes the last one's place
            // in the same comparison (another look, a free retry): the result
            // wipes in, past the middle, then settles.
            guard !UIAccessibility.isReduceMotionEnabled, !CompareReveal.played.contains(after) else { return }
            CompareReveal.played.add(after)
            isTouched = false
            position = 1
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, !isTouched else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { position = 0.24 }
            try? await Task.sleep(for: .milliseconds(380))
            guard !Task.isCancelled, !isTouched else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.74)) { position = 0.5 }
        }
    }

    private var handle: some View {
        ZStack {
            Rectangle()
                .fill(Color.white)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .shadow(color: .black.opacity(0.4), radius: 3)
            Circle()
                .fill(Color.white)
                .frame(width: 34, height: 34)
                .shadow(color: .black.opacity(0.35), radius: 6)
                .overlay(
                    Image(systemName: "chevron.left.chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Palette.ink)
                )
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.legibleCaption2.weight(.bold))
            // One line: on a narrow photo the words shrink instead of breaking.
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Palette.ink.opacity(reduceTransparency ? 0.9 : 0.65), in: .tag)
    }
}

/// Results that already wiped in, so going back to the comparison doesn't
/// replay it (weak: a result that's gone leaves no trace).
@MainActor
private enum CompareReveal {
    static let played = NSHashTable<UIImage>.weakObjects()
}
