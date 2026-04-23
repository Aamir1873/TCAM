//
//  CameraManager.swift
//  TCAM - Swift 6 Actor Isolation Fixed
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
    
    var isFlashOn      = false
    var permissionState: PermissionState = .unknown
    var photoPermissionGranted = false
    var showSavedBanner = false
    var exposureBias: Float = 0.0
    
    // ✅ FIX: Marked nonisolated(unsafe) so Coordinator can read it from background queue
    @ObservationIgnored nonisolated(unsafe) var watermarkEnabled = true
    @ObservationIgnored nonisolated(unsafe) var currentZoomFactor: CGFloat = 1.0
    
    let cameraPosition: AVCaptureDevice.Position = .back
    var currentLens: AVCaptureDevice.DeviceType = .builtInWideAngleCamera
    
    let session      = AVCaptureSession()
    let engine       = TechnicolorEngine()

    private let sessionQueue = DispatchQueue(label: "tc.session", qos: .userInitiated)
    private let filterQueue  = DispatchQueue(label: "tc.filter",  qos: .userInteractive)
    @ObservationIgnored
    private var coordinator: Coordinator = Coordinator(engine: TechnicolorEngine())
    nonisolated(unsafe) var currentProcessCache: TechnicolorProcess = .native

    init() {
        self.coordinator.engine = self.engine
        self.coordinator.manager = self
    }

    deinit {
        sessionQueue.async { [weak self] in self?.session.stopRunning() }
    }

    func requestPermissions() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionState = .granted
            await configureAndStartSession()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            permissionState = granted ? .granted : .denied
            if granted { await configureAndStartSession() }
        default: permissionState = .denied
        }

        let photoStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        photoPermissionGranted = (photoStatus == .authorized || photoStatus == .limited)
    }

    private func configureAndStartSession() async {
        let position = self.cameraPosition
        let lens     = self.currentLens
        let isFront = position == AVCaptureDevice.Position.front

        sessionQueue.async { [weak self, position, lens, isFront] in
            guard let self else { return }
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }
            
            self.session.sessionPreset = .photo
            self.session.inputs.forEach { self.session.removeInput($0) }
            self.session.outputs.forEach { self.session.removeOutput($0) }
            
            if self.addInput(session: self.session, position: position, preferredLens: lens) {
                let coordinator = self.coordinator
                coordinator.videoOutput.setSampleBufferDelegate(coordinator, queue: self.filterQueue)
                coordinator.videoOutput.alwaysDiscardsLateVideoFrames = true
                
                if self.session.canAddOutput(coordinator.videoOutput) {
                    self.session.addOutput(coordinator.videoOutput)
                    coordinator.videoOutput.connection(with: .video)?.videoRotationAngle = 90
                    coordinator.videoOutput.connection(with: .video)?.isVideoMirrored = isFront
                }
                
                if self.session.canAddOutput(coordinator.photoOutput) {
                    self.session.addOutput(coordinator.photoOutput)
                    coordinator.photoOutput.maxPhotoQualityPrioritization = .quality
                }
            }
            
            if !self.session.isRunning { self.session.startRunning() }
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

    @discardableResult
    private func addInput(session: AVCaptureSession, position: AVCaptureDevice.Position, preferredLens: AVCaptureDevice.DeviceType) -> Bool {
        let types: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInTripleCamera, .builtInDualCamera, .builtInDualWideCamera, .builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera]
            : [.builtInWideAngleCamera]
        
        var ordered = types
        if ordered.contains(preferredLens) { ordered.insert(preferredLens, at: 0) }

        guard let device = AVCaptureDevice.DiscoverySession(deviceTypes: ordered, mediaType: .video, position: position).devices.first,
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return false }
        session.addInput(input)
        return true
    }

    func switchToLens(type: AVCaptureDevice.DeviceType, zoom: CGFloat) {
        // Update UI state instantly on main actor
        currentLens = type
        currentZoomFactor = zoom

        sessionQueue.async { [weak self, type, zoom] in
            guard let self else { return }
            let coordinator = self.coordinator
            let position = self.cameraPosition
            let isFront = position == AVCaptureDevice.Position.front

            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }

            if let current = self.session.inputs.first as? AVCaptureDeviceInput, current.device.deviceType != type {
                self.session.removeInput(current)
                self.addInput(session: self.session, position: position, preferredLens: type)
            }

            if let conn = coordinator.videoOutput.connection(with: .video) {
                conn.videoRotationAngle = 90
                conn.isVideoMirrored = isFront
            }

            if let device = (self.session.inputs.first as? AVCaptureDeviceInput)?.device {
                try? device.lockForConfiguration()
                let clamped = max(device.minAvailableVideoZoomFactor, min(zoom, device.maxAvailableVideoZoomFactor))
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            }
        }
    }

    func setZoomFactor(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, let device = (self.session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
            try? device.lockForConfiguration()
            let clamped = max(device.minAvailableVideoZoomFactor, min(factor, device.maxAvailableVideoZoomFactor))
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
            Task { @MainActor [weak self] in self?.currentZoomFactor = clamped }
        }
    }

    func capturePhoto() {
        guard !isCapturing else { return }
        fireShutter()
    }

    private func fireShutter() {
        isCapturing = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        let settings = AVCapturePhotoSettings()
        settings.flashMode = isFlashOn ? .on : .off
        settings.maxPhotoDimensions = coordinator.photoOutput.maxPhotoDimensions
        coordinator.photoOutput.capturePhoto(with: settings, delegate: coordinator)
    }

    func setExposureBias(_ ev: Float) {
        sessionQueue.async { [weak self] in
            guard let self, let device = (self.session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
            try? device.lockForConfiguration()
            let clamped = max(device.minExposureTargetBias, min(ev, device.maxExposureTargetBias))
            device.setExposureTargetBias(clamped)
            device.unlockForConfiguration()
            Task { @MainActor [weak self] in self?.exposureBias = clamped }
        }
    }

    func updateProcess(_ process: TechnicolorProcess) {
        currentProcess = process
        currentProcessCache = process
    }
}

// MARK: - Coordinator
private final class Coordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {
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
        guard error == nil, let data = photo.fileDataRepresentation(), let ciSource = CIImage(data: data) else {
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
        let original = UIImage(cgImage: cg, scale: 1.0, orientation: orientation)
        
        // ✅ Now safely reads nonisolated(unsafe) property
        let zoom = manager?.currentZoomFactor ?? 1.0
        let final = PhotoWatermarker.apply(to: original, metadata: photo.metadata, zoomFactor: zoom, isEnabled: manager?.watermarkEnabled ?? true)

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

extension UIImage.Orientation {
    static func fromCG(_ cgOrientation: UInt32) -> UIImage.Orientation {
        switch cgOrientation {
        case 1: .up; case 2: .upMirrored; case 3: .down; case 4: .downMirrored
        case 5: .leftMirrored; case 6: .right; case 7: .rightMirrored; case 8: .left
        default: .up
        }
    }
}