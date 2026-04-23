//
//  PhotoWatermarker.swift
//  TCAM - iPhone 15 Pro Max Optimized
//

import UIKit
import AVFoundation

final class PhotoWatermarker {
    private static let maxRenderWidth: CGFloat = 3840

    static func apply(to image: UIImage, metadata: [String: Any], zoomFactor: CGFloat, isEnabled: Bool) -> UIImage {
        guard isEnabled else { return image }

        let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]

        // ISO
        let isoArray = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int] ?? []
        let isoString = isoArray.first.map { "ISO \($0)" } ?? ""

        // Shutter Speed
        let exposureTime = exif[kCGImagePropertyExifExposureTime as String] as? Double ?? 0
        let shutterString = exposureTime > 0 ? formatShutter(exposureTime) : ""

        // ✅ FIX: Use zoom factor instead of physical mm for accurate 15 Pro Max equivalents
        let focalString = formatFocalLength(for: zoomFactor)

        // Aperture
        let fNumber = exif[kCGImagePropertyExifFNumber as String] as? Double ?? 0
        let fString = fNumber > 0 ? String(format: "ƒ/%.1f", fNumber) : ""

        // Build clean specs string
        var specs = [String]()
        if !focalString.isEmpty { specs.append(focalString) }
        if !fString.isEmpty { specs.append(fString) }
        if !shutterString.isEmpty { specs.append(shutterString) }
        if !isoString.isEmpty { specs.append(isoString) }
        let specsLine = specs.joined(separator: "   ")

        return render(on: image, specs: specsLine)
    }

    private static func formatShutter(_ seconds: Double) -> String {
        if seconds >= 1 { return String(format: "%.1fs", seconds) }
        return "1/\(Int(round(1.0 / seconds)))s"
    }

    // ✅ iPhone 15 Pro Max exact equivalents
    private static func formatFocalLength(for zoom: CGFloat) -> String {
        switch zoom {
        case ..<0.8:  return "13mm"   // 0.5x Ultra Wide
        case 0.8..<1.8: return "24mm"   // 1x Main Wide
        case 1.8..<4.0: return "48mm"   // 2x Digital Crop
        case 4.0..<7.0: return "120mm"  // 5x Optical Tele
        default:        return "240mm"  // 10x Digital Crop
        }
    }

    private static func render(on image: UIImage, specs: String) -> UIImage {
        let originalWidth = image.size.width
        let renderWidth = min(originalWidth, maxRenderWidth)
        let aspectRatio = image.size.height / originalWidth
        let renderHeight = renderWidth * aspectRatio
        let footerHeight: CGFloat = 320
        let totalHeight = renderHeight + footerHeight

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: renderWidth, height: totalHeight),
                                               format: .init(for: .init(displayScale: 1.0)))

        return renderer.image { ctx in
            image.draw(in: CGRect(x: 0, y: 0, width: renderWidth, height: renderHeight))
            
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: renderHeight, width: renderWidth, height: footerHeight))
            
            UIColor(white: 0.92, alpha: 1.0).setFill()
            ctx.fill(CGRect(x: 0, y: renderHeight, width: renderWidth, height: 1))

            let specsFont = UIFont(name: "HelveticaNeue-UltraLight", size: 96) 
                         ?? UIFont.systemFont(ofSize: 96, weight: .ultraLight)
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: specsFont,
                .foregroundColor: UIColor.black,
                .kern: 2.0
            ]
            
            let specsSize = (specs as NSString).size(withAttributes: attributes)
            let x = (renderWidth - specsSize.width) / 2
            let y = renderHeight + (footerHeight - specsSize.height) / 2 + 4

            (specs as NSString).draw(in: CGRect(x: x, y: y, width: specsSize.width, height: specsSize.height),
                                     withAttributes: attributes)
            
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