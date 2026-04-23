//
//  CameraView.swift
//  TCAM - Clean UI + Removed Focus Gesture
//

import SwiftUI
import AVFoundation

struct CameraView: View {
    @State private var camera: CameraManager = CameraManager()
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var showProcessPicker = false
    @State private var showExposureSlider = false // ✅ Explicit state for slider visibility
    
    private let ratio4x3: CGFloat = 4.0 / 3.0
    
    private var lensOptions: [LensItem] {
        [
            .init(id: 0, type: .builtInUltraWideCamera, label: "0.5", baseZoomFactor: 1.0, digitalMultiplier: 1.0),
            .init(id: 1, type: .builtInWideAngleCamera, label: "1", baseZoomFactor: 1.0, digitalMultiplier: 1.0),
            .init(id: 2, type: .builtInWideAngleCamera, label: "2", baseZoomFactor: 1.0, digitalMultiplier: 2.0),
            .init(id: 3, type: .builtInTelephotoCamera, label: "5", baseZoomFactor: 1.0, digitalMultiplier: 1.0),
            .init(id: 4, type: .builtInTelephotoCamera, label: "10", baseZoomFactor: 1.0, digitalMultiplier: 2.0)
        ]
    }
    
    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let safe = geo.safeAreaInsets
            
            let reservedForUI: CGFloat = 220
            let maxPreviewH = size.height - safe.top - safe.bottom - reservedForUI
            let previewH = min(maxPreviewH, size.width * ratio4x3)
            let previewW = previewH / ratio4x3
            
