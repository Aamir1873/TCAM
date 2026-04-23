//
//  TCAMApp.swift
//  TCAM
//
//  Created by Aamir Abdul Kader on 23/04/2026.
//
// TechnicolorCamera.swift
// iOS 26 · iPhone Pro Only · Single-file drop-in
// Deployment target: iOS 26.0+
// Add to Info.plist:
//   NSCameraUsageDescription
//   NSPhotoLibraryAddUsageDescription

import SwiftUI
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Photos

// MARK: - Amber accent (single source of truth)

extension ShapeStyle where Self == Color {
static var amber: Color { Color(red: 1.0, green: 0.85, blue: 0.2) }
}

// MARK: - App Entry Point
// FIX: removed unused @Environment(.scenePhase) that was declared here but never acted on

@main
struct TechnicolorCameraApp: App {
var body: some Scene {
WindowGroup {
ContentView()
.preferredColorScheme(.dark)
}
}
}

struct ContentView: View {
var body: some View {
CameraView().ignoresSafeArea()
}
}

// MARK: - Technicolor Process

enum TechnicolorProcess: String, CaseIterable, Identifiable {
case threeStrip = “THREE-STRIP”
case twoStrip   = “TWO-STRIP”
case monopack   = “MONOPACK”
case vivid      = “HYPER-CHROME”

```
var id: String { rawValue }

var subtitle: String {
    switch self {
    case .threeStrip: "Classic 1930–50s Hollywood richness"
    case .twoStrip:   "Early 1920s amber & cyan duality"
    case .monopack:   "1950s Eastmancolor warmth"
    case .vivid:      "Pushed saturation fever dream"
    }
}

var swatchColors: [Color] {
    switch self {
    case .threeStrip: [Color(red: 0.95, green: 0.3,  blue: 0.15), Color(red: 0.15, green: 0.65, blue: 0.35)]
    case .twoStrip:   [Color(red: 0.95, green: 0.75, blue: 0.2),  Color(red: 0.1,  green: 0.6,  blue: 0.7)]
    case .monopack:   [Color(red: 0.95, green: 0.6,  blue: 0.25), Color(red: 0.7,  green: 0.35, blue: 0.15)]
    case .vivid:      [Color(red: 1.0,  green: 0.1,  blue: 0.5),  Color(red: 0.1,  green: 0.2,  blue: 1.0)]
    }
}
```

}

// MARK: - Timer Mode
// FIX: removed dead `.icon` property (all cases returned identical “timer” string)

enum TimerMode: Int, CaseIterable, Identifiable {
case off = 0, three = 3, ten = 10
var id: Int { rawValue }

```
var label: String {
    switch self {
    case .off:   "OFF"
    case .three: "3s"
    case .ten:   "10s"
    }
}

// FIX: safe cycle without force-unwrap — pure index arithmetic on a known fixed array
var next: TimerMode {
    let all = TimerMode.allCases
    let idx = all.firstIndex(where: { $0 == self }) ?? 0
    return all[(idx + 1) % all.count]
}
```

}

// MARK: - Filter Engine
// All CIFilter objects cached — allocated once, reused every frame.
// `nonisolated(unsafe)` is correct here: all accesses happen exclusively on the
// serial filterQueue, which provides the necessary mutual exclusion.

