//
//  Components.swift
//  TCAM
//
//  Reusable UI components:
//    HUDIconButton, FocusReticle, ExposureSlider, ProcessStrip,
//    ShutterButton, ZoomIndicator, FilmFrameOverlay, GridOverlay,
//    TimerCountdownOverlay, ProcessPickerOverlay, ProcessRow,
//    PermissionDeniedView

import SwiftUI

// MARK: - HUD Icon Button

struct HUDIconButton: View {
    let icon: String
    var label: String? = nil
    var isOn: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let label {
                    VStack(spacing: 1) {
                        Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                        Text(label).font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                } else {
                    Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                }
            }
            .foregroundStyle(isOn ? Color.amber : .white)
            .frame(width: 44, height: 44)
            .glassEffect(.regular.interactive(), in: Circle())
        }
    }
}

// MARK: - Focus Reticle

struct FocusReticle: View {
    let position: CGPoint
    @State private var scale: CGFloat = 1.4
    @State private var opacity: Double = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .stroke(Color.amber, lineWidth: 1.5)
            .frame(width: 70, height: 70)
            .scaleEffect(scale)
            .opacity(opacity)
            .position(position)
            .onAppear {
                withAnimation(.spring(duration: 0.25)) { scale = 1.0; opacity = 1.0 }
            }
    }
}

// MARK: - Exposure Slider

struct ExposureSlider: View {
    let bias: Float
    let onChange: (Float) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sun.min").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            Slider(
                value: Binding(get: { Double(bias) }, set: { onChange(Float($0)) }),
                in: -3...3, step: 0.1
            ).tint(.amber)
            Image(systemName: "sun.max").font(.system(size: 16)).foregroundStyle(.white.opacity(0.5))
            Text(String(format: "%+.1f", bias))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.amber)
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Process Strip

struct ProcessStrip: View {
    let selected: TechnicolorProcess
    let onSelect: (TechnicolorProcess) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(TechnicolorProcess.allCases) { process in
                        Button { onSelect(process) } label: {
                            Text(process.rawValue)
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .foregroundStyle(selected == process ? .black : .white)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(
                                    selected == process ? Color.amber : Color.white.opacity(0.12),
                                    in: Capsule()
                                )
                                .animation(.spring(duration: 0.25), value: selected)
                        }
                        .sensoryFeedback(.selection, trigger: selected == process)
                        .id(process.id)
                    }
                }
                .padding(.horizontal, 20)
            }
            .onChange(of: selected) { _, newValue in
                withAnimation { proxy.scrollTo(newValue.id, anchor: .center) }
            }
        }
    }
}

// MARK: - Shutter Button

struct ShutterButton: View {
    let isCapturing: Bool
    let timerCountdown: Int?
    let timerTotal: Int
    let action: () -> Void

    @State private var pressed = false

    private var timerProgress: Double {
        guard let c = timerCountdown, timerTotal > 0 else { return 0 }
        return Double(timerTotal - c) / Double(timerTotal)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if timerCountdown != nil {
                    Circle()
                        .stroke(Color.amber.opacity(0.25), lineWidth: 4)
                        .frame(width: 88, height: 88)
                    Circle()
                        .trim(from: 0, to: timerProgress)
                        .stroke(Color.amber, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 88, height: 88)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: timerProgress)
                }
                Circle().stroke(.white, lineWidth: 3).frame(width: 80, height: 80)
                Circle()
                    .fill(isCapturing ? Color.amber : .white)
                    .frame(width: 66, height: 66)
                    .scaleEffect(pressed ? 0.88 : 1.0)
                    .animation(.spring(duration: 0.18), value: pressed)
                if let c = timerCountdown, c > 0 {
                    Text("\(c)")
                        .font(.system(size: 22, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.amber)
                }
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: isCapturing)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded   { _ in pressed = false }
        )
    }
}

// MARK: - Zoom Indicator

struct ZoomIndicator: View {
    let zoom: CGFloat
    let onTap: () -> Void

    private var label: String {
        zoom < 1.05 ? "1×" :
        zoom < 2.05 ? String(format: "%.1f×", zoom) :
                      String(format: "%.0f×",  zoom)
    }

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .glassEffect(.regular.interactive(), in: Capsule())
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.2), value: zoom)
        }
    }
}

// MARK: - Film Frame Overlay

