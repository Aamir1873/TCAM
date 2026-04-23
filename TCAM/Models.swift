//
//  Models.swift
//  TCAM
//

import SwiftUI

// MARK: - Technicolor Process

enum TechnicolorProcess: String, CaseIterable, Identifiable {
    case threeStrip = "THREE-STRIP"
    case twoStrip   = "TWO-STRIP"
    case monopack   = "MONOPACK"
    case vivid      = "HYPER-CHROME"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .threeStrip: "Classic 1930–50s Hollywood richness"
        case .twoStrip:   "Early 1920s amber & cyan duality"
        case .monopack:   "1950s Eastmancolor warmth"
        case .vivid:      "Pushed saturation fever dream"
        }
    }

    var swatchColors: [Color] {
        switch self {
        case .threeStrip: [Color(red: 0.95, green: 0.3,  blue: 0.15), Color(red: 0.15, green: 0.65, blue: 0.35)]
        case .twoStrip:   [Color(red: 0.95, green: 0.75, blue: 0.2),  Color(red: 0.1,  green: 0.6,  blue: 0.7)]
        case .monopack:   [Color(red: 0.95, green: 0.6,  blue: 0.25), Color(red: 0.7,  green: 0.35, blue: 0.15)]
        case .vivid:      [Color(red: 1.0,  green: 0.1,  blue: 0.5),  Color(red: 0.1,  green: 0.2,  blue: 1.0)]
        }
    }
}

// MARK: - Timer Mode

enum TimerMode: Int, CaseIterable, Identifiable {
    case off = 0, three = 3, ten = 10
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .off:   "OFF"
        case .three: "3s"
        case .ten:   "10s"
        }
    }

    /// Cycles to the next mode without force-unwrapping.
    var next: TimerMode {
        let all = TimerMode.allCases
        let idx = all.firstIndex(where: { $0 == self }) ?? 0
        return all[(idx + 1) % all.count]
    }
}