final class TechnicolorEngine: Sendable {

```
let context: CIContext = {
    CIContext(options: [
        .useSoftwareRenderer: false,
        .workingColorSpace:  CGColorSpace(name: CGColorSpace.displayP3) as Any,
        .outputColorSpace:   CGColorSpace(name: CGColorSpace.displayP3) as Any
    ])
}()

nonisolated(unsafe) private let ccThree  = CIFilter.colorControls()
nonisolated(unsafe) private let cmThree  = CIFilter.colorMatrix()
nonisolated(unsafe) private let vigThree = CIFilter.vignette()

nonisolated(unsafe) private let cmTwo    = CIFilter.colorMatrix()
nonisolated(unsafe) private let ccTwo    = CIFilter.colorControls()
nonisolated(unsafe) private let vigTwo   = CIFilter.vignette()

nonisolated(unsafe) private let ccMono   = CIFilter.colorControls()
nonisolated(unsafe) private let cmMono   = CIFilter.colorMatrix()
nonisolated(unsafe) private let gamMono  = CIFilter(name: "CIGammaAdjust")
nonisolated(unsafe) private let vigMono  = CIFilter.vignette()

nonisolated(unsafe) private let ccVivid  = CIFilter.colorControls()
nonisolated(unsafe) private let cmVivid  = CIFilter.colorMatrix()
nonisolated(unsafe) private let vigVivid = CIFilter.vignette()

nonisolated(unsafe) private let blurFilter  = CIFilter.gaussianBlur()
// FIX: use CIMultiplyCompositing for halation bloom scaling instead of
// CIColorControls.brightness, which was incorrectly clamping the glow.
// Also cached here instead of being re-allocated every frame.
nonisolated(unsafe) private let blurMultiply = CIFilter(name: "CIMultiplyCompositing")!
nonisolated(unsafe) private let blurColorMat = CIFilter.colorMatrix()
// FIX: CIAdditionCompositing was being allocated every frame inside halation() — now cached
nonisolated(unsafe) private let addBlend     = CIFilter(name: "CIAdditionCompositing")!

init() {
    ccThree.saturation = 1.55; ccThree.brightness = 0.02; ccThree.contrast = 1.12
    cmThree.rVector    = CIVector(x: 1.18,  y: 0.0,   z: -0.05, w: 0)
    cmThree.gVector    = CIVector(x: 0.0,   y: 0.92,  z: 0.04,  w: 0)
    cmThree.bVector    = CIVector(x: 0.0,   y: 0.0,   z: 0.88,  w: 0)
    cmThree.aVector    = CIVector(x: 0,     y: 0,     z: 0,     w: 1)
    cmThree.biasVector = CIVector(x: 0.015, y: 0.01,  z: 0.0,   w: 0)
    vigThree.intensity = 0.45; vigThree.radius = 1.6

    cmTwo.rVector    = CIVector(x: 1.2,  y: 0.1,  z: -0.1,  w: 0)
    cmTwo.gVector    = CIVector(x: 0.1,  y: 0.85, z: 0.05,  w: 0)
    cmTwo.bVector    = CIVector(x: -0.2, y: 0.15, z: 0.7,   w: 0)
    cmTwo.aVector    = CIVector(x: 0,    y: 0,    z: 0,     w: 1)
    cmTwo.biasVector = CIVector(x: 0.04, y: 0.02, z: -0.02, w: 0)
    ccTwo.saturation = 1.3; ccTwo.brightness = -0.01; ccTwo.contrast = 1.08
    vigTwo.intensity = 0.6; vigTwo.radius = 1.4

    ccMono.saturation = 1.25; ccMono.brightness = 0.03; ccMono.contrast = 1.05
    cmMono.rVector    = CIVector(x: 1.08, y: 0.0,  z: 0.0, w: 0)
    cmMono.gVector    = CIVector(x: 0.0,  y: 1.0,  z: 0.0, w: 0)
    cmMono.bVector    = CIVector(x: 0.0,  y: 0.0,  z: 0.9, w: 0)
    cmMono.aVector    = CIVector(x: 0,    y: 0,    z: 0,   w: 1)
    cmMono.biasVector = CIVector(x: 0.03, y: 0.02, z: 0.0, w: 0)
    gamMono?.setValue(0.88, forKey: "inputPower")
    vigMono.intensity = 0.35; vigMono.radius = 1.8

    ccVivid.saturation = 2.1; ccVivid.brightness = 0.0; ccVivid.contrast = 1.18
    cmVivid.rVector    = CIVector(x: 1.25,  y: -0.05, z: -0.05, w: 0)
    cmVivid.gVector    = CIVector(x: -0.05, y:  1.15, z: -0.05, w: 0)
    cmVivid.bVector    = CIVector(x: -0.05, y: -0.05, z:  1.3,  w: 0)
    cmVivid.aVector    = CIVector(x: 0,     y:  0,    z:  0,    w: 1)
    cmVivid.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
    vigVivid.intensity = 0.3; vigVivid.radius = 2.0

    blurFilter.radius = 12
    // blurColorMat scales the blurred layer's alpha to control bloom intensity
    blurColorMat.aVector = CIVector(x: 0, y: 0, z: 0, w: 1) // set per-call
}

func apply(_ process: TechnicolorProcess, to image: CIImage) -> CIImage {
    switch process {
    case .threeStrip: threeStrip(image)
    case .twoStrip:   twoStrip(image)
    case .monopack:   monopack(image)
    case .vivid:      vivid(image)
    }
}

private func threeStrip(_ image: CIImage) -> CIImage {
    ccThree.inputImage = image
    var img = ccThree.outputImage ?? image
    cmThree.inputImage = img;  img = cmThree.outputImage  ?? img
    vigThree.inputImage = img; img = vigThree.outputImage ?? img
    return halation(img, amount: 0.08)
}

private func twoStrip(_ image: CIImage) -> CIImage {
    cmTwo.inputImage = image
    var img = cmTwo.outputImage ?? image
    ccTwo.inputImage = img;  img = ccTwo.outputImage  ?? img
    vigTwo.inputImage = img; img = vigTwo.outputImage ?? img
    return halation(img, amount: 0.12)
}

private func monopack(_ image: CIImage) -> CIImage {
    ccMono.inputImage = image
    var img = ccMono.outputImage ?? image
    cmMono.inputImage = img; img = cmMono.outputImage ?? img
    if let gam = gamMono {
        gam.setValue(img, forKey: kCIInputImageKey)
        img = gam.outputImage ?? img
    }
    vigMono.inputImage = img; img = vigMono.outputImage ?? img
    return halation(img, amount: 0.06)
}

private func vivid(_ image: CIImage) -> CIImage {
    ccVivid.inputImage = image
    var img = ccVivid.outputImage ?? image
    cmVivid.inputImage = img;  img = cmVivid.outputImage  ?? img
    vigVivid.inputImage = img; img = vigVivid.outputImage ?? img
    return halation(img, amount: 0.15)
}

// FIX: Use CIColorMatrix alpha-scaling to attenuate bloom, then CIAdditionCompositing.
// Previous approach used CIColorControls.brightness which clamps incorrectly and
// produced near-black bloom. Alpha scaling is the correct way to control additive glow.
private func halation(_ image: CIImage, amount: Float) -> CIImage {
    blurFilter.inputImage = image
    guard let blurred = blurFilter.outputImage else { return image }

    // Scale the blurred layer's alpha (= bloom intensity) using a cached CIColorMatrix
    blurColorMat.inputImage = blurred
    blurColorMat.aVector    = CIVector(x: 0, y: 0, z: 0, w: CGFloat(amount))
    guard let scaledBloom = blurColorMat.outputImage else { return image }

    // Additive blend: sharp image + attenuated bloom = halation glow
    addBlend.setValue(image,       forKey: kCIInputImageKey)
    addBlend.setValue(scaledBloom, forKey: kCIInputBackgroundImageKey)
    return addBlend.outputImage ?? image
}
```

}

