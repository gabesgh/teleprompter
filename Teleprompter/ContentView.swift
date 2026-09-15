import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(PrompterModel.self) private var model
    @State private var controlsVisible = true
    @State private var hideWork: DispatchWorkItem?
    @State private var dropTargeted = false

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.width < 560 || geo.size.height < 360

            ZStack {
                Color.black

                ScriptView()
                    .contentShape(Rectangle())
                    .onTapGesture { model.togglePlay() }

                EdgeFades()

                if model.showGuide && !model.script.isEmpty {
                    ReadingGuide()
                }

                if model.script.isEmpty {
                    EmptyState(compact: compact)
                }

                ControlsOverlay(compact: compact, visible: controlsVisible)

                HStack {
                    Spacer()
                    ProgressTrack(dimmed: !controlsVisible)
                }

                if dropTargeted {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.orange, lineWidth: 3)
                        .padding(6)
                        .allowsHitTesting(false)
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active: reveal()
                case .ended: scheduleHide(after: 1.0, hideCursor: false)
                }
            }
            .onChange(of: model.isPlaying) { _, playing in
                if playing {
                    scheduleHide(after: 2.5, hideCursor: true)
                } else {
                    hideWork?.cancel()
                    withAnimation(.easeIn(duration: 0.15)) { controlsVisible = true }
                }
            }
        }
        .frame(minWidth: 180, minHeight: 100)
        .background(WindowAccessor { model.attach(window: $0) })
        .onDrop(of: [.fileURL, .plainText], isTargeted: $dropTargeted, perform: handleDrop)
        .preferredColorScheme(.dark)
    }

    // MARK: - Control auto-hide

    private func reveal() {
        if !controlsVisible {
            withAnimation(.easeIn(duration: 0.15)) { controlsVisible = true }
        }
        if model.isPlaying {
            scheduleHide(after: 2.5, hideCursor: true)
        } else {
            hideWork?.cancel()
        }
    }

    private func scheduleHide(after delay: Double, hideCursor: Bool) {
        hideWork?.cancel()
        let work = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.3)) { controlsVisible = false }
            if hideCursor && model.isPlaying { NSCursor.setHiddenUntilMouseMoves(true) }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Drag & drop

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                var url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else if let direct = item as? URL { url = direct }
                if let url { DispatchQueue.main.async { model.load(url: url) } }
            }
            return true
        }
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                var text: String?
                if let string = item as? String { text = string }
                else if let data = item as? Data { text = String(data: data, encoding: .utf8) }
                if let text { DispatchQueue.main.async { model.setScript(text) } }
            }
            return true
        }
        return false
    }
}

// MARK: - Scrolling text

private struct TextHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct ScriptView: View {
    @Environment(PrompterModel.self) private var model

    var body: some View {
        GeometryReader { geo in
            let viewportHeight = geo.size.height
            let guideY = viewportHeight * model.guidePosition
            // Half a line, so the guide runs through the middle of the current line.
            let topPad = max(0, guideY - model.fontSize * 0.7)

            VStack(spacing: 0) {
                // Top pad: first line starts on the guide. Bottom pad: last line scrolls past it.
                Color.clear.frame(height: topPad)
                Text(model.script)
                    .font(.system(size: model.fontSize, weight: .medium))
                    .foregroundStyle(.white)
                    .lineSpacing(model.fontSize * 0.28)
                    .multilineTextAlignment(model.centered ? .center : .leading)
                    .fixedSize(horizontal: false, vertical: true)   // never truncate: take full natural height
                    .frame(maxWidth: .infinity, alignment: model.centered ? .center : .leading)
                    .padding(.horizontal, max(18, geo.size.width * 0.06))
                    .padding(.trailing, 14)
                    .background(GeometryReader { text in
                        Color.clear.preference(key: TextHeightKey.self, value: text.size.height)
                    })
                Color.clear.frame(height: viewportHeight - guideY)
            }
            .frame(width: geo.size.width, alignment: .top)
            .offset(y: -model.offset)
            .onPreferenceChange(TextHeightKey.self) { model.updateTextHeight($0) }
            .onAppear { model.viewportHeight = viewportHeight }
            .onChange(of: viewportHeight) { _, new in model.viewportHeight = new }
        }
        .clipped()
        .scaleEffect(x: model.mirrored ? -1 : 1)
    }
}

// MARK: - Decorations

struct ReadingGuide: View {
    @Environment(PrompterModel.self) private var model

    var body: some View {
        GeometryReader { geo in
            let y = geo.size.height * model.guidePosition
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.orange.opacity(0.75))
                    .frame(height: 2)
                    .offset(y: y - 1)
                Image(systemName: "arrowtriangle.right.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .offset(x: 4, y: y - 7)
            }
        }
        .allowsHitTesting(false)
    }
}

struct EdgeFades: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(0.9), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 50)
            Spacer()
            LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                .frame(height: 70)
        }
        .allowsHitTesting(false)
    }
}

struct EmptyState: View {
    @Environment(PrompterModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let compact: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.alignleft")
                .font(.system(size: compact ? 26 : 42))
                .foregroundStyle(.secondary)
            Text("No script loaded")
                .font(compact ? .headline : .title2.weight(.semibold))
            if !compact {
                Text("Drop a .txt, .md, .rtf or .docx file here — or")
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("Import…") { model.importFromFile() }
                    Button("Paste") { model.pasteFromClipboard() }
                    Button("Type It") { openWindow(id: "editor") }
                }
            }
        }
        .foregroundStyle(.white)
        .padding()
    }
}
