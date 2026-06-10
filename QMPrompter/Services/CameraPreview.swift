import AVFoundation
import SwiftUI
import UIKit

struct CameraPreview: UIViewRepresentable {
    @Binding var permissionState: CameraPermissionState

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        context.coordinator.attach(to: view)
        context.coordinator.requestAndStart()
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        context.coordinator.attach(to: uiView)
    }

    static func dismantleUIView(_ uiView: PreviewContainerView, coordinator: CameraCoordinator) {
        coordinator.invalidate()
        uiView.previewLayer.session = nil
    }

    func makeCoordinator() -> CameraCoordinator {
        CameraCoordinator(permissionState: $permissionState)
    }
}

enum CameraPermissionState: Equatable {
    case checking
    case authorized
    case denied
    case unavailable
}

final class PreviewContainerView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class CameraCoordinator: NSObject {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.qiaomu.prompter.camera")
    private var didConfigure = false
    private weak var previewView: PreviewContainerView?
    private var permissionState: Binding<CameraPermissionState>
    private var isActive = true
    private var isInvalidated = false

    init(permissionState: Binding<CameraPermissionState>) {
        self.permissionState = permissionState
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        invalidate()
    }

    func attach(to view: PreviewContainerView) {
        previewView = view
        view.previewLayer.session = session
    }

    func requestAndStart() {
        guard !isInvalidated else { return }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setPermissionState(.authorized)
            startSession()
        case .notDetermined:
            setPermissionState(.checking)
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self, !self.isInvalidated else { return }
                self.setPermissionState(granted ? .authorized : .denied)
                if granted {
                    self.startSession()
                }
            }
        case .denied, .restricted:
            setPermissionState(.denied)
        @unknown default:
            setPermissionState(.unavailable)
        }
    }

    func stopSession() {
        let session = session
        sessionQueue.async {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    func invalidate() {
        isInvalidated = true
        isActive = false
        previewView?.previewLayer.session = nil
        previewView = nil
        stopSession()
    }

    private func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard isActive, !isInvalidated else { return }
            if !didConfigure {
                configureSession()
            }
            if didConfigure, !session.isRunning {
                session.startRunning()
            }
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .medium
        defer { session.commitConfiguration() }

        guard
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let input = try? AVCaptureDeviceInput(device: camera),
            session.canAddInput(input)
        else {
            setPermissionState(.unavailable)
            return
        }

        session.addInput(input)
        didConfigure = true
    }

    private func setPermissionState(_ state: CameraPermissionState) {
        DispatchQueue.main.async { [weak self] in
            self?.permissionState.wrappedValue = state
        }
    }

    @objc private func handleWillResignActive() {
        isActive = false
        stopSession()
    }

    @objc private func handleDidBecomeActive() {
        guard !isInvalidated else { return }
        isActive = true
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            requestAndStart()
            return
        }
        setPermissionState(.authorized)
        startSession()
    }
}