            VStack(spacing: 0) {
                // 1️⃣ TOP BAR (Flash + Exposure Toggle always visible)
                topBar(safeAreaTop: safe.top)
                    .padding(.horizontal, 16)
                    .zIndex(2)
                
                Spacer().frame(height: 8)
                
                // 2️⃣ CAMERA PREVIEW
                ZStack {
                    cameraPreview(size: CGSize(width: previewW, height: previewH))
                        .frame(width: previewW, height: previewH)
                    overlayViews
                        .frame(width: previewW, height: previewH)
                }
                .frame(maxWidth: .infinity)
                .clipped()
                .background(Color.black.ignoresSafeArea())
                .zIndex(1)
                
                Spacer().frame(height: 8)
                
                // 3️⃣ BOTTOM CONTROLS (Exposure Slider + Lenses + Shutter)
                bottomControls(safeAreaBottom: safe.bottom)
                    .padding(.horizontal, 16)
                    .zIndex(3)
            }
            .background(Color.black)
            .animation(.spring(duration: 0.35, bounce: 0.3), value: self.camera.showSavedBanner)
            .animation(.spring(duration: 0.4), value: showProcessPicker)
            .animation(.easeInOut(duration: 0.25), value: showExposureSlider)
            .sensoryFeedback(.success, trigger: self.camera.showSavedBanner)
            .onChange(of: scenePhase) { self.camera.handleScenePhase($1) }
            .task { await self.camera.requestPermissions() }
        }
    }
    
    // MARK: - Preview
    @ViewBuilder
    private func cameraPreview(size: CGSize) -> some View {
        if let frame = self.camera.filteredFrame {
            Image(decorative: frame, scale: 1.0, orientation: .up)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            Color.black
                .ignoresSafeArea()
                .overlay(ProgressView().tint(.amber).scaleEffect(1.2))
        }
    }
    
    // MARK: - Overlays (No focus reticle)
    @ViewBuilder
    private var overlayViews: some View {
        FilmFrameOverlay()
        if self.camera.showGrid { GridOverlay() }
        if let countdown = self.camera.timerCountdown {
            TimerCountdownOverlay(count: countdown) { self.camera.cancelTimer() }
        }
    }
    
    // MARK: - Top Bar
    @ViewBuilder
    private func topBar(safeAreaTop: CGFloat) -> some View {
        HStack(spacing: 12) {
            // Process Picker Button
            Button {
                withAnimation(.spring(duration: 0.3)) { showProcessPicker.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "film.fill").font(.system(size: 10, weight: .bold))
                    Text(self.camera.currentProcess.rawValue)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(.amber)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(.black.opacity(0.6)).overlay(Capsule().stroke(.amber.opacity(0.4), lineWidth: 1)))
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Controls
            HStack(spacing: 8) {
                ControlButton(icon: self.camera.showGrid ? "grid.fill" : "grid", isActive: self.camera.showGrid) {
                    self.camera.showGrid.toggle()
                }
                ControlButton(icon: "timer", badge: self.camera.timerMode == .off ? nil : "\(self.camera.timerMode.rawValue)", isActive: self.camera.timerMode != .off) {
                    self.camera.timerMode = self.camera.timerMode.next
                }
                ControlButton(icon: showExposureSlider ? "sun.max.fill" : "sun.max", isActive: showExposureSlider) {
                    withAnimation { showExposureSlider.toggle() }
                }
                ControlButton(icon: self.camera.isFlashOn ? "bolt.fill" : "bolt.slash", isActive: self.camera.isFlashOn) {
                    self.camera.isFlashOn.toggle()
                }
            }
        }
        .padding(.top, max(safeAreaTop, 8))
        .padding(.bottom, 4)
    }
    
    // MARK: - Bottom Controls
    @ViewBuilder
    private func bottomControls(safeAreaBottom: CGFloat) -> some View {
        VStack(spacing: 12) {
            // ✅ Exposure Slider (Visible when toggled)
            if showExposureSlider {
                ExposureSlider(bias: self.camera.exposureBias) { self.camera.setExposureBias($0) }
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            
            // Lens Selector
            lensSelectorRow
            
            // Shutter Row
            HStack(alignment: .center, spacing: 28) {
                thumbnailView
                
                ShutterButton(
                    isCapturing: self.camera.isCapturing,
                    timerCountdown: self.camera.timerCountdown,
                    timerTotal: self.camera.timerMode.rawValue
                ) { self.camera.capturePhoto() }
                
                
            }
            
            // Process Strip
            ProcessStrip(selected: self.camera.currentProcess) { self.camera.updateProcess($0) }
            
            Spacer().frame(height: max(safeAreaBottom, 10))
        }
    }
    
    // MARK: - Lens Selector
    private var lensSelectorRow: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(lensOptions) { lens in
                        Button { selectLens(lens) } label: {
                            VStack(spacing: 2) {
                                Text(lens.label)
                                    .font(.system(size: 14, weight: isLensActive(lens) ? .bold : .medium, design: .rounded))
                                    .foregroundStyle(isLensActive(lens) ? .black : .white)
                                if !lens.isOptical && isLensActive(lens) {
                                    Text("D")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.amber)
                                }
                            }
                            .frame(width: 48, height: 48)
                            .background(
                                Circle()
                                    .fill(isLensActive(lens) ? Color.amber : .black.opacity(0.6))
                                    .overlay(Circle().stroke(isLensActive(lens) ? Color.clear : .white.opacity(0.3), lineWidth: 1.5))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: geo.size.width, alignment: .center)
                .padding(.horizontal, 2)
            }
        }
        .frame(height: 56)
    }
    
    // MARK: - Thumbnail
    @ViewBuilder
    private var thumbnailView: some View {
        Group {
            if let img = self.camera.capturedImage {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.15))
                    .overlay(Image(systemName: "photo").font(.system(size: 16)).foregroundStyle(.white.opacity(0.4)))
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.3), lineWidth: 1))
    }
    
    // MARK: - Helpers
    private func isLensActive(_ lens: LensItem) -> Bool {
        guard self.camera.currentLens == lens.type else { return false }
        let expectedZoom = lens.baseZoomFactor * lens.digitalMultiplier
        return abs(self.camera.currentZoomFactor - expectedZoom) < 0.15
    }
    
    private func selectLens(_ lens: LensItem) {
        if self.camera.currentLens != lens.type {
            while self.camera.currentLens != lens.type { self.camera.toggleLens() }
        }
        let target = lens.baseZoomFactor * lens.digitalMultiplier
        self.camera.setZoomFactor(target)
    }
}

// MARK: - Control Button
struct ControlButton: View {
    let icon: String
    var badge: String? = nil
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                if let badge { Text(badge).font(.system(size: 8, weight: .bold, design: .monospaced)) }
            }
            .foregroundStyle(isActive ? Color.amber : .white)
            .frame(width: 40, height: 40)
            .background(Circle().fill(.black.opacity(0.5)).overlay(Circle().stroke(.white.opacity(isActive ? 0.4 : 0.2), lineWidth: 1)))
        }
        .buttonStyle(.plain)
    }
}

private struct LensItem: Identifiable {
    let id: Int
    let type: AVCaptureDevice.DeviceType
    let label: String
    let baseZoomFactor: CGFloat
    let digitalMultiplier: CGFloat
    var isOptical: Bool { digitalMultiplier == 1.0 }
}
