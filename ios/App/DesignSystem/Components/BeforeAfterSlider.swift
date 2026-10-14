import SwiftUI
import UIKit

/// Drag the handle to compare the original (left) with the result (right).
/// The single most-loved interaction in photo-enhancement apps.
struct BeforeAfterSlider: View {
    let before: UIImage
    let after: UIImage
    var showsTransparencyGrid = false

    @State private var position: CGFloat = 0.5
    @State private var hasPeeked = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

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
                        position = min(max(value.location.x / max(width, 1), 0), 1)
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Before and after comparison")
            .accessibilityValue("\(Int(position * 100)) percent original")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: position = min(position + 0.1, 1)
                case .decrement: position = max(position - 0.1, 0)
                @unknown default: break
                }
            }
        }
        .aspectRatio(after.size.width / max(after.size.height, 1), contentMode: .fit)
        .task {
            // A little "peek" so people discover the handle.
            guard !hasPeeked, !reduceMotion else { return }
            hasPeeked = true
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.easeInOut(duration: 0.45)) { position = 0.3 }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.easeInOut(duration: 0.6)) { position = 0.7 }
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { position = 0.5 }
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
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Palette.ink.opacity(reduceTransparency ? 0.9 : 0.65), in: Capsule())
    }
}
