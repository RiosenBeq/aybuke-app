import SwiftUI
import AppCore

/// Retro Cam: a full-screen camera with the retro effects live, a self-timer
/// and Photo Booth (four shots, 3-2-1 before each, printed as a strip or a
/// grid). Dark like a real camera; free and on the device.
struct RetroCamView: View {
    /// Edit: the shot opens in the editor once the camera has closed.
    let onEdit: (UIImage) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = RetroCamModel()
    @State private var flash = 0.0
    @State private var stripPosition: RetroEffect?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch model.phase {
            case .starting:
                ProgressView().tint(.white)
            case .needsPermission:
                permissionPrompt
            case .denied:
                deniedNotice
            case .unavailable:
                unavailableNotice
            case .live:
                // Under the review its controls (and Space and Esc on the Mac) rest.
                camera
                    .disabled(model.shot != nil)
            }
            if let shot = model.shot {
                RetroCamReviewView(shot: shot, onRetake: { Task { await model.retake() } }, onEdit: edit, onClose: close)
                    .transition(.opacity)
            }
        }
        // Dark like a camera; the share sheet and alerts keep the app's look.
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
        .animation(.easeInOut(duration: 0.25), value: model.shot?.id)
        .task {
            // Photo Booth from Siri, Shortcuts or a control.
            if app.retroCamStartsInBooth {
                app.retroCamStartsInBooth = false
                model.mode = .booth
            }
            await model.prepare()
            #if DEBUG
            await model.applyScreenshotOptions(app: app)
            #endif
        }
        // File › Close (⌘W) on the Mac: the camera's own Close button.
        .onAppear { registerClose() }
        .onChange(of: model.shot == nil) { _, _ in registerClose() }
        .onDisappear {
            model.close()
            app.closeActiveCover = nil
        }
        .onChange(of: scenePhase) { _, phase in model.sceneChanged(to: phase) }
        .onChange(of: model.shutterCount) { _, _ in
            guard !reduceMotion else { return }
            flash = 0.85
            withAnimation(.easeOut(duration: 0.35)) { flash = 0 }
        }
        // Toasts, the share composer and the Photos alert: the root's copy is covered.
        .modifier(AppPresentations(isActive: true))
    }

    // MARK: Camera

    private var camera: some View {
        VStack(spacing: 0) {
            topBar
            preview
            effectStrip
            bottomBar
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            CamButton(symbol: "xmark", label: Text("Close"), action: close)
                .macKeyboardShortcut(.cancelAction)
            Spacer()
            HStack(spacing: 10) {
                if model.features.hasFlash {
                    CamButton(symbol: model.isFlashOn ? "bolt.fill" : "bolt.slash.fill", label: Text("Flash"), isOn: model.isFlashOn) {
                        model.isFlashOn.toggle()
                        Haptics.selection()
                    }
                }
                CamButton(symbol: "timer", label: Text("Self-timer"), isOn: model.timer > 0,
                          badge: model.timer > 0 ? Text("\(model.timer)s", comment: "Self-timer length on the camera button, in seconds") : nil) {
                    model.cycleTimer()
                }
                .accessibilityValue(model.timer > 0 ? Text("\(model.timer) seconds") : Text("Off"))
                if let option = model.extraOption {
                    CamButton(symbol: option.symbolName, label: Text(option.label), isOn: model.showsExtra) { model.toggleExtra() }
                }
            }
            .disabled(model.isShooting)
        }
        .padding(.horizontal, Metrics.gutter)
        .frame(height: 60)
    }

    private var preview: some View {
        RetroCamPreview(view: model.previewView)
            .aspectRatio(model.aspect, contentMode: .fit)
            .overlay {
                Color.white.opacity(flash).allowsHitTesting(false)
            }
            .overlay {
                if let value = model.countdown {
                    Text(verbatim: "\(value)")
                        .font(.display(132, weight: .heavy, relativeTo: .largeTitle))
                        .foregroundStyle(.white)
                        .shadow(color: Palette.auraPink.opacity(0.9), radius: 28)
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                        .id(value)
                        .transition(reduceMotion ? .opacity : .scale(scale: 1.6).combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .top) {
                if model.mode == .booth, model.isShooting {
                    boothProgress
                }
            }
            .overlay(alignment: .bottom) {
                if model.isDeveloping {
                    HStack(spacing: 8) {
                        ProgressView().tint(.white)
                        Text("Developing…")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.55), in: .chip)
                    .padding(.bottom, 16)
                }
            }
            .overlay {
                if let pause = model.pause {
                    VStack(spacing: 10) {
                        Image(systemName: "video.slash.fill")
                            .font(.title.weight(.semibold))
                        Text(pause.message)
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.white)
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black.opacity(0.7))
                }
            }
            .animation(.snappy(duration: 0.3), value: model.countdown)
            .clipShape(.card)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 24).onEnded { value in
                    guard !model.isShooting, abs(value.translation.width) > abs(value.translation.height) else { return }
                    if value.translation.width < -50 { model.step(1) }
                    if value.translation.width > 50 { model.step(-1) }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 8)
            .accessibilityElement()
            .accessibilityLabel(Text("Camera preview"))
            .accessibilityValue(Text(verbatim: model.effect.title))
            .accessibilityHint(Text("Swipe up or down to change the effect."))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: model.step(1)
                case .decrement: model.step(-1)
                @unknown default: break
                }
            }
    }

    private var boothProgress: some View {
        HStack(spacing: 6) {
            ForEach(0..<PhotoBooth.shotCount, id: \.self) { index in
                Capsule()
                    .fill(index < model.boothCount ? Palette.blush : Color.white.opacity(0.3))
                    .frame(width: 26, height: 6)
            }
            Text("\(min(model.boothCount + 1, PhotoBooth.shotCount)) of \(PhotoBooth.shotCount)",
                 comment: "Photo booth progress: which of the four shots is next")
                .font(.legibleCaption.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.leading, 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.45), in: .chip)
        .padding(.top, 14)
        .animation(.snappy, value: model.boothCount)
    }

    private var effectStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                // Identified by the effect itself, like the scroll position.
                ForEach(RetroCamModel.effects, id: \.self) { effect in
                    let isSelected = model.effect == effect
                    Button { model.select(effect) } label: {
                        VStack(spacing: 1) {
                            Text(verbatim: effect.title)
                                .font(.subheadline.weight(.bold))
                            Text(verbatim: effect.era)
                                .font(.legibleCaption2.weight(.semibold))
                                .opacity(0.7)
                        }
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 14)
                        .frame(minHeight: 48)
                        .foregroundStyle(isSelected ? Palette.ink : .white)
                        .background(isSelected ? Palette.blush : Color.white.opacity(0.12), in: .chip)
                    }
                    .buttonStyle(.pressable)
                    .macHoverLift()
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, Metrics.gutter)
        }
        .scrollIndicators(.hidden)
        // Keeps the chosen effect in view, also after a swipe on the preview.
        .scrollPosition(id: $stripPosition, anchor: .center)
        .onChange(of: model.effect, initial: true) { _, effect in
            withAnimation(.snappy) { stripPosition = effect }
        }
        .padding(.vertical, 10)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 28) {
                ForEach(RetroCamModel.Mode.allCases) { mode in
                    Button {
                        model.mode = mode
                        Haptics.selection()
                    } label: {
                        Text(mode.title)
                            .font(.legibleFootnote.weight(.heavy))
                            .textCase(.uppercase)
                            .kerning(1.2)
                            .foregroundStyle(model.mode == mode ? Palette.blush : .white.opacity(0.65))
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.mode == mode ? .isSelected : [])
                }
            }
            .disabled(model.isShooting)

            HStack {
                Color.clear.frame(width: 52, height: 52)
                Spacer()
                shutter
                Spacer()
                if model.features.canSwitchCamera {
                    CamButton(symbol: "arrow.triangle.2.circlepath.camera", label: Text("Switch camera"), size: 52) {
                        Task { await model.switchCamera() }
                    }
                    .disabled(model.isShooting)
                } else {
                    Color.clear.frame(width: 52, height: 52)
                }
            }
            .padding(.horizontal, 28)
        }
        .padding(.bottom, 10)
        .readableWidth(Metrics.compactWidth, alignment: .center)
    }

    private var shutter: some View {
        Button { model.shutter(app: app) } label: {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 5)
                    .frame(width: 80, height: 80)
                if model.isShooting {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.auraPink)
                        .frame(width: 30, height: 30)
                } else {
                    Circle()
                        .fill(model.mode == .booth ? Palette.blush : .white)
                        .frame(width: 64, height: 64)
                    if model.mode == .booth {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Palette.ink)
                    }
                }
            }
            .frame(width: 84, height: 84)
            .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.92))
        .macHoverLift(scale: 1.04)
        .disabled(model.isDeveloping || model.pause != nil)
        .accessibilityLabel(model.isShooting ? Text("Stop") : model.mode == .booth ? Text("Start Retro Booth") : Text("Take photo"))
        .macHelp(model.isShooting ? Text("Stop") : model.mode == .booth ? Text("Start Retro Booth") : Text("Take photo"))
        .macKeyboardShortcut(KeyboardShortcut(.space, modifiers: []))
    }

    // MARK: Permission and errors

    private var permissionPrompt: some View {
        CamNotice(symbol: "camera.fill",
                  title: "Strike a *pose*",
                  message: Text("Retro Cam shows 80s, 90s and Y2K effects live, right in the camera. Your photos stay on your device until you share them.")) {
            Button("Turn on the camera") { Task { await model.requestAccess() } }
                .buttonStyle(.primary)
            Button("Not now", action: close)
                .buttonStyle(.secondary)
        }
    }

    private var deniedNotice: some View {
        CamNotice(symbol: "video.slash.fill",
                  title: "Camera access is *off*",
                  message: Platform.isMac
                      ? Text("Allow camera access for Aybuke in System Settings › Privacy & Security › Camera.")
                      : Text("Allow camera access in Settings to use Retro Cam and Retro Booth.")) {
            Button {
                let settings = Platform.isMac ? "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera" : UIApplication.openSettingsURLString
                if let url = URL(string: settings) { openURL(url) }
            } label: {
                Platform.isMac ? Text("Open System Settings") : Text("Open Settings")
            }
            .buttonStyle(.primary)
            Button("Close", action: close)
                .buttonStyle(.secondary)
        }
    }

    private var unavailableNotice: some View {
        CamNotice(symbol: "camera.fill",
                  title: "No camera *found*",
                  message: Text("Retro Cam needs a camera. Connect one and try again.")) {
            Button("Close", action: close)
                .buttonStyle(.secondary)
        }
    }

    // MARK: Actions

    private func close() {
        model.close()
        dismiss()
    }

    /// While a shot is in review, the review registers its own Close (it asks
    /// before an unsaved shot is discarded), so this only sets the camera's.
    private func registerClose() {
        if model.shot == nil { app.closeActiveCover = { close() } }
    }

    private func edit(_ image: UIImage) {
        onEdit(image)
        close()
    }
}

