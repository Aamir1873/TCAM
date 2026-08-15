//
//  CameraView.swift
//  TCAM — Dark Luxury / Cinematic UI
//  Optimized for iPhone 15 Pro Max (430×932pt, Dynamic Island)
//  ✅ UPDATED: Works with AspectRatio enum + orientation-aware cropping
//

import SwiftUI
import AVFoundation

// MARK: - Design Tokens
private enum DS {
    // Typography
    static let monoSm  = Font.system(size: 10, weight: .medium, design: .monospaced)
    static let monoMd  = Font.system(size: 12, weight: .medium, design: .monospaced)
    static let monoLg  = Font.system(size: 14, weight: .semibold, design: .monospaced)
    static let sansXs  = Font.system(size: 9,  weight: .medium)
    static let sansSm  = Font.system(size: 11, weight: .medium)
    static let sansMd  = Font.system(size: 13, weight: .semibold)

    // Palette
    static let gold        = Color(red: 0.92, green: 0.78, blue: 0.50)   // warm champagne gold
    static let goldDim     = Color(red: 0.92, green: 0.78, blue: 0.50).opacity(0.55)
    static let surface     = Color.white.opacity(0.06)
    static let surfaceHi   = Color.white.opacity(0.10)
    static let border      = Color.white.opacity(0.12)
    static let borderHi    = Color.white.opacity(0.22)
    static let textPrimary = Color.white
    static let textDim     = Color.white.opacity(0.45)
    static let textMute    = Color.white.opacity(0.25)
    static let scrim       = Color.black.opacity(0.55)

    // Layout (iPhone 15 Pro Max)
    static let controlBottomPad: CGFloat = 28
    static let hPad: CGFloat             = 22
    static let rowSpacing: CGFloat       = 12
    static let pillH: CGFloat            = 40
}

// MARK: - Glass Effect Modifiers
private extension View {
    @available(iOS 17.0, *)
    func glassCard(shape: GlassShape = .pill) -> some View {
        switch shape {
        case .pill:
            return AnyView(
                self
                    .glassEffect()
                    .clipShape(Capsule())
            )
        case .circle:
            return AnyView(
                self
                    .glassEffect()
                    .clipShape(Circle())
            )
        case .card:
            return AnyView(
                self
                    .glassEffect()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            )
        }
    }
}

enum GlassShape {
    case pill
    case circle
    case card
}

// MARK: - Main Camera View
struct CameraView: View {
    @State private var camera: CameraManager = CameraManager()
    @Environment(\.scenePhase) private var scenePhase

    @State private var wideZoomToggle: CGFloat  = 1.0
    @State private var teleZoomToggle: CGFloat  = 1.0
    @State private var pinchZoom: CGFloat       = 1.0
    @State private var lastPinchZoom: CGFloat   = 1.0
    @State private var zoomUpdateTask: Task<Void, Never>?
    
    // ✅ UPDATED: Use AspectRatio enum instead of raw CGFloat
    @State private var aspectRatio: CameraManager.AspectRatio = .standard

    // Animation states
    @State private var controlsVisible = false
    @State private var hudVisible      = false
    @State private var shutterFlash    = false
    @State private var isShowingPhotoPreview = false

    private let filters: [TechnicolorProcess]  = [.cinematic, .twoStrip, .monopack, .threeStrip]
    private let exposurePresets: [Float]        = [-1.0, 0.0, 1.0]

