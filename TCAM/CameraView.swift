//
//  CameraView.swift
//  TCAM - Clean Layout
//

import SwiftUI
import AVFoundation

private struct UIConstants {
    static let shutterSize: CGFloat = 78
    static let thumbnailSize: CGFloat = 48
    static let controlButtonSize: CGFloat = 44
    static let horizontalPadding: CGFloat = 20
}

struct CameraView: View {
    @State private var camera = CameraManager()
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var showProcessPicker = false
    @State private var focusDot: CGPoint? = nil
    @State private var showExposureSlider = false
    
    private var lensOptions: [LensItem] {
        [
            .init(id: 0, type: .builtInUltraWideCamera, label: "0.5"),
            .init(id: 1, type: .builtInWideAngleCamera, label: "1"),
            .init(id: 2, type: .builtInTelephotoCamera, label: "2"),
            .init(id: 3, type: .builtInTelephotoCamera, label: "5", isDigitalZoom: true)
        ]
    }
    
    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let safeArea = geo.safeAreaInsets
            
            ZStack {
                // Background
                Color.black.ignoresSafeArea()
                
                // Camera Preview
                cameraPreview(size: size)
                
                // Overlays
                overlayViews
                
                VStack(spacing: 0) {
                    // TOP BAR - Spacious
                    topBar(safeAreaTop: safeArea.top)
                    
                    Spacer()
                    
                    // Exposure Slider (above controls)
                    if showExposureSlider {
                        ExposureSlider(bias: camera.exposureBias) { camera.setExposureBias($0) }
                            .padding(.horizontal, 40)
                            .padding(.bottom, 12)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    
                    // BOTTOM CONTROLS - Clean separation
                    bottomControls(safeAreaBottom: safeArea.bottom)
                }
                
                // Modals
                modalOverlays
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { camera.toggleLens() }
            .simultaneousGesture(focusGesture(in: size))
            .animation(.spring(duration: 0.35, bounce: 0.3), value: camera.showSavedBanner)
            .animation(.spring(duration: 0.4), value: showProcessPicker)
            .animation(.easeInOut(duration: 0.25), value: showExposureSlider)
            .sensoryFeedback(.success, trigger: camera.showSavedBanner)
            .onChange(of: scenePhase) { camera.handleScenePhase($1) }
            .task { await camera.requestPermissions() }
        }
    }
    
    // MARK: - Preview
    @ViewBuilder
    private func cameraPreview(size: CGSize) -> some View {
        if let frame = camera.filteredFrame {
            Image(decorative: frame, scale: 1.0, orientation: .up)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            // Placeholder while camera initializes
            Color.black
                .overlay(
                    ProgressView()
                        .tint(.amber)
                        .scaleEffect(1.5)
                )
        }
    }
    
    // MARK: - Overlays
    @ViewBuilder
    private var overlayViews: some View {
        FilmFrameOverlay()
        
        if camera.showGrid {
            GridOverlay()
        }
        
        if let dot = focusDot {
            FocusReticle(position: dot)
        }
        
        if let countdown = camera.timerCountdown {
            TimerCountdownOverlay(count: countdown) { camera.cancelTimer() }
        }
    }
    
    // MARK: - Top Bar - CLEAN
    @ViewBuilder
    private func topBar(safeAreaTop: CGFloat) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Process Button (Left)
                Button {
                    withAnimation(.spring(duration: 0.3)) { showProcessPicker.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "film.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(camera.currentProcess.rawValue)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(.amber)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(.black.opacity(0.6))
                            .overlay(Capsule().stroke(.amber.opacity(0.4), lineWidth: 1))
                    )
                }
                
                Spacer()
                
