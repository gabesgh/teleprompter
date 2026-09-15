import SwiftUI

struct ControlsOverlay: View {
    @Environment(PrompterEngine.self) private var prompter
    @Environment(CameraController.self) private var camera
    let visible: Bool
    @Binding var showEditor: Bool
    @Binding var showSettings: Bool
    @Binding var showImporter: Bool
    @Binding var cameraHidden: Bool
    let onInteract: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            bottomBar
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
    }

    // MARK: - Top bar

    private var topBar: some View {
        @Bindable var prompter = prompter
        return HStack(spacing: 8) {
            barGroup {
                Menu {
                    Button { showImporter = true } label: { Label("Import from Files", systemImage: "folder") }
                    Button { _ = prompter.pasteFromClipboard() } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                    Button { showEditor = true } label: { Label("Edit Script", systemImage: "square.and.pencil") }
                    Divider()
                    Button(role: .destructive) { prompter.setScript("") } label: { Label("Clear", systemImage: "trash") }
                } label: {
                    Image(systemName: "doc.text")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(.white)
            }
            Spacer()
            barGroup {
                iconToggle("text.line.first.and.arrowtriangle.forward", isOn: $prompter.showGuide)
                iconToggle("arrow.left.and.right.righttriangle.left.righttriangle.right", isOn: $prompter.mirrored)
            }
            barGroup {
                iconButton("arrow.triangle.2.circlepath.camera") { camera.flipCamera() }
                    .disabled(camera.isRecording)
                iconToggle("video.slash", isOn: $cameraHidden)
                iconButton("slider.horizontal.3") { showSettings = true }
            }
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 10) {
            HStack {
                stepper("Speed", value: prompter.speed.formatted(.number.precision(.fractionLength(0...2))) + "×",
                        minus: { prompter.adjustSpeed(by: -0.25) }, plus: { prompter.adjustSpeed(by: 0.25) })
                Spacer(minLength: 8)
                stepper("Size", value: "\(Int(prompter.fontSize))",
                        minus: { prompter.adjustFontSize(by: -2) }, plus: { prompter.adjustFontSize(by: 2) })
            }
            HStack(spacing: 14) {
                iconButton("backward.end.fill") { prompter.restart() }
                playPauseButton
                VStack(alignment: .leading, spacing: 1) {
                    Text(formatTime(prompter.remainingSeconds))
                        .font(.system(.subheadline, design: .rounded).monospacedDigit().weight(.semibold))
                    Text("left")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if camera.isRecording {
                    Text(formatTime(camera.recordingSeconds))
                        .font(.system(.subheadline, design: .rounded).monospacedDigit().weight(.semibold))
                        .foregroundStyle(.red)
                }
                recordButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var playPauseButton: some View {
        Button {
            prompter.togglePlay()
            onInteract()
        } label: {
            Image(systemName: prompter.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 20, weight: .bold))
                .frame(width: 50, height: 50)
                .background(prompter.isPlaying ? Color.white.opacity(0.18) : Color.orange, in: Circle())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(prompter.script.isEmpty)
    }

    private var recordButton: some View {
        Button {
            camera.toggleRecording()
            onInteract()
        } label: {
            ZStack {
                Circle().strokeBorder(.white, lineWidth: 3).frame(width: 60, height: 60)
                RoundedRectangle(cornerRadius: camera.isRecording ? 6 : 24, style: .continuous)
                    .fill(.red)
                    .frame(width: camera.isRecording ? 26 : 48, height: camera.isRecording ? 26 : 48)
                    .animation(.easeInOut(duration: 0.2), value: camera.isRecording)
            }
        }
        .buttonStyle(.plain)
        .disabled(camera.status != .running)
        .opacity(camera.status == .running ? 1 : 0.4)
    }

    // MARK: - Pieces

    private func stepper(_ title: String, value: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
                .padding(.trailing, 4)
            Button { minus(); onInteract() } label: {
                Image(systemName: "minus").frame(width: 30, height: 30).contentShape(Rectangle())
            }
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .frame(minWidth: 44)
            Button { plus(); onInteract() } label: {
                Image(systemName: "plus").frame(width: 30, height: 30).contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(.white.opacity(0.1), in: Capsule())
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button { action(); onInteract() } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private func iconToggle(_ symbol: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle(); onInteract() } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(isOn.wrappedValue ? Color.orange.opacity(0.9) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private func barGroup<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 2, content: content)
            .padding(3)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