    var body: some View {
        ZStack {
            // ── Viewfinder ──────────────────────────────────────────────
            Color.black.ignoresSafeArea()

            ViewfinderImage(frame: camera.filteredFrame, aspectRatio: aspectRatio)
                .gesture(pinchGesture)

            // Shutter flash overlay
            Color.white
                .ignoresSafeArea()
                .opacity(shutterFlash ? 0.18 : 0)
                .animation(.easeOut(duration: 0.25), value: shutterFlash)
                .allowsHitTesting(false)

            // ── HUD: focal length chip ───────────────────────────────────
            VStack {
                HStack {
                    FocalLengthChip(label: focalLengthLabel)
                        .offset(y: hudVisible ? 0 : -12)
                        .opacity(hudVisible ? 1 : 0)
                    Spacer()
                    // ISO / shutter speed ghost info
                    ExposureInfoChip(
                        iso: camera.currentISO,
                        shutterSpeed: camera.currentShutterSpeed
                    )
                        .offset(y: hudVisible ? 0 : -12)
                        .opacity(hudVisible ? 1 : 0)
                }
                .padding(.horizontal, DS.hPad)
                .padding(.top, 62) // clears Dynamic Island
                Spacer()
            }

            // ── Control Panel ────────────────────────────────────────────
            VStack {
                Spacer()
                ControlPanel(
                    camera: camera,
                    filters: filters,
                    exposurePresets: exposurePresets,
                    wideZoomToggle: $wideZoomToggle,
                    teleZoomToggle: $teleZoomToggle,
                    aspectRatio: $aspectRatio,  // ✅ Now binds to AspectRatio enum
                    onCapture: triggerShutterFeedback
                )
                .offset(y: controlsVisible ? 0 : 60)
                .opacity(controlsVisible ? 1 : 0)
                .padding(.bottom, DS.controlBottomPad)
            }
        }
        .background(.black)
        // ✅ UPDATED: onChange now sets the enum directly
        .onChange(of: aspectRatio) { _, newValue in
            camera.setAspectRatio(newValue)
        }
        .onChange(of: scenePhase) { camera.handleScenePhase($1) }
        .animation(.easeInOut(duration: 0.3), value: aspectRatio)
        .task {
            await camera.requestPermissions()
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(0.1)) {
                controlsVisible = true
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.25)) {
                hudVisible = true
            }
        }
        .transaction { $0.animation = nil }
        .fullScreenCover(isPresented: $isShowingPhotoPreview) {
            if let image = camera.capturedImage {
                PhotoPreviewView(image: image) {
                    isShowingPhotoPreview = false
                }
            }
        }
    }

    // MARK: Helpers
    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoomUpdateTask?.cancel()
                zoomUpdateTask = Task {
                    try? await Task.sleep(nanoseconds: 16_000_000)
                    let clamped = max(0.5, min(10.0, lastPinchZoom * value))
                    await MainActor.run {
                        pinchZoom = clamped
                        updateZoomForCurrentLens(clamped)
                    }
                }
            }
            .onEnded { _ in lastPinchZoom = pinchZoom }
    }

    private func triggerShutterFeedback() {
        shutterFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { shutterFlash = false }
        camera.capturePhoto()
    }

    private var focalLengthLabel: String {
        let mm: Int; let label: String
        switch camera.activeLensType {
        case .builtInUltraWideCamera:
            mm = 13; label = "0.5×"
        case .builtInWideAngleCamera:
            mm = wideZoomToggle == 1.0 ? 24 : 48
            label = wideZoomToggle == 1.0 ? "1×" : "2×"
        case .builtInTelephotoCamera:
            mm = teleZoomToggle == 1.0 ? 120 : 240
            label = teleZoomToggle == 1.0 ? "5×" : "10×"
        default:
            mm = 24; label = "1×"
        }
        return "\(mm)mm  \(label)"
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
}

// MARK: - Viewfinder
private struct ViewfinderImage: View {
    let frame: CGImage?
    let aspectRatio: CameraManager.AspectRatio  // ✅ Now uses enum

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black

                if let frame {
                    Image(uiImage: UIImage(cgImage: frame))
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else {
                    ProgressView()
                        .tint(DS.gold)
                        .scaleEffect(1.4)
                }
            }
            .aspectRatio(displayAspectRatio, contentMode: .fit)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }

    // ✅ UPDATED: Calculate display aspect ratio using orientedRatio
    private var displayAspectRatio: CGFloat {
        // Use portrait as default for preview calculation
        // The actual crop ratio is handled by CameraManager with device orientation
        return 1.0 / aspectRatio.orientedRatio(for: .portrait)
    }
}

