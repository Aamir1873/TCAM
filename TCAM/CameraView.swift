//
//  CameraView.swift
//  TCAM
//

import SwiftUI
import AVFoundation

// MARK: - Constants
private struct UIConstants {
    static let cornerRadius: CGFloat = 12
    static let buttonSize: CGFloat = 48
    static let shutterSize: CGFloat = 72
    static let thumbnailSize: CGFloat = 56
    static let controlSpacing: CGFloat = 16
    static let horizontalPadding: CGFloat = 20
    static let focusReticleDuration: CGFloat = 1.0
    static let focusReticleDelay: CGFloat = 0.6
}

// MARK: - CameraView
struct CameraView: View {
    @State private var camera = CameraManager()
    @Environment(\.scenePhase) private var scenePhase

    @State private var showProcessPicker = false
    @State private var focusDot: CGPoint? = nil
    @State private var showExposureSlider = false

    // Extracted lens options for reusability
    private var lensOptions: [LensItem] {
        [
            .init(id: 0, type: .builtInUltraWideCamera, label: "0.5x"),
            .init(id: 1, type: .builtInWideAngleCamera, label: "1x"),
            .init(id: 2, type: .builtInTelephotoCamera, label: "2x")
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

                // Overlays (all share same coordinate space)
                overlayViews

                // Controls Layer (respects safe area)
                controlsLayer(safeArea: safeArea)

                // Modal Overlays
                modalOverlays
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { camera.toggleLens() }
            .simultaneousGesture(focusGesture(in: size))
            .animation(.spring(duration: 0.35), value: camera.showSavedBanner)
            .animation(.spring(duration: 0.4), value: showProcessPicker)
            .animation(.easeInOut(duration: 0.25), value: showExposureSlider)
            .animation(.easeInOut(duration: 0.2), value: camera.showGrid)
            .sensoryFeedback(.success, trigger: camera.showSavedBanner)
            .onChange(of: scenePhase) { camera.handleScenePhase($1) }
            .task { await camera.requestPermissions() }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func cameraPreview(size: CGSize) -> some View {
        if let frame = camera.filteredFrame {
            Image(decorative: frame, scale: 1.0, orientation: .up)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
        }
    }

    @ViewBuilder
    private var overlayViews: some View {
        // Frame & Grid
        FilmFrameOverlay()
        if camera.showGrid {
            GridOverlay().transition(.opacity)
        }

        // Focus Reticle
        if let dot = focusDot {
            FocusReticle(position: dot)
                .transition(.opacity)
        }

        // Timer Countdown
        if let countdown = camera.timerCountdown {
            TimerCountdownOverlay(count: countdown) { camera.cancelTimer() }
        }
    }

    @ViewBuilder
    private func controlsLayer(safeArea: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            topBar(safeAreaTop: safeArea.top)

            if showExposureSlider {
                ExposureSlider(bias: camera.exposureBias) { camera.setExposureBias($0) }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer()
            bottomSection(safeAreaBottom: safeArea.bottom)  // ✅ Pass the value
                .padding(.bottom, 8)
        }
        .padding(.horizontal, UIConstants.horizontalPadding)
    }
    
    @ViewBuilder
    private func topBar(safeAreaTop: CGFloat) -> some View {
        HStack(spacing: 12) {
            processButton
            Spacer()
            topRightButtons
        }
        .padding(.top, max(safeAreaTop, 20))
        .padding(.bottom, 12)
    }

    private var processButton: some View {
        Button {
            withAnimation { showProcessPicker.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("TECHNICOLOR")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                Text(camera.currentProcess.rawValue)
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(.amber)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: UIConstants.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: UIConstants.cornerRadius)
                .stroke(Color.amber.opacity(0.3), lineWidth: 1))
        }
    }

    private var topRightButtons: some View {
        HStack(spacing: 16) {
            HUDIconButton(
                icon: camera.showGrid ? "grid.circle.fill" : "grid.circle",
                isOn: camera.showGrid
            ) { camera.showGrid.toggle() }

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
    }

    @ViewBuilder
    private func bottomSection(safeAreaBottom: CGFloat) -> some View {
        VStack(spacing: UIConstants.controlSpacing) {
            ProcessStrip(selected: camera.currentProcess) { camera.updateProcess($0) }
            lensSelector
            mainControlsRow
            // Safe area spacer for home indicator
            Color.clear.frame(height: max(safeAreaBottom, 16))
        }
    }

    private var lensSelector: some View {
        HStack(spacing: 24) {
            ForEach(lensOptions) { lens in
                Button {
                    if camera.currentLens != lens.type {
                        camera.toggleLens()
                    }
                } label: {
                    Text(lens.label)
                        .font(.system(size: 15, weight: camera.currentLens == lens.type ? .bold : .medium, design: .rounded))
                        .foregroundStyle(camera.currentLens == lens.type ? .yellow : .white)
                        .frame(width: UIConstants.buttonSize, height: UIConstants.buttonSize)
                        .background(
                            Circle()
                                .fill(camera.currentLens == lens.type ? Color.white.opacity(0.2) : Color.clear)
                        )
                }
            }
        }
    }

    private var mainControlsRow: some View {
        HStack(alignment: .center) {
            thumbnailView
                .frame(maxWidth: .infinity, alignment: .leading)

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
                    .background(.ultraThinMaterial, in: Circle())
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        Group {
            if let img = camera.capturedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: UIConstants.thumbnailSize, height: UIConstants.thumbnailSize)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(0.08))
                    .frame(width: UIConstants.thumbnailSize, height: UIConstants.thumbnailSize)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(.white.opacity(0.3), lineWidth: 1))
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(duration: 0.3), value: camera.capturedImage != nil)
    }

    @ViewBuilder
    private var modalOverlays: some View {
        // Permission Denied
        if camera.permissionState == .denied {
            PermissionDeniedView()
        }

        // Saved Banner
        if camera.showSavedBanner {
            VStack {
                Spacer()
                Label("SAVED TO CAMERA ROLL", systemImage: "checkmark")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color.amber)
                    .clipShape(Capsule())
                    .padding(.bottom, 140)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }

        // Process Picker
        if showProcessPicker {
            ProcessPickerOverlay(
                selected: camera.currentProcess,
                isShowing: $showProcessPicker
            ) { camera.updateProcess($0) }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func focusGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { value in
                let point = value.location
                focusDot = point
                camera.focusAndExpose(at: point, in: size)
                withAnimation(.easeOut(duration: UIConstants.focusReticleDuration)
                    .delay(UIConstants.focusReticleDelay)) {
                    focusDot = nil
                }
            }
    }
}

// MARK: - Helper Types
private struct LensItem: Identifiable {
    let id: Int
    let type: AVCaptureDevice.DeviceType
    let label: String
}
