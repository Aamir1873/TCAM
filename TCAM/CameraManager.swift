//
//  CameraManager.swift
//  TCAM
//

import SwiftUI
@preconcurrency import AVFoundation
import CoreImage
import Photos
import CoreLocation
import UIKit

@Observable
@MainActor
final class CameraManager {
    enum PermissionState { case unknown, granted, denied }
    var activeLensType: AVCaptureDevice.DeviceType = .builtInWideAngleCamera

    var filteredFrame: CGImage?
    var capturedImage: UIImage?
    var isCapturing = false
    var currentProcess: TechnicolorProcess = .cinematic
    var isFlashOn = false
    var permissionState: PermissionState = .unknown
    var photoPermissionGranted = false
    var showSavedBanner = false
    var exposureBias: Float = 0.0
    var currentISO: Float           = 0
    var currentShutterSpeed: Double = 0
    var currentLens: AVCaptureDevice.DeviceType = .builtInWideAngleCamera
    var lastLocation: CLLocation?
    var lastLocationString: String?
    var captureAspectRatio: CGFloat = 4.0 / 3.0

    @ObservationIgnored nonisolated(unsafe) var logicalZoomFactor: CGFloat = 1.0
    @ObservationIgnored nonisolated(unsafe) var currentProcessCache: TechnicolorProcess = .cinematic
    @ObservationIgnored nonisolated(unsafe) var watermarkEnabled = true

    let cameraPosition: AVCaptureDevice.Position = .back
    let session = AVCaptureSession()
    let engine = TechnicolorEngine()

    private let locationManager = CLLocationManager()
    private let sessionQueue = DispatchQueue(label: "tc.session", qos: .userInitiated)
    private let filterQueue  = DispatchQueue(label: "tc.filter",  qos: .userInteractive)
    private let coordinator: Coordinator

    @ObservationIgnored private lazy var locationDelegate = LocationDelegate(manager: self)
    @ObservationIgnored private var exposureObserver: NSKeyValueObservation?
    @ObservationIgnored private var orientationObserver: NSObjectProtocol?