// MARK: - HUD Chips
private struct FocalLengthChip: View {
    let label: String
    var body: some View {
        Text(label)
            .font(DS.monoMd)
            .foregroundStyle(DS.gold)
            .tracking(1.5)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(DS.scrim)
            .overlay(Capsule().stroke(DS.gold.opacity(0.35), lineWidth: 0.75))
            .clipShape(Capsule())
    }
}

struct ExposureInfoChip: View {
    let iso: Float
    let shutterSpeed: Double   // raw seconds from AVFoundation
 
    private var shutterLabel: String {
        guard shutterSpeed > 0 else { return "—" }
        let denom = Int((1.0 / shutterSpeed).rounded())
        return denom >= 2 ? "1/\(denom)" : String(format: "%.1f\"", shutterSpeed)
    }
 
    private var isoLabel: String {
        iso > 0 ? "ISO \(Int(iso.rounded()))" : "ISO —"
    }
 
    var body: some View {
        HStack(spacing: 8) {
            Text(shutterLabel)
            Rectangle()
                .fill(Color.white.opacity(0.25))
                .frame(width: 0.5, height: 10)
            Text(isoLabel)
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(Color.white.opacity(0.45))
        .tracking(0.8)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.55))
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.75))
        .clipShape(Capsule())
        .contentTransition(.numericText())
        .animation(.easeInOut(duration: 0.2), value: shutterLabel)
        .animation(.easeInOut(duration: 0.2), value: isoLabel)
    }
}

// MARK: - Control Panel
private struct ControlPanel: View {
    var camera: CameraManager
    let filters: [TechnicolorProcess]
    let exposurePresets: [Float]
    @Binding var wideZoomToggle: CGFloat
    @Binding var teleZoomToggle: CGFloat
    @Binding var aspectRatio: CameraManager.AspectRatio  // ✅ Enum binding
    let onCapture: () -> Void

    var body: some View {
        VStack(spacing: DS.rowSpacing) {
            // ── Row 1: Exposure ─────────────────────────────────────────
            ExposureRow(presets: exposurePresets, camera: camera)

            // ── Row 2: Film Process filters ─────────────────────────────
            FilterRow(filters: filters, camera: camera)

            // ── Divider ─────────────────────────────────────────────────
            Rectangle()
                .fill(DS.border)
                .frame(height: 0.5)
                .padding(.horizontal, DS.hPad)
                .padding(.vertical, 2)

            // ── Row 3: Lens selector ─────────────────────────────────────
            LensRow(
                camera: camera,
                wideZoomToggle: $wideZoomToggle,
                teleZoomToggle: $teleZoomToggle
            )

            // ── Row 4: Shutter + Aspect Ratio ────────────────────────────
                ShutterRow(
                    camera: camera,
                    onCapture: onCapture,
                    onPreview: { isShowingPhotoPreview = true },
                    aspectRatio: $aspectRatio
                )
        }
        .padding(.horizontal, DS.hPad)
    }
}

// MARK: - Exposure Row
private struct ExposureRow: View {
    let presets: [Float]
    var camera: CameraManager

    var body: some View {
        HStack(spacing: 0) {
            ForEach(presets, id: \.self) { value in
                let isActive = abs(camera.exposureBias - value) < 0.05
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        camera.setExposureBias(value)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: value == 0 ? "circle" : (value > 0 ? "plus" : "minus"))
                            .font(.system(size: 9, weight: .medium))
                        Text(value == 0 ? "0 EV" : (value > 0 ? "1 EV" : "1 EV"))
                            .font(DS.monoSm)
                            .tracking(0.5)
                    }
                    .foregroundStyle(isActive ? DS.gold : DS.textDim)
                    .frame(maxWidth: .infinity)
                    .frame(height: DS.pillH)
                    .background(isActive ? DS.gold.opacity(0.12) : Color.clear)
                    .overlay(
                        Capsule()
                            .stroke(isActive ? DS.gold.opacity(0.45) : Color.clear, lineWidth: 0.75)
                    )
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(ScaleButtonStyle(scale: 0.94))
            }
        }
        .padding(4)
        .glassCard(shape: .pill)
    }
}
// MARK: - Filter Row (Liquid Glass / Apple Glass)
private struct FilterRow: View {
    let filters: [TechnicolorProcess]
    var camera: CameraManager

