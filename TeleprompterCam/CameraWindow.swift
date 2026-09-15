import SwiftUI

/// The small live-camera window. Drag it to any corner, pinch it to zoom,
/// double-tap to toggle its size. Lens shortcuts sit underneath it.
struct CameraWindow: View {
    @Environment(CameraController.self) private var camera
    let container: CGSize
    @Binding var large: Bool

    @AppStorage("cameraCorner") private var cornerRaw = Corner.topTrailing.rawValue
    @State private var dragTranslation: CGSize = .zero
    @State private var pinchStartZoom: Double?

    enum Corner: String, CaseIterable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
        var isTop: Bool { self == .topLeading || self == .topTrailing }
        var isLeading: Bool { self == .topLeading || self == .bottomLeading }
    }

    private var corner: Corner {
        get { Corner(rawValue: cornerRaw) ?? .topTrailing }
        nonmutating set { cornerRaw = newValue.rawValue }
    }

    var body: some View {
        let landscape = container.width > container.height
        let width = container.width * (landscape ? (large ? 0.40 : 0.24) : (large ? 0.52 : 0.30))
        let size = landscape ? CGSize(width: width, height: width * 9 / 16)
                             : CGSize(width: width, height: width * 16 / 9)
        let home = position(for: corner, size: size)

        VStack(spacing: 6) {
            if !corner.isTop { lensButtons }
            preview(size: size)
            if corner.isTop { lensButtons }
        }
        .position(x: home.x + dragTranslation.width, y: home.y + dragTranslation.height)
        .gesture(
            DragGesture()
                .onChanged { dragTranslation = $0.translation }
                .onEnded { value in
                    let center = CGPoint(x: home.x + value.predictedEndTranslation.width,
                                         y: home.y + value.predictedEndTranslation.height)
                    withAnimation(.spring(duration: 0.35)) {
                        corner = nearestCorner(to: center)
                        dragTranslation = .zero
                    }
                }
        )
    }

    private func preview(size: CGSize) -> some View {
        ZStack {
            CameraPreview(camera: camera)
            if camera.status != .running { statusPlaceholder }

            VStack {
                HStack {
                    if camera.isRecording {
                        HStack(spacing: 5) {
                            Circle().fill(.red).frame(width: 8, height: 8)
                            Text(formatTime(camera.recordingSeconds))
                                .font(.caption2.monospacedDigit().weight(.semibold))
                        }
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(.black.opacity(0.5), in: Capsule())
                    }
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    Text(camera.displayZoom.formatted(.number.precision(.fractionLength(0...1))) + "×")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.black.opacity(0.5), in: Capsule())
                }
            }
            .padding(6)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(camera.isRecording ? Color.red : Color.white.opacity(0.35),
                              lineWidth: camera.isRecording ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { scale in
                    if pinchStartZoom == nil { pinchStartZoom = camera.displayZoom }
                    camera.setZoom((pinchStartZoom ?? 1) * Double(scale))
                }
                .onEnded { _ in pinchStartZoom = nil }
        )
        .onTapGesture(count: 2) { withAnimation(.spring(duration: 0.3)) { large.toggle() } }
    }

    private var lensButtons: some View {
        HStack(spacing: 4) {
            ForEach(camera.lensOptions, id: \.self) { option in
                let selected = abs(camera.displayZoom - option) < 0.05
                Button {
                    camera.setZoom(option, animated: true)
                } label: {
                    Text(option.formatted(.number.precision(.fractionLength(0...1))) + "×")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(selected ? .black : .white)
                        .frame(minWidth: 34, minHeight: 26)
                        .background(selected ? Color.orange : Color.white.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(.ultraThinMaterial, in: Capsule())
        .opacity(camera.status == .running ? 1 : 0)
    }

    @ViewBuilder
    private var statusPlaceholder: some View {
        VStack(spacing: 6) {
            Image(systemName: camera.status == .unauthorized ? "camera.fill.badge.ellipsis" : "camera.fill")
                .font(.title2)
            Text(statusText)
                .font(.caption2)
                .multilineTextAlignment(.center)
            if camera.status == .unauthorized {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(.caption2.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
            }
        }
        .foregroundStyle(.white.opacity(0.8))
        .padding(8)
    }

    private var statusText: String {
        switch camera.status {
        case .idle, .starting: return "Starting camera…"
        case .unauthorized: return "Camera access is off"
        case .unavailable: return "No camera available"
        case .failed(let message): return message
        case .running: return ""
        }
    }

    // MARK: - Geometry

    /// Corners sit inside the container, clear of the top bar, the bottom bar, and the progress track.
    private func position(for corner: Corner, size: CGSize) -> CGPoint {
        let lensRow: CGFloat = 32
        let topInset: CGFloat = 60
        let bottomInset: CGFloat = 165
        let side: CGFloat = 10
        let trailingExtra: CGFloat = 26   // progress track
        let x = corner.isLeading ? side + size.width / 2
                                 : container.width - side - trailingExtra - size.width / 2
        let blockHeight = size.height + lensRow
        let y = corner.isTop ? topInset + blockHeight / 2
                             : container.height - bottomInset - blockHeight / 2
        return CGPoint(x: x, y: y)
    }

    private func nearestCorner(to point: CGPoint) -> Corner {
        let top = point.y < container.height / 2
        let leading = point.x < container.width / 2
        switch (top, leading) {
        case (true, true): return .topLeading
        case (true, false): return .topTrailing
        case (false, true): return .bottomLeading
        case (false, false): return .bottomTrailing
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