struct FilmFrameOverlay: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let sh: CGFloat = 28
            let strip   = Color.black.opacity(0.72)
            let hole    = Color.white.opacity(0.12)
            let bracket = Color.white.opacity(0.6)

            context.fill(Path(CGRect(x: 0, y: 0,      width: w, height: sh)), with: .color(strip))
            context.fill(Path(CGRect(x: 0, y: h - sh, width: w, height: sh)), with: .color(strip))

            let hW: CGFloat = 14, hH: CGFloat = 10, sp: CGFloat = 28
            let count  = Int(w / sp) + 1
            let startX = (w - CGFloat(count - 1) * sp) / 2
            for i in 0..<count {
                let x = startX + CGFloat(i) * sp - hW / 2
                context.fill(Path(roundedRect: CGRect(x: x, y: (sh - hH) / 2,          width: hW, height: hH), cornerRadius: 2), with: .color(hole))
                context.fill(Path(roundedRect: CGRect(x: x, y: h - sh + (sh - hH) / 2, width: hW, height: hH), cornerRadius: 2), with: .color(hole))
            }

            let bL: CGFloat = 28, bT: CGFloat = 2.5, m: CGFloat = sh + 10
            for (ox, oy, sx, sy) in [(14.0, m, 1.0, 1.0), (w - 14, m, -1.0, 1.0),
                                      (14.0, h - m, 1.0, -1.0), (w - 14, h - m, -1.0, -1.0)] {
                context.fill(Path(CGRect(x: ox, y: oy - (sy < 0 ? bT : 0), width: bL * sx, height: bT     )), with: .color(bracket))
                context.fill(Path(CGRect(x: ox, y: oy - (sy < 0 ? bL : 0), width: bT,      height: bL * sy)), with: .color(bracket))
            }
        }
    }
}

// MARK: - Grid Overlay (rule of thirds)

struct GridOverlay: View {
    var body: some View {
        Canvas { context, size in
            let line = Color.white.opacity(0.2)
            for i in 1...2 {
                let x = size.width  * CGFloat(i) / 3
                let y = size.height * CGFloat(i) / 3
                context.stroke(Path { p in p.move(to: .init(x: x, y: 0));          p.addLine(to: .init(x: x, y: size.height)) }, with: .color(line), lineWidth: 0.5)
                context.stroke(Path { p in p.move(to: .init(x: 0, y: y));          p.addLine(to: .init(x: size.width, y: y))  }, with: .color(line), lineWidth: 0.5)
            }
        }
    }
}

// MARK: - Timer Countdown Overlay

struct TimerCountdownOverlay: View {
    let count: Int
    let onCancel: () -> Void
    @State private var scale: CGFloat = 1.4

    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 24) {
                Text("\(count)")
                    .font(.system(size: 120, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.amber)
                    .scaleEffect(scale)
                    .onChange(of: count) { _, _ in
                        scale = 1.4
                        withAnimation(.spring(duration: 0.3)) { scale = 1.0 }
                    }
                    .onAppear { withAnimation(.spring(duration: 0.3)) { scale = 1.0 } }

                Button("CANCEL", action: onCancel)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .glassEffect(.regular.interactive(), in: Capsule())
            }
        }
    }
}

// MARK: - Process Picker Sheet

struct ProcessPickerOverlay: View {
    let selected: TechnicolorProcess
    @Binding var isShowing: Bool
    let onSelect: (TechnicolorProcess) -> Void
    @GestureState private var dragY: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { withAnimation { isShowing = false } }

            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(0.3))
                    .frame(width: 40, height: 4)
                    .padding(.top, 12).padding(.bottom, 20)
                Text("SELECT PROCESS")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.bottom, 16)
                ForEach(TechnicolorProcess.allCases) { process in
                    ProcessRow(process: process, isSelected: selected == process) {
                        withAnimation(.spring(duration: 0.25)) { onSelect(process); isShowing = false }
                    }
                }
                Spacer().frame(height: 40)
            }
            .frame(maxWidth: .infinity)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1))
            .padding(.horizontal, 12).padding(.bottom, 8)
            .offset(y: max(0, dragY))
            .gesture(
                DragGesture()
                    .updating($dragY) { v, s, _ in s = v.translation.height }
                    .onEnded { v in if v.translation.height > 80 { withAnimation { isShowing = false } } }
            )
        }
        .ignoresSafeArea()
    }
}

struct ProcessRow: View {
    let process: TechnicolorProcess
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(colors: process.swatchColors,
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(process.rawValue)
                        .font(.system(size: 14, weight: .black, design: .monospaced))
                        .foregroundStyle(isSelected ? Color.amber : .white)
                    Text(process.subtitle)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.amber)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(isSelected ? Color.white.opacity(0.06) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Permission Denied View

struct PermissionDeniedView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "camera.slash")
                    .font(.system(size: 52, weight: .thin))
                    .foregroundStyle(.white.opacity(0.4))
                Text("CAMERA ACCESS REQUIRED")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
                Text("Enable camera access in Settings\nto use Technicolor Camera.")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.black)
                .padding(.horizontal, 24).padding(.vertical, 12)
                .background(Color.amber).clipShape(Capsule())
            }
            .padding(.horizontal, 40)
        }
    }
}