/// A round camera control: white glyph on smoky glass, ink on white when on.
private struct CamButton: View {
    let symbol: String
    let label: Text
    var isOn = false
    var badge: Text?
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.4, weight: .semibold))
                if let badge {
                    badge.font(.legibleCaption.weight(.heavy).monospacedDigit())
                }
            }
            .foregroundStyle(isOn ? Palette.ink : .white)
            .padding(.horizontal, badge == nil ? 0 : 12)
            .frame(minWidth: size, minHeight: size)
            .background(isOn ? Color.white : Color.white.opacity(0.14), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.92))
        .macHoverLift(scale: 1.05)
        .accessibilityLabel(label)
        .macHelp(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Permission and no-camera screens, in the camera's dark look.
private struct CamNotice<Actions: View>: View {
    let symbol: String
    let title: LocalizedStringResource
    let message: Text
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 84, height: 84)
                .background(Palette.blush, in: Circle())
                .accessibilityHidden(true)
            Text(styled: title, size: 27)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            message
                .font(.body)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 12) { actions }
                .padding(.top, 8)
        }
        .padding(Metrics.gutter * 1.5)
        .readableWidth(440, alignment: .center)
    }
}

// MARK: - Entry points

extension View {
    /// Retro Cam's full-screen cover. Edit opens the shot in the editor once
    /// the camera has closed: one full-screen cover at a time.
    func retroCamCover() -> some View {
        modifier(RetroCamCover())
    }
}

private struct RetroCamCover: ViewModifier {
    @Environment(AppModel.self) private var app
    @State private var pendingEdit: UIImage?

    func body(content: Content) -> some View {
        @Bindable var app = app
        content.fullScreenCover(isPresented: $app.isRetroCamPresented, onDismiss: {
            if let image = pendingEdit {
                pendingEdit = nil
                app.openEditor(with: image)
            }
            app.presentationEnded()
        }) {
            RetroCamView { pendingEdit = $0 }
                .environment(app)
        }
    }
}

/// Retro Cam's card on the Edit tab.
struct RetroCamHubCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Button {
            Haptics.tap()
            app.isRetroCamPresented = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "camera.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 54, height: 54)
                    .background(AuraFill(palette: .mint).clipShape(.control))
                VStack(alignment: .leading, spacing: 3) {
                    TitleWithNewBadge(title: "Retro Cam")
                    Text("Live retro effects & Retro Booth · free")
                        .font(.legibleFootnote)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Palette.textTertiary)
            }
            .macFillsCell()
            .padding(14)
            .cardStyle()
        }
        .buttonStyle(PressableButtonStyle(scale: 0.97))
        .macHoverLift()
    }
}
