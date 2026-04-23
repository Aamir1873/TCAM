//
//  CameraView.swift
//  TCAM - Double-Tap Lens Toggles (Fixed Zoom Mapping)
//

import SwiftUI
import AVFoundation

struct CameraView: View {
    @State private var camera: CameraManager = CameraManager()
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var wideZoomToggle: CGFloat = 1.0 // 1.0 ↔ 2.0
    @State private var teleZoomToggle: CGFloat = 1.0 // 1.0 ↔ 2.0
    
    private let filters: [TechnicolorProcess] = [.native, .twoStrip, .monopack, .threeStrip]
    private let exposurePresets: [Float] = [-1.0, 0.0, 1.0]
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            GeometryReader { geo in
                ImageOrPlaceholder(frame: camera.filteredFrame)
                    .aspectRatio(4.0/3.0, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            .ignoresSafeArea()
            
            VStack {
                Spacer()
                ControlPanel(
                    camera: camera,
                    filters: filters,
                    exposurePresets: exposurePresets,
                    wideZoomToggle: $wideZoomToggle,
                    teleZoomToggle: $teleZoomToggle
                )
                .padding(.bottom, 12)
            }
        }
        .background(.black)
        .sensoryFeedback(.success, trigger: camera.showSavedBanner)
        .onChange(of: scenePhase) { camera.handleScenePhase($1) }
        .task { await camera.requestPermissions() }
    }
    
    @ViewBuilder
    private func ImageOrPlaceholder(frame: CGImage?) -> some View {
        if let frame = frame {
            Image(decorative: frame, scale: 1.0, orientation: .up)
                .resizable().aspectRatio(contentMode: .fill)
        } else {
            ProgressView().tint(.amber).scaleEffect(1.5)
        }
    }
}

// MARK: - Control Panel
private struct ControlPanel: View {
    @Bindable var camera: CameraManager
    let filters: [TechnicolorProcess]
    let exposurePresets: [Float]
    @Binding var wideZoomToggle: CGFloat
    @Binding var teleZoomToggle: CGFloat
    
    var body: some View {
        VStack(spacing: 10) {
            
            // 1️⃣ Exposure Toggle (-1 | 0 | +1)
            HStack(spacing: 0) {
                ForEach(exposurePresets, id: \.self) { value in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            camera.setExposureBias(value)
                        }
                    } label: {
                        Text(value == 0 ? "0" : (value > 0 ? "+1" : "-1"))
                            .font(.system(size: 13, weight: isActiveExposure(value) ? .bold : .medium))
                            .foregroundStyle(isActiveExposure(value) ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(isActiveExposure(value) ? Color.amber : .black.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(.black.opacity(0.3))
            .clipShape(Capsule())
            .padding(.horizontal, 20)
            
            // 2️⃣ Filter Toggles
            HStack(spacing: 6) {
                ForEach(filters) { filter in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            camera.updateProcess(filter)
                        }
                    } label: {
                        Text(filter.rawValue.replacingOccurrences(of: "-", with: " "))
                            .font(.system(size: 10, weight: camera.currentProcess == filter ? .bold : .medium, design: .monospaced))
                            .foregroundStyle(camera.currentProcess == filter ? .black : .white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(camera.currentProcess == filter ? Color.amber : .black.opacity(0.5))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            
            // 3️⃣ Lens Toggles (0.5 | 1↔2 | 5↔10)
            HStack(spacing: 0) {
                // 0.5x Ultra Wide
                lensButton(label: "0.5", type: .builtInUltraWideCamera, avZoom: 0.5, logicalZoom: 0.5)
                
                // 1x ↔ 2x Wide
                lensButton(label: wideZoomToggle == 1.0 ? "1" : "2", type: .builtInWideAngleCamera, avZoom: wideZoomToggle, logicalZoom: wideZoomToggle)
                    .onTapGesture(count: 2) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            wideZoomToggle = wideZoomToggle == 1.0 ? 2.0 : 1.0
                            camera.switchToLens(type: .builtInWideAngleCamera, avZoom: wideZoomToggle, logicalZoom: wideZoomToggle)
                        }
                    }
                
                // 5x ↔ 10x Telephoto
                // AVFoundation: 1.0 = optical tele, 2.0 = 2x crop on tele
                // Logical: 5.0 = 5x equiv, 10.0 = 10x equiv
                lensButton(label: teleZoomToggle == 1.0 ? "5" : "10", type: .builtInTelephotoCamera, avZoom: teleZoomToggle, logicalZoom: teleZoomToggle * 5.0)
                    .onTapGesture(count: 2) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            teleZoomToggle = teleZoomToggle == 1.0 ? 2.0 : 1.0
                            camera.switchToLens(type: .builtInTelephotoCamera, avZoom: teleZoomToggle, logicalZoom: teleZoomToggle * 5.0)
                        }
                    }
            }
            .background(.black.opacity(0.3))
            .clipShape(Capsule())
            .padding(.horizontal, 20)
            
            // 4️⃣ Shutter Row
            HStack(alignment: .center, spacing: 0) {
                ThumbnailView(capturedImage: camera.capturedImage).frame(width: 44)
                Spacer()
                ShutterButton(isCapturing: camera.isCapturing) { camera.capturePhoto() }
                Spacer()
                Button {
                    withAnimation { camera.isFlashOn.toggle() }
                } label: {
                    Image(systemName: camera.isFlashOn ? "bolt.fill" : "bolt.slash")
                        .font(.title2)
                        .foregroundStyle(camera.isFlashOn ? .amber : .white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.5), in: Circle())
                }
                .padding(.trailing, 24)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 4)
        }
    }
    
    @ViewBuilder
    private func lensButton(label: String, type: AVCaptureDevice.DeviceType, avZoom: CGFloat, logicalZoom: CGFloat) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                camera.switchToLens(type: type, avZoom: avZoom, logicalZoom: logicalZoom)
            }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: isLensActive(logicalZoom) ? .bold : .medium))
                .foregroundStyle(isLensActive(logicalZoom) ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isLensActive(logicalZoom) ? Color.amber : .black.opacity(0.5))
        }
        .buttonStyle(.plain)
    }
    
    private func isActiveExposure(_ value: Float) -> Bool {
        abs(camera.exposureBias - value) < 0.05
    }
    
    private func isLensActive(_ logicalZoom: CGFloat) -> Bool {
        abs(camera.logicalZoomFactor - logicalZoom) < 0.15
    }
}

// MARK: - Small Components
struct ThumbnailView: View {
    let capturedImage: UIImage?
    var body: some View {
        Group {
            if let img = capturedImage { Image(uiImage: img).resizable().scaledToFill() }
            else { RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.15)).overlay(Image(systemName: "photo").font(.system(size: 16)).foregroundStyle(.white.opacity(0.4))) }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.3), lineWidth: 1))
    }
}
