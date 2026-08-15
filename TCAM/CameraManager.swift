//
//  CameraManager.swift
//  TCAM
//

@preconcurrency import SwiftUI
@preconcurrency import AVFoundation
import CoreImage
import ImageIO
import Photos
import CoreLocation
import MapKit
import UIKit

@Observable
@MainActor
final class CameraManager {
    enum PermissionState { case unknown, granted, denied }
    
    // MARK: - Aspect Ratio Support
    enum AspectRatio: CaseIterable {
        case standard       // 4:3
        
        var ratio: CGFloat {
            switch self {
            case .standard: return 4.0 / 3.0
            }
        }
        
    }
    
    var activeLensType: AVCaptureDevice.DeviceType = .builtInWideAngleCamera

    var filteredFrame: CGImage?
    var capturedImage: UIImage?
    var isCapturing = false
    var currentProcess: TechnicolorProcess = .cinematic
    var isFlashOn = false
    var permissionState: PermissionState = .unknown
    var photoPermissionGranted = false
    var showSavedBanner = false
    var captureErrorMessage: String?
    var exposureBias: Float = 0.0
    var currentISO: Float           = 0
    var currentShutterSpeed: Double = 0
    var currentLens: AVCaptureDevice.DeviceType = .builtInWideAngleCamera
    var lastLocation: CLLocation?
    var lastLocationString: String?
    
    // Portrait-only capture keeps the viewfinder and final photo aligned.
    var captureAspectRatio: AspectRatio = .standard
    
    var displayLogicalZoomFactor: CGFloat = 1.0

    @ObservationIgnored nonisolated(unsafe) var logicalZoomFactor: CGFloat = 1.0
    @ObservationIgnored nonisolated(unsafe) var currentProcessCache: TechnicolorProcess = .cinematic
    @ObservationIgnored nonisolated private let stateLock = NSLock()
    // ✅ watermarkEnabled removed - no longer needed

    let cameraPosition: AVCaptureDevice.Position = .back
    let session = AVCaptureSession()
    let engine = TechnicolorEngine()

    private let locationManager = CLLocationManager()
    private let sessionQueue = DispatchQueue(label: "tc.session", qos: .userInitiated)
    private let filterQueue  = DispatchQueue(label: "tc.filter",  qos: .userInteractive)
    private let coordinator: Coordinator

    @ObservationIgnored private lazy var locationDelegate = LocationDelegate(manager: self)
    @ObservationIgnored private var exposureObserver: NSKeyValueObservation?

    init() {
        self.coordinator = Coordinator(engine: engine)
        self.coordinator.manager = self
    }

    deinit {
        exposureObserver?.invalidate()
        let sessionRef = session
        sessionQueue.async { sessionRef.stopRunning() }
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
        if locationManager.authorizationStatus == .authorizedWhenInUse ||
            locationManager.authorizationStatus == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
    }

    // MARK: - Session Setup

