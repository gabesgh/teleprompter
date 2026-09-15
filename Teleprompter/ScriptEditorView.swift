import SwiftUI

/// Separate window for typing or tweaking the script. Edits flow to the
/// prompter live (debounced) so it stays usable even with long scripts.
struct ScriptEditorView: View {
    @Environment(PrompterModel.self) private var model
    @State private var draft = ""
    @State private var syncWork: DispatchWorkItem?

    private var wordCount: Int {
        draft.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Import…") { model.importFromFile() }
                Button("Paste") { model.pasteFromClipboard() }
                Spacer()
                Text("\(wordCount) words · ~\(max(1, Int((Double(wordCount) / 150).rounded()))) min at 150 wpm")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(12)

            Divider()

            TextEditor(text: $draft)
                .font(.system(size: 16))
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .padding(10)

            Divider()

            HStack {
                Text("Changes show up in the prompter as you type.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { draft = "" }
                Button("Restart from Top") { model.restart() }
            }
            .padding(12)
        }
        .frame(minWidth: 480, minHeight: 360)
        .onAppear { draft = model.script }
        .onChange(of: model.script) { _, new in
            if new != draft { draft = new }      // e.g. after Import / Paste
        }
        .onChange(of: draft) { _, new in
            syncWork?.cancel()
            let work = DispatchWorkItem {
                if model.script != new { model.script = new }
            }
            syncWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }
}
