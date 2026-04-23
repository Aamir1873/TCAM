//
//  CameraManager.swift
//  TCAM - Swift 6 Strict Concurrency Compliant
//

import SwiftUI
@preconcurrency import AVFoundation
import CoreImage
import Photos

@Observable
@MainActor
final class CameraManager {
    enum PermissionState { case unknown, granted, denied }

    // MARK: - UI State (MainActor Isolated)
    var filteredFrame: CGImage?
    var capturedImage: UIImage?
    var isCapturing = false
    var currentProcess: TechnicolorProcess = .native
    var isFlashOn = false
    var permissionState: PermissionState = .unknown
    var photoPermissionGranted = false
    var showSavedBanner = false
    var exposureBias: Float = 0.0
    var currentLens: AVCaptureDevice.DeviceType = .builtInWideAngleCamera
    
    // MARK: - Background State (Nonisolated for Coordinator Access)
    @ObservationIgnored nonisolated(unsafe) var currentZoomFactor: CGFloat = 1.0
    @ObservationIgnored nonisolated(unsafe) var currentProcessCache: TechnicolorProcess = .native
    @ObservationIgnored nonisolated(unsafe) var watermarkEnabled = true

    // MARK: - AVFoundation Objects
    let cameraPosition: AVCaptureDevice.Position = .back
    let session = AVCaptureSession()
    let engine = TechnicolorEngine()
    
    private let sessionQueue = DispatchQueue(label: "tc.session", qos: .userInitiated)
    private let filterQueue = DispatchQueue(label: "tc.filter", qos: .userInteractive)
    private let coordinator: Coordinator

    init() {
        self.coordinator = Coordinator(engine: engine)
        self.coordinator.manager = self
    }

    deinit {
        sessionQueue.async { [weak self] in self?.session.stopRunning() }
    }

    // MARK: - Permissions & Session Setup