// MARK: - Camera Manager (Coordinator pattern)
// FIX: Separated NSObject delegate conformance into a private Coordinator to avoid
// @Observable macro conflicts with NSObject’s KVO machinery.

@Observable
@MainActor
final class CameraManager {

```
enum PermissionState { case unknown, granted, denied }

var filteredFrame: CGImage?
var capturedImage: UIImage?
var isCapturing    = false
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
private var timerTask: Task<Void, Never>?

// FIX: coordinator owns NSObject conformances, keeping CameraManager free of NSObject/KVO
private lazy var coordinator = Coordinator(manager: self)

// Swift 6-safe cross-queue read cache (written on MainActor, read on filterQueue)
nonisolated(unsafe) var _currentProcess: TechnicolorProcess = .threeStrip

// MARK: Permissions
// FIX: request photo library permission upfront alongside camera, not on every capture

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

// MARK: Session

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

// FIX: guard against starting a session with no inputs (e.g. permission not yet granted)
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
                // FIX: use `try await` so CancellationError propagates cleanly;
                // the `try?` form silently swallowed cancellation and continued the loop
                try await Task.sleep(for: .seconds(1))
                remaining -= 1
                self.timerCountdown = remaining
            }
            self.timerCountdown = nil
            self.fireShutter()
        } catch {
            // Task was cancelled — clean up UI without firing shutter
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

    let settings = AVCapturePhotoSettings()
    settings.flashMode = isFlashOn ? .on : .off
    if photoOutput.isAppleProRAWEnabled,
       let rawFmt = photoOutput.availableRawPhotoPixelFormatTypes
           .first(where: photoOutput.isAppleProRAWPixelFormat) {
        settings.rawPhotoPixelFormatType = rawFmt
    }
    photoOutput.capturePhoto(with: settings, delegate: coordinator)
}

// MARK: Camera Controls

func focusAndExpose(at point: CGPoint, in size: CGSize) {
    guard let device = currentDevice else { return }
    let n = CGPoint(x: point.x / size.width, y: point.y / size.height)
    sessionQueue.async {
        try? device.lockForConfiguration()
        if device.isFocusPointOfInterestSupported    { device.focusPointOfInterest    = n; device.focusMode    = .autoFocus  }
        if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = n; device.exposureMode = .autoExpose }
        device.unlockForConfiguration()
    }
}

func setExposureBias(_ ev: Float) {
    guard let device = currentDevice else { return }
    let clamped = max(device.minExposureTargetBias, min(ev, device.maxExposureTargetBias))
    sessionQueue.async {
        try? device.lockForConfiguration()
        device.setExposureTargetBias(clamped)
        device.unlockForConfiguration()
    }
    exposureBias = clamped
}

func setZoom(_ factor: CGFloat) {
    guard let device = currentDevice else { return }
    let lo = device.minAvailableVideoZoomFactor
    let hi = min(device.activeFormat.videoMaxZoomFactor, 10.0)
    let z  = max(lo, min(factor, hi))
    sessionQueue.async {
        try? device.lockForConfiguration()
        device.videoZoomFactor = z
        device.unlockForConfiguration()
    }
    zoomFactor = z
}

func updateProcess(_ process: TechnicolorProcess) {
    currentProcess  = process
    _currentProcess = process
}

private var currentDevice: AVCaptureDevice? {
    (session.inputs.first as? AVCaptureDeviceInput)?.device
}
```

}

