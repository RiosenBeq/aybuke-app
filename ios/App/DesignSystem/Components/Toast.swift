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
                    .glassPanel(radius: 18)
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { self.message = nil }
                    .task(id: message.id) {
                        UIAccessibility.post(notification: .announcement, argument: message.text)
                        try? await Task.sleep(for: .seconds(3))
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