    var body: some View {
        HStack(spacing: 18) {
            ForEach(filters) { filter in
                let isSelected = camera.currentProcess == filter
                
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.18)) {
                        camera.updateProcess(filter)
                    }
                } label: {
                    // 🪞 Liquid Glass circle
                    ZStack {
                        // Base glass circle with frosted blur effect
                        Circle()
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(isSelected ? 0.35 : 0.18),
                                                Color.white.opacity(isSelected ? 0.12 : 0.06)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: isSelected ? 1.5 : 1.0
                                    )
                            )
                            .frame(width: 40, height: 40)
                            .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                        
                        // Subtle colored tint glow (filter identity)
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        glassTint(for: filter).opacity(isSelected ? 0.35 : 0.18),
                                        glassTint(for: filter).opacity(0)
                                    ],
                                    center: .center,
                                    startRadius: 8,
                                    endRadius: 28
                                )
                            )
                            .frame(width: 40, height: 40)
                        
                        // Soft inner sheen highlight (liquid reflection)
                        Circle()
                            .fill(
                                AngularGradient(
                                    gradient: Gradient(colors: [
                                        .white.opacity(0.12),
                                        .white.opacity(0.03),
                                        .clear
                                    ]),
                                    center: .center,
                                    startAngle: .degrees(-45),
                                    endAngle: .degrees(135)
                                )
                            )
                            .frame(width: 36, height: 36)
                        
                        // Minimal center dot (filter indicator)
                        Circle()
                            .fill(glassTint(for: filter).opacity(isSelected ? 0.9 : 0.65))
                            .frame(width: isSelected ? 14 : 12, height: isSelected ? 14 : 12)
                            .shadow(
                                color: glassTint(for: filter).opacity(isSelected ? 0.5 : 0.3),
                                radius: isSelected ? 4 : 2,
                                y: 1
                            )
                        
                        // Subtle animated ring pulse on selection
                        if isSelected {
                            Circle()
                                .stroke(glassTint(for: filter).opacity(0.45), lineWidth: 1)
                                .frame(width: 48, height: 48)
                                .scaleEffect(1.2)
                                .opacity(0)
                                .animation(
                                    .easeOut(duration: 0.6).repeatForever(autoreverses: false),
                                    value: isSelected
                                )
                        }
                    }
                    .scaleEffect(isSelected ? 1.06 : 1.0)
                    .animation(.easeOut(duration: 0.15), value: isSelected)
                    .glassEffect()  // ✅ Apple-style frosted blur
                }
                .buttonStyle(ScaleButtonStyle(scale: 0.94))
                .accessibilityLabel(filter.rawValue)
                .accessibilityAddTraits(isSelected ? .isSelected : .isButton)
            }
        }
        .padding(.vertical, 6)
    }

    // 🎨 Dark luxury glass tint colors (subtle, elegant)
    private func glassTint(for filter: TechnicolorProcess) -> Color {
        switch filter {
        case .cinematic:  return Color(red: 0.12, green: 0.38, blue: 0.78)    // deep sapphire blue
        case .twoStrip:   return Color(red: 0.82, green: 0.45, blue: 0.18)    // rich amber
        case .monopack:   return Color(red: 0.92, green: 0.78, blue: 0.22)    // warm golden yellow
        case .threeStrip: return Color(red: 0.95, green: 0.48, blue: 0.22)    // deep burnt orange
        }
    }
}
// MARK: - Lens Row
private struct LensRow: View {
    var camera: CameraManager
    @Binding var wideZoomToggle: CGFloat
    @Binding var teleZoomToggle: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            // 0.5×
            LensSegment(
                primary:   "0.5×",
                secondary: "13mm",
                isActive:  isLensActive(0.5)
            ) {
                camera.switchToLens(type: .builtInUltraWideCamera, avZoom: 0.5, logicalZoom: 0.5)
            }

