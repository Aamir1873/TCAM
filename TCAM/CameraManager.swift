//
//  CameraManager.swift
//  TCAM
//
//  Uses the Coordinator pattern: NSObject delegate conformances are isolated into
//  a private Coordinator class to avoid @Observable macro conflicts with NSObject's
//  KVO machinery.

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
    var zoomFactor: CGFloat = 1.0
    var permissionState: PermissionState = .unknown
    var photoPermissionGranted = false
    var showSavedBanner = false
    var exposureBias: Float = 0.0
    var showGrid       = false
    var timerMode: TimerMode = .off
    var timerCountdown: Int? = nil

    let session      = AVCaptureSession()
    let engine       = TechnicolorEngine()

    private let videoOutput  = AVCaptureVideoDataOutput()
    private let photoOutput  = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "tc.session", qos: .userInitiated)
    private let filterQueue  = DispatchQueue(label: "tc.filter",  qos: .userInteractive)
    @ObservationIgnored
    private var timerTask: Task<Void, Never>?
    private var coordinator = Coordinator(manager: nil) // bootstrapped in init

    /// Swift 6-safe cross-queue read cache (written on MainActor, read on filterQueue).
    @ObservationIgnored
    nonisolated(unsafe) var currentProcessCache: TechnicolorProcess = .threeStrip

    init() {
        coordinator = Coordinator(manager: self)
    }

    deinit {
        timerTask?.cancel()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    // MARK: Permissions

    func requestPermissions() async {
        // Camera
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

        // Photos (addOnly — minimal footprint)
        let photoStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        photoPermissionGranted = photoStatus == .authorized || photoStatus == .limited
    }

    // MARK: Session Setup

    private func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            self.addInput(position: .back)

            self.videoOutput.setSampleBufferDelegate(self.coordinator, queue: self.filterQueue)
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
                self.videoOutput.connection(with: .video)?.videoRotationAngle = 90
            }
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
                self.photoOutput.maxPhotoQualityPrioritization = .quality
                if self.photoOutput.isAppleProRAWSupported {
                    self.photoOutput.isAppleProRAWEnabled = true
                }
            }
            self.session.commitConfiguration()
            self.session.startRunning()
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
    private func addInput(position: AVCaptureDevice.Position) -> Bool {
        session.inputs.forEach { session.removeInput($0) }
        let types: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera]
            : [.builtInWideAngleCamera]
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
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.stopRunning()
            self.session.beginConfiguration()
            self.addInput(position: newPos)
            self.videoOutput.connection(with: .video)?.videoRotationAngle = 90
            self.session.commitConfiguration()
            self.session.startRunning()
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
                // Cancelled — clean up UI without firing shutter
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

        // Prefer ProRAW if supported; otherwise fall back to standard JPEG/HEIF settings.
        if photoOutput.isAppleProRAWEnabled,
           let rawFmt = photoOutput.availableRawPhotoPixelFormatTypes
                .first(where: { AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) }) {
            // For RAW capture, initialize settings with the RAW pixel format type.
            settings = AVCapturePhotoSettings(rawPixelFormatType: rawFmt)
        } else {
            settings = AVCapturePhotoSettings()
        }

        // Configure flash
        settings.flashMode = isFlashOn ? .on : .off

        photoOutput.capturePhoto(with: settings, delegate: coordinator)
    }

    // MARK: Camera Controls

    func focusAndExpose(at point: CGPoint, in size: CGSize) {
        let n = CGPoint(x: point.x / size.width, y: point.y / size.height)
        sessionQueue.async {
            guard let device = (self.session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
            try? device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported    { device.focusPointOfInterest    = n; device.focusMode    = .autoFocus  }
            if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = n; device.exposureMode = .autoExpose }
            device.unlockForConfiguration()
        }
    }

    func setExposureBias(_ ev: Float) {
        sessionQueue.async { [weak self] in
            guard let self,
                  let device = (self.session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
            let clamped = max(device.minExposureTargetBias, min(ev, device.maxExposureTargetBias))
            try? device.lockForConfiguration()
            device.setExposureTargetBias(clamped)
            device.unlockForConfiguration()
            Task { @MainActor [weak self] in self?.exposureBias = clamped }
        }
    }

    func setZoom(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self,
                  let device = (self.session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
            let lo = device.minAvailableVideoZoomFactor
            let hi = min(device.activeFormat.videoMaxZoomFactor, 10.0)
            let z  = max(lo, min(factor, hi))
            try? device.lockForConfiguration()
            device.videoZoomFactor = z
            device.unlockForConfiguration()
            Task { @MainActor [weak self] in self?.zoomFactor = z }
        }
    }

    func updateProcess(_ process: TechnicolorProcess) {
        currentProcess  = process
        currentProcessCache = process
    }
}

// MARK: - Coordinator

/// Owns NSObject delegate conformances, keeping CameraManager free of NSObject/KVO conflicts.
private final class Coordinator: NSObject,
    AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCapturePhotoCaptureDelegate {

    private weak var manager: CameraManager?
    init(manager: CameraManager?) { self.manager = manager }

    // MARK: Video frames

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let mgr = manager,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage  = CIImage(cvPixelBuffer: pixelBuffer, options: [.applyOrientationProperty: true])
        let process  = mgr.currentProcessCache
        let filtered = mgr.engine.apply(process, to: ciImage)

        guard let cgImage = mgr.engine.context.createCGImage(filtered, from: filtered.extent) else { return }
        Task { @MainActor [weak mgr] in mgr?.filteredFrame = cgImage }
    }

    // MARK: Photo capture

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard let mgr = manager else { return }
        Task { @MainActor [weak mgr] in mgr?.isCapturing = false }

        guard error == nil,
              let data     = photo.fileDataRepresentation(),
              let ciSource = CIImage(data: data) else { return }

        let process  = mgr.currentProcessCache
        let filtered = mgr.engine.apply(process, to: ciSource)
        guard let cg = mgr.engine.context.createCGImage(filtered, from: filtered.extent) else { return }
        let final = UIImage(cgImage: cg)

        Task { @MainActor [weak mgr] in mgr?.capturedImage = final }

        guard mgr.photoPermissionGranted else { return }
        PHPhotoLibrary.shared().performChanges {
            let req = PHAssetChangeRequest.creationRequestForAsset(from: final)
            req.creationDate = Date()
        } completionHandler: { [weak mgr] ok, _ in
            guard ok, let mgr else { return }
            Task { @MainActor in
                mgr.showSavedBanner = true
                try? await Task.sleep(for: .seconds(2))
                mgr.showSavedBanner = false
            }
        }
    }
}

