import SwiftUI

/// Floating controls. Full toolbar + transport bar in a normal-sized window;
/// just play/pause + restart when the window is small.
struct ControlsOverlay: View {
    @Environment(PrompterModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let compact: Bool
    let visible: Bool

    var body: some View {
        VStack(spacing: 0) {
            if compact {
                Spacer()
                HStack {
                    compactTransport
                    Spacer()
                }
                .padding(8)
            } else {
                topBar
                    .padding(.top, 8)
                    .padding(.leading, 78)   // clear the traffic lights
                    .padding(.trailing, 16)
                Spacer()
                bottomBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
        }
        .padding(.trailing, 14)   // leave the progress track uncovered
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
    }

    // MARK: - Top bar

    private var topBar: some View {
        @Bindable var model = model
        return HStack(spacing: 10) {
            barGroup {
                iconButton("square.and.arrow.down", help: "Import script (⌘O)") { model.importFromFile() }
                iconButton("doc.on.clipboard", help: "Paste from clipboard (⇧⌘V)") { model.pasteFromClipboard() }
                iconButton("square.and.pencil", help: "Edit script (⌘E)") { openWindow(id: "editor") }
            }
            Spacer()
            barGroup {
                iconToggle("text.aligncenter", help: "Center text (⇧⌘C)", isOn: $model.centered)
                iconToggle("text.line.first.and.arrowtriangle.forward", help: "Reading guide (G)", isOn: $model.showGuide)
                iconToggle("arrow.left.and.right.righttriangle.left.righttriangle.right", help: "Mirror for beam-splitter glass (M)", isOn: $model.mirrored)
            }
            barGroup {
                iconToggle("pin", help: "Float on top of other windows (⌘T)", isOn: $model.floatOnTop)
                iconToggle("eye.slash", help: "Hide from screen recording & sharing (⇧⌘H)", isOn: $model.hideFromCapture)
                iconButton(model.isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                           help: "Full screen (F)") { model.toggleFullScreen() }
            }
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                transport
                Divider().frame(height: 28)
                sliders
                Divider().frame(height: 28)
                remaining
            }
            VStack(spacing: 10) {
                HStack(spacing: 18) {
                    transport
                    Spacer()
                    remaining
                }
                sliders
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var transport: some View {
        HStack(spacing: 8) {
            iconButton("backward.end.fill", help: "Restart (R)") { model.restart() }
            iconButton("gobackward", help: "Jump back (←)") { model.jump(screens: -0.25) }
            playPauseButton(size: 40)
            iconButton("goforward", help: "Jump forward (→)") { model.jump(screens: 0.25) }
        }
    }

    private var sliders: some View {
        @Bindable var model = model
        return HStack(spacing: 18) {
            labeledSlider("Speed", value: $model.speed, range: PrompterModel.speedRange, step: 0.25,
                          display: model.speed.formatted(.number.precision(.fractionLength(0...2))) + "×")
            labeledSlider("Size", value: $model.fontSize, range: PrompterModel.fontSizeRange, step: 2,
                          display: "\(Int(model.fontSize)) pt")
        }
    }

    private var remaining: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(formatTime(model.remainingSeconds))
                .font(.system(.title3, design: .rounded).monospacedDigit().weight(.semibold))
            Text("left · \(Int((model.progress * 100).rounded()))% read")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 64, alignment: .trailing)
    }

    // MARK: - Compact

    private var compactTransport: some View {
        HStack(spacing: 6) {
            iconButton("backward.end.fill", help: "Restart") { model.restart() }
                .font(.system(size: 12))
            playPauseButton(size: 30)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: - Pieces

    private func playPauseButton(size: CGFloat) -> some View {
        Button {
            model.togglePlay()
        } label: {
            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .frame(width: size, height: size)
                .background(model.isPlaying ? Color.white.opacity(0.18) : Color.orange, in: Circle())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .help(model.isPlaying ? "Pause (space)" : "Play (space)")
        .disabled(model.script.isEmpty)
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .help(help)
    }

    private func iconToggle(_ symbol: String, help: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(isOn.wrappedValue ? Color.orange.opacity(0.9) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .help(help)
    }

    private func barGroup<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 2, content: content)
            .padding(4)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func labeledSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                               step: Double, display: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(display).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
                .controlSize(.small)
        }
        .frame(minWidth: 130, maxWidth: 220)
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Vertical progress track on the right edge. Always visible; drag to seek.
struct ProgressTrack: View {
    @Environment(PrompterModel.self) private var model
    @State private var dragging = false
    let dimmed: Bool

    var body: some View {
        GeometryReader { geo in
            let trackHeight = geo.size.height
            let total = max(model.textHeight + model.viewportHeight, 1)
            let thumbHeight = max(24, trackHeight * (model.viewportHeight / total))
            let travel = max(trackHeight - thumbHeight, 0)
            let thumbY = travel * CGFloat(model.progress)

            ZStack(alignment: .top) {
                Capsule().fill(.white.opacity(0.12))
                Capsule()
                    .fill(dragging ? Color.orange : Color.white.opacity(dimmed ? 0.45 : 0.7))
                    .frame(height: thumbHeight)
                    .offset(y: thumbY)
            }
            .frame(width: 6)
            .frame(width: 22)              // wider hit area than the visible track
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        dragging = true
                        let fraction = (drag.location.y - thumbHeight / 2) / max(travel, 1)
                        model.seek(fraction: Double(fraction))
                    }
                    .onEnded { _ in dragging = false }
            )
        }
        .frame(width: 22)
        .padding(.vertical, 10)
        .opacity(model.script.isEmpty ? 0 : 1)
        .help("Drag to jump anywhere in the script")
    }
}
