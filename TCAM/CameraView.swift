//
//  CameraView.swift
//  TCAM
//

import SwiftUI
import AVFoundation

struct LensItem: Identifiable {
    let id: Int
    let type: AVCaptureDevice.DeviceType
    let label: String
    let baseZoomFactor: CGFloat
    let digitalMultiplier: CGFloat
    var isOptical: Bool { digitalMultiplier == 1.0 }
}

struct CameraView: View {
    @State private var camera: CameraManager = CameraManager()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showExposureSlider = false
    
    private let filters: [TechnicolorProcess] = [.native, .twoStrip, .monopack, .threeStrip]
    
    private let lensOptions: [LensItem] = [
        .init(id: 0, type: .builtInUltraWideCamera, label: "0.5", baseZoomFactor: 1.0, digitalMultiplier: 1.0),
        .init(id: 1, type: .builtInWideAngleCamera, label: "1", baseZoomFactor: 1.0, digitalMultiplier: 1.0),
        .init(id: 2, type: .builtInWideAngleCamera, label: "2", baseZoomFactor: 1.0, digitalMultiplier: 2.0),
        .init(id: 3, type: .builtInTelephotoCamera, label: "5", baseZoomFactor: 1.0, digitalMultiplier: 1.0),
        .init(id: 4, type: .builtInTelephotoCamera, label: "10", baseZoomFactor: 1.0, digitalMultiplier: 2.0)
    ]
    
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
                
                if showExposureSlider {
                    Color.black.opacity(0.01)
                        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { showExposureSlider = false } }
                }
                
                ControlPanel(
                    showExposure: $showExposureSlider,
                    camera: camera, // ✅ Passed as plain value for @Observable
                    filters: filters,
                    lensOptions: lensOptions
                )
                // ✅ Fixed: Explicit Edge.bottom to resolve inference error
                .padding(Edge.Set.bottom, 12)
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
    @Binding var showExposure: Bool
    // ✅ Fixed: Use 'let' for @Observable classes, not @ObservedObject
    let camera: CameraManager
    let filters: [TechnicolorProcess]
    let lensOptions: [LensItem]
    
    var body: some View {
        VStack(spacing: 12) {
            
            if showExposure {
                HStack(spacing: 12) {
                    Image(systemName: "sun.min").foregroundStyle(.white).font(.caption)
                    
                    // Assumes your existing ExposureSlider exists in another file
                    ExposureSlider(bias: camera.exposureBias) {
                        camera.setExposureBias($0)
                    }
                    .frame(maxWidth: 200)
                    
                    Image(systemName: "sun.max").foregroundStyle(.white).font(.caption)
                    
                    Button {
                        withAnimation { showExposure = false }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.7))
                            .font(.title3)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filters) { filter in
                        FilterButton(
                            title: filter.rawValue.replacingOccurrences(of: "-", with: " "),
                            isSelected: camera.currentProcess == filter
                        ) {
                            camera.updateProcess(filter)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            
            HStack(spacing: 0) {
                ForEach(lensOptions) { (lens: LensItem) in
                    Button {
                        selectLens(lens)
                    } label: {
                        Text(lens.label)
                            .font(.system(size: 13, weight: isLensActive(lens) ? .bold : .medium))
                            .foregroundStyle(isLensActive(lens) ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(isLensActive(lens) ? Color.amber : .black.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(.black.opacity(0.3))
            .clipShape(Capsule())
            .padding(.horizontal, 20)
            
            HStack(alignment: .center, spacing: 0) {
                ThumbnailView(capturedImage: camera.capturedImage)
                    .frame(width: 44)
                
                Spacer()
                
                // Assumes your existing ShutterButton exists in another file
                ShutterButton(isCapturing: camera.isCapturing) {
                    camera.capturePhoto()
                }
                
                Spacer()
                
                HStack(spacing: 16) {
                    Button {
                        camera.isFlashOn.toggle()
                    } label: {
                        Image(systemName: camera.isFlashOn ? "bolt.fill" : "bolt.slash")
                            .font(.title2)
                            .foregroundStyle(camera.isFlashOn ? .amber : .white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.5), in: Circle())
                    }
                    
                    Button {
                        withAnimation { showExposure.toggle() }
                    } label: {
                        Image(systemName: "sun.max")
                            .font(.title2)
                            .foregroundStyle(showExposure ? .amber : .white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.5), in: Circle())
                    }
                }
                .frame(width: 44 + 16 + 44 + 16)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
    }
    
    private func isLensActive(_ lens: LensItem) -> Bool {
        guard camera.currentLens == lens.type else { return false }
        let expectedZoom = lens.baseZoomFactor * lens.digitalMultiplier
        return abs(camera.currentZoomFactor - expectedZoom) < 0.15
    }
    
    private func selectLens(_ lens: LensItem) {
        if camera.currentLens != lens.type {
            while camera.currentLens != lens.type { camera.toggleLens() }
        }
        let target = lens.baseZoomFactor * lens.digitalMultiplier
        camera.setZoomFactor(target)
    }
}

// MARK: - Small Components
struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .monospaced))
                .foregroundStyle(isSelected ? .black : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.amber : .black.opacity(0.5))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct ThumbnailView: View {
    let capturedImage: UIImage?
    
    var body: some View {
        Group {
            if let img = capturedImage {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.15))
                    .overlay(Image(systemName: "photo").font(.system(size: 16)).foregroundStyle(.white.opacity(0.4)))
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.3), lineWidth: 1))
    }
}

// ✅ Removed duplicate ShutterButton & ExposureSlider definitions.
// Use the ones already in your project. If you need them, keep them in separate files.