            SegmentDivider()

            // 1× / 2×
            LensSegment(
                primary:   wideZoomToggle == 1.0 ? "1×" : "2×",
                secondary: wideZoomToggle == 1.0 ? "24mm" : "48mm",
                isActive:  isLensActive(wideZoomToggle)
            ) {
                camera.switchToLens(type: .builtInWideAngleCamera, avZoom: wideZoomToggle, logicalZoom: wideZoomToggle)
            }
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    wideZoomToggle = wideZoomToggle == 1.0 ? 2.0 : 1.0
                    camera.switchToLens(type: .builtInWideAngleCamera, avZoom: wideZoomToggle, logicalZoom: wideZoomToggle)
                }
            }

            SegmentDivider()

            // 5× / 10×
            LensSegment(
                primary:   teleZoomToggle == 1.0 ? "5×" : "10×",
                secondary: teleZoomToggle == 1.0 ? "120mm" : "240mm",
                isActive:  isLensActive(teleZoomToggle * 5.0)
            ) {
                camera.switchToLens(type: .builtInTelephotoCamera, avZoom: teleZoomToggle, logicalZoom: teleZoomToggle * 5.0)
            }
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    teleZoomToggle = teleZoomToggle == 1.0 ? 2.0 : 1.0
                    camera.switchToLens(type: .builtInTelephotoCamera, avZoom: teleZoomToggle, logicalZoom: teleZoomToggle * 5.0)
                }
            }
        }
        .frame(height: DS.pillH)
        .glassCard(shape: .pill)
    }

    private func isLensActive(_ logicalZoom: CGFloat) -> Bool {
        abs(camera.displayLogicalZoomFactor - logicalZoom) < 0.15
    }
}

private struct LensSegment: View {
    let primary:   String
    let secondary: String
    let isActive:  Bool
    let action:    () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(primary)
                    .font(DS.monoMd)
                    .foregroundStyle(isActive ? DS.gold : DS.textPrimary)
                    .fontWeight(isActive ? .semibold : .regular)
                Text(secondary)
                    .font(DS.sansXs)
                    .foregroundStyle(isActive ? DS.goldDim : DS.textMute)
                    .tracking(0.3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isActive ? DS.gold.opacity(0.13) : Color.clear)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.92))
    }
}

private struct SegmentDivider: View {
    var body: some View {
        Rectangle()
            .fill(DS.border)
            .frame(width: 0.5, height: 18)
    }
}

// MARK: - Shutter Row
private struct ShutterRow: View {
    var camera: CameraManager
    let onCapture: () -> Void
    let onPreview: () -> Void
    @Binding var aspectRatio: CameraManager.AspectRatio  // ✅ Enum binding

    var body: some View {
        HStack(alignment: .center) {
            // Thumbnail
            ThumbnailView(capturedImage: camera.capturedImage, onTap: onPreview)

            Spacer()

            // Shutter
            ShutterButton(isCapturing: camera.isCapturing, action: onCapture)

            Spacer()

            // Aspect Ratio Toggle + Flash
            HStack(spacing: 8) {
                // ✅ UPDATED: Cycle through AspectRatio enum cases
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        aspectRatio = aspectRatio.next
                    }
                } label: {
                    Text(aspectRatio.displayLabel)
                        .font(DS.monoSm)
                        .foregroundStyle(aspectRatio == .standard ? DS.textDim : DS.gold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(aspectRatio == .standard ? Color.clear : DS.scrim)
                        .overlay(Capsule().stroke(aspectRatio == .standard ? DS.border : DS.gold.opacity(0.35), lineWidth: 0.75))
                        .clipShape(Capsule())
                }
                .buttonStyle(ScaleButtonStyle(scale: 0.94))

                // Flash
                FlashButton(isOn: camera.isFlashOn) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        camera.isFlashOn.toggle()
                    }
                }
            }
        }
        .padding(.top, 6)
    }
}

