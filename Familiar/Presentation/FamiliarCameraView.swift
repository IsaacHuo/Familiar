import AVFoundation
import Combine
import SwiftUI
import UIKit

struct FamiliarCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = FamiliarCameraController()
    let onCapture: (UIImage) -> Void

    var body: some View {
        Group {
            switch camera.state {
            case .denied:
                unavailable(title: String(localized: "camera.permission.title"), message: String(localized: "camera.permission.detail"), settings: true)
            case .unavailable(let message):
                unavailable(title: String(localized: "camera.unavailable.title"), message: message, settings: false)
            case .loading, .ready:
                ZStack {
                    Color.black.ignoresSafeArea()
                    FamiliarCameraPreview(session: camera.session).ignoresSafeArea()
                    ProgressView().tint(.white).controlSize(.large).opacity(camera.state == .loading ? 1 : 0)
                    controls
                }
            }
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .alert(String(localized: "camera.capture_failed.title"), isPresented: Binding(get: { camera.errorMessage != nil }, set: { if !$0 { camera.errorMessage = nil } })) {
            Button(String(localized: "common.ok")) { camera.errorMessage = nil }
        } message: { Text(camera.errorMessage ?? "") }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                cameraButton(systemName: camera.isFlashEnabled ? "bolt.fill" : "bolt.slash.fill", label: String(localized: camera.isFlashEnabled ? "camera.flash.off" : "camera.flash.on"), disabled: !camera.isFlashAvailable, action: camera.toggleFlash)
            }
            Spacer()
            HStack {
                cameraButton(systemName: "xmark", label: String(localized: "camera.close"), action: dismiss.callAsFunction)
                Spacer()
                Button {
                    camera.capture { image in
                        onCapture(image)
                        dismiss()
                    }
                } label: {
                    ZStack {
                        Circle().stroke(.white.opacity(0.9), lineWidth: 5).frame(width: 72, height: 72)
                        Circle().fill(.white).frame(width: 58, height: 58)
                    }
                    .frame(width: 76, height: 76)
                }
                .buttonStyle(.plain)
                .disabled(camera.state != .ready || camera.isCapturing)
                Spacer()
                cameraButton(systemName: "arrow.triangle.2.circlepath.camera", label: String(localized: "camera.switch"), disabled: !camera.canSwitchCamera, action: camera.switchCamera)
            }
        }
        .padding(18)
    }

    private func cameraButton(systemName: String, label: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white).frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .familiarGlassCircle(interactive: true)
        .disabled(disabled)
        .opacity(disabled ? 0.38 : 1)
        .accessibilityLabel(label)
    }

    private func unavailable(title: String, message: String, settings: Bool) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "camera.fill").font(.system(size: 36, weight: .medium))
            Text(title).font(.headline)
            Text(message).font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.72))
            if settings {
                Button(String(localized: "camera.open_settings")) {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .buttonStyle(.borderedProminent)
            }
            Button(String(localized: "camera.close"), action: dismiss.callAsFunction).buttonStyle(.bordered)
        }
        .foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black.ignoresSafeArea()).padding(28)
    }
}

private struct FamiliarCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView { PreviewView(session: session) }
    func updateUIView(_ view: PreviewView, context: Context) { view.session = session }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var session: AVCaptureSession { get { previewLayer.session! } set { previewLayer.session = newValue } }
        init(session: AVCaptureSession) {
            super.init(frame: .zero)
            previewLayer.session = session
            previewLayer.videoGravity = .resizeAspectFill
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }
}

@MainActor
private final class FamiliarCameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    enum State: Equatable { case loading, ready, denied, unavailable(String) }
    let session = AVCaptureSession()
    @Published var state: State = .loading
    @Published var isCapturing = false
    @Published var isFlashAvailable = false
    @Published var isFlashEnabled = false
    @Published var canSwitchCamera = false
    @Published var errorMessage: String?

    private let queue = DispatchQueue(label: "com.familiar.camera")
    private let output = AVCapturePhotoOutput()
    private var input: AVCaptureDeviceInput?
    private var position: AVCaptureDevice.Position = .back
    private var configured = false
    private var completion: ((UIImage) -> Void)?

    func start() {
        state = .loading
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted { self.configureAndStart() } else { Task { @MainActor in self.state = .denied } }
            }
        case .denied, .restricted: state = .denied
        @unknown default: state = .unavailable(String(localized: "camera.unknown_permission"))
        }
    }

    func stop() { queue.async { [weak self] in guard let self, self.session.isRunning else { return }; self.session.stopRunning() } }
    func toggleFlash() { guard isFlashAvailable else { return }; isFlashEnabled.toggle() }

    func switchCamera() {
        queue.async { [weak self] in
            guard let self, configured, let old = input else { return }
            let next: AVCaptureDevice.Position = position == .back ? .front : .back
            guard let device = Self.device(position: next), let nextInput = try? AVCaptureDeviceInput(device: device) else { return }
            session.beginConfiguration(); session.removeInput(old)
            if session.canAddInput(nextInput) { session.addInput(nextInput); input = nextInput; position = next } else { session.addInput(old) }
            session.commitConfiguration(); publishCapabilities()
        }
    }

    func capture(_ onCapture: @escaping (UIImage) -> Void) {
        guard state == .ready, !isCapturing else { return }
        isCapturing = true
        let flash = isFlashEnabled
        queue.async { [weak self] in
            guard let self, configured else { Task { @MainActor in self?.isCapturing = false }; return }
            let settings = AVCapturePhotoSettings()
            settings.flashMode = flash && input?.device.hasFlash == true ? .on : .off
            if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = position == .front
            }
            completion = onCapture
            output.capturePhoto(with: settings, delegate: self)
        }
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        let description = error?.localizedDescription
        Task { @MainActor [weak self] in
            guard let self else { return }
            let callback = completion; completion = nil; isCapturing = false
            if let description { errorMessage = description; return }
            guard let data, let image = UIImage(data: data) else { errorMessage = String(localized: "camera.invalid_photo"); return }
            callback?(image)
        }
    }

    private func configureAndStart() {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                if !configured { try configure() }
                if !session.isRunning { session.startRunning() }
                Task { @MainActor in self.state = .ready }
            } catch { Task { @MainActor in self.state = .unavailable(error.localizedDescription) } }
        }
    }

    private func configure() throws {
        guard let device = Self.device(position: .back) else { throw CameraError.unavailable }
        let newInput = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration(); defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(newInput), session.canAddOutput(output) else { throw CameraError.configuration }
        session.addInput(newInput); session.addOutput(output); input = newInput; configured = true; publishCapabilities()
    }

    private func publishCapabilities() {
        let flash = input?.device.hasFlash == true
        let switchable = Self.device(position: .back) != nil && Self.device(position: .front) != nil
        Task { @MainActor in isFlashAvailable = flash; if !flash { isFlashEnabled = false }; canSwitchCamera = switchable }
    }

    private static func device(position: AVCaptureDevice.Position) -> AVCaptureDevice? { AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) }
    private enum CameraError: LocalizedError { case unavailable, configuration; var errorDescription: String? { String(localized: "camera.configuration_failed") } }
}
