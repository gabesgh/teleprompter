import SwiftUI

/// Menu bar. ⌘-modified shortcuts live here; single-key shortcuts (space, arrows…)
/// are handled by the model's key monitor so they never steal keystrokes from the editor.
struct AppCommands: Commands {
    @Bindable var model: PrompterModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) { }

        CommandMenu("Script") {
            Button("Import Script…") { model.importFromFile() }
                .keyboardShortcut("o")
            Button("Paste from Clipboard") { model.pasteFromClipboard() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            Button("Edit Script…") { openWindow(id: "editor") }
                .keyboardShortcut("e")
            Divider()
            Button("Clear Script") { model.setScript("") }
        }

        CommandMenu("Playback") {
            Button("Play / Pause") { model.togglePlay() }
                .keyboardShortcut(.return)
            Button("Restart from Top") { model.restart() }
                .keyboardShortcut("r")
            Divider()
            Button("Faster") { model.adjustSpeed(by: 0.25) }
                .keyboardShortcut(.upArrow)
            Button("Slower") { model.adjustSpeed(by: -0.25) }
                .keyboardShortcut(.downArrow)
            Button("Jump Back") { model.jump(screens: -0.25) }
                .keyboardShortcut(.leftArrow)
            Button("Jump Forward") { model.jump(screens: 0.25) }
                .keyboardShortcut(.rightArrow)
        }

        CommandMenu("Display") {
            Button("Bigger Text") { model.adjustFontSize(by: 4) }
                .keyboardShortcut("=")
            Button("Smaller Text") { model.adjustFontSize(by: -4) }
                .keyboardShortcut("-")
            Divider()
            Toggle("Mirror Text", isOn: $model.mirrored)
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Toggle("Reading Guide", isOn: $model.showGuide)
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Toggle("Center Text", isOn: $model.centered)
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Divider()
            Toggle("Float on Top", isOn: $model.floatOnTop)
                .keyboardShortcut("t")
            Toggle("Hide from Screen Capture", isOn: $model.hideFromCapture)
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Divider()
            Button("Toggle Full Screen") { model.toggleFullScreen() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
        }
    }
}