// MARK: - Shutter Button
struct ShutterButton: View {
    let isCapturing: Bool
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer ring — gold when capturing
                Circle()
                    .stroke(
                        isCapturing ? DS.gold : DS.borderHi,
                        lineWidth: 1.5
                    )
                    .frame(width: 84, height: 84)
                    .scaleEffect(isCapturing ? 1.06 : 1.0)
                    .animation(.easeInOut(duration: 0.25), value: isCapturing)

                // Second decorative ring
                Circle()
                    .stroke(DS.gold.opacity(0.18), lineWidth: 0.5)
                    .frame(width: 76, height: 76)

                // Fill
                Circle()
                    .fill(shutterFill)
                    .frame(width: 64, height: 64)
                    .scaleEffect(isPressed ? 0.90 : 1.0)
                    .shadow(
                        color: isCapturing ? DS.gold.opacity(0.35) : .clear,
                        radius: 14,
                        y: 0
                    )
                    .animation(.easeOut(duration: 0.2), value: isCapturing)

                // Inner glint
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                    .frame(width: 58, height: 58)
                    .scaleEffect(isPressed ? 0.90 : 1.0)
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeOut(duration: 0.08)) { isPressed = true }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isPressed = false }
                }
        )
    }

    private var shutterFill: some ShapeStyle {
        if isCapturing {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [DS.gold, DS.gold.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.white, Color.white.opacity(0.88)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
}

// MARK: - Flash Button
private struct FlashButton: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .glassCard(shape: .circle)
                    .frame(width: 48, height: 48)
                Image(systemName: isOn ? "bolt.fill" : "bolt.slash")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isOn ? DS.gold : DS.textDim)
            }
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.92))
        .padding(.trailing, 6)
    }
}

// MARK: - Thumbnail View
struct ThumbnailView: View {
    let capturedImage: UIImage?
    let onTap: () -> Void

    var body: some View {
        ZStack {
            if let img = capturedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .glassCard(shape: .card)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 15))
                            .foregroundStyle(DS.textMute)
                    )
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(DS.border, lineWidth: 0.75))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
        .padding(.leading, 6)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            guard capturedImage != nil else { return }
            onTap()
        }
        .accessibilityLabel(capturedImage == nil ? "No captured photo" : "View captured photo")
        .accessibilityAddTraits(capturedImage == nil ? [] : .isButton)
    }
}

private struct PhotoPreviewView: View {
    let image: UIImage
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .ignoresSafeArea(edges: .horizontal)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(ScaleButtonStyle(scale: 0.9))
            .padding(.top, 18)
            .padding(.trailing, 18)
            .accessibilityLabel("Close photo preview")
        }
        .statusBarHidden(true)
    }
}

// MARK: - Scale Button Style
struct ScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - AspectRatio UI Extensions
// ✅ Helper extensions for AspectRatio enum in UI
private extension CameraManager.AspectRatio {
    /// User-friendly display label for the toggle button
    var displayLabel: String {
        switch self {
        case .standard:   return "4:3"
        case .widescreen: return "16:9"
        case .cinematic:  return "2.39:1"
        }
    }
    
    /// Cycle to next aspect ratio in the sequence
    var next: CameraManager.AspectRatio {
        let all = CameraManager.AspectRatio.allCases
        guard let idx = all.firstIndex(of: self) else { return .standard }
        return all[(idx + 1) % all.count]
    }
}
