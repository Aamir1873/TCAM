//
//  Components.swift
//  TCAM - Refined UI Components
//

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
                    VStack(spacing: 2) {
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .semibold))
                        Text(label)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .textCase(.uppercase)
                    }
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .foregroundStyle(isOn ? Color.amber : .white)
            .frame(width: 42, height: 42)
            .background(
                Circle()
                    .fill(.black.opacity(0.45))
                    .overlay(Circle().stroke(.white.opacity(isOn ? 0.4 : 0.2), lineWidth: 1))
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isOn ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isOn)
    }
}

// MARK: - Focus Reticle
struct FocusReticle: View {
    let position: CGPoint
    @State private var scale: CGFloat = 1.3
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.amber.opacity(0.6), lineWidth: 1.5)
                .frame(width: 80, height: 80)
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.amber, lineWidth: 2)
                .frame(width: 60, height: 60)
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .position(position)
        .onAppear {
            withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                scale = 1.0
                opacity = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeOut(duration: 0.4)) {
                    opacity = 0
                }
            }
        }
    }
}

// MARK: - Exposure Slider
struct ExposureSlider: View {
    let bias: Float
    let onChange: (Float) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sun.min")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
            
            Slider(
                value: Binding(get: { Double(bias) }, set: { onChange(Float($0)) }),
                in: -3...3, step: 0.1
            )
            .tint(.amber)
            .frame(width: 180)
            
            Text(String(format: "%+.1f", bias))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.amber)
                .frame(width: 42, alignment: .trailing)
            
            Image(systemName: "sun.max")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.black.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.white.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

// MARK: - Process Strip
struct ProcessStrip: View {
    let selected: TechnicolorProcess
    let onSelect: (TechnicolorProcess) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TechnicolorProcess.allCases) { process in
                        Button {
                            withAnimation(.spring(duration: 0.2)) {
                                onSelect(process)
                            }
                        } label: {
                            Text(process.rawValue)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(selected == process ? .black : .white.opacity(0.85))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(selected == process ? Color.amber : .white.opacity(0.12))
                                        .overlay(
                                            Capsule()
                                                .stroke(selected == process ? Color.clear : .white.opacity(0.2), lineWidth: 1)
                                        )
                                )
                                .contentTransition(.numericText())
                        }
                        .buttonStyle(.plain)
                        .id(process.id)
                    }
                }
                .padding(.horizontal, 4)
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


    let action: () -> Void

    @State private var isPressed = false

   

    var body: some View {
        Button(action: action) {
            ZStack {
              
                Circle()
                    .stroke(.white.opacity(0.9), lineWidth: 2.5)
                    .frame(width: 82, height: 82)
                
                Circle()
                    .fill(isCapturing ? Color.amber : .white)
                    .frame(width: 68, height: 68)
                    .scaleEffect(isPressed ? 0.92 : 1.0)
                    .shadow(
                        color: isCapturing ? .amber.opacity(0.5) : .black.opacity(0.3),
                        radius: isPressed ? 4 : 8,
                        y: isPressed ? 2 : 4
                    )
               
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: isCapturing)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in
                    withAnimation(.spring(duration: 0.2)) { isPressed = false }
                }
        )
    }
}

// MARK: - Film Frame Overlay (Subtle)
struct FilmFrameOverlay: View {
    var body: some View {
        Canvas { context, size in
            let stripHeight: CGFloat = 24
            let stripColor = Color.black.opacity(0.4)
            let holeColor = Color.white.opacity(0.15)
            
            context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: stripHeight)), with: .color(stripColor))
            context.fill(Path(CGRect(x: 0, y: size.height - stripHeight, width: size.width, height: stripHeight)), with: .color(stripColor))
            
            let holeWidth: CGFloat = 10, holeHeight: CGFloat = 8, spacing: CGFloat = 32
            let count = Int(size.width / spacing) + 1
            let startX = (size.width - CGFloat(count - 1) * spacing) / 2
            
            for i in 0..<count {
                let x = startX + CGFloat(i) * spacing - holeWidth / 2
                context.fill(Path(roundedRect: CGRect(x: x, y: (stripHeight - holeHeight) / 2, width: holeWidth, height: holeHeight), cornerRadius: 2), with: .color(holeColor))
                context.fill(Path(roundedRect: CGRect(x: x, y: size.height - stripHeight + (stripHeight - holeHeight) / 2, width: holeWidth, height: holeHeight), cornerRadius: 2), with: .color(holeColor))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Grid Overlay
struct GridOverlay: View {
    var body: some View {
        Canvas { context, size in
            let lineColor = Color.white.opacity(0.25)
            let lineWidth: CGFloat = 0.75
            
            for i in 1...2 {
                let x = size.width * CGFloat(i) / 3
                let y = size.height * CGFloat(i) / 3
                
                context.stroke(Path { p in
                    p.move(to: .init(x: x, y: 0))
                    p.addLine(to: .init(x: x, y: size.height))
                }, with: .color(lineColor), lineWidth: lineWidth)
                
                context.stroke(Path { p in
                    p.move(to: .init(x: 0, y: y))
                    p.addLine(to: .init(x: size.width, y: y))
                }, with: .color(lineColor), lineWidth: lineWidth)
            }
        }
        .allowsHitTesting(false)
    }
}


// MARK: - Process Picker Overlay
struct ProcessPickerOverlay: View {
    let selected: TechnicolorProcess
    @Binding var isShowing: Bool
    let onSelect: (TechnicolorProcess) -> Void
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { withAnimation { isShowing = false } }
                .transition(.opacity)

            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(0.4))
                    .frame(width: 48, height: 4)
                    .padding(.top, 14)
                    .padding(.bottom, 20)
                
                Text("TECHNICOLOR PROCESS")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .textCase(.uppercase)
                    .padding(.bottom, 8)
                
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(TechnicolorProcess.allCases) { process in
                            ProcessRow(process: process, isSelected: selected == process) {
                                withAnimation(.spring(duration: 0.25)) {
                                    onSelect(process)
                                    isShowing = false
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Spacer().frame(height: 24)
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.black.opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(.white.opacity(0.15), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .offset(y: dragOffset)
            .gesture(
                DragGesture()
                    .updating($dragOffset) { val, state, _ in
                        state = max(0, val.translation.height)
                    }
                    .onEnded { val in
                        if val.translation.height > 100 || val.velocity.height > 800 {
                            withAnimation { isShowing = false }
                        }
                    }
            )
            .transition(.move(edge: .bottom))
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
