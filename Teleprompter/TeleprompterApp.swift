import SwiftUI
import AppKit

@main
struct TeleprompterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model = PrompterModel.shared

    var body: some Scene {
        Window("Teleprompter", id: "main") {
            ContentView()
                .environment(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 960, height: 620)
        .commands { AppCommands(model: model) }

        Window("Script Editor", id: "editor") {
            ScriptEditorView()
                .environment(model)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 720, height: 540)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// "Open With → Teleprompter" from Finder, or dropping a file on the Dock icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first { PrompterModel.shared.load(url: url) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