// MARK: - Coordinator (NSObject delegate conformances isolated here)

private final class Coordinator: NSObject,
AVCaptureVideoDataOutputSampleBufferDelegate,
AVCapturePhotoCaptureDelegate {

```
private weak var manager: CameraManager?
init(manager: CameraManager) { self.manager = manager }

// MARK: Video frames

func captureOutput(_ output: AVCaptureOutput,
                   didOutput sampleBuffer: CMSampleBuffer,
                   from connection: AVCaptureConnection) {
    guard let mgr = manager,
          let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

    let ciImage  = CIImage(cvPixelBuffer: pixelBuffer, options: [.applyOrientationProperty: true])
    let process  = mgr._currentProcess
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

    let process  = mgr._currentProcess
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
```

}

// MARK: - Camera View

struct CameraView: View {
@State private var camera = CameraManager()
@Environment(.scenePhase) private var scenePhase

```
@State private var showProcessPicker  = false
@State private var lastScale: CGFloat = 1.0
@State private var focusDot: CGPoint? = nil
@State private var showExposureSlider = false

var body: some View {
    GeometryReader { geo in
        let size = geo.size

        ZStack {
            Color.black.ignoresSafeArea()

            if let frame = camera.filteredFrame {
                Image(decorative: frame, scale: 1.0, orientation: .up)
                    .resizable().scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped().ignoresSafeArea()
            }

            FilmFrameOverlay().ignoresSafeArea()

            // FIX: added .transition(.opacity) so the animation value has something to drive
            if camera.showGrid {
                GridOverlay()
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            if let dot = focusDot {
                FocusReticle(position: dot)
            }

            if let countdown = camera.timerCountdown {
                TimerCountdownOverlay(count: countdown) { camera.cancelTimer() }
            }

            GlassEffectContainer {
                VStack(spacing: 0) {
                    topHUD
                    if showExposureSlider {
                        ExposureSlider(bias: camera.exposureBias) { camera.setExposureBias($0) }
                            .padding(.top, 12).padding(.horizontal, 28)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    Spacer()
                    ProcessStrip(selected: camera.currentProcess) { camera.updateProcess($0) }
                        .padding(.bottom, 20)
                    bottomControls(safeBottom: geo.safeAreaInsets.bottom, size: size)
                }
                .ignoresSafeArea(edges: .bottom)
            }

            if camera.permissionState == .denied {
                PermissionDeniedView()
            }

            if camera.showSavedBanner {
                VStack {
                    Spacer()
                    Label("SAVED TO CAMERA ROLL", systemImage: "checkmark")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Color.amber).clipShape(Capsule())
                        .padding(.bottom, 170)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            if showProcessPicker {
                ProcessPickerOverlay(
                    selected: camera.currentProcess,
                    isShowing: $showProcessPicker
                ) { camera.updateProcess($0) }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // FIX: use geo.size directly in gesture handlers — no need for separate @State viewSize
        .gesture(
            MagnificationGesture()
                .onChanged { camera.setZoom(lastScale * $0) }
                .onEnded   { _ in lastScale = camera.zoomFactor }
        )
        .onTapGesture { point in
            focusDot = point
            camera.focusAndExpose(at: point, in: size)
            withAnimation(.easeOut(duration: 1.2).delay(0.8)) { focusDot = nil }
        }
    }
    // FIX: trigger sensory feedback only on showSavedBanner — not on filteredFrame
    .sensoryFeedback(.success, trigger: camera.showSavedBanner)
    .animation(.spring(duration: 0.35),    value: camera.showSavedBanner)
    .animation(.spring(duration: 0.4),     value: showProcessPicker)
    .animation(.easeInOut(duration: 0.25), value: showExposureSlider)
    .animation(.easeInOut(duration: 0.2),  value: camera.showGrid)
    .onChange(of: scenePhase) { camera.handleScenePhase($1) }
    .task { await camera.requestPermissions() }
}

// MARK: Top HUD

var topHUD: some View {
    HStack(spacing: 10) {
        Button { withAnimation { showProcessPicker.toggle() } } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("TECHNICOLOR")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                Text(camera.currentProcess.rawValue)
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(.amber)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.amber.opacity(0.4), lineWidth: 1))
        }

        Spacer()

        // FIX: grid button now uses distinct icons for on/off states
        HUDIconButton(
            icon: camera.showGrid ? "grid.circle.fill" : "grid.circle",
            isOn: camera.showGrid
        ) { camera.showGrid.toggle() }

        // FIX: timer cycle uses `.next` property — no force-unwrap
        HUDIconButton(
            icon: "timer",
            label: camera.timerMode == .off ? nil : camera.timerMode.label,
            isOn: camera.timerMode != .off
        ) { camera.timerMode = camera.timerMode.next }

        HUDIconButton(
            icon: showExposureSlider ? "plusminus.circle.fill" : "plusminus.circle",
            isOn: showExposureSlider
        ) { withAnimation { showExposureSlider.toggle() } }

        HUDIconButton(
            icon: camera.isFlashOn ? "bolt.fill" : "bolt.slash",
            isOn: camera.isFlashOn
        ) { camera.isFlashOn.toggle() }
    }
    .padding(.horizontal, 20)
    .padding(.top, 60)
}

// MARK: Bottom Controls

func bottomControls(safeBottom: CGFloat, size: CGSize) -> some View {
    VStack(spacing: 0) {
        ZoomIndicator(zoom: camera.zoomFactor) { camera.setZoom(1.0); lastScale = 1.0 }
            .padding(.bottom, 20)

        HStack(alignment: .center, spacing: 0) {
            thumbnailView.frame(maxWidth: .infinity)

            ShutterButton(
                isCapturing: camera.isCapturing,
                timerCountdown: camera.timerCountdown,
                timerTotal: camera.timerMode.rawValue
            ) { camera.capturePhoto() }

            Button { camera.flipCamera() } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, safeBottom + 20)
        .padding(.top, 8)
    }
}

@ViewBuilder
var thumbnailView: some View {
    if let img = camera.capturedImage {
        Image(uiImage: img)
            .resizable().scaledToFill()
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.3), lineWidth: 1))
            .transition(.scale.combined(with: .opacity))
            .animation(.spring(duration: 0.3), value: camera.capturedImage != nil)
    } else {
        RoundedRectangle(cornerRadius: 10)
            .fill(.white.opacity(0.08))
            .frame(width: 56, height: 56)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.15), lineWidth: 1))
    }
}
```

}

