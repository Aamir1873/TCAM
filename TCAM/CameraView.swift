//
//  CameraView.swift
//  TCAM
//

import SwiftUI

struct CameraView: View {
    @State private var camera = CameraManager()
    @Environment(\.scenePhase) private var scenePhase

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
        .sensoryFeedback(.success, trigger: camera.showSavedBanner)
        .animation(.spring(duration: 0.35),    value: camera.showSavedBanner)
        .animation(.spring(duration: 0.4),     value: showProcessPicker)
        .animation(.easeInOut(duration: 0.25), value: showExposureSlider)
        .animation(.easeInOut(duration: 0.2),  value: camera.showGrid)
        .onChange(of: scenePhase) { camera.handleScenePhase($1) }
        .task { await camera.requestPermissions() }
    }

    // MARK: - Top HUD

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
        .padding(.horizontal, 20)
        .padding(.top, 60)
    }

    // MARK: - Bottom Controls

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
}