    private func configureAndStartSession() async {
        let position       = self.cameraPosition
        let lens           = self.currentLens
        let isFront        = position == .front
        let sessionRef     = self.session
        let coordinatorRef = self.coordinator
        let filterQueueRef = self.filterQueue
        
        let previewRotationAngle = portraitRotationAngle

        sessionQueue.async { [weak self] in
            sessionRef.beginConfiguration()
            sessionRef.sessionPreset = .photo
            sessionRef.inputs.forEach  { sessionRef.removeInput($0) }
            sessionRef.outputs.forEach { sessionRef.removeOutput($0) }

            if CameraManager.addInput(session: sessionRef, position: position, preferredLens: lens) {
                // Keep preview samples in a known, Core Image-compatible format.
                // Leaving this unset lets AVFoundation renegotiate formats while
                // a still is captured, which can yield invalid frame descriptions.
                coordinatorRef.videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                coordinatorRef.videoOutput.setSampleBufferDelegate(coordinatorRef, queue: filterQueueRef)
                coordinatorRef.videoOutput.alwaysDiscardsLateVideoFrames = true

                if sessionRef.canAddOutput(coordinatorRef.videoOutput) {
                    sessionRef.addOutput(coordinatorRef.videoOutput)
                }
                if sessionRef.canAddOutput(coordinatorRef.photoOutput) {
                    sessionRef.addOutput(coordinatorRef.photoOutput)
                    coordinatorRef.photoOutput.maxPhotoQualityPrioritization = .quality
                    if coordinatorRef.photoOutput.isAppleProRAWSupported {
                        coordinatorRef.photoOutput.isAppleProRAWEnabled = true
                    }
                }
                coordinatorRef.updateVideoConnection(rotationAngle: previewRotationAngle, isMirrored: isFront)
            }

            sessionRef.commitConfiguration()
            if !sessionRef.isRunning { sessionRef.startRunning() }

            // KVO — observe ISO; read both ISO + shutter together so they stay in sync
            if let device = (sessionRef.inputs.first as? AVCaptureDeviceInput)?.device {
                let observer = device.observe(\.iso, options: [.new]) { [weak self] dev, _ in
                    let iso     = dev.iso
                    let shutter = dev.exposureDuration.seconds
                    Task { @MainActor [weak self] in
                        self?.currentISO          = iso
                        self?.currentShutterSpeed = shutter
                    }
                }
                Task { @MainActor [weak self] in
                    self?.exposureObserver?.invalidate()
                    self?.exposureObserver = observer
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
    nonisolated private static func addInput(
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
        displayLogicalZoomFactor = logicalZoom
        stateLock.lock()
        logicalZoomFactor = logicalZoom
        stateLock.unlock()
        activeLensType    = type

        let position       = self.cameraPosition
        let isFront        = position == .front
        let sessionRef     = self.session
        let coordinatorRef = self.coordinator
        
        let previewRotationAngle = portraitRotationAngle

        sessionQueue.async {
            // Reconfigure only while the session is stopped. Removing or replacing
            // the active input while video delivery is running can expose transient
            // invalid format descriptions to the sample-buffer callback.
            if sessionRef.isRunning { sessionRef.stopRunning() }
            sessionRef.beginConfiguration()
            if let currentInput = sessionRef.inputs.first as? AVCaptureDeviceInput,
               currentInput.device.deviceType != type {
                sessionRef.removeInput(currentInput)
                CameraManager.addInput(session: sessionRef, position: position, preferredLens: type)
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

    private let portraitRotationAngle: CGFloat = 90
    
    // ✅ Public API to change aspect ratio
    func setAspectRatio(_ ratio: AspectRatio) {
        captureAspectRatio = ratio
    }

    // MARK: - Exposure

    func setExposureBias(_ ev: Float) {
        let sessionRef = self.session
        sessionQueue.async { [weak self] in
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
        guard permissionState == .granted else {
            captureErrorMessage = "Camera permission is required to capture a photo."
            return
        }
        guard !isCapturing else { return }
        captureErrorMessage = nil
        fireShutter()
    }

    private func fireShutter() {
        isCapturing = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let rotationAngle = portraitRotationAngle
        let isFront = cameraPosition == .front
        let wantsFlash = isFlashOn
        let sessionRef = session
        let coordinatorRef = coordinator
        let captureContext = Coordinator.CaptureContext(
            process: currentProcess,
            shouldSaveToPhotoLibrary: photoPermissionGranted
        )

        sessionQueue.async {
            guard sessionRef.isRunning,
                  coordinatorRef.photoOutput.connection(with: .video) != nil else {
                Task { @MainActor [weak manager = coordinatorRef.manager] in
                    manager?.isCapturing = false
                    manager?.captureErrorMessage = "The camera is still starting. Try again in a moment."
                }
                return
            }

            // All AVCapturePhotoOutput state is read on the same queue that
            // owns session configuration and photo capture. This avoids a
            // format renegotiation racing the shutter request.
            let settings: AVCapturePhotoSettings
            if let rawFormat = coordinatorRef.photoOutput.availableRawPhotoPixelFormatTypes.first(where: {
                AVCapturePhotoOutput.isAppleProRAWPixelFormat($0)
            }), coordinatorRef.photoOutput.isAppleProRAWSupported {
                settings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat)
            } else {
                settings = AVCapturePhotoSettings()
            }
            settings.photoQualityPrioritization = .quality
            let flashSupported = coordinatorRef.photoOutput.supportedFlashModes.contains(.on)
            settings.flashMode = wantsFlash && flashSupported ? .on : .off
            settings.maxPhotoDimensions = coordinatorRef.photoOutput.maxPhotoDimensions

            coordinatorRef.updatePhotoConnection(rotationAngle: rotationAngle, isMirrored: isFront)
            coordinatorRef.beginCapture(with: captureContext)
            coordinatorRef.photoOutput.capturePhoto(with: settings, delegate: coordinatorRef)
        }
    }

    func updateProcess(_ process: TechnicolorProcess) {
        currentProcess = process
        stateLock.lock()
        currentProcessCache = process
        stateLock.unlock()
    }

    nonisolated func processSnapshot() -> TechnicolorProcess {
        stateLock.lock()
        defer { stateLock.unlock() }
        return currentProcessCache
    }

    nonisolated func zoomSnapshot() -> CGFloat {
        stateLock.lock()
        defer { stateLock.unlock() }
        return logicalZoomFactor
    }
}

// MARK: - Coordinator
private final class Coordinator: NSObject, @unchecked Sendable,
    AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCapturePhotoCaptureDelegate
{
    let videoOutput = AVCaptureVideoDataOutput()
    let photoOutput = AVCapturePhotoOutput()
    nonisolated(unsafe) var engine: TechnicolorEngine
    weak var manager: CameraManager?
    private let photoProcessingQueue = DispatchQueue(label: "tc.photo-processing", qos: .userInitiated)
    private let captureContextLock = NSLock()
    private var activeCaptureContext: CaptureContext?

    struct CaptureContext: @unchecked Sendable {
        let process: TechnicolorProcess
        let shouldSaveToPhotoLibrary: Bool
    }
    
    init(engine: TechnicolorEngine) { self.engine = engine }

    func beginCapture(with context: CaptureContext) {
        captureContextLock.lock()
        activeCaptureContext = context
        captureContextLock.unlock()
    }

    private func takeCaptureContext() -> CaptureContext? {
        captureContextLock.lock()
        defer { captureContextLock.unlock() }
        defer { activeCaptureContext = nil }
        return activeCaptureContext
    }
    
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
        guard CMSampleBufferDataIsReady(sampleBuffer),
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              CMFormatDescriptionGetMediaType(formatDescription) == kCMMediaType_Video,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              CVPixelBufferGetWidth(pixelBuffer) > 0,
              CVPixelBufferGetHeight(pixelBuffer) > 0 else { return }
        let ciImage  = CIImage(cvPixelBuffer: pixelBuffer, options: [.applyOrientationProperty: true])
        let process  = manager?.processSnapshot() ?? .cinematic
        guard let cgImage = engine.render(process, image: ciImage) else { return }
        Task { @MainActor [weak manager] in manager?.filteredFrame = cgImage }
    }
    
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let captureContext = takeCaptureContext() ?? CaptureContext(
            process: .cinematic,
            shouldSaveToPhotoLibrary: false
        )
        guard error == nil else {
            Task { @MainActor [weak manager] in
                manager?.isCapturing = false
                manager?.captureErrorMessage = "ProRAW capture failed."
            }
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            Task { @MainActor [weak manager] in
                manager?.isCapturing = false
                manager?.captureErrorMessage = "The ProRAW file was empty."
            }
            return
        }
        guard let ciSource = engine.sourceImage(from: data, isRaw: photo.isRawPhoto) else {
            Task { @MainActor [weak manager] in
                manager?.isCapturing = false
                manager?.captureErrorMessage = "The ProRAW file could not be decoded."
            }
            return
        }

        // ProRAW pixel data is commonly stored in the sensor's native layout.
        // Apply its EXIF orientation before rendering so the later UIKit framing
        // step receives physically upright pixels rather than a rotated image.
        let orientationKey = kCGImagePropertyOrientation as String
        let exifOrientation = (photo.metadata[orientationKey] as? NSNumber)?.int32Value ?? 1
        let orientedSource = ciSource.oriented(forExifOrientation: exifOrientation)
        
        let process = captureContext.process
        // The finished image is capped at 3840 px. Downsize the
        // ProRAW frame before creating a CGImage so a 48 MP capture does not
        // create several full-resolution UIKit bitmaps during processing.
        guard let cg = engine.render(process, image: orientedSource, maximumDimension: 3840) else {
            Task { @MainActor [weak manager] in
                manager?.isCapturing = false
                manager?.captureErrorMessage = "The image processor could not render the ProRAW frame."
            }
            return
        }
        
        let original = UIImage(cgImage: cg, scale: 1.0, orientation: .up)
        let processingQueue = photoProcessingQueue
        let engine = engine
        let manager = manager
        
        processingQueue.async {
            // Crop, JPEG encoding, and file I/O are intentionally
            // off the main actor. A ProRAW shot can otherwise hold the UI for
            // several seconds even after its CI render has been downscaled.
            // Preserve the original 3:4 or 4:3 photo and add a white frame
            // around it so the complete Instagram canvas is exactly 4:5.
            let final = original.framedToAspectRatio(4.0 / 5.0)

            Task { @MainActor [weak manager] in
                manager?.isCapturing = false
                manager?.capturedImage = final
            }

            guard captureContext.shouldSaveToPhotoLibrary,
                  let jpegData = engine.jpegData(from: final) else { return }
            let exportURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("jpg")
            do {
                try jpegData.write(to: exportURL, options: .atomic)
            } catch {
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let req = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: exportURL)
                req?.creationDate = Date()
            }) { ok, _ in
                try? FileManager.default.removeItem(at: exportURL)
                guard ok else { return }
                Task { @MainActor [weak manager] in
                    manager?.showSavedBanner = true
                    try? await Task.sleep(for: .seconds(2))
                    manager?.showSavedBanner = false
                }
            }
        }
    }
}

// MARK: - Aspect Ratio Crop & Orientation (Updated)
private extension UIImage {

    /// Fits the image inside an editorial gallery mat at the requested aspect
    /// ratio, preserving every source pixel instead of cropping the photo.
    func framedToAspectRatio(_ targetRatio: CGFloat) -> UIImage {
        let normalized = normalizedForProcessing()
        guard targetRatio > 0, let normalizedCG = normalized.cgImage else { return self }

        let sourceWidth = CGFloat(normalizedCG.width)
        let sourceHeight = CGFloat(normalizedCG.height)
        let canvasWidth = max(sourceWidth, sourceHeight * targetRatio)
        let canvasHeight = canvasWidth / targetRatio

        // A restrained, asymmetric print margin gives the image a considered
        // editorial/gallery feel while keeping the complete canvas 4:5.
        let sideMargin = canvasWidth * 0.045
        let topMargin = canvasHeight * 0.040
        let bottomMargin = canvasHeight * 0.062
        let availableWidth = canvasWidth - sideMargin * 2
        let availableHeight = canvasHeight - topMargin - bottomMargin
        let imageScale = min(availableWidth / sourceWidth, availableHeight / sourceHeight)
        let imageWidth = sourceWidth * imageScale
        let imageHeight = sourceHeight * imageScale
        let imageRect = CGRect(
            x: (canvasWidth - imageWidth) / 2,
            y: topMargin + (availableHeight - imageHeight) / 2,
            width: imageWidth,
            height: imageHeight
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: canvasWidth, height: canvasHeight),
            format: format
        )

        return renderer.image { _ in
            UIColor(red: 0.945, green: 0.930, blue: 0.895, alpha: 1.0).setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))

            let cgContext = UIGraphicsGetCurrentContext()
            cgContext?.saveGState()
            cgContext?.setShadow(
                offset: CGSize(width: 0, height: canvasWidth * 0.004),
                blur: canvasWidth * 0.010,
                color: UIColor.black.withAlphaComponent(0.16).cgColor
            )
            normalized.draw(in: imageRect)
            cgContext?.restoreGState()

            UIColor(red: 0.08, green: 0.085, blue: 0.08, alpha: 0.72).setStroke()
            let lineWidth = max(1.0, canvasWidth / 1800.0)
            let keylineRect = imageRect.insetBy(dx: lineWidth * 0.5, dy: lineWidth * 0.5)
            cgContext?.setLineWidth(lineWidth)
            cgContext?.stroke(keylineRect)
        }
    }
    
