//
//  PhotoWatermarker.swift
//  TCAM - Premium Specs Watermark
//

import UIKit
import AVFoundation

final class PhotoWatermarker {
    private static let maxRenderWidth: CGFloat = 3840

    static func apply(to image: UIImage, metadata: [String: Any], isEnabled: Bool) -> UIImage {
        guard isEnabled else { return image }

        let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]

        // ISO
        let isoArray = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int] ?? []
        let isoString = isoArray.first.map { "ISO \($0)" } ?? ""

        // Shutter Speed
        let exposureTime = exif[kCGImagePropertyExifExposureTime as String] as? Double ?? 0
        let shutterString = exposureTime > 0 ? formatShutter(exposureTime) : ""

        // Map physical focal length to 35mm equivalent
        let focalRaw = exif[kCGImagePropertyExifFocalLength as String] as? Double ?? 0
        let focalString = formatFocalLength(focalRaw)

        // Aperture
        let fNumber = exif[kCGImagePropertyExifFNumber as String] as? Double ?? 0
        let fString = fNumber > 0 ? String(format: "ƒ/%.1f", fNumber) : ""

        // Build clean specs string
        var specs = [String]()
        if !focalString.isEmpty { specs.append(focalString) }
        if !fString.isEmpty { specs.append(fString) }
        if !shutterString.isEmpty { specs.append(shutterString) }
        if !isoString.isEmpty { specs.append(isoString) }
        let specsLine = specs.joined(separator: "   ") // Wider spacing for premium look

        return render(on: image, specs: specsLine)
    }

    private static func formatShutter(_ seconds: Double) -> String {
        if seconds >= 1 { return String(format: "%.1fs", seconds) }
        return "1/\(Int(round(1.0 / seconds)))s"
    }

    private static func formatFocalLength(_ physicalMM: Double) -> String {
        guard physicalMM > 0 else { return "" }
        switch physicalMM {
        case ..<2.0: return "13mm"
        case 2.0..<3.0: return "15mm"
        case 3.0..<5.0: return "19mm"
        case 5.0..<7.5: return "24mm"
        case 7.5..<8.5: return "26mm"
        case 8.5..<11.0: return "28mm"
        case 11.0..<13.5: return "52mm"
        case 13.5..<15.0: return "77mm"
        case 15.0..<18.0: return "85mm"
        case 18.0..<22.0: return "120mm"
        case 22.0...: return "135mm"
        default: return String(format: "%.0fmm", physicalMM)
        }
    }

    private static func render(on image: UIImage, specs: String) -> UIImage {
        let originalWidth = image.size.width
        let renderWidth = min(originalWidth, maxRenderWidth)
        let aspectRatio = image.size.height / originalWidth
        let renderHeight = renderWidth * aspectRatio
        
        // ✅ Bigger white footer
        let footerHeight: CGFloat = 320
        let totalHeight = renderHeight + footerHeight

        // Memory-safe renderer
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: renderWidth, height: totalHeight),
                                               format: .init(for: .init(displayScale: 1.0)))

        return renderer.image { ctx in
            // Draw original image
            image.draw(in: CGRect(x: 0, y: 0, width: renderWidth, height: renderHeight))
            
            // ✅ Draw premium white footer with subtle top border
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: renderHeight, width: renderWidth, height: footerHeight))
            
            // Subtle top divider line
            UIColor(white: 0.92, alpha: 1.0).setFill()
            ctx.fill(CGRect(x: 0, y: renderHeight, width: renderWidth, height: 1))

            // ✅ Premium typography settings
            let specsFont = UIFont(name: "HelveticaNeue-UltraLight", size: 96)
                         ?? UIFont.systemFont(ofSize: 96, weight: .ultraLight)
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: specsFont,
                .foregroundColor: UIColor.black,
                .kern: 2.0 // ✅ Elegant letter spacing
            ]
            
            let specsSize = (specs as NSString).size(withAttributes: attributes)

            // Center the text perfectly
            let x = (renderWidth - specsSize.width) / 2
            let y = renderHeight + (footerHeight - specsSize.height) / 2 + 4 // Slight optical adjustment

            (specs as NSString).draw(in: CGRect(x: x, y: y, width: specsSize.width, height: specsSize.height),
                                     withAttributes: attributes)
            
            // ✅ Optional: Add tiny subtle tagline below specs for extra premium feel
            let tagline = "TCAM"
            let taglineFont = UIFont(name: "HelveticaNeue-Light", size: 28)
                           ?? UIFont.systemFont(ofSize: 28, weight: .light)
            let taglineSize = (tagline as NSString).size(withAttributes: [.font: taglineFont])
            let taglineY = y + specsSize.height + 12
            
            UIColor(white: 0.4, alpha: 1.0).set()
            (tagline as NSString).draw(in: CGRect(x: (renderWidth - taglineSize.width) / 2,
                                                  y: taglineY,
                                                  width: taglineSize.width,
                                                  height: taglineSize.height),
                                       withAttributes: [.font: taglineFont,
                                                       .foregroundColor: UIColor(white: 0.4, alpha: 1.0),
                                                       .kern: 1.0])
        }
    }
}