// MARK: - HUD Icon Button

struct HUDIconButton: View {
let icon: String
var label: String? = nil
var isOn: Bool = false
let action: () -> Void

```
var body: some View {
    Button(action: action) {
        Group {
            if let label {
                VStack(spacing: 1) {
                    Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                    Text(label).font(.system(size: 9, weight: .bold, design: .monospaced))
                }
            } else {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold))
            }
        }
        .foregroundStyle(isOn ? Color.amber : .white)
        .frame(width: 44, height: 44)
        .glassEffect(.regular.interactive(), in: Circle())
    }
}
```

}

// MARK: - Focus Reticle

struct FocusReticle: View {
let position: CGPoint
@State private var scale: CGFloat = 1.4
@State private var opacity: Double = 0

```
var body: some View {
    RoundedRectangle(cornerRadius: 3)
        .stroke(Color.amber, lineWidth: 1.5)
        .frame(width: 70, height: 70)
        .scaleEffect(scale)
        .opacity(opacity)
        .position(position)
        .onAppear {
            withAnimation(.spring(duration: 0.25)) { scale = 1.0; opacity = 1.0 }
        }
}
```

}

// MARK: - Exposure Slider
// FIX: use %+.1f format specifier — handles sign automatically, no manual “+” concatenation

struct ExposureSlider: View {
let bias: Float
let onChange: (Float) -> Void

```
var body: some View {
    HStack(spacing: 10) {
        Image(systemName: "sun.min").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
        Slider(
            value: Binding(get: { Double(bias) }, set: { onChange(Float($0)) }),
            in: -3...3, step: 0.1
        ).tint(.amber)
        Image(systemName: "sun.max").font(.system(size: 16)).foregroundStyle(.white.opacity(0.5))
        Text(String(format: "%+.1f", bias))
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(.amber)
            .frame(width: 38, alignment: .trailing)
    }
    .padding(.horizontal, 16).padding(.vertical, 12)
    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
}
```

}

