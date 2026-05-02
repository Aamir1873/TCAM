//
//  CameraView.swift
//  TCAM - Glass UI (Compiler-Optimized & Fixed)
//

import SwiftUI
import AVFoundation
import CoreHaptics

// MARK: - Reusable Glass Modifiers
private extension View {
    func glassPill() -> some View {
        self
            .background(.ultraThinMaterial)
            .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 1))
            .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
            .clipShape(Capsule())
    }
    
    func glassCircle() -> some View {
        self
            .background(.ultraThinMaterial)
            .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
            .clipShape(Circle())
    }
    
    func glassCard() -> some View {
        self
            .background(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.2), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Main Camera View
struct CameraView: View {
    @State private var camera: CameraManager = CameraManager()
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var wideZoomToggle: CGFloat = 1.0
    @State private var teleZoomToggle: CGFloat = 1.0
    @State private var pinchZoom: CGFloat = 1.0
    @State private var lastPinchZoom: CGFloat = 1.0
    
    private let filters: [TechnicolorProcess] = [.native, .twoStrip, .monopack, .threeStrip]
    private let exposurePresets: [Float] = [-1.0, 0.0, 1.0]
    
    @State private var hapticEngine: CHHapticEngine?
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ImageOrPlaceholder(frame: camera.filteredFrame)
                .aspectRatio(4.0/3.0, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let newZoom = lastPinchZoom * value
                            pinchZoom = max(0.5, min(10.0, newZoom))
                            updateZoomForCurrentLens(pinchZoom)
                        }
                        .onEnded { _ in
                            lastPinchZoom = pinchZoom
                            triggerHaptic(.selection)
                        }
                )
            
            VStack {
                Text(focalLengthLabel)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .glassPill()
                    .padding(.top, 44)
                Spacer()
            }
            
            VStack {
                Spacer()
                ControlPanel(
                    camera: camera,
                    filters: filters,
                    exposurePresets: exposurePresets,
                    wideZoomToggle: $wideZoomToggle,
                    teleZoomToggle: $teleZoomToggle,
                    onHaptic: triggerHaptic
                )
                .padding(.bottom, 12)
            }
        }
        .background(.black)
        .sensoryFeedback(.success, trigger: camera.showSavedBanner)
        .onChange(of: scenePhase) { camera.handleScenePhase($1) }
        .task {
            await camera.requestPermissions()
            prepareHaptics()
        }
        .transaction { $0.animation = nil }
    }
    
    private var focalLengthLabel: String {
        let mm: Int, label: String
        switch camera.activeLensType {
        case .builtInUltraWideCamera: mm = 13; label = "0.5×"
        case .builtInWideAngleCamera:
            mm = wideZoomToggle == 1.0 ? 24 : 48
            label = wideZoomToggle == 1.0 ? "1×" : "2×"
        case .builtInTelephotoCamera:
            mm = teleZoomToggle == 1.0 ? 120 : 240
            label = teleZoomToggle == 1.0 ? "5×" : "10×"
        default: mm = 24; label = "1×"
        }
        return "\(mm)mm • \(label)"
    }
    
    private func updateZoomForCurrentLens(_ target: CGFloat) {
        switch camera.activeLensType {
        case .builtInUltraWideCamera:
            camera.switchToLens(type: .builtInUltraWideCamera, avZoom: 0.5, logicalZoom: 0.5)
        case .builtInWideAngleCamera:
            let c = max(1.0, min(2.0, target))
            wideZoomToggle = c
            camera.switchToLens(type: .builtInWideAngleCamera, avZoom: c, logicalZoom: c)
        case .builtInTelephotoCamera:
            let av = max(1.0, min(2.0, (target - 5.0) / 5.0 + 1.0))
            let lg = max(5.0, min(10.0, target))
            teleZoomToggle = av
            camera.switchToLens(type: .builtInTelephotoCamera, avZoom: av, logicalZoom: lg)
        default: break
        }
    }
    
    private func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            hapticEngine = try CHHapticEngine()
            try hapticEngine?.start()
        } catch { print("Haptics init error: \(error)") }
    }
    
    private func triggerHaptic(_ pattern: HapticPattern) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        let intensity: Float = pattern == .success ? 0.9 : 0.6
        let sharpness: Float = pattern == .success ? 0.8 : 0.5
        
        do {
            let p1 = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
            let p2 = CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [p1, p2], relativeTime: 0)
            let hapticPattern = try CHHapticPattern(events: [event], parameters: [])
            
            if let player = try? hapticEngine?.makePlayer(with: hapticPattern) {
                try? player.start(atTime: 0)
            }
        } catch { print("Haptic play error: \(error)") }
    }
    
    @ViewBuilder
    private func ImageOrPlaceholder(frame: CGImage?) -> some View {
        if let frame = frame {
            Image(uiImage: UIImage(cgImage: frame))
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            ProgressView()
                .tint(.amber)
                .scaleEffect(1.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassCard()
        }
    }
}