    init() {
        self.coordinator = Coordinator(engine: engine)
        self.coordinator.manager = self
        
        // Observe device orientation changes to update video rotation
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateVideoRotationForOrientation()
        }
    }

    deinit {
        exposureObserver?.invalidate()
        if let observer = orientationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        sessionQueue.async { [weak self] in self?.session.stopRunning() }
    }

    // MARK: - Permissions

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

        locationManager.delegate = locationDelegate
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    // MARK: - Session Setup

    private func configureAndStartSession() async {
        let position       = self.cameraPosition
        let lens           = self.currentLens
        let isFront        = position == .front
        let sessionRef     = self.session
        let coordinatorRef = self.coordinator
        let filterQueueRef = self.filterQueue
        
        let previewRotationAngle = getRotationAngleForOrientation(.portrait)

        sessionQueue.async {
            sessionRef.beginConfiguration()
            sessionRef.sessionPreset = .photo
            sessionRef.inputs.forEach  { sessionRef.removeInput($0) }
            sessionRef.outputs.forEach { sessionRef.removeOutput($0) }

            if self.addInput(session: sessionRef, position: position, preferredLens: lens) {
                coordinatorRef.videoOutput.setSampleBufferDelegate(coordinatorRef, queue: filterQueueRef)
                coordinatorRef.videoOutput.alwaysDiscardsLateVideoFrames = true

                if sessionRef.canAddOutput(coordinatorRef.videoOutput) {
                    sessionRef.addOutput(coordinatorRef.videoOutput)
                }
                if sessionRef.canAddOutput(coordinatorRef.photoOutput) {
                    sessionRef.addOutput(coordinatorRef.photoOutput)
                    coordinatorRef.photoOutput.maxPhotoQualityPrioritization = .quality
                }
                coordinatorRef.updateVideoConnection(rotationAngle: previewRotationAngle, isMirrored: isFront)
            }

            sessionRef.commitConfiguration()
            if !sessionRef.isRunning { sessionRef.startRunning() }

            // KVO — observe ISO; read both ISO + shutter together so they stay in sync
            if let device = (sessionRef.inputs.first as? AVCaptureDeviceInput)?.device {
                self.exposureObserver?.invalidate()
                self.exposureObserver = device.observe(\.iso, options: [.new]) { [weak self] dev, _ in
                    let iso     = dev.iso
                    let shutter = dev.exposureDuration.seconds
                    Task { @MainActor [weak self] in
                        self?.currentISO          = iso
                        self?.currentShutterSpeed = shutter
                    }
                }
            }
        }
    }

    // MARK: - Scene Phase

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

    // MARK: - Lens / Zoom

    @discardableResult
    nonisolated private func addInput(
        session: AVCaptureSession,
        position: AVCaptureDevice.Position,
        preferredLens: AVCaptureDevice.DeviceType
    ) -> Bool {
        let types: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInTripleCamera, .builtInDualCamera, .builtInDualWideCamera,
               .builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera]
            : [.builtInWideAngleCamera]
        var ordered = types
        if ordered.contains(preferredLens) { ordered.insert(preferredLens, at: 0) }
        guard let device = AVCaptureDevice.DiscoverySession(
                deviceTypes: ordered, mediaType: .video, position: position
              ).devices.first,
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return false }
        session.addInput(input)
        return true
    }

    func switchToLens(type: AVCaptureDevice.DeviceType, avZoom: CGFloat, logicalZoom: CGFloat) {
        currentLens       = type
        logicalZoomFactor = logicalZoom
        activeLensType    = type

        let position       = self.cameraPosition
        let isFront        = position == .front
        let sessionRef     = self.session
        let coordinatorRef = self.coordinator
        
        let previewRotationAngle = getRotationAngleForOrientation(.portrait)

        sessionQueue.async {
            sessionRef.beginConfiguration()
            if let currentInput = sessionRef.inputs.first as? AVCaptureDeviceInput,
               currentInput.device.deviceType != type {
                sessionRef.removeInput(currentInput)
                self.addInput(session: sessionRef, position: position, preferredLens: type)
            }
            coordinatorRef.updateVideoConnection(rotationAngle: previewRotationAngle, isMirrored: isFront)
            if let device = (sessionRef.inputs.first as? AVCaptureDeviceInput)?.device {
                try? device.lockForConfiguration()
                let clamped = max(device.minAvailableVideoZoomFactor,
                                  min(avZoom, device.maxAvailableVideoZoomFactor))
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            }
            sessionRef.commitConfiguration()
            if !sessionRef.isRunning { sessionRef.startRunning() }
        }
    }

    // MARK: - Orientation

    private func getRotationAngleForOrientation(_ orientation: UIDeviceOrientation) -> CGFloat {
        switch orientation {
        case .portrait:
            return 90
        case .portraitUpsideDown:
            return -90
        case .landscapeLeft:
            return 0
        case .landscapeRight:
            return 180
        default:
            return 90
        }
    }

    private func updateVideoRotationForOrientation() {
        let previewRotationAngle = getRotationAngleForOrientation(.portrait)

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.coordinator.updateVideoConnection(
                rotationAngle: previewRotationAngle,
                isMirrored: self.cameraPosition == .front
            )
        }
    }

    // MARK: - Exposure

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

        let rotationAngle = getRotationAngleForOrientation(UIDevice.current.orientation)
        let isFront = cameraPosition == .front
        let coordinatorRef = coordinator

        sessionQueue.async {
            coordinatorRef.updatePhotoConnection(rotationAngle: rotationAngle, isMirrored: isFront)
            coordinatorRef.photoOutput.capturePhoto(with: settings, delegate: coordinatorRef)
        }
    }

    func updateProcess(_ process: TechnicolorProcess) {
        currentProcess      = process
        currentProcessCache = process
    }
}

