import SwiftUI
import AppCore

/// Retro Cam: a full-screen camera with the retro effects live, Glow Cam's
/// looks (light, colour, a makeup tint and sparkle, never retouching), a
/// self-timer and Photo Booth (four shots, 3-2-1 before each, printed as a
/// strip or a grid). Dark like a real camera; free and on the device.
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
            // A Glow look from Explore's look finder.
            if let look = app.retroCamGlowLook {
                app.retroCamGlowLook = nil
                model.select(.glow)
                model.selectGlow(AdjustVibes.preset(id: look))
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
        .onChange(of: reduceMotion, initial: true) { _, reduce in model.reducesMotion = reduce }
        .onChange(of: model.tintPauses) { _, _ in
            app.showToast("Makeup tint turned off to keep the camera smooth.")
        }
        // Toasts, the share composer and the Photos alert: the root's copy is covered.
        .modifier(AppPresentations(isActive: true))
    }

    // MARK: Camera

    private var camera: some View {
        VStack(spacing: 0) {
            topBar
            preview
            controls
        }
    }

    private var isPanelOpen: Bool {
        model.family == .glow && model.glowPanel != nil
    }

    /// The looks, modes and shutter. An open Glow panel takes their place,
    /// so the whole picture stays in view while she picks.
    private var controls: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                familyPicker
                lookStrip
                bottomBar
            }
            .opacity(isPanelOpen ? 0 : 1)
            .allowsHitTesting(!isPanelOpen)
            .accessibilityHidden(isPanelOpen)
            if isPanelOpen, let panel = model.glowPanel {
                glowPanel(panel)
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.top, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.28), value: model.glowPanel)
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
        livePicture
            .overlay(alignment: .trailing) {
                if model.family == .glow, !model.isShooting {
                    glowRail
                        .padding(.trailing, 10)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .top) {
                if model.family == .glow, model.glow.hasTint, !model.tintSeesFace, !model.isShooting {
                    Label("Looking for a face…", systemImage: "face.dashed")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.55), in: .pill)
                        .padding(.top, 14)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.tintSeesFace)
            .animation(.easeInOut(duration: 0.2), value: model.isShooting)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 8)
    }

    /// The camera's picture: exactly what the shot will get.
    private var livePicture: some View {
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
                    .background(.black.opacity(0.55), in: .pill)
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
            // A tap on the picture closes a Glow panel.
            .onTapGesture {
                if model.glowPanel != nil { model.glowPanel = nil }
            }
            .gesture(
                DragGesture(minimumDistance: 24).onEnded { value in
                    guard !model.isShooting, abs(value.translation.width) > abs(value.translation.height) else { return }
                    if value.translation.width < -50 { model.step(1) }
                    if value.translation.width > 50 { model.step(-1) }
                }
            )
            .accessibilityElement()
            .accessibilityLabel(Text("Camera preview"))
            .accessibilityValue(Text(verbatim: model.lookTitle))
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
        .background(.black.opacity(0.45), in: .pill)
        .padding(.top, 14)
        .animation(.snappy, value: model.boothCount)
    }

    // MARK: Looks

    /// Retro effects or Glow looks.
    private var familyPicker: some View {
        HStack(spacing: 2) {
            ForEach(RetroCamModel.Family.allCases) { family in
                let isSelected = model.family == family
                Button { model.select(family) } label: {
                    Label { Text(family.title) } icon: { Image(systemName: family.symbolName) }
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(isSelected ? Palette.ink : .white)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 36)
                        .background(isSelected ? Palette.blush : Color.clear, in: .pill)
                        .contentShape(.pill)
                }
                .buttonStyle(.pressable)
                .macHoverLift()
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.12), in: .pill)
        .padding(.top, 8)
        .animation(.snappy(duration: 0.25), value: model.family)
    }

    @ViewBuilder
    private var lookStrip: some View {
        switch model.family {
        case .retro: effectStrip
        case .glow: glowStrip
        }
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

    /// Natural, then the editor's vibes: the same names and numbers as Adjust.
    private var glowStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                glowChip(nil)
                ForEach(GlowCam.vibes) { vibe in
                    glowChip(vibe)
                }
            }
            .padding(.horizontal, Metrics.gutter)
        }
        .scrollIndicators(.hidden)
        .padding(.vertical, 10)
    }

    private func glowChip(_ vibe: AdjustVibe?) -> some View {
        let isSelected = model.glow.vibeID == vibe?.id
        let title = RetroCamModel.glowTitle(vibe)
        return Button { model.selectGlow(vibe) } label: {
            VStack(spacing: 2) {
                Image(systemName: vibe?.symbolName ?? "sun.min")
                    .font(.footnote.weight(.bold))
                Text(verbatim: title)
                    .font(.subheadline.weight(.bold))
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .foregroundStyle(isSelected ? Palette.ink : .white)
            .background(isSelected ? Palette.blush : Color.white.opacity(0.12), in: .chip)
        }
        .buttonStyle(.pressable)
        .macHoverLift()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Glow tools

    /// Light, sparkle and makeup down the side of the picture, like a social camera.
    private var glowRail: some View {
        VStack(spacing: 14) {
            RailButton(symbol: "sun.max", label: Text("Adjust"), isOn: model.glow.hasLightChange, isOpen: model.glowPanel == .light) {
                model.toggleGlowPanel(.light)
            }
            RailButton(symbol: "sparkle", label: Text("Sparkle"), isOn: model.glow.sparkle) {
                model.toggleSparkle()
            }
            RailButton(symbol: "paintbrush.pointed", label: Text("Makeup"), isOn: model.glow.hasTint, isOpen: model.glowPanel == .makeup) {
                model.toggleGlowPanel(.makeup)
            }
        }
    }

    private func glowPanel(_ panel: RetroCamModel.GlowPanel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                (panel == .light ? Text("Adjust") : Text("Makeup"))
                    .font(.headline.weight(.heavy))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if panel == .light, model.glow.hasLightChange {
                    Button("Reset") { model.resetGlowLight() }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Palette.blush)
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                }
                Button { model.glowPanel = nil } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 40, height: 40)
                        .background(Palette.blush, in: Circle())
                }
                .buttonStyle(PressableButtonStyle(scale: 0.92))
                .accessibilityLabel(Text("Done"))
                .macHelp(Text("Done"))
            }
            switch panel {
            case .light: lightControls
            case .makeup: makeupControls
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(Color.white.opacity(0.1), in: .card)
        .readableWidth(Metrics.compactWidth, alignment: .center)
    }

    private var lightControls: some View {
        VStack(spacing: 6) {
            lightSlider(Text("Brightness"), symbol: "sun.max", value: Binding(
                get: { model.glow.brightness },
                set: { model.setGlowLight(brightness: abs($0) < 0.04 ? 0 : $0) }
            ))
            lightSlider(Text("Contrast"), symbol: "circle.lefthalf.filled", value: Binding(
                get: { model.glow.contrast },
                set: { model.setGlowLight(contrast: abs($0) < 0.04 ? 0 : $0) }
            ))
        }
    }

    private func lightSlider(_ label: Text, symbol: String, value: Binding<Double>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(width: 22)
                .accessibilityHidden(true)
            label
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 96, alignment: .leading)
                .accessibilityHidden(true)
            Slider(value: value, in: -1...1) { label }
                .tint(Palette.blush)
        }
        .frame(minHeight: 44)
    }

    private var makeupControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            swatchRow(Text("Lips"), choices: [MakeupLips.none] + GlowCam.lipColors, selected: model.glow.lips) { model.setLips($0) }
            swatchRow(Text("Cheeks"), choices: [MakeupCheeks.none] + GlowCam.cheekColors, selected: model.glow.cheeks) { model.setCheeks($0) }
            Text("Just color, made on your device. Your face stays exactly as it is.")
                .font(.legibleCaption2)
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func swatchRow<Choice: MakeupChoice>(_ title: Text, choices: [Choice], selected: Choice,
                                                 select: @escaping (Choice) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            title
                .font(.legibleCaption.weight(.bold))
                .foregroundStyle(.white.opacity(0.8))
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(choices) { choice in
                        SwatchButton(hex: choice.swatch, name: L10n.core(choice.name), isSelected: choice == selected) {
                            select(choice)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
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
        Button {
            model.glowPanel = nil
            model.shutter(app: app)
        } label: {
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

/// A Glow tool down the side of the picture: a round button with its name
/// under it; white when it's on, ringed while its panel is open.
private struct RailButton: View {
    let symbol: String
    let label: Text
    var isOn = false
    var isOpen = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isOn ? Palette.ink : .white)
                    .frame(width: 44, height: 44)
                    .background(isOn ? Color.white : Color.black.opacity(0.4), in: Circle())
                    .overlay(Circle().strokeBorder(Palette.blush, lineWidth: isOpen ? 2.5 : 0))
                label
                    .font(.legibleCaption2.weight(.bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
                    .lineLimit(1)
                    .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.92))
        .macHoverLift(scale: 1.05)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .macHelp(label)
    }
}

/// A round makeup colour; "As is" is a crossed-out ring.
private struct SwatchButton: View {
    let hex: String?
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if let hex, let color = UIColor(hexString: hex) {
                    Circle().fill(Color(uiColor: color))
                } else {
                    Circle().fill(Color.white.opacity(0.12))
                    Image(systemName: "nosign")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(width: 36, height: 36)
            .padding(4)
            .overlay(Circle().strokeBorder(isSelected ? Color.white : Color.clear, lineWidth: 2.5))
            .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.9))
        .macHoverLift(scale: 1.06)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .macHelp(Text(verbatim: name))
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
                    Text("Live retro effects, Glow looks & Retro Booth · free")
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
