//
//  CameraManager.swift
//  TCAM - Production-Ready AVFoundation
//

import SwiftUI
@preconcurrency import AVFoundation
import CoreImage
import Photos

@Observable
@MainActor
final class CameraManager {

    enum PermissionState { case unknown, granted, denied }

    var filteredFrame: CGImage?
    var capturedImage: UIImage?
    var isCapturing    = false
    @ObservationIgnored
    var currentProcess: TechnicolorProcess = .native
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
    var currentZoomFactor: CGFloat = 1.0
    
    let session      = AVCaptureSession()
    let engine       = TechnicolorEngine()

    private let sessionQueue = DispatchQueue(label: "tc.session", qos: .userInitiated)
    private let filterQueue  = DispatchQueue(label: "tc.filter",  qos: .userInteractive)
    @ObservationIgnored
    private var timerTask: Task<Void, Never>?

    @ObservationIgnored
    private var coordinator: Coordinator = Coordinator(engine: TechnicolorEngine())

    nonisolated(unsafe) var currentProcessCache: TechnicolorProcess = .native

    init() {
        self.coordinator.engine = self.engine
        self.coordinator.manager = self
    }

    deinit {
        timerTask?.cancel()
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    // MARK: - Permissions

    func requestPermissions() async {
        #if targetEnvironment(simulator)
        print("⚠️ Simulator detected. Enable Virtual Camera in Settings → Developer or test on real device.")
        #endif

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionState = .granted
            await configureAndStartSession()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            permissionState = granted ? .granted : .denied
            if granted { await configureAndStartSession() }
        default:
            permissionState = .denied
        }

        let photoStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        photoPermissionGranted = (photoStatus == .authorized || photoStatus == .limited)
    }

    // MARK: - Session Configuration

    private func configureAndStartSession() async {
        let session = self.session
        let position = self.cameraPosition
        let preferredLens = self.currentLens

        await sessionQueue.async { [weak self] in
            guard let self else { return }
            
            // 🔒 ATOMIC CONFIGURATION BLOCK
            session.beginConfiguration()
            defer { session.commitConfiguration() }

            session.sessionPreset = .photo

            // Clear previous
            session.inputs.forEach { session.removeInput($0) }
            session.outputs.forEach { session.removeOutput($0) }

            // Add camera input
            let inputAdded = self.addInput(session: session, position: position, preferredLens: preferredLens)
            guard inputAdded else {
                print("❌ Failed to add camera input. Hardware unavailable or mismatched.")
                return
            }

            // Video Data Output
            let coordinator = self.coordinator
            coordinator.videoOutput.setSampleBufferDelegate(coordinator, queue: self.filterQueue)
            coordinator.videoOutput.alwaysDiscardsLateVideoFrames = true
            if session.canAddOutput(coordinator.videoOutput) {
                session.addOutput(coordinator.videoOutput)
                coordinator.videoOutput.connection(with: .video)?.videoRotationAngle = 90
                coordinator.videoOutput.connection(with: .video)?.isVideoMirrored = (position == .front)
            }

            // Photo Output
            if session.canAddOutput(coordinator.photoOutput) {
                session.addOutput(coordinator.photoOutput)
                coordinator.photoOutput.maxPhotoQualityPrioritization = .quality
                // ✅ Safe ProRAW gating
                if coordinator.photoOutput.isAppleProRAWSupported {
                    coordinator.photoOutput.isAppleProRAWEnabled = false // Disable by default to prevent -16990
                }
            }

            // ✅ START RUNNING INSIDE SAME QUEUE, AFTER COMMIT
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        guard permissionState == .granted else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            switch phase {
            case .active:     if !self.session.isRunning { self.session.startRunning() }
            case .background: if  self.session.isRunning { self.session.stopRunning()  }
            default: break
            }
        }
    }

    // MARK: - Input Discovery