    /// Crops image to target aspect ratio with correct orientation handling.
    /// Normalizes orientation FIRST, then crops, ensuring output is always .up
    func croppedToAspectRatio(_ targetRatio: CGFloat) -> UIImage {
        guard targetRatio > 0, self.cgImage != nil else { return self }
        
        // Step 1: Normalize orientation — apply EXIF rotation to pixel data
        let normalized = self.normalizedForProcessing()
        guard let normalizedCG = normalized.cgImage else { return self }
        
        let sourceWidth = CGFloat(normalizedCG.width)
        let sourceHeight = CGFloat(normalizedCG.height)
        
        // Step 2: Calculate centered crop rect for target ratio
        let cropRect = calculateCenteredCropRect(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            targetRatio: targetRatio
        )
        
        // Step 3: Perform crop
        guard let croppedCG = normalizedCG.cropping(to: cropRect.integral) else {
            return normalized
        }
        
        // Step 4: Return with .up orientation (pixels are physically correct)
        return UIImage(cgImage: croppedCG, scale: normalized.scale, orientation: .up)
    }
    
    /// Calculates a centered crop rect for the target aspect ratio
    private func calculateCenteredCropRect(
        sourceWidth: CGFloat,
        sourceHeight: CGFloat,
        targetRatio: CGFloat
    ) -> CGRect {
        let sourceRatio = sourceWidth / sourceHeight
        
        let cropWidth: CGFloat
        let cropHeight: CGFloat
        
        if sourceRatio > targetRatio {
            // Source is wider than target: crop width to match target ratio
            cropHeight = sourceHeight
            cropWidth = cropHeight * targetRatio
        } else {
            // Source is taller than target: crop height to match target ratio
            cropWidth = sourceWidth
            cropHeight = cropWidth / targetRatio
        }
        
        let x = (sourceWidth - cropWidth) / 2
        let y = (sourceHeight - cropHeight) / 2
        
        return CGRect(x: x, y: y, width: cropWidth, height: cropHeight)
    }
    
    /// Returns a new image with EXIF orientation applied to pixel data.
    /// Output image has orientation = .up and correct physical pixel dimensions.
    func normalizedForProcessing() -> UIImage {
        guard imageOrientation != .up else { return self }
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.preferredRange = .extended
        
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        
        return renderer.image { _ in
            // Drawing applies the orientation transform to pixel data
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Location Delegate
final class LocationDelegate: NSObject, @unchecked Sendable, CLLocationManagerDelegate {
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
        Task { @MainActor [weak self] in
            guard let self, let request = MKReverseGeocodingRequest(location: location) else { return }
            let mapItems: [MKMapItem]
            do {
                mapItems = try await request.mapItems
            } catch {
                return
            }
            guard let mapItem = mapItems.first else { return }

            let placeName = mapItem.addressRepresentations?.cityWithContext(.full)
                ?? mapItem.address?.shortAddress
                ?? mapItem.address?.fullAddress
            guard let placeName else { return }
            self.manager?.lastLocationString = placeName
        }
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