                // Right Controls - FIXED ICONS
                HStack(spacing: 12) {
                    ControlButton(
                        icon: camera.showGrid ? "grid.fill" : "grid",
                        isActive: camera.showGrid
                    ) { camera.showGrid.toggle() }
                    
                    ControlButton(
                        icon: "timer",
                        badge: camera.timerMode == .off ? nil : "\(camera.timerMode.rawValue)",
                        isActive: camera.timerMode != .off
                    ) { camera.timerMode = camera.timerMode.next }
                    
                    ControlButton(
                        icon: camera.isFlashOn ? "bolt.fill" : "bolt.slash",
                        isActive: camera.isFlashOn
                    ) { camera.isFlashOn.toggle() }
                }
            }
            .padding(.horizontal, UIConstants.horizontalPadding)
            
            // Lens Selector - Separate Row
            lensSelectorRow
                .padding(.horizontal, UIConstants.horizontalPadding)
        }
        .padding(.top, max(safeAreaTop, 12))
    }
    
    // MARK: - Lens Selector Row
    private var lensSelectorRow: some View {
        HStack(spacing: 12) {
            ForEach(lensOptions) { lens in
                Button {
                    selectLens(lens)
                } label: {
                    Text(lens.label)
                        .font(.system(size: 15, weight: isLensActive(lens) ? .bold : .medium, design: .rounded))
                        .foregroundStyle(isLensActive(lens) ? .black : .white)
                        .frame(width: 52, height: 52)
                        .background(
                            Circle()
                                .fill(isLensActive(lens) ? Color.amber : .black.opacity(0.5))
                                .overlay(
                                    Circle()
                                        .stroke(isLensActive(lens) ? Color.clear : .white.opacity(0.3), lineWidth: 1)
                                )
                        )
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Bottom Controls - CLEAN
    @ViewBuilder
    private func bottomControls(safeAreaBottom: CGFloat) -> some View {
        VStack(spacing: 16) {
            // Main Shutter Row
            HStack(alignment: .center, spacing: 32) {
                // Thumbnail (Left)
                thumbnailView
                
                // Shutter Button (Center)
                ShutterButton(
                    isCapturing: camera.isCapturing,
                    timerCountdown: camera.timerCountdown,
                    timerTotal: camera.timerMode.rawValue
                ) { camera.capturePhoto() }
                
                // Flip Camera (Right)
                Button { camera.flipCamera() } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .padding(.horizontal, 40)
            
            // Process Strip - Bottom
            ProcessStrip(selected: camera.currentProcess) { camera.updateProcess($0) }
                .padding(.horizontal, 20)
            
            // Safe Area Spacer
            Spacer()
                .frame(height: max(safeAreaBottom, 8))
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - Thumbnail
    @ViewBuilder
    private var thumbnailView: some View {
        Group {
            if let img = camera.capturedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.15))
                    .overlay(Image(systemName: "photo").foregroundStyle(.white.opacity(0.4)))
            }
        }
        .frame(width: UIConstants.thumbnailSize, height: UIConstants.thumbnailSize)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.3), lineWidth: 1))
    }
    
    // MARK: - Helpers
    private func isLensActive(_ lens: LensItem) -> Bool {
        if lens.isDigitalZoom {
            return camera.currentLens == .builtInTelephotoCamera
        }
        return camera.currentLens == lens.type
    }
    
    private func selectLens(_ lens: LensItem) {
        if lens.isDigitalZoom {
            if camera.currentLens != .builtInTelephotoCamera {
                while camera.currentLens != .builtInTelephotoCamera {
                    camera.toggleLens()
                }
            }
            camera.setZoomFactor(5.0)
        } else if camera.currentLens != lens.type {
            while camera.currentLens != lens.type {
                camera.toggleLens()
            }
        }
    }
    
    @ViewBuilder
    private var modalOverlays: some View {
        if camera.permissionState == .denied {
            PermissionDeniedView()
        }
        
        if camera.showSavedBanner {
            VStack {
                Spacer()
                Label("SAVED", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.amber)
                    .clipShape(Capsule())
                    .padding(.bottom, 120)
            }
        }
        
        if showProcessPicker {
            ProcessPickerOverlay(
                selected: camera.currentProcess,
                isShowing: $showProcessPicker
            ) { camera.updateProcess($0) }
        }
    }
    
    private func focusGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { value in
                focusDot = value.location
                camera.focusAndExpose(at: value.location, in: size)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        focusDot = nil
                    }
                }
            }
    }
}

// MARK: - Control Button Component
struct ControlButton: View {
    let icon: String
    var badge: String? = nil
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                if let badge {
                    Text(badge)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                }
            }
            .foregroundStyle(isActive ? Color.amber : .white)
            .frame(width: 44, height: 44)
            .background(
                Circle()
                    .fill(.black.opacity(0.5))
                    .overlay(Circle().stroke(.white.opacity(isActive ? 0.4 : 0.2), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Lens Item
private struct LensItem: Identifiable {
    let id: Int
    let type: AVCaptureDevice.DeviceType
    let label: String
    var isDigitalZoom: Bool = false
}