// MARK: - Coordinator
private final class Coordinator: NSObject,
    AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCapturePhotoCaptureDelegate
{
    let videoOutput = AVCaptureVideoDataOutput()
    let photoOutput = AVCapturePhotoOutput()
    nonisolated(unsafe) var engine: TechnicolorEngine
    weak var manager: CameraManager?

    init(engine: TechnicolorEngine) { self.engine = engine }

    nonisolated func updateVideoConnection(rotationAngle: CGFloat, isMirrored: Bool) {
        update(connection: videoOutput.connection(with: .video), rotationAngle: rotationAngle, isMirrored: isMirrored)
    }

    nonisolated func updatePhotoConnection(rotationAngle: CGFloat, isMirrored: Bool) {
        update(connection: photoOutput.connection(with: .video), rotationAngle: rotationAngle, isMirrored: isMirrored)
    }

    private nonisolated func update(connection: AVCaptureConnection?, rotationAngle: CGFloat, isMirrored: Bool) {
        guard let connection else { return }
        if connection.isVideoRotationAngleSupported(rotationAngle) {
            connection.videoRotationAngle = rotationAngle
        }
        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = isMirrored
        }
    }

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage  = CIImage(cvPixelBuffer: pixelBuffer, options: [.applyOrientationProperty: true])
        let process  = manager?.currentProcessCache ?? .cinematic
        let filtered = engine.apply(process, to: ciImage)
        guard let cgImage = engine.context.createCGImage(filtered, from: filtered.extent) else { return }
        Task { @MainActor [weak manager] in manager?.filteredFrame = cgImage }
    }

    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil,
              let data     = photo.fileDataRepresentation(),
              let ciSource = CIImage(data: data)
        else {
            Task { @MainActor [weak manager] in manager?.isCapturing = false }
            return
        }

        let process     = manager?.currentProcessCache ?? .cinematic
        let filtered    = engine.apply(process, to: ciSource)

        guard let cg = engine.context.createCGImage(filtered, from: filtered.extent) else {
            Task { @MainActor [weak manager] in manager?.isCapturing = false }
            return
        }

        let orientation = UIImage.Orientation.fromCG(
            photo.metadata[kCGImagePropertyOrientation as String] as? UInt32 ?? 1
        )
        let original = UIImage(cgImage: cg, scale: 1.0, orientation: orientation)
        let zoom     = manager?.logicalZoomFactor ?? 1.0
        let enabled  = manager?.watermarkEnabled ?? true
        let metadata = photo.metadata

        // ✅ Hop to MainActor to safely read @MainActor-isolated properties,
        //    then do watermarking and photo library save from there.
        Task { @MainActor [weak manager] in
            guard let manager else { return }

            let location       = manager.lastLocation        // ✅ safe — on MainActor
            let locationString = manager.lastLocationString  // ✅ safe — on MainActor

            let cropped = original.croppedToLongSideAspectRatio(manager.captureAspectRatio)

            let final = PhotoWatermarker.apply(
                to:             cropped,
                metadata:       metadata,
                zoomFactor:     zoom,
                process:        process,
                location:       location,
                locationString: locationString,
                isEnabled:      enabled
            )

            manager.isCapturing   = false
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

// MARK: - UIImage.Orientation helper
extension UIImage.Orientation {
    static nonisolated func fromCG(_ cgOrientation: UInt32) -> UIImage.Orientation {
        switch cgOrientation {
        case 1: .up;          case 2: .upMirrored
        case 3: .down;        case 4: .downMirrored
        case 5: .leftMirrored; case 6: .right
        case 7: .rightMirrored; case 8: .left
        default: .up
        }
    }
}

// MARK: - Aspect Ratio Crop
private extension UIImage {
    func croppedToLongSideAspectRatio(_ longSideRatio: CGFloat) -> UIImage {
        guard longSideRatio > 0 else { return self }

        let upright = normalizedForCropping()
        guard let cgImage = upright.cgImage else { return self }

        let sourceWidth = CGFloat(cgImage.width)
        let sourceHeight = CGFloat(cgImage.height)
        let targetRatio = sourceHeight >= sourceWidth ? 1 / longSideRatio : longSideRatio
        let sourceRatio = sourceWidth / sourceHeight

        let cropRect: CGRect
        if sourceRatio > targetRatio {
            let cropWidth = sourceHeight * targetRatio
            cropRect = CGRect(
                x: (sourceWidth - cropWidth) / 2,
                y: 0,
                width: cropWidth,
                height: sourceHeight
            )
        } else {
            let cropHeight = sourceWidth / targetRatio
            cropRect = CGRect(
                x: 0,
                y: (sourceHeight - cropHeight) / 2,
                width: sourceWidth,
                height: cropHeight
            )
        }

        let integralCropRect = cropRect.integral
        guard let cropped = cgImage.cropping(to: integralCropRect) else { return upright }
        return UIImage(cgImage: cropped, scale: upright.scale, orientation: .up)
    }

    private func normalizedForCropping() -> UIImage {
        guard imageOrientation != .up else { return self }

        let normalizedSize = imageOrientation.isSideways ? CGSize(width: size.height, height: size.width) : size
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: normalizedSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: normalizedSize))
        }
    }
}

private extension UIImage.Orientation {
    var isSideways: Bool {
        switch self {
        case .left, .leftMirrored, .right, .rightMirrored:
            return true
        default:
            return false
        }
    }
}
// MARK: - Location Delegate
final class LocationDelegate: NSObject, CLLocationManagerDelegate {
    weak var manager: CameraManager?
    private var lastResolvedCoordinate: CLLocationCoordinate2D?

    init(manager: CameraManager) { self.manager = manager }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor [weak self] in self?.manager?.lastLocation = loc }

        if let prev = lastResolvedCoordinate {
            let prevLoc = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
            guard loc.distance(from: prevLoc) > 2000 else { return }
        }
        lastResolvedCoordinate = loc.coordinate
        resolveLocation(loc)
    }

    private func resolveLocation(_ location: CLLocation) {
        CLGeocoder().reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self, let place = placemarks?.first else { return }

            // areasOfInterest is what the native iOS camera uses —
            // returns named places like "The Pearl-Qatar", "Education City", "Duhail"
            let placeName = place.areasOfInterest?.first
                         ?? place.subLocality
                         ?? place.locality
                         ?? place.administrativeArea

            guard let placeName else { return }

            var parts: [String] = [placeName]
            if let country = place.country, !self.isSmallCountry(place) {
                parts.append(country)
            }

            let result = parts.joined(separator: ", ")
            Task { @MainActor [weak self] in self?.manager?.lastLocationString = result }
        }
    }

    private func isSmallCountry(_ place: CLPlacemark) -> Bool {
        let smallCountryCodes = ["QA", "AE", "BH", "KW", "SG", "MC", "LU", "MT", "MV"]
        guard let code = place.isoCountryCode else { return false }
        return smallCountryCodes.contains(code)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }
}