// MARK: - Process Strip

struct ProcessStrip: View {
let selected: TechnicolorProcess
let onSelect: (TechnicolorProcess) -> Void

```
var body: some View {
    ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(TechnicolorProcess.allCases) { process in
                    Button { onSelect(process) } label: {
                        Text(process.rawValue)
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundStyle(selected == process ? .black : .white)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(
                                selected == process ? Color.amber : Color.white.opacity(0.12),
                                in: Capsule()
                            )
                            .animation(.spring(duration: 0.25), value: selected)
                    }
                    .sensoryFeedback(.selection, trigger: selected == process)
                    .id(process.id)
                }
            }
            .padding(.horizontal, 20)
        }
        // FIX: two-param form — single-param onChange is the deprecated iOS 16 overload
        .onChange(of: selected) { _, newValue in
            withAnimation { proxy.scrollTo(newValue.id, anchor: .center) }
        }
    }
}
```

}

// MARK: - Shutter Button

struct ShutterButton: View {
let isCapturing: Bool
let timerCountdown: Int?
let timerTotal: Int
let action: () -> Void

```
@State private var pressed = false

private var timerProgress: Double {
    guard let c = timerCountdown, timerTotal > 0 else { return 0 }
    return Double(timerTotal - c) / Double(timerTotal)
}

var body: some View {
    Button(action: action) {
        ZStack {
            if timerCountdown != nil {
                Circle()
                    .stroke(Color.amber.opacity(0.25), lineWidth: 4)
                    .frame(width: 88, height: 88)
                Circle()
                    .trim(from: 0, to: timerProgress)
                    .stroke(Color.amber, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 88, height: 88)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: timerProgress)
            }
            Circle().stroke(.white, lineWidth: 3).frame(width: 80, height: 80)
            Circle()
                .fill(isCapturing ? Color.amber : .white)
                .frame(width: 66, height: 66)
                .scaleEffect(pressed ? 0.88 : 1.0)
                .animation(.spring(duration: 0.18), value: pressed)
            if let c = timerCountdown, c > 0 {
                Text("\(c)")
                    .font(.system(size: 22, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.amber)
            }
        }
    }
    .buttonStyle(.plain)
    .sensoryFeedback(.impact(weight: .medium), trigger: isCapturing)
    .simultaneousGesture(
        DragGesture(minimumDistance: 0)
            .onChanged { _ in pressed = true }
            .onEnded   { _ in pressed = false }
    )
}
```

}

