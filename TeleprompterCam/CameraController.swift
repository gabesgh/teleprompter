import AVFoundation
import Photos
import UIKit
import Observation

/// Owns the capture session: camera selection, lens-aware zoom, orientation,
/// recording to a movie file, and saving the result to Photos.
@Observable
final class CameraController: NSObject {
    enum Status: Equatable {
        case idle, starting, running, unauthorized, unavailable, failed(String)
    }

    enum Quality: String, CaseIterable, Identifiable {
        case hd1080 = "1080p", uhd4K = "4K"
        var id: String { rawValue }
        var preset: AVCaptureSession.Preset {
            self == .uhd4K ? .hd4K3840x2160 : .hd1920x1080
        }
    }

    // MARK: - Observable state

    var status: Status = .idle
    var position: AVCaptureDevice.Position = .back
    var quality: Quality = .hd1080
    var isRecording = false
    var recordingSeconds: Double = 0
    /// Zoom as the user sees it: 1× = the main wide lens, 0.5× = ultra wide.
    var displayZoom: Double = 1
    var minDisplayZoom: Double = 1
    var maxDisplayZoom: Double = 10
    /// Quick lens buttons, e.g. [0.5, 1, 2, 5].
    var lensOptions: [Double] = [1]
    var toast: String?

    let session = AVCaptureSession()

