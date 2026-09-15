import SwiftUI

@main
struct TeleprompterCamApp: App {
    private let prompter = PrompterEngine.shared
    private let camera = CameraController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(prompter)
                .environment(camera)
                .preferredColorScheme(.dark)
        }
    }
}
