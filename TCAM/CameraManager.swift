//
//  CameraManager.swift
//  TCAM
//
//  Swift 6 strict compliant. Coordinator pattern isolates NSObject delegates.

import SwiftUI
@preconcurrency import AVFoundation
import CoreImage
import Photos

// MARK: - Camera Manager

@Observable
@MainActor
final class CameraManager {

    enum PermissionState { case unknown, granted, denied }

    var filteredFrame: CGImage?
    var capturedImage: UIImage?
    var isCapturing    = false
    @ObservationIgnored
    var currentProcess: TechnicolorProcess = .threeStrip
    var cameraPosition: AVCaptureDevice.Position = .back
    var isFlashOn      = false
    var permissionState: PermissionState = .unknown
    var photoPermissionGranted = false
    var showSavedBanner = false
    var exposureBias: Float = 0.0
    var showGrid       = false
    var timerMode: TimerMode = .off
    var timerCountdown: Int? = nil
    var currentLens: AVCaptureDevice.DeviceType = .builtInWideAngleCamera

    let session      = AVCaptureSession()
    let engine       = TechnicolorEngine()

    private let videoOutput  = AVCaptureVideoDataOutput()
    private let photoOutput  = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "tc.session", qos: .userInitiated)
    private let filterQueue  = DispatchQueue(label: "tc.filter",  qos: .userInteractive)
    @ObservationIgnored
    private var timerTask: Task<Void, Never>?
    private var coordinator: Coordinator = Coordinator(engine: TechnicolorEngine(), manager: nil)

    /// Cross-queue cache. MainActor writes, filterQueue reads. Safe via happens-after.
    @ObservationIgnored
    nonisolated(unsafe) var currentProcessCache: TechnicolorProcess = .threeStrip

    init() {
        coordinator = Coordinator(engine: engine, manager: self)
    }

    deinit {
        timerTask?.cancel()
        let session = self.session
        sessionQueue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    // MARK: Permissions

    func requestPermissions() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionState = .granted
            setupSession()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            permissionState = granted ? .granted : .denied
            if granted { setupSession() }
        default:
            permissionState = .denied
        }

        let photoStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        photoPermissionGranted = photoStatus == .authorized || photoStatus == .limited
    }

    // MARK: Session Setup

    private func setupSession() {
        let session = self.session
        let currentLens = self.currentLens

        sessionQueue.async { [weak self] in
            guard let self else { return }
            let coordinator = self.coordinator
            session.beginConfiguration()
            session.sessionPreset = .photo
            self.addInput(session: session, position: .back, preferredLens: currentLens)

            coordinator.videoOutput.setSampleBufferDelegate(coordinator, queue: self.filterQueue)
            coordinator.videoOutput.alwaysDiscardsLateVideoFrames = true
            if session.canAddOutput(coordinator.videoOutput) {
                session.addOutput(coordinator.videoOutput)
                coordinator.videoOutput.connection(with: .video)?.videoRotationAngle = 90
            }
            if session.canAddOutput(coordinator.photoOutput) {
                session.addOutput(coordinator.photoOutput)
                coordinator.photoOutput.maxPhotoQualityPrioritization = .quality
                if coordinator.photoOutput.isAppleProRAWSupported {
                    coordinator.photoOutput.isAppleProRAWEnabled = true
                }
            }
            session.commitConfiguration()
            session.startRunning()
        }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        guard permissionState == .granted else { return }
        let session = self.session
        sessionQueue.async {
            switch phase {
            case .active:     if !session.isRunning { session.startRunning() }
            case .background: if  session.isRunning { session.stopRunning()  }
            default: break
            }
        }
    }

    @discardableResult
    private func addInput(session: AVCaptureSession, position: AVCaptureDevice.Position, preferredLens: AVCaptureDevice.DeviceType? = nil) -> Bool {
        session.inputs.forEach { session.removeInput($0) }

        let types: [AVCaptureDevice.DeviceType]
        if let lens = preferredLens, position == .back {
            types = [lens]
        } else {
            types = position == .back
                ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera]
                : [.builtInWideAngleCamera]
        }

        guard let device = AVCaptureDevice.DiscoverySession(
                  deviceTypes: types, mediaType: .video, position: position).devices.first,
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return false }
        session.addInput(input)
        return true
    }

    func flipCamera() {
        cameraPosition = cameraPosition == .back ? .front : .back
        let newPos = cameraPosition
        if newPos == .front {
            currentLens = .builtInWideAngleCamera
        }
        let session = self.session
        let currentLens = self.currentLens

        sessionQueue.async { [weak self] in
            guard let self else { return }
            let coordinator = self.coordinator
            session.stopRunning()
            session.beginConfiguration()
            self.addInput(session: session, position: newPos, preferredLens: newPos == .back ? currentLens : nil)
            coordinator.videoOutput.connection(with: .video)?.videoRotationAngle = 90
            session.commitConfiguration()
            session.startRunning()
        }
    }

    // MARK: Lens Toggle

    func toggleLens() {
        guard cameraPosition == .back else { return }

        let available: [AVCaptureDevice.DeviceType] = [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera]
        guard let currentIndex = available.firstIndex(of: currentLens) else {
            currentLens = .builtInWideAngleCamera
            reconfigureForLens()
            return
        }

        let nextIndex = (currentIndex + 1) % available.count
        currentLens = available[nextIndex]
        reconfigureForLens()
    }

    private func reconfigureForLens() {
        let lens = currentLens
        let session = self.session

        sessionQueue.async { [weak self] in
            guard let self else { return }
            let coordinator = self.coordinator
            session.stopRunning()
            session.beginConfiguration()
            self.addInput(session: session, position: .back, preferredLens: lens)
            coordinator.videoOutput.connection(with: .video)?.videoRotationAngle = 90
            session.commitConfiguration()
            session.startRunning()
        }
    }

    // MARK: Capture & Timer

    func capturePhoto() {
        guard !isCapturing else { return }
        timerMode == .off ? fireShutter() : startTimer()
    }

    private func startTimer() {
        timerTask?.cancel()
        var remaining = timerMode.rawValue
        timerCountdown = remaining
        timerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                while remaining > 0 {
                    try await Task.sleep(for: .seconds(1))
                    remaining -= 1
                    self.timerCountdown = remaining
                }
                self.timerCountdown = nil
                self.fireShutter()
            } catch {
                self.timerCountdown = nil
            }
        }
    }

    func cancelTimer() {
        timerTask?.cancel()
        timerTask = nil
        timerCountdown = nil
    }

    private func fireShutter() {
        isCapturing = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let settings: AVCapturePhotoSettings
        if photoOutput.isAppleProRAWEnabled,
           let rawFmt = photoOutput.availableRawPhotoPixelFormatTypes
                .first(where: { AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) }) {
            settings = AVCapturePhotoSettings(rawPixelFormatType: rawFmt)
        } else {
            settings = AVCapturePhotoSettings()
        }

        settings.flashMode = isFlashOn ? .on : .off
        photoOutput.capturePhoto(with: settings, delegate: coordinator)
    }

    // MARK: Camera Controls

    func focusAndExpose(at point: CGPoint, in size: CGSize) {
        let normalized = CGPoint(x: point.x / size.width, y: point.y / size.height)
        let session = self.session

        sessionQueue.async { [weak self] in
            guard let self,
                  let device = (session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
            try? device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = normalized
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = normalized
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        }
    }

    func setExposureBias(_ ev: Float) {
        let session = self.session

        sessionQueue.async { [weak self] in
            guard let self,
                  let device = (session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
            let clamped = max(device.minExposureTargetBias, min(ev, device.maxExposureTargetBias))
            try? device.lockForConfiguration()
            device.setExposureTargetBias(clamped)
            device.unlockForConfiguration()
            Task { @MainActor [weak self] in
                self?.exposureBias = clamped
            }
        }
    }

    func updateProcess(_ process: TechnicolorProcess) {
        currentProcess = process
        currentProcessCache = process
    }
}

// MARK: - Coordinator

/// Isolated from @MainActor. All delegate callbacks are nonisolated.
/// Holds direct references to outputs to avoid crossing actor boundaries for session management.
private final class Coordinator: NSObject,
    @preconcurrency AVCaptureVideoDataOutputSampleBufferDelegate,
    @preconcurrency AVCapturePhotoCaptureDelegate {

    let videoOutput = AVCaptureVideoDataOutput()
    let photoOutput = AVCapturePhotoOutput()

    nonisolated(unsafe) let engine: TechnicolorEngine
    weak var manager: CameraManager?

    init(engine: TechnicolorEngine, manager: CameraManager?) {
        self.engine = engine
        self.manager = manager
    }

    // MARK: Video frames

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage  = CIImage(cvPixelBuffer: pixelBuffer, options: [.applyOrientationProperty: true])
        let process  = manager?.currentProcessCache ?? .threeStrip
        let filtered = engine.apply(process, to: ciImage)

        guard let cgImage = engine.context.createCGImage(filtered, from: filtered.extent) else { return }
        Task { @MainActor [weak manager] in
            manager?.filteredFrame = cgImage
        }
    }

    // MARK: Photo capture

    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let ciSource = CIImage(data: data) else {
            Task { @MainActor [weak manager] in
                manager?.isCapturing = false
            }
            return
        }

        let process = manager?.currentProcessCache ?? .threeStrip
        let filtered = engine.apply(process, to: ciSource)
        guard let cg = engine.context.createCGImage(filtered, from: filtered.extent) else {
            Task { @MainActor [weak manager] in
                manager?.isCapturing = false
            }
            return
        }
        let final = UIImage(cgImage: cg)

        Task { @MainActor [weak manager] in
            guard let manager else { return }
            manager.isCapturing = false
            manager.capturedImage = final

            guard manager.photoPermissionGranted else { return }
            PHPhotoLibrary.shared().performChanges({
                let req = PHAssetChangeRequest.creationRequestForAsset(from: final)
                req.creationDate = Date()
            }) { ok, _ in
                guard ok else { return }
                Task { @MainActor in
                    manager.showSavedBanner = true
                    try? await Task.sleep(for: .seconds(2))
                    manager.showSavedBanner = false
                }
            }
        }
    }
}
