import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Single source of truth for the prompter: the script, display settings,
/// playback state, and the window features (float, full screen, capture hiding).
@Observable
final class PrompterModel {
    static let shared = PrompterModel()

    // MARK: - Script

    var script: String = ""

    // MARK: - Settings (persisted)

    var fontSize: Double = 56
    /// Abstract speed 0.5–10. Converted to points/sec relative to font size
    /// so changing text size doesn't change reading pace.
    var speed: Double = 2.0
    var mirrored = false
    var showGuide = true
    /// Reading-guide position as a fraction of the viewport height, from the top.
    var guidePosition: Double = 0.35
    var centered = true
    var floatOnTop = false
    var hideFromCapture = false

    static let fontSizeRange = 16.0...200.0
    static let speedRange = 0.5...10.0

    // MARK: - Playback state

    var isPlaying = false
    /// Current scroll position in points. 0 = first line sits on the guide.
    var offset: CGFloat = 0
    var textHeight: CGFloat = 0
    var viewportHeight: CGFloat = 0
    var isFullScreen = false

    var maxOffset: CGFloat { max(textHeight, 0) }
    var progress: Double { maxOffset > 0 ? Double(offset / maxOffset) : 0 }
    var pointsPerSecond: Double { speed * fontSize * 0.5 }
    var remainingSeconds: Double {
        pointsPerSecond > 0 ? Double(maxOffset - offset) / pointsPerSecond : 0
    }
    var wordCount: Int {
        script.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    // MARK: - Private

    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored private let driver = DisplayLinkDriver()
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private let defaults = UserDefaults.standard

    private init() {
        loadPersisted()
        driver.onFrame = { [weak self] dt in self?.advance(by: dt) }
        observePersistedState()
    }

    // MARK: - Playback

    func play() {
        guard !script.isEmpty else { return }
        if maxOffset > 0, offset >= maxOffset { offset = 0 }
        isPlaying = true
        driver.start(on: window?.screen ?? NSScreen.main)
    }

    func pause() {
        isPlaying = false
        driver.stop()
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func restart() {
        offset = 0
    }

    func seek(fraction: Double) {
        offset = maxOffset * CGFloat(min(max(fraction, 0), 1))
    }

    /// Jump by a fraction of the visible height (negative = back).
    func jump(screens: Double) {
        offset = clampOffset(offset + viewportHeight * CGFloat(screens))
    }

    func adjustSpeed(by delta: Double) {
        speed = min(max(speed + delta, Self.speedRange.lowerBound), Self.speedRange.upperBound)
    }

    func adjustFontSize(by delta: Double) {
        fontSize = min(max(fontSize + delta, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
    }

    func updateTextHeight(_ height: CGFloat) {
        guard height != textHeight else { return }
        textHeight = height
        offset = clampOffset(offset)
    }

    private func advance(by dt: Double) {
        let next = offset + CGFloat(pointsPerSecond * dt)
        if next >= maxOffset {
            offset = maxOffset
            pause()
        } else {
            offset = next
        }
    }

    private func clampOffset(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), maxOffset)
    }

    // MARK: - Script loading

    /// Replace the script. Normalizes line endings and resets playback.
    func setScript(_ raw: String) {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        pause()
        script = normalized
        offset = 0
    }

    func importFromFile() {
        let panel = NSOpenPanel()
        let types: [UTType?] = [
            .plainText, .utf8PlainText, .text, .rtf, .rtfd,
            UTType("net.daringfireball.markdown"),
            UTType("org.openxmlformats.wordprocessingml.document"),
        ]
        panel.allowedContentTypes = types.compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a script to load into the teleprompter"
        panel.level = .floating
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.load(url: url)
        }
    }

    func load(url: URL) {
        let richTypes: Set<String> = ["rtf", "rtfd", "docx", "doc", "html", "htm", "odt"]
        var text: String?

        if richTypes.contains(url.pathExtension.lowercased()) {
            text = try? NSAttributedString(url: url, options: [:], documentAttributes: nil).string
        }
        if text == nil {
            var encoding = String.Encoding.utf8
            text = try? String(contentsOf: url, usedEncoding: &encoding)
        }
        if text == nil, let data = try? Data(contentsOf: url) {
            text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        }

        guard let text, !text.isEmpty else {
            presentError("Couldn't read \(url.lastPathComponent)",
                         detail: "Try a .txt, .md, .rtf or .docx file.")
            return
        }
        setScript(text)
    }

    func pasteFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            presentError("Clipboard is empty", detail: "Copy some text first, then paste it here.")
            return
        }
        setScript(text)
    }

    private func presentError(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.runModal()
    }

    // MARK: - Window integration

    func attach(window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .black
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isReleasedWhenClosed = false

        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main) { [weak self] _ in
            self?.isFullScreen = true
            self?.applyWindowSettings()
        }
        center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in
            self?.isFullScreen = false
            self?.applyWindowSettings()
        }

        installKeyMonitor()
        applyWindowSettings()
    }

    func applyWindowSettings() {
        guard let window else { return }
        window.level = (floatOnTop && !isFullScreen) ? .floating : .normal
        window.sharingType = hideFromCapture ? .none : .readOnly
    }

    func toggleFullScreen() {
        window?.toggleFullScreen(nil)
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.handle(keyEvent: event) else { return event }
            return nil
        }
    }

    /// Unmodified single-key shortcuts. Returns true if consumed.
    private func handle(keyEvent event: NSEvent) -> Bool {
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return false }
        if let responder = NSApp.keyWindow?.firstResponder,
           responder is NSTextView || responder is NSTextField {
            return false
        }

        switch event.keyCode {
        case 49:  if !event.isARepeat { togglePlay() }; return true   // space
        case 123: jump(screens: -0.25); return true                    // ←
        case 124: jump(screens: 0.25); return true                     // →
        case 126: adjustSpeed(by: 0.25); return true                   // ↑
        case 125: adjustSpeed(by: -0.25); return true                  // ↓
        case 115: restart(); return true                               // home
        case 119: seek(fraction: 1); return true                       // end
        default: break
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "r": if !event.isARepeat { restart() }; return true
        case "m": if !event.isARepeat { mirrored.toggle() }; return true
        case "g": if !event.isARepeat { showGuide.toggle() }; return true
        case "f": if !event.isARepeat { toggleFullScreen() }; return true
        case "=", "+": adjustFontSize(by: 4); return true
        case "-", "_": adjustFontSize(by: -4); return true
        default: return false
        }
    }

    // MARK: - Persistence

    private enum Key {
        static let script = "script"
        static let fontSize = "fontSize"
        static let speed = "speed"
        static let mirrored = "mirrored"
        static let showGuide = "showGuide"
        static let guidePosition = "guidePosition"
        static let centered = "centered"
        static let floatOnTop = "floatOnTop"
        static let hideFromCapture = "hideFromCapture"
    }

    private func loadPersisted() {
        script = defaults.string(forKey: Key.script) ?? ""
        if defaults.object(forKey: Key.fontSize) != nil { fontSize = defaults.double(forKey: Key.fontSize) }
        if defaults.object(forKey: Key.speed) != nil { speed = defaults.double(forKey: Key.speed) }
        if defaults.object(forKey: Key.showGuide) != nil { showGuide = defaults.bool(forKey: Key.showGuide) }
        if defaults.object(forKey: Key.guidePosition) != nil { guidePosition = defaults.double(forKey: Key.guidePosition) }
        if defaults.object(forKey: Key.centered) != nil { centered = defaults.bool(forKey: Key.centered) }
        mirrored = defaults.bool(forKey: Key.mirrored)
        floatOnTop = defaults.bool(forKey: Key.floatOnTop)
        hideFromCapture = defaults.bool(forKey: Key.hideFromCapture)
    }

    private func persist() {
        defaults.set(script, forKey: Key.script)
        defaults.set(fontSize, forKey: Key.fontSize)
        defaults.set(speed, forKey: Key.speed)
        defaults.set(mirrored, forKey: Key.mirrored)
        defaults.set(showGuide, forKey: Key.showGuide)
        defaults.set(guidePosition, forKey: Key.guidePosition)
        defaults.set(centered, forKey: Key.centered)
        defaults.set(floatOnTop, forKey: Key.floatOnTop)
        defaults.set(hideFromCapture, forKey: Key.hideFromCapture)
    }

    /// Re-arms an observation on every persisted property; fires once per change.
    private func observePersistedState() {
        withObservationTracking {
            _ = (script, fontSize, speed, mirrored, showGuide, guidePosition,
                 centered, floatOnTop, hideFromCapture)
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.persist()
                self.applyWindowSettings()
                self.observePersistedState()
            }
        }
    }
}

/// Wraps CADisplayLink so the model gets a frame-accurate delta time.
final class DisplayLinkDriver: NSObject {
    var onFrame: ((Double) -> Void)?
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    func start(on screen: NSScreen?) {
        stop()
        lastTimestamp = 0
        guard let screen else { return }
        let link = screen.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = link.timestamp
        if lastTimestamp > 0 {
            onFrame?(min(now - lastTimestamp, 0.1))   // cap so a stall doesn't jump the text
        }
        lastTimestamp = now
    }
}

// Only ever touched on the main thread; the observation callback is dispatched back to main.
extension PrompterModel: @unchecked Sendable {}