    // MARK: - Private

    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "teleprompter.camera.session")
    @ObservationIgnored private var videoDevice: AVCaptureDevice?
    @ObservationIgnored private var videoInput: AVCaptureDeviceInput?
    @ObservationIgnored private var audioInput: AVCaptureDeviceInput?
    @ObservationIgnored private let movieOutput = AVCaptureMovieFileOutput()
    /// videoZoomFactor that corresponds to 1× on screen (2.0 on a device with an ultra wide).
    @ObservationIgnored private var wideFactor: CGFloat = 1
    @ObservationIgnored private weak var previewLayer: AVCaptureVideoPreviewLayer?
    @ObservationIgnored private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    @ObservationIgnored private var rotationObservation: NSKeyValueObservation?
    @ObservationIgnored private var recordingTimer: Timer?
    @ObservationIgnored private var recordingStart: Date?
    @ObservationIgnored private var configured = false

    override init() {
        super.init()
        if let raw = UserDefaults.standard.string(forKey: "quality"), let q = Quality(rawValue: raw) {
            quality = q
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard status == .idle || status == .unauthorized else { resume(); return }
        status = .starting
        Task {
            let video = await AVCaptureDevice.requestAccess(for: .video)
            let audio = await AVCaptureDevice.requestAccess(for: .audio)   // optional; we record without it
            guard video else { await MainActor.run { status = .unauthorized }; return }
            sessionQueue.async { [self] in
                configureSession(withAudio: audio)
                if configured {
                    session.startRunning()
                    DispatchQueue.main.async { self.status = .running }
                }
            }
        }
    }

    func resume() {
        guard configured else { return }
        sessionQueue.async { [self] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func suspend() {
        stopRecording()
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    // MARK: - Session configuration (session queue)

    private func configureSession(withAudio: Bool) {
        guard let device = Self.bestDevice(for: position) else {
            DispatchQueue.main.async { self.status = .unavailable }
            return
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = session.canSetSessionPreset(quality.preset) ? quality.preset : .high

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
            session.addInput(input)
            videoInput = input
            videoDevice = device
        } catch {
            DispatchQueue.main.async { self.status = .failed("Camera couldn't start: \(error.localizedDescription)") }
            return
        }

        if withAudio, let mic = AVCaptureDevice.default(for: .audio),
           let input = try? AVCaptureDeviceInput(device: mic), session.canAddInput(input) {
            session.addInput(input)
            audioInput = input
        }

        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
            if let connection = movieOutput.connection(with: .video), connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }
        }

        applyZoomModel(for: device)
        configured = true
        DispatchQueue.main.async { self.attachRotationCoordinator() }
    }

    private static func bestDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        // Virtual devices first so zooming can switch lenses seamlessly.
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera,
        ]
        return AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: position)
            .devices.first
    }

    private enum CameraError: Error { case cannotAddInput }

    // MARK: - Zoom

    /// Works out which videoZoomFactor is "1×" and which lens shortcuts to offer.
    private func applyZoomModel(for device: AVCaptureDevice) {
        let constituents = device.isVirtualDevice ? device.constituentDevices : [device]
        let types = constituents.map(\.deviceType)
        let switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }

        let hasUltraWide = types.contains(.builtInUltraWideCamera)
        let hasTelephoto = types.contains(.builtInTelephotoCamera)
        wideFactor = hasUltraWide ? (switchOvers.first ?? 2) : 1

        var options: [Double] = []
        if hasUltraWide { options.append(0.5) }
        options.append(1)
        options.append(2)
        if hasTelephoto, let teleSwitch = switchOvers.last {
            let tele = (teleSwitch / wideFactor).rounded()
            if tele > 2 { options.append(Double(tele)) }
        }

        let minZoom = Double(device.minAvailableVideoZoomFactor / wideFactor)
        let maxZoom = min(Double(device.maxAvailableVideoZoomFactor / wideFactor), 15)

        try? device.lockForConfiguration()
        device.videoZoomFactor = wideFactor
        device.unlockForConfiguration()

        DispatchQueue.main.async {
            self.lensOptions = options
            self.minDisplayZoom = minZoom
            self.maxDisplayZoom = maxZoom
            self.displayZoom = 1
        }
    }

    func setZoom(_ zoom: Double, animated: Bool = false) {
        let clamped = min(max(zoom, minDisplayZoom), maxDisplayZoom)
        displayZoom = clamped
        sessionQueue.async { [self] in
            guard let device = videoDevice else { return }
            let factor = CGFloat(clamped) * wideFactor
            do {
                try device.lockForConfiguration()
                if animated {
                    device.ramp(toVideoZoomFactor: factor, withRate: 6)
                } else {
                    device.videoZoomFactor = factor
                }
                device.unlockForConfiguration()
            } catch { }
        }
    }

    // MARK: - Camera position & quality

    func flipCamera() {
        guard !isRecording else { return }
        position = position == .back ? .front : .back
        sessionQueue.async { [self] in
            guard let device = Self.bestDevice(for: position),
                  let newInput = try? AVCaptureDeviceInput(device: device) else { return }
            session.beginConfiguration()
            if let old = videoInput { session.removeInput(old) }
            if session.canAddInput(newInput) {
                session.addInput(newInput)
                videoInput = newInput
                videoDevice = device
            } else if let old = videoInput {
                session.addInput(old)
            }
            if let connection = movieOutput.connection(with: .video) {
                connection.isVideoMirrored = position == .front
            }
            session.commitConfiguration()
            applyZoomModel(for: device)
            DispatchQueue.main.async { self.attachRotationCoordinator() }
        }
    }

    func setQuality(_ newQuality: Quality) {
        guard !isRecording, newQuality != quality else { return }
        quality = newQuality
        UserDefaults.standard.set(newQuality.rawValue, forKey: "quality")
        sessionQueue.async { [self] in
            session.beginConfiguration()
            if session.canSetSessionPreset(newQuality.preset) { session.sessionPreset = newQuality.preset }
            session.commitConfiguration()
            if let device = videoDevice { applyZoomModel(for: device) }
        }
    }

    // MARK: - Orientation

    func attach(previewLayer: AVCaptureVideoPreviewLayer) {
        self.previewLayer = previewLayer
        attachRotationCoordinator()
    }

    /// Keeps preview and recordings level with the horizon as the phone rotates.
    private func attachRotationCoordinator() {
        guard let device = videoDevice else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] coordinator, _ in
            guard let self, let connection = previewLayer?.connection else { return }
            let angle = coordinator.videoRotationAngleForHorizonLevelPreview
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
    }

    // MARK: - Recording

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    func startRecording() {
        guard status == .running, !movieOutput.isRecording else { return }
        let captureAngle = rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? 90
        sessionQueue.async { [self] in
            if let connection = movieOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(captureAngle) {
                connection.videoRotationAngle = captureAngle
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("Teleprompter-\(Int(Date().timeIntervalSince1970)).mov")
            movieOutput.startRecording(to: url, recordingDelegate: self)
        }
    }

    func stopRecording() {
        sessionQueue.async { [self] in
            if movieOutput.isRecording { movieOutput.stopRecording() }
        }
    }

    private func save(_ url: URL) {
        Task {
            let auth = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard auth == .authorized || auth == .limited else {
                await MainActor.run { showToast("Allow Photos access to save recordings") }
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }
                try? FileManager.default.removeItem(at: url)
                await MainActor.run { showToast("Saved to Photos") }
            } catch {
                await MainActor.run { showToast("Couldn't save: \(error.localizedDescription)") }
            }
        }
    }

    private func showToast(_ message: String) {
        toast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if self?.toast == message { self?.toast = nil }
        }
    }
}

extension CameraController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async { [self] in
            isRecording = true
            recordingStart = Date()
            recordingSeconds = 0
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                guard let self, let start = recordingStart else { return }
                recordingSeconds = Date().timeIntervalSince(start)
            }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async { [self] in
            isRecording = false
            recordingTimer?.invalidate()
            recordingTimer = nil
            // AVFoundation reports a "recording stopped" error even when the file is fine.
            let fileIsUsable = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? (error == nil)
            if fileIsUsable {
                save(outputFileURL)
            } else {
                showToast("Recording failed: \(error?.localizedDescription ?? "unknown error")")
            }
        }
    }
}

extension CameraController: @unchecked Sendable {}
