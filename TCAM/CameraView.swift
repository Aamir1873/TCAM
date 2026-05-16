//
//  CameraView.swift
//  TCAM — Dark Luxury / Cinematic UI
//  Optimized for iPhone 15 Pro Max (430×932pt, Dynamic Island)
//  ✅ FIXED: glassEffect recursion bug → renamed to glassCard
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

// MARK: - Glass Effect Modifiers (✅ FIXED: renamed to avoid recursion)
private extension View {
    @available(iOS 17.0, *)
    func glassCard(shape: GlassShape = .pill) -> some View {
        switch shape {
        case .pill:
            return AnyView(
                self
                    .glassEffect()  // ✅ Now correctly calls SwiftUI's built-in modifier
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
    @State private var aspectRatio: CGFloat     = 4.0 / 3.0  // Default to 4:3 standard (can toggle to 16:9 cinematic)

    // Animation states
    @State private var controlsVisible = false
    @State private var hudVisible      = false
    @State private var shutterFlash    = false

    private let filters: [TechnicolorProcess]  = [.cinematic, .twoStrip, .monopack, .threeStrip]
    private let exposurePresets: [Float]        = [-1.0, 0.0, 1.0]

    var body: some View {
        ZStack {
            // ── Viewfinder ──────────────────────────────────────────────
            Color.black.ignoresSafeArea()

            ImageOrPlaceholder(frame: camera.filteredFrame)
                .aspectRatio(contentMode: aspectRatio == 16.0 / 9.0 ? .fit : .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .gesture(pinchGesture)

            // Shutter flash overlay
            Color.white
                .ignoresSafeArea()
                .opacity(shutterFlash ? 0.18 : 0)
                .animation(.easeOut(duration: 0.25), value: shutterFlash)
                .allowsHitTesting(false)

            // ── Cinematic letterbox bars (only for 16:9) ─────────────────────────────────
            if aspectRatio == 16.0 / 9.0 {
                VStack(spacing: 0) {
                    LetterboxBar(edge: .top)
                        .frame(maxWidth: .infinity)
                    Spacer(minLength: 0)
                    LetterboxBar(edge: .bottom)
                        .frame(maxWidth: .infinity)
                }
                .ignoresSafeArea(edges: [.horizontal])
                .allowsHitTesting(false)
                .transition(.opacity)
            }

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
                    aspectRatio: $aspectRatio,
                    onCapture: triggerShutterFeedback
                )
                .offset(y: controlsVisible ? 0 : 60)
                .opacity(controlsVisible ? 1 : 0)
                .padding(.bottom, DS.controlBottomPad)
            }
        }
        .background(.black)
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

    @ViewBuilder
    private func ImageOrPlaceholder(frame: CGImage?) -> some View {
        if let frame {
            Image(uiImage: UIImage(cgImage: frame))
        } else {
            ProgressView()
                .tint(DS.gold)
                .scaleEffect(1.4)
        }
    }
}

// MARK: - Letterbox Bar
private struct LetterboxBar: View {
    enum Edge { case top, bottom }
    let edge: Edge

    var body: some View {
        LinearGradient(
            colors: edge == .top
                ? [.black, .black.opacity(0.6), .clear]
                : [.clear, .black.opacity(0.65), .black],
            startPoint: edge == .top ? .top : .bottom,
            endPoint:   edge == .top ? .bottom : .top
        )
        .frame(height: edge == .top ? 130 : 200)
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
        // Fast shutter: show as fraction. Slow shutter (≥1s): show with ″ symbol
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
    @Binding var aspectRatio: CGFloat
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
            ShutterRow(camera: camera, onCapture: onCapture, aspectRatio: $aspectRatio)
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
        .glassCard(shape: .pill)  // ✅ FIXED: renamed from glassEffect
    }
}

// MARK: - Filter Row
private struct FilterRow: View {
    let filters: [TechnicolorProcess]
    var camera: CameraManager

    var body: some View {
        HStack(spacing: 6) {
            ForEach(filters) { filter in
                let isSelected = camera.currentProcess == filter
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        camera.updateProcess(filter)
                    }
                } label: {
                    VStack(spacing: 3) {
                        // Color swatch dot
                        Circle()
                            .fill(swatchColor(for: filter))
                            .frame(width: 5, height: 5)
                            .opacity(isSelected ? 1 : 0.4)

                        Text(filter.rawValue.replacingOccurrences(of: "-", with: " ").uppercased())
                            .font(DS.sansXs)
                            .tracking(1.2)
                            .foregroundStyle(isSelected ? DS.gold : DS.textDim)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(isSelected ? DS.gold.opacity(0.10) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? DS.gold.opacity(0.45) : DS.border, lineWidth: 0.75)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(ScaleButtonStyle(scale: 0.93))
            }
        }
    }

    private func swatchColor(for filter: TechnicolorProcess) -> Color {
        switch filter {
        case .cinematic: return Color(red: 0.4, green: 0.7, blue: 0.9)      // cool cyan-blue
        case .twoStrip:  return Color(red: 0.85, green: 0.50, blue: 0.40)  // warm red
        case .monopack:  return Color(red: 0.70, green: 0.70, blue: 0.70)  // silver
        case .threeStrip:return Color(red: 0.45, green: 0.72, blue: 0.58)  // teal-green
        default:         return Color.white.opacity(0.4)
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
        .glassCard(shape: .pill)  // ✅ FIXED: renamed from glassEffect
    }

    private func isLensActive(_ logicalZoom: CGFloat) -> Bool {
        abs(camera.logicalZoomFactor - logicalZoom) < 0.15
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
    @Binding var aspectRatio: CGFloat

    var body: some View {
        HStack(alignment: .center) {
            // Thumbnail
            ThumbnailView(capturedImage: camera.capturedImage)

            Spacer()

            // Shutter
            ShutterButton(isCapturing: camera.isCapturing, action: onCapture)

            Spacer()

            // Aspect Ratio Toggle + Flash
            HStack(spacing: 8) {
                // Aspect Ratio Toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        aspectRatio = aspectRatio == 16.0 / 9.0 ? 4.0 / 3.0 : 16.0 / 9.0
                    }
                } label: {
                    Text(aspectRatio == 16.0 / 9.0 ? "16:9" : "4:3")
                        .font(DS.monoSm)
                        .foregroundStyle(aspectRatio == 16.0 / 9.0 ? DS.gold : DS.textDim)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(aspectRatio == 16.0 / 9.0 ? DS.scrim : Color.clear)
                        .overlay(Capsule().stroke(aspectRatio == 16.0 / 9.0 ? DS.gold.opacity(0.35) : DS.border, lineWidth: 0.75))
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
                    .glassCard(shape: .circle)  // ✅ FIXED: renamed from glassEffect
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

    var body: some View {
        ZStack {
            if let img = capturedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .glassCard(shape: .card)  // ✅ FIXED: renamed from glassEffect
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
