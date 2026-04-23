//
//  PhotoWatermarker.swift
//  TCAM - Memory-Optimized OPPO Style
//

import UIKit
import AVFoundation

final class PhotoWatermarker {
    
    // ✅ Cap max width to 4K to prevent memory crashes
    private static let maxRenderWidth: CGFloat = 3840
    
    static func apply(to image: UIImage, metadata: [String: Any], isEnabled: Bool) -> UIImage {
        guard isEnabled else { return image }
        
        let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let tiff = metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        
        let isoArray = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int] ?? []
        let isoString = isoArray.first.map { "ISO\($0)" } ?? ""
        
        let exposureTime = exif[kCGImagePropertyExifExposureTime as String] as? Double ?? 0
        let shutterString = exposureTime > 0 ? formatShutter(exposureTime) : ""
        
        let focalRaw = exif[kCGImagePropertyExifFocalLength as String] as? Double ?? 0
        let focalString = focalRaw > 0 ? String(format: "%.0fmm", focalRaw) : ""
        
        let fNumber = exif[kCGImagePropertyExifFNumber as String] as? Double ?? 0
        let fString = fNumber > 0 ? String(format: "f/%.2g", fNumber) : ""
        
        let model = tiff[kCGImagePropertyTIFFModel as String] as? String ?? UIDevice.current.model
        
        var specs = [String]()
        if !focalString.isEmpty { specs.append(focalString) }
        if !fString.isEmpty { specs.append(fString) }
        if !shutterString.isEmpty { specs.append(shutterString) }
        if !isoString.isEmpty { specs.append(isoString) }
        let specsLine = specs.joined(separator: " ")
        
        return render(on: image,
                      modelName: model.uppercased(),
                      brandName: "TCAM",
                      specs: specsLine)
    }
    
    private static func formatShutter(_ seconds: Double) -> String {
        if seconds >= 1 { return String(format: "%.1fs", seconds) }
        return "1/\(Int(round(1.0 / seconds)))s"
    }
    
    private static func render(on image: UIImage, modelName: String, brandName: String, specs: String) -> UIImage {
        // ✅ Calculate safe render size
        let originalWidth = image.size.width
        let originalHeight = image.size.height
        let aspectRatio = originalHeight / originalWidth
        
        // Cap width to prevent memory crash
        let renderWidth = min(originalWidth, maxRenderWidth)
        let renderHeight = renderWidth * aspectRatio
        let footerHeight: CGFloat = 400
        let totalHeight = renderHeight + footerHeight
        
        // ✅ Use scale=1.0 for memory efficiency (text will still look sharp at 4K)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: renderWidth, height: totalHeight),
                                              format: .init(for: .init(displayScale: 1.0)))
        
        return renderer.image { ctx in
            // Draw scaled image
            image.draw(in: CGRect(x: 0, y: 0, width: renderWidth, height: renderHeight))
            
            // Draw white footer
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: renderHeight, width: renderWidth, height: footerHeight))
            
            let padding: CGFloat = 40
            let startY = renderHeight + 60
            
            // Calculate font sizes relative to render width for consistency
            let modelFontSize = renderWidth * 0.026 // ~100pt at 3840px width
            let brandFontSize = renderWidth * 0.029 // ~110pt at 3840px width
            let specsFontSize = renderWidth * 0.0125 // ~48pt at 3840px width
            
            // Left Side: Phone Model
            let modelFont = UIFont.systemFont(ofSize: modelFontSize, weight: .semibold)
            let modelText = "SHOT ON \(modelName)"
            let modelSize = (modelText as NSString).size(withAttributes: [.font: modelFont])
            
            UIColor.black.set()
            (modelText as NSString).draw(in: CGRect(x: padding, y: startY, width: modelSize.width, height: modelFontSize + 10), withAttributes: [.font: modelFont])
            
            // Right Side: Brand & Specs
            let brandFont = UIFont(name: "Georgia", size: brandFontSize) ?? UIFont.systemFont(ofSize: brandFontSize, weight: .bold)
            let brandSize = (brandName as NSString).size(withAttributes: [.font: brandFont])
            
            let specsFont = UIFont.monospacedSystemFont(ofSize: specsFontSize, weight: .medium)
            let specsSize = (specs as NSString).size(withAttributes: [.font: specsFont])
            
            let rightContentWidth = max(brandSize.width, specsSize.width + 60)
            let startX = renderWidth - rightContentWidth - padding
            
            // Draw Brand Name
            UIColor.black.set()
            (brandName as NSString).draw(in: CGRect(x: startX, y: startY, width: brandSize.width, height: brandFontSize + 10), withAttributes: [.font: brandFont])
            
            // Draw Orange Dot
            let dotColor = UIColor(hex: 0xFF6B35)
            dotColor.setFill()
            let dotY = startY + brandFontSize + 20
            let dotSize = renderWidth * 0.005 // ~20pt at 3840px
            let dotRect = CGRect(x: startX, y: dotY, width: dotSize, height: dotSize)
            
            let dotPath = UIBezierPath(ovalIn: dotRect)
            dotPath.fill()
            
            // Draw Specs
            UIColor.darkGray.set()
            (specs as NSString).draw(in: CGRect(x: startX + dotSize + 28, y: dotY + 24, width: specsSize.width, height: specsFontSize + 28), withAttributes: [.font: specsFont])
        }
    }
}

extension UIColor {
    convenience init(hex: Int) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
