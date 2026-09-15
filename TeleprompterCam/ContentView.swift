import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(PrompterEngine.self) private var prompter
    @Environment(CameraController.self) private var camera
    @Environment(\.scenePhase) private var scenePhase

    @State private var controlsVisible = true
    @State private var hideWork: DispatchWorkItem?
    @State private var showEditor = false
    @State private var showSettings = false
    @State private var showImporter = false
    @State private var errorMessage: String?
    @State private var cameraHidden = false
    @State private var cameraLarge = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                ScriptView()
                    .ignoresSafeArea()

                EdgeFades()

                if prompter.showGuide && !prompter.script.isEmpty {
                    ReadingGuide()
                }

                if prompter.script.isEmpty {
                    EmptyState(showEditor: $showEditor, showImporter: $showImporter)
                }

                // Tap anywhere on the text to show/hide the controls.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { toggleControls() }

                ProgressTrack()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .opacity(controlsVisible ? 1 : 0.5)

                if !cameraHidden {
                    CameraWindow(container: geo.size, large: $cameraLarge)
                }

                ControlsOverlay(visible: controlsVisible,
                                showEditor: $showEditor, showSettings: $showSettings,
                                showImporter: $showImporter, cameraHidden: $cameraHidden,
                                onInteract: { keepControlsAlive() })

                if let toast = camera.toast {
                    Toast(text: toast)
                }
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            camera.start()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: camera.resume()
            case .background: prompter.pause(); camera.suspend()
            default: break
            }
        }
        .onChange(of: prompter.isPlaying) { _, playing in
            if playing { scheduleHide() } else { hideWork?.cancel(); show() }
        }
        .sheet(isPresented: $showEditor) { ScriptEditorSheet() }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(cameraLarge: $cameraLarge)
                .presentationDetents([.medium, .large])
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: PrompterEngine.importableTypes) { result in
            switch result {
            case .success(let url): errorMessage = prompter.load(url: url)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .alert("Couldn't load script", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Controls visibility

    private func toggleControls() {
        if controlsVisible {
            hideWork?.cancel()
            withAnimation(.easeOut(duration: 0.2)) { controlsVisible = false }
        } else {
            show()
            if prompter.isPlaying { scheduleHide() }
        }
    }

    private func show() {
        withAnimation(.easeIn(duration: 0.15)) { controlsVisible = true }
    }

    private func keepControlsAlive() {
        if prompter.isPlaying { scheduleHide() }
    }

    private func scheduleHide() {
        hideWork?.cancel()
        let work = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.3)) { controlsVisible = false }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }
}

// MARK: - Scrolling text

private struct TextHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct ScriptView: View {
    @Environment(PrompterEngine.self) private var prompter

    var body: some View {
        GeometryReader { geo in
            let viewportHeight = geo.size.height
            let guideY = viewportHeight * prompter.guidePosition
            let topPad = max(0, guideY - prompter.fontSize * 0.7)

            VStack(spacing: 0) {
                Color.clear.frame(height: topPad)
                Text(prompter.script)
                    .font(.system(size: prompter.fontSize, weight: .medium))
                    .foregroundStyle(.white)
                    .lineSpacing(prompter.fontSize * 0.28)
                    .multilineTextAlignment(prompter.centered ? .center : .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: prompter.centered ? .center : .leading)
                    .padding(.horizontal, max(16, geo.size.width * 0.06))
                    .padding(.trailing, 10)
                    .background(GeometryReader { text in
                        Color.clear.preference(key: TextHeightKey.self, value: text.size.height)
                    })
                Color.clear.frame(height: viewportHeight - guideY)
            }
            .frame(width: geo.size.width, alignment: .top)
            .offset(y: -prompter.offset)
            .onPreferenceChange(TextHeightKey.self) { prompter.updateTextHeight($0) }
            .onAppear { prompter.viewportHeight = viewportHeight }
            .onChange(of: viewportHeight) { _, new in prompter.viewportHeight = new }
        }
        .clipped()
        .scaleEffect(x: prompter.mirrored ? -1 : 1)
    }
}

struct ReadingGuide: View {
    @Environment(PrompterEngine.self) private var prompter

    var body: some View {
        GeometryReader { geo in
            let y = geo.size.height * prompter.guidePosition
            ZStack(alignment: .topLeading) {
                Rectangle().fill(.orange.opacity(0.75)).frame(height: 2).offset(y: y - 1)
                Image(systemName: "arrowtriangle.right.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .offset(x: 3, y: y - 6)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct EdgeFades: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(0.9), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 70)
            Spacer()
            LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                .frame(height: 110)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct ProgressTrack: View {
    @Environment(PrompterEngine.self) private var prompter
    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let trackHeight = geo.size.height
            let total = max(prompter.textHeight + prompter.viewportHeight, 1)
            let thumbHeight = max(28, trackHeight * (prompter.viewportHeight / total))
            let travel = max(trackHeight - thumbHeight, 0)

            ZStack(alignment: .top) {
                Capsule().fill(.white.opacity(0.12))
                Capsule()
                    .fill(dragging ? Color.orange : Color.white.opacity(0.7))
                    .frame(height: thumbHeight)
                    .offset(y: travel * CGFloat(prompter.progress))
            }
            .frame(width: 5)
            .frame(width: 28)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        dragging = true
                        prompter.seek(fraction: Double((drag.location.y - thumbHeight / 2) / max(travel, 1)))
                    }
                    .onEnded { _ in dragging = false }
            )
        }
        .frame(width: 28)
        .padding(.vertical, 90)
        .opacity(prompter.script.isEmpty ? 0 : 1)
    }
}

struct EmptyState: View {
    @Environment(PrompterEngine.self) private var prompter
    @Binding var showEditor: Bool
    @Binding var showImporter: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No script yet")
                .font(.title3.weight(.semibold))
            HStack(spacing: 10) {
                Button("Import") { showImporter = true }
                Button("Paste") { _ = prompter.pasteFromClipboard() }
                Button("Type") { showEditor = true }
            }
            .buttonStyle(.bordered)
        }
        .foregroundStyle(.white)
        .padding()
    }
}

struct Toast: View {
    let text: String
    var body: some View {
        VStack {
            Spacer()
            Text(text)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 150)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .allowsHitTesting(false)
    }
}
