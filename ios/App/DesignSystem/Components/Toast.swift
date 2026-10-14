import SwiftUI
import UIKit

struct ToastMessage: Identifiable, Equatable {
    enum Style: Equatable {
        case info, success, error
    }

    let id = UUID()
    let text: String
    var style: Style = .info

    fileprivate var symbolName: String {
        switch style {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    /// Long enough to read: by characters, since Japanese and Chinese have no
    /// spaces to count words by, and twice as long while VoiceOver reads it.
    fileprivate var duration: Double {
        let reading = min(8, max(3, Double(text.count) / 14))
        return UIAccessibility.isVoiceOverRunning ? reading * 2 : reading
    }

    fileprivate var tint: Color {
        switch style {
        case .info: return Palette.textPrimary
        case .success: return Palette.success
        case .error: return Palette.danger
        }
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var message: ToastMessage?
    /// A finger on the toast holds it on screen.
    @State private var isHeld = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    HStack(spacing: 10) {
                        Image(systemName: message.symbolName).foregroundStyle(message.tint)
                        Text(message.text)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.textPrimary)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassPanel()
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in isHeld = true }
                            .onEnded { value in
                                isHeld = false
                                // A tap (or a flick up) dismisses it.
                                if abs(value.translation.height) < 10 || value.translation.height < -20 {
                                    self.message = nil
                                }
                            }
                    )
                    .accessibilityAction { self.message = nil }
                    .task(id: message.id) {
                        UIAccessibility.post(notification: .announcement, argument: message.text)
                        var remaining = message.duration
                        while remaining > 0 {
                            try? await Task.sleep(for: .milliseconds(250))
                            if Task.isCancelled { return }
                            if !isHeld { remaining -= 0.25 }
                        }
                        if self.message?.id == message.id {
                            self.message = nil
                        }
                    }
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: message)
    }
}

extension View {
    func toast(_ message: Binding<ToastMessage?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}