enum HapticPattern { case selection, success, warning }

// MARK: - Control Panel (Decomposed for Compiler Stability)
private struct ControlPanel: View {
    var camera: CameraManager
    let filters: [TechnicolorProcess]
    let exposurePresets: [Float]
    @Binding var wideZoomToggle: CGFloat
    @Binding var teleZoomToggle: CGFloat
    let onHaptic: (HapticPattern) -> Void
    
    var body: some View {
        VStack(spacing: 10) {
            exposureToggleRow
            filterToggleRow
            lensToggleRow
            shutterRow
        }
        .padding(.horizontal, 20)
    }
    
    private var exposureToggleRow: some View {
        HStack(spacing: 0) {
            ForEach(exposurePresets, id: \.self) { value in
                ExposureButton(value: value, isActive: abs(camera.exposureBias - value) < 0.05) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        camera.setExposureBias(value)
                        onHaptic(.selection)
                    }
                }
            }
        }
        .glassPill()
    }
    
    private var filterToggleRow: some View {
        HStack(spacing: 6) {
            ForEach(filters) { filter in
                FilterButton(filter: filter, isSelected: camera.currentProcess == filter) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        camera.updateProcess(filter)
                        onHaptic(.selection)
                    }
                }
            }
        }
    }
    
    private var lensToggleRow: some View {
        HStack(spacing: 0) {
            LensButton(label: "0.5", type: .builtInUltraWideCamera, avZoom: 0.5, logicalZoom: 0.5,
                       isActive: isLensActive(0.5)) {
                camera.switchToLens(type: .builtInUltraWideCamera, avZoom: 0.5, logicalZoom: 0.5)
                onHaptic(.selection)
            }
            
            LensButton(label: wideZoomToggle == 1.0 ? "1" : "2",
                       type: .builtInWideAngleCamera, avZoom: wideZoomToggle, logicalZoom: wideZoomToggle,
                       isActive: isLensActive(wideZoomToggle)) {
                camera.switchToLens(type: .builtInWideAngleCamera, avZoom: wideZoomToggle, logicalZoom: wideZoomToggle)
                onHaptic(.selection)
            }
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    wideZoomToggle = wideZoomToggle == 1.0 ? 2.0 : 1.0
                    camera.switchToLens(type: .builtInWideAngleCamera, avZoom: wideZoomToggle, logicalZoom: wideZoomToggle)
                    onHaptic(.success)
                }
            }
            
            LensButton(label: teleZoomToggle == 1.0 ? "5" : "10",
                       type: .builtInTelephotoCamera, avZoom: teleZoomToggle, logicalZoom: teleZoomToggle * 5.0,
                       isActive: isLensActive(teleZoomToggle * 5.0)) {
                camera.switchToLens(type: .builtInTelephotoCamera, avZoom: teleZoomToggle, logicalZoom: teleZoomToggle * 5.0)
                onHaptic(.selection)
            }
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    teleZoomToggle = teleZoomToggle == 1.0 ? 2.0 : 1.0
                    camera.switchToLens(type: .builtInTelephotoCamera, avZoom: teleZoomToggle, logicalZoom: teleZoomToggle * 5.0)
                    onHaptic(.success)
                }
            }
        }
        .glassPill()
    }
    
    private var shutterRow: some View {
        HStack(alignment: .center, spacing: 0) {
            ThumbnailView(capturedImage: camera.capturedImage).frame(width: 44)
            Spacer()
            ShutterButton(isCapturing: camera.isCapturing) {
                onHaptic(.success)
                camera.capturePhoto()
            }
            Spacer()
            FlashButton(isOn: camera.isFlashOn) {
                withAnimation {
                    camera.isFlashOn.toggle()
                    onHaptic(.selection)
                }
            }
        }
    }
    
    private func isLensActive(_ logicalZoom: CGFloat) -> Bool {
        abs(camera.logicalZoomFactor - logicalZoom) < 0.15
    }
}

