//
//  CameraView.swift
//  TCAM - Fixed Layout & Filters
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
    
    // Removed showExposureSlider state - slider is now permanent
    
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
            
            // 4:3 Preview Box
            GeometryReader { geo in
                ImageOrPlaceholder(frame: camera.filteredFrame)
                    .aspectRatio(4.0/3.0, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            .ignoresSafeArea()
            
            VStack {
                Spacer()
                
                // Control Panel (Pushed Up slightly by geometry or padding)
                ControlPanel(
                    camera: camera, 
                    filters: filters, 
                    lensOptions: lensOptions
                )
                .padding(.bottom, 8)
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
    // ✅ Fix: Use @Bindable for @Observable classes in subviews to ensure visual updates
    @Bindable var camera: CameraManager
    let filters: [TechnicolorProcess]
    let lensOptions: [LensItem]
    
    var body: some View {
        VStack(spacing: 14) {
            
            // ✅ Permanent Exposure Slider (Always visible)
            HStack(spacing: 10) {
                Image(systemName: "sun.min").foregroundStyle(.white.opacity(0.6)).font(.caption)
                
                ExposureSlider(bias: camera.exposureBias) { 
                    camera.setExposureBias($0) 
                }
                .frame(maxWidth: 220)
                
                Image(systemName: "sun.max").foregroundStyle(.white.opacity(0.6)).font(.caption)
            }
            .padding(.vertical, 4)
            
            // Filter Selector (Fixed Visual Highlighting)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filters) { filter in
                        FilterButton(
                            title: filter.rawValue.replacingOccurrences(of: "-", with: " "),
                            isSelected: camera.currentProcess == filter // ✅ Now updates correctly
                        ) {
                            camera.updateProcess(filter)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            
            // Lens Selector
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
            
            // Shutter Row
            HStack(alignment: .center, spacing: 0) {
                ThumbnailView(capturedImage: camera.capturedImage)
                    .frame(width: 44)
                
                Spacer()
                
                ShutterButton(isCapturing: camera.isCapturing) {
                    camera.capturePhoto()
                }
                
                Spacer()
                
                // Flash Button
                Button {
                    camera.isFlashOn.toggle()
                } label: {
                    Image(systemName: camera.isFlashOn ? "bolt.fill" : "bolt.slash")
                        .font(.title2)
                        .foregroundStyle(camera.isFlashOn ? .amber : .white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.5), in: Circle())
                }
                .padding(.trailing, 24) // Align with thumbnail padding
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 4)
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