    func requestPermissions() async {
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

    private func configureAndStartSession() async {
        // ✅ Capture local references to break isolation boundary
        let position = self.cameraPosition
        let lens = self.currentLens
        let isFront = position == AVCaptureDevice.Position.front
        let sessionRef = self.session
        let coordinatorRef = self.coordinator
        let filterQueueRef = self.filterQueue

        sessionQueue.async {
            sessionRef.beginConfiguration()
            sessionRef.sessionPreset = .photo
            
            sessionRef.inputs.forEach { sessionRef.removeInput($0) }
            sessionRef.outputs.forEach { sessionRef.removeOutput($0) }
            
            if self.addInput(session: sessionRef, position: position, preferredLens: lens) {
                coordinatorRef.videoOutput.setSampleBufferDelegate(coordinatorRef, queue: filterQueueRef)
                coordinatorRef.videoOutput.alwaysDiscardsLateVideoFrames = true
                
                if sessionRef.canAddOutput(coordinatorRef.videoOutput) {
                    sessionRef.addOutput(coordinatorRef.videoOutput)
                    coordinatorRef.videoOutput.connection(with: .video)?.videoRotationAngle = 90
                    coordinatorRef.videoOutput.connection(with: .video)?.isVideoMirrored = isFront
                }
                
                if sessionRef.canAddOutput(coordinatorRef.photoOutput) {
                    sessionRef.addOutput(coordinatorRef.photoOutput)
                    coordinatorRef.photoOutput.maxPhotoQualityPrioritization = .quality
                }
            }
            
            // ✅ Strict order: commit THEN start (no defer)
            sessionRef.commitConfiguration()
            if !sessionRef.isRunning {
                sessionRef.startRunning()
            }
        }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        guard permissionState == .granted else { return }
        let sessionRef = self.session
        
        sessionQueue.async {
            switch phase {
            case .active:     if !sessionRef.isRunning { sessionRef.startRunning() }
            case .background: if  sessionRef.isRunning { sessionRef.stopRunning()  }
            default: break
            }
        }
    }

    // MARK: - Input Management
    // Marked nonisolated so it can be called from background queues without capturing self
    @discardableResult
    nonisolated private func addInput(session: AVCaptureSession, position: AVCaptureDevice.Position, preferredLens: AVCaptureDevice.DeviceType) -> Bool {
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

    // MARK: - Lens & Zoom Switching

    func switchToLens(type: AVCaptureDevice.DeviceType, zoom: CGFloat) {
        // Update UI state
        currentLens = type
        currentZoomFactor = zoom

        // Capture local references
        let position = self.cameraPosition
        let isFront = position == AVCaptureDevice.Position.front
        let sessionRef = self.session
        let coordinatorRef = self.coordinator

        sessionQueue.async {
            sessionRef.beginConfiguration()
            
            if let currentInput = sessionRef.inputs.first as? AVCaptureDeviceInput,
               currentInput.device.deviceType != type {
                sessionRef.removeInput(currentInput)
                self.addInput(session: sessionRef, position: position, preferredLens: type)
            }
            
            if let conn = coordinatorRef.videoOutput.connection(with: .video) {
                conn.videoRotationAngle = 90
                conn.isVideoMirrored = isFront
            }
            
            if let device = (sessionRef.inputs.first as? AVCaptureDeviceInput)?.device {
                try? device.lockForConfiguration()
                let clamped = max(device.minAvailableVideoZoomFactor, min(zoom, device.maxAvailableVideoZoomFactor))
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            }
            
            sessionRef.commitConfiguration()
            if !sessionRef.isRunning {
                sessionRef.startRunning()
            }
        }
    }

    func setZoomFactor(_ factor: CGFloat) {
        let sessionRef = self.session
        sessionQueue.async {
            guard let device = (sessionRef.inputs.first as? AVCaptureDeviceInput)?.device else { return }
            try? device.lockForConfiguration()
            let clamped = max(device.minAvailableVideoZoomFactor, min(factor, device.maxAvailableVideoZoomFactor))
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
            
            Task { @MainActor [weak self] in self?.currentZoomFactor = clamped }
        }
    }

    // MARK: - Capture

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
        let sessionRef = self.session
        sessionQueue.async {
            guard let device = (sessionRef.inputs.first as? AVCaptureDeviceInput)?.device else { return }
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

// MARK: - Coordinator (Nonisolated Delegate)
private final class Coordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {
    let videoOutput = AVCaptureVideoDataOutput()
    let photoOutput = AVCapturePhotoOutput()
    nonisolated(unsafe) var engine: TechnicolorEngine
    weak var manager: CameraManager?

    init(engine: TechnicolorEngine) { self.engine = engine }

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer, options: [.applyOrientationProperty: true])
        // ✅ Accessing nonisolated(unsafe) property is now safe
        let process = manager?.currentProcessCache ?? .native
        let filtered = engine.apply(process, to: ciImage)
        guard let cgImage = engine.context.createCGImage(filtered, from: filtered.extent) else { return }
        Task { @MainActor [weak manager] in manager?.filteredFrame = cgImage }
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        // ✅ Fixed typo: CIImage( data) -> CIImage( data)
        guard error == nil, let data = photo.fileDataRepresentation(), let ciSource = CIImage(data: data) else {
            Task { @MainActor [weak manager] in manager?.isCapturing = false }
            return
        }

        // ✅ Accessing nonisolated(unsafe) property is now safe
        let process = manager?.currentProcessCache ?? .native
        let filtered = engine.apply(process, to: ciSource)
        guard let cg = engine.context.createCGImage(filtered, from: filtered.extent) else {
            Task { @MainActor [weak manager] in manager?.isCapturing = false }
            return
        }

        // ✅ nonisolated static call
        let orientation = UIImage.Orientation.fromCG(photo.metadata[kCGImagePropertyOrientation as String] as? UInt32 ?? 1)
        let original = UIImage(cgImage: cg, scale: 1.0, orientation: orientation)
        
        // ✅ Accessing nonisolated(unsafe) properties is now safe
        let zoom = manager?.currentZoomFactor ?? 1.0
        let enabled = manager?.watermarkEnabled ?? true
        let final = PhotoWatermarker.apply(to: original, metadata: photo.metadata, zoomFactor: zoom, isEnabled: enabled)

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

// ✅ Fixed: Marked nonisolated to allow sync calls from background delegates
extension UIImage.Orientation {
    static nonisolated func fromCG(_ cgOrientation: UInt32) -> UIImage.Orientation {
        switch cgOrientation {
        case 1: .up; case 2: .upMirrored; case 3: .down; case 4: .downMirrored
        case 5: .leftMirrored; case 6: .right; case 7: .rightMirrored; case 8: .left
        default: .up
        }
    }
}