    @discardableResult
    private func addInput(session: AVCaptureSession, position: AVCaptureDevice.Position, preferredLens: AVCaptureDevice.DeviceType) -> Bool {
        // Dynamically discover ONLY lenses that exist on this device
        var deviceTypes: [AVCaptureDevice.DeviceType]
        if position == .back {
            let session = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInTripleCamera, .builtInDualCamera, .builtInDualWideCamera,
                              .builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera],
                mediaType: .video, position: .back
            )
            deviceTypes = session.devices.map(\.deviceType).unique()
        } else {
            deviceTypes = [.builtInWideAngleCamera]
        }

        // Prefer requested lens, fallback to first available
        if deviceTypes.contains(preferredLens) {
            deviceTypes.insert(preferredLens, at: 0)
        }

        guard let device = AVCaptureDevice.DiscoverySession(
                  deviceTypes: deviceTypes, mediaType: .video, position: position).devices.first,
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else {
            print("❌ No compatible camera input for \(position) / \(preferredLens)")
            return false
        }
        session.addInput(input)
        return true
    }

    // MARK: - Lens Switching

    func toggleLens() {
        guard cameraPosition == .back else { return }
        
        // Discover available lenses
        let available = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera],
            mediaType: .video, position: .back
        ).devices.map(\.deviceType).unique()

        guard let currentIndex = available.firstIndex(of: currentLens) else {
            currentLens = available.first ?? .builtInWideAngleCamera
            reconfigureForLens()
            return
        }

        let nextIndex = (currentIndex + 1) % available.count
        currentLens = available[nextIndex]
        reconfigureForLens()
    }

    private func reconfigureForLens() {
        let lens = currentLens
        let position = cameraPosition

        sessionQueue.async { [weak self] in
            guard let self else { return }
            let coordinator = self.coordinator
            
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }

            self.session.inputs.forEach { self.session.removeInput($0) }
            self.addInput(session: self.session, position: position, preferredLens: lens)

            if let conn = coordinator.videoOutput.connection(with: .video) {
                conn.videoRotationAngle = 90
                conn.isVideoMirrored = (position == .front)
            }

            // Restart if needed
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    // MARK: - Zoom

    func setZoomFactor(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self,
                  let device = (self.session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                let clamped = max(device.minAvailableVideoZoomFactor,
                                  min(factor, device.maxAvailableVideoZoomFactor))
                device.videoZoomFactor = clamped
                Task { @MainActor [weak self] in self?.currentZoomFactor = clamped }
            } catch { print("Zoom lock failed: \(error)") }
        }
    }

    // MARK: - Capture & Timer (unchanged logic, cleaned up)

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
            } catch { self.timerCountdown = nil }
        }
    }

    func cancelTimer() {
        timerTask?.cancel(); timerTask = nil; timerCountdown = nil
    }

    private func fireShutter() {
        isCapturing = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let photoOutput = coordinator.photoOutput
        let settings = AVCapturePhotoSettings()
        
        settings.flashMode = isFlashOn ? .on : .off
        // ✅ iOS 16+ replacement for deprecated isHighResolutionCaptureEnabled
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        
        photoOutput.capturePhoto(with: settings, delegate: coordinator)
    }

    // MARK: - Focus & Exposure

    func focusAndExpose(at point: CGPoint, in size: CGSize) {
        let normalized = CGPoint(x: point.x / size.width, y: point.y / size.height)
        sessionQueue.async { [weak self] in
            guard let self,
                  let device = (self.session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = normalized; device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = normalized; device.exposureMode = .autoExpose
                }
            } catch { print("Focus config failed: \(error)") }
        }
    }

    func setExposureBias(_ ev: Float) {
        sessionQueue.async { [weak self] in
            guard let self,
                  let device = (self.session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                let clamped = max(device.minExposureTargetBias, min(ev, device.maxExposureTargetBias))
                device.setExposureTargetBias(clamped)
                Task { @MainActor [weak self] in self?.exposureBias = clamped }
            } catch { print("Exposure bias failed: \(error)") }
        }
    }

    func updateProcess(_ process: TechnicolorProcess) {
        currentProcess = process
        currentProcessCache = process
    }
}

// MARK: - Coordinator (unchanged, well-isolated)
private final class Coordinator: NSObject,
                                 AVCaptureVideoDataOutputSampleBufferDelegate,
                                 AVCapturePhotoCaptureDelegate {
    let videoOutput = AVCaptureVideoDataOutput()
    let photoOutput = AVCapturePhotoOutput()
    nonisolated(unsafe) var engine: TechnicolorEngine
    weak var manager: CameraManager?

    init(engine: TechnicolorEngine) { self.engine = engine }

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer, options: [.applyOrientationProperty: true])
        let process = manager?.currentProcessCache ?? .native
        let filtered = engine.apply(process, to: ciImage)
        guard let cgImage = engine.context.createCGImage(filtered, from: filtered.extent) else { return }
        Task { @MainActor [weak manager] in manager?.filteredFrame = cgImage }
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let ciSource = CIImage(data: data) else {
            Task { @MainActor [weak manager] in manager?.isCapturing = false }
            return
        }

        let process = manager?.currentProcessCache ?? .native
        let filtered = engine.apply(process, to: ciSource)
        guard let cg = engine.context.createCGImage(filtered, from: filtered.extent) else {
            Task { @MainActor [weak manager] in manager?.isCapturing = false }
            return
        }

        let orientation = UIImage.Orientation.fromCG(photo.metadata[kCGImagePropertyOrientation as String] as? UInt32 ?? 1)
        let final = UIImage(cgImage: cg, scale: 1.0, orientation: orientation)

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

extension Array where Element: Hashable {
    func unique() -> [Element] { var seen = Set<Element>(); return filter { seen.insert($0).inserted } }
}

extension UIImage.Orientation {
    static func fromCG(_ cgOrientation: UInt32) -> UIImage.Orientation {
        switch cgOrientation {
        case 1: return .up; case 2: return .upMirrored; case 3: return .down
        case 4: return .downMirrored; case 5: return .leftMirrored; case 6: return .right
        case 7: return .rightMirrored; case 8: return .left; default: return .up
        }
    }
}
