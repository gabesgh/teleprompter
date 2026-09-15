import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Script, display settings and the scroll engine. Same model as the Mac app,
/// minus the window plumbing.
@Observable
final class PrompterEngine {
    static let shared = PrompterEngine()

    // MARK: - Script

    var script: String = ""

    // MARK: - Settings (persisted)

    var fontSize: Double = 34
    /// Abstract speed 0.5–10, converted to points/sec relative to font size.
    var speed: Double = 2.0
    var mirrored = false
    var showGuide = true
    var guidePosition: Double = 0.3
    var centered = true

    static let fontSizeRange = 16.0...120.0
    static let speedRange = 0.5...10.0

    // MARK: - Playback state

    var isPlaying = false
    var offset: CGFloat = 0
    var textHeight: CGFloat = 0
    var viewportHeight: CGFloat = 0

    var maxOffset: CGFloat { max(textHeight, 0) }
    var progress: Double { maxOffset > 0 ? Double(offset / maxOffset) : 0 }
    var pointsPerSecond: Double { speed * fontSize * 0.5 }
    var remainingSeconds: Double {
        pointsPerSecond > 0 ? Double(maxOffset - offset) / pointsPerSecond : 0
    }
    var wordCount: Int {
        script.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    @ObservationIgnored private let driver = DisplayLinkDriver()
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
        driver.start()
    }

    func pause() {
        isPlaying = false
        driver.stop()
    }

    func togglePlay() { isPlaying ? pause() : play() }
    func restart() { offset = 0 }

    func seek(fraction: Double) {
        offset = maxOffset * CGFloat(min(max(fraction, 0), 1))
    }

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

    func setScript(_ raw: String) {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        pause()
        script = normalized
        offset = 0
    }

    static let importableTypes: [UTType] = [
        .plainText, .utf8PlainText, .text, .rtf, .html,
        UTType("net.daringfireball.markdown"),
    ].compactMap { $0 }

    /// Returns an error message on failure.
    @discardableResult
    func load(url: URL) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        var text: String?
        if ["rtf", "rtfd", "html", "htm"].contains(url.pathExtension.lowercased()) {
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
            return "Couldn't read \(url.lastPathComponent). Try a .txt, .md or .rtf file."
        }
        setScript(text)
        return nil
    }

    @discardableResult
    func pasteFromClipboard() -> String? {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            return "The clipboard is empty."
        }
        setScript(text)
        return nil
    }

    // MARK: - Persistence

    private enum Key {
        static let script = "script", fontSize = "fontSize", speed = "speed", mirrored = "mirrored"
        static let showGuide = "showGuide", guidePosition = "guidePosition", centered = "centered"
    }

    private func loadPersisted() {
        script = defaults.string(forKey: Key.script) ?? ""
        if defaults.object(forKey: Key.fontSize) != nil { fontSize = defaults.double(forKey: Key.fontSize) }
        if defaults.object(forKey: Key.speed) != nil { speed = defaults.double(forKey: Key.speed) }
        if defaults.object(forKey: Key.showGuide) != nil { showGuide = defaults.bool(forKey: Key.showGuide) }
        if defaults.object(forKey: Key.guidePosition) != nil { guidePosition = defaults.double(forKey: Key.guidePosition) }
        if defaults.object(forKey: Key.centered) != nil { centered = defaults.bool(forKey: Key.centered) }
        mirrored = defaults.bool(forKey: Key.mirrored)
    }

    private func persist() {
        defaults.set(script, forKey: Key.script)
        defaults.set(fontSize, forKey: Key.fontSize)
        defaults.set(speed, forKey: Key.speed)
        defaults.set(mirrored, forKey: Key.mirrored)
        defaults.set(showGuide, forKey: Key.showGuide)
        defaults.set(guidePosition, forKey: Key.guidePosition)
        defaults.set(centered, forKey: Key.centered)
    }

    private func observePersistedState() {
        withObservationTracking {
            _ = (script, fontSize, speed, mirrored, showGuide, guidePosition, centered)
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.persist()
                self.observePersistedState()
            }
        }
    }
}

extension PrompterEngine: @unchecked Sendable {}

/// CADisplayLink wrapper that reports delta time per frame.
final class DisplayLinkDriver: NSObject {
    var onFrame: ((Double) -> Void)?
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    func start() {
        stop()
        lastTimestamp = 0
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
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
            onFrame?(min(now - lastTimestamp, 0.1))
        }
        lastTimestamp = now
    }
}
