
//
//  LensIndicator.swift
//  TCAM
//

import SwiftUI
import AVFoundation

struct LensIndicator: View {
    let currentLens: AVCaptureDevice.DeviceType
    let action: () -> Void

    private var lensLabel: String {
        switch currentLens {
        case .builtInUltraWideCamera:
            return "0.5x"
        case .builtInWideAngleCamera:
            return "1x"
        case .builtInTelephotoCamera:
            return "2x"
        default:
            return "1x"
        }
    }

    private var lensIcon: String {
        switch currentLens {
        case .builtInUltraWideCamera:
            return "arrow.up.left.and.arrow.down.right"
        case .builtInWideAngleCamera:
            return "camera.fill"
        case .builtInTelephotoCamera:
            return "arrow.down.right.and.arrow.up.left"
        default:
            return "camera.fill"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: lensIcon)
                    .font(.system(size: 10, weight: .medium))
                Text(lensLabel)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.white.opacity(0.15))
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }
}
