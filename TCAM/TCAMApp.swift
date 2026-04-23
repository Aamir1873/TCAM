//
//  TCAMApp.swift
//  TCAM
//
//  Created by Aamir Abdul Kader on 23/04/2026.
//
//  Deployment target: iOS 26.0+
//  Info.plist keys required:
//    NSCameraUsageDescription
//    NSPhotoLibraryAddUsageDescription

import SwiftUI

// MARK: - Amber accent (single source of truth)

extension ShapeStyle where Self == Color {
    static var amber: Color { Color(red: 1.0, green: 0.85, blue: 0.2) }
}

// MARK: - App Entry Point

@main
struct TechnicolorCameraApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

struct ContentView: View {
    var body: some View {
        CameraView().ignoresSafeArea()
    }
}
