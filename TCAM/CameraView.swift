//
//  CameraView.swift
//  TCAM - Smooth UI Updates
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
                ControlPanel(camera: camera, filters: filters, lensOptions: lensOptions)
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

private struct ControlPanel: View {
    @Bindable var camera: CameraManager
    let filters: [TechnicolorProcess]
    let lensOptions: [LensItem]
    
    var body: some View {
        VStack(spacing: 14) {
            // Permanent Exposure Slider
            HStack(spacing: 10) {
                Image(systemName: "sun.min").foregroundStyle(.white.opacity(0.6)).font(.caption)
                ExposureSlider(bias: camera.exposureBias) { camera.setExposureBias($0) }.frame(maxWidth: 220)
                Image(systemName: "sun.max").foregroundStyle(.white.opacity(0.6)).font(.caption)
            }
            .padding(.vertical, 4)
            
            // ✅ Smooth Filter Toggle
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filters) { filter in
                        FilterButton(title: filter.rawValue.replacingOccurrences(of: "-", with: " "),
                                     isSelected: camera.currentProcess == filter) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                camera.updateProcess(filter)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            
            // ✅ Smooth Lens Toggle
            HStack(spacing: 0) {
                ForEach(lensOptions) { (lens: LensItem) in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            camera.switchToLens(type: lens.type, zoom: lens.baseZoomFactor * lens.digitalMultiplier)
                        }
                    } label: {
                        Text(lens.label)
                            .font(.system(size: 13, weight: camera.currentLens == lens.type && abs(camera.currentZoomFactor - (lens.baseZoomFactor * lens.digitalMultiplier)) < 0.15 ? .bold : .medium))
                            .foregroundStyle(camera.currentLens == lens.type && abs(camera.currentZoomFactor - (lens.baseZoomFactor * lens.digitalMultiplier)) < 0.15 ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(camera.currentLens == lens.type && abs(camera.currentZoomFactor - (lens.baseZoomFactor * lens.digitalMultiplier)) < 0.15 ? Color.amber : .black.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(.black.opacity(0.3))
            .clipShape(Capsule())
            .padding(.horizontal, 20)
            
            // Shutter Row
            HStack(alignment: .center, spacing: 0) {
                ThumbnailView(capturedImage: camera.capturedImage).frame(width: 44)
                Spacer()
                ShutterButton(isCapturing: camera.isCapturing) { camera.capturePhoto() }
                Spacer()
                Button {
                    camera.isFlashOn.toggle()
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
}

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
            if let img = capturedImage { Image(uiImage: img).resizable().scaledToFill() }
            else { RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.15)).overlay(Image(systemName: "photo").font(.system(size: 16)).foregroundStyle(.white.opacity(0.4))) }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.3), lineWidth: 1))
    }
}