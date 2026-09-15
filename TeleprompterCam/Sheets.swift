import SwiftUI

struct SettingsSheet: View {
    @Environment(PrompterEngine.self) private var prompter
    @Environment(CameraController.self) private var camera
    @Environment(\.dismiss) private var dismiss
    @Binding var cameraLarge: Bool

    var body: some View {
        @Bindable var prompter = prompter
        NavigationStack {
            Form {
                Section("Prompter") {
                    LabeledSlider("Speed", value: $prompter.speed, range: PrompterEngine.speedRange, step: 0.25,
                                  display: prompter.speed.formatted(.number.precision(.fractionLength(0...2))) + "×")
                    LabeledSlider("Text size", value: $prompter.fontSize, range: PrompterEngine.fontSizeRange, step: 1,
                                  display: "\(Int(prompter.fontSize)) pt")
                    LabeledSlider("Guide position", value: $prompter.guidePosition, range: 0.1...0.7, step: 0.05,
                                  display: "\(Int(prompter.guidePosition * 100))%")
                    Toggle("Reading guide", isOn: $prompter.showGuide)
                    Toggle("Center text", isOn: $prompter.centered)
                    Toggle("Mirror text", isOn: $prompter.mirrored)
                }

                Section("Camera") {
                    Picker("Quality", selection: Binding(get: { camera.quality }, set: { camera.setQuality($0) })) {
                        ForEach(CameraController.Quality.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(camera.isRecording)
                    LabeledSlider("Zoom", value: Binding(get: { camera.displayZoom }, set: { camera.setZoom($0) }),
                                  range: camera.minDisplayZoom...max(camera.maxDisplayZoom, camera.minDisplayZoom + 0.1), step: 0.1,
                                  display: camera.displayZoom.formatted(.number.precision(.fractionLength(0...1))) + "×")
                    Toggle("Large camera window", isOn: $cameraLarge)
                    Button("Switch to \(camera.position == .back ? "front" : "back") camera") { camera.flipCamera() }
                        .disabled(camera.isRecording)
                }

                Section {
                    Text("\(prompter.wordCount) words · about \(max(1, Int((Double(prompter.wordCount) / 150).rounded()))) min at 150 wpm")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Script")
                } footer: {
                    Text("Tap the text to show or hide the controls. Drag the camera window to any corner, pinch it to zoom, double-tap to resize it.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let display: String

    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, display: String) {
        self.title = title; _value = value; self.range = range; self.step = step; self.display = display
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(display).foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}

struct ScriptEditorSheet: View {
    @Environment(PrompterEngine.self) private var prompter
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var showImporter = false
    @State private var errorMessage: String?

    private var wordCount: Int {
        draft.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $draft)
                .font(.body)
                .padding(.horizontal, 8)
                .scrollContentBackground(.hidden)
                .background(Color(.systemBackground))
                .navigationTitle("Script")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            prompter.script = draft
                                .replacingOccurrences(of: "\r\n", with: "\n")
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button { showImporter = true } label: { Label("Import", systemImage: "folder") }
                        Button {
                            if let text = UIPasteboard.general.string { draft = text }
                        } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                        Spacer()
                        Text("\(wordCount) words").font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        Button(role: .destructive) { draft = "" } label: { Label("Clear", systemImage: "trash") }
                    }
                }
        }
        .onAppear { draft = prompter.script }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: PrompterEngine.importableTypes) { result in
            switch result {
            case .success(let url):
                errorMessage = prompter.load(url: url)
                if errorMessage == nil { draft = prompter.script }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .alert("Couldn't load script", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }
}