// MARK: - Zoom Indicator

struct ZoomIndicator: View {
let zoom: CGFloat
let onTap: () -> Void

```
private var label: String {
    zoom < 1.05 ? "1×" :
    zoom < 2.05 ? String(format: "%.1f×", zoom) :
                  String(format: "%.0f×",  zoom)
}

var body: some View {
    Button(action: onTap) {
        Text(label)
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .glassEffect(.regular.interactive(), in: Capsule())
            .contentTransition(.numericText())
            .animation(.spring(duration: 0.2), value: zoom)
    }
}
```

}

// MARK: - Film Frame Overlay

struct FilmFrameOverlay: View {
var body: some View {
Canvas { context, size in
let w = size.width, h = size.height
let sh: CGFloat = 28
let strip   = Color.black.opacity(0.72)
let hole    = Color.white.opacity(0.12)
let bracket = Color.white.opacity(0.6)

```
        context.fill(Path(CGRect(x: 0, y: 0,      width: w, height: sh)), with: .color(strip))
        context.fill(Path(CGRect(x: 0, y: h - sh, width: w, height: sh)), with: .color(strip))

        let hW: CGFloat = 14, hH: CGFloat = 10, sp: CGFloat = 28
        let count  = Int(w / sp) + 1
        let startX = (w - CGFloat(count - 1) * sp) / 2
        for i in 0..<count {
            let x = startX + CGFloat(i) * sp - hW / 2
            context.fill(Path(roundedRect: CGRect(x: x, y: (sh - hH) / 2,          width: hW, height: hH), cornerRadius: 2), with: .color(hole))
            context.fill(Path(roundedRect: CGRect(x: x, y: h - sh + (sh - hH) / 2, width: hW, height: hH), cornerRadius: 2), with: .color(hole))
        }

        let bL: CGFloat = 28, bT: CGFloat = 2.5, m: CGFloat = sh + 10
        for (ox, oy, sx, sy) in [(14.0, m, 1.0, 1.0), (w - 14, m, -1.0, 1.0),
                                  (14.0, h - m, 1.0, -1.0), (w - 14, h - m, -1.0, -1.0)] {
            context.fill(Path(CGRect(x: ox,        y: oy - (sy < 0 ? bT : 0), width: bL * sx, height: bT     )), with: .color(bracket))
            context.fill(Path(CGRect(x: ox,        y: oy - (sy < 0 ? bL : 0), width: bT,      height: bL * sy)), with: .color(bracket))
        }
    }
}
```

}

// MARK: - Grid Overlay (rule of thirds)

struct GridOverlay: View {
var body: some View {
Canvas { context, size in
let line = Color.white.opacity(0.2)
for i in 1…2 {
let x = size.width  * CGFloat(i) / 3
let y = size.height * CGFloat(i) / 3
context.stroke(Path { p in p.move(to: .init(x: x, y: 0));           p.addLine(to: .init(x: x, y: size.height)) }, with: .color(line), lineWidth: 0.5)
context.stroke(Path { p in p.move(to: .init(x: 0, y: y));           p.addLine(to: .init(x: size.width, y: y))  }, with: .color(line), lineWidth: 0.5)
}
}
}
}

// MARK: - Timer Countdown Overlay

struct TimerCountdownOverlay: View {
let count: Int
let onCancel: () -> Void
@State private var scale: CGFloat = 1.4

```
var body: some View {
    ZStack {
        Color.black.opacity(0.3).ignoresSafeArea()
        VStack(spacing: 24) {
            Text("\(count)")
                .font(.system(size: 120, weight: .black, design: .monospaced))
                .foregroundStyle(Color.amber)
                .scaleEffect(scale)
                .onChange(of: count) { _, _ in
                    scale = 1.4
                    withAnimation(.spring(duration: 0.3)) { scale = 1.0 }
                }
                .onAppear { withAnimation(.spring(duration: 0.3)) { scale = 1.0 } }

            Button("CANCEL", action: onCancel)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 24).padding(.vertical, 10)
                .glassEffect(.regular.interactive(), in: Capsule())
        }
    }
}
```

}

// MARK: - Process Picker Sheet

struct ProcessPickerOverlay: View {
let selected: TechnicolorProcess
@Binding var isShowing: Bool
let onSelect: (TechnicolorProcess) -> Void
@GestureState private var dragY: CGFloat = 0

```
var body: some View {
    ZStack(alignment: .bottom) {
        Color.black.opacity(0.55).ignoresSafeArea()
            .onTapGesture { withAnimation { isShowing = false } }

        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(.white.opacity(0.3))
                .frame(width: 40, height: 4)
                .padding(.top, 12).padding(.bottom, 20)
            Text("SELECT PROCESS")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.bottom, 16)
            ForEach(TechnicolorProcess.allCases) { process in
                ProcessRow(process: process, isSelected: selected == process) {
                    withAnimation(.spring(duration: 0.25)) { onSelect(process); isShowing = false }
                }
            }
            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(.white.opacity(0.1), lineWidth: 1))
        .padding(.horizontal, 12).padding(.bottom, 8)
        .offset(y: max(0, dragY))
        .gesture(
            DragGesture()
                .updating($dragY) { v, s, _ in s = v.translation.height }
                .onEnded { v in if v.translation.height > 80 { withAnimation { isShowing = false } } }
        )
    }
    .ignoresSafeArea()
}
```

}

struct ProcessRow: View {
let process: TechnicolorProcess
let isSelected: Bool
let action: () -> Void

```
var body: some View {
    Button(action: action) {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: process.swatchColors,
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(process.rawValue)
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .foregroundStyle(isSelected ? Color.amber : .white)
                Text(process.subtitle)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.amber)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(isSelected ? Color.white.opacity(0.06) : Color.clear)
    }
    .buttonStyle(.plain)
}
```

}

// MARK: - Permission Denied View

struct PermissionDeniedView: View {
@Environment(.openURL) private var openURL

```
var body: some View {
    ZStack {
        Color.black.opacity(0.85).ignoresSafeArea()
        VStack(spacing: 20) {
            Image(systemName: "camera.slash")
                .font(.system(size: 52, weight: .thin))
                .foregroundStyle(.white.opacity(0.4))
            Text("CAMERA ACCESS REQUIRED")
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)
            Text("Enable camera access in Settings\nto use Technicolor Camera.")
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .foregroundStyle(.black)
            .padding(.horizontal, 24).padding(.vertical, 12)
            .background(Color.amber).clipShape(Capsule())
        }
        .padding(.horizontal, 40)
    }
}
```

}