// MARK: - Extracted Button Components (Fixes Timeouts & Inference)
private struct ExposureButton: View {
    let value: Float
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            Text(value == 0 ? "0" : (value > 0 ? "+1" : "-1"))
                .font(.system(size: 13, weight: isActive ? .bold : .medium))
                .foregroundStyle(isActive ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(ConditionalGlassBackground(isActive: isActive))
                .overlay(Capsule().stroke(isActive ? Color.clear : .white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct FilterButton: View {
    let filter: TechnicolorProcess
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            Text(filter.rawValue.replacingOccurrences(of: "-", with: " "))
                .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .monospaced))
                .foregroundStyle(isSelected ? .black : .white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(ConditionalGlassBackground(isActive: isSelected))
                .overlay(Capsule().stroke(isSelected ? Color.clear : .white.opacity(0.25), lineWidth: 1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct LensButton: View {
    let label: String
    let type: AVCaptureDevice.DeviceType
    let avZoom: CGFloat
    let logicalZoom: CGFloat
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            Text(label)
                .font(.system(size: 13, weight: isActive ? .bold : .medium))
                .foregroundStyle(isActive ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(ConditionalGlassBackground(isActive: isActive))
                .overlay(Capsule().stroke(isActive ? Color.clear : .white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct FlashButton: View {
    let isOn: Bool
    let action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: isOn ? "bolt.fill" : "bolt.slash")
                .font(.title2)
                .foregroundStyle(isOn ? .amber : .white)
                .frame(width: 44, height: 44)
                .glassCircle()
        }
        .padding(.trailing, 24)
    }
}
// ✅ FIXED: Conform to ShapeStyle, not View
private struct ConditionalGlassBackground: ShapeStyle {
    let isActive: Bool
    
    func resolve(in environment: EnvironmentValues) -> AnyShapeStyle {
        if isActive {
            return AnyShapeStyle(Color.amber)
        } else {
            return AnyShapeStyle(.ultraThinMaterial)
        }
    }
}

// MARK: - ThumbnailView
struct ThumbnailView: View {
    let capturedImage: UIImage?
    var body: some View {
        Group {
            if let img = capturedImage {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.1))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.4))
                    )
            }
        }
        .frame(width: 44, height: 44)
        .glassCard()
    }
}

// MARK: - ShutterButton (✅ FIXED: Added 'gradient:' label)
struct ShutterButton: View {
    let isCapturing: Bool
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button {
            action()
        } label: {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.9), lineWidth: 2.5)
                    .frame(width: 82, height: 82)
                    .shadow(color: .amber.opacity(0.3), radius: 10, y: 2)
                
                Circle()
                    .fill(shutterGradient)
                    .frame(width: 68, height: 68)
                    .scaleEffect(isPressed ? 0.92 : 1.0)
                    .overlay(Circle().stroke(.black.opacity(0.1), lineWidth: 1))
                    .shadow(
                        color: isCapturing ? .amber.opacity(0.6) : .black.opacity(0.35),
                        radius: isPressed ? 4 : 12,
                        y: isPressed ? 2 : 6
                    )
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: isCapturing)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in
                    withAnimation(.spring(duration: 0.2)) { isPressed = false }
                }
        )
    }
    
    // ✅ FIXED: Added 'gradient:' label to LinearGradient initializer
    private var shutterGradient: some ShapeStyle {
        let c1: Color = isCapturing ? .amber : .white
        let c2: Color = isCapturing ? .amber.opacity(0.85) : .white.opacity(0.92)
        return LinearGradient(
            gradient: Gradient(colors: [c1, c2]),  // ← Added 'gradient:' label here
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
