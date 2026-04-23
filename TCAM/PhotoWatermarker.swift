//
//  PhotoWatermarker.swift
//  TCAM
//

import UIKit
import AVFoundation

final class PhotoWatermarker {
    
    static func apply(to image: UIImage, metadata: [String: Any], isEnabled: Bool) -> UIImage {
        guard isEnabled else { return image }
        
        let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let tiff = metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        
        let isoArray = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int] ?? []
        let isoString = isoArray.first.map { "ISO \($0)" } ?? ""
        
        let exposureTime = exif[kCGImagePropertyExifExposureTime as String] as? Double ?? 0
        let shutterString = exposureTime > 0 ? formatShutter(exposureTime) : ""
        
        // ✅ Fixed: Use standard EXIF key
        let focalRaw = exif[kCGImagePropertyExifFocalLength as String] as? Double ?? 0
        let focalString = focalRaw > 0 ? String(format: "%.0fmm", focalRaw) : ""
        
        let fNumber = exif[kCGImagePropertyExifFNumber as String] as? Double ?? 0
        let fString = fNumber > 0 ? String(format: "f/%.2g", fNumber) : ""
        
        let model = tiff[kCGImagePropertyTIFFModel as String] as? String ?? UIDevice.current.model
        
        let deviceLine = "SHOT ON \(model.uppercased())"
        var specs = [String]()
        if !isoString.isEmpty { specs.append(isoString) }
        if !shutterString.isEmpty { specs.append(shutterString) }
        if !focalString.isEmpty { specs.append(focalString) }
        if !fString.isEmpty { specs.append(fString) }
        let specsLine = specs.joined(separator: " • ")
        
        return render(on: image, deviceLine: deviceLine, specsLine: specsLine)
    }
    
    private static func formatShutter(_ seconds: Double) -> String {
        if seconds >= 1 { return String(format: "%.1fs", seconds) }
        return "1/\(Int(round(1.0 / seconds)))s"
    }
    
    private static func render(on image: UIImage, deviceLine: String, specsLine: String) -> UIImage {
        let size = image.size
        
        // ✅ Fixed: Simplified renderer init to avoid trait collection mismatch
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            image.draw(in: CGRect(origin: .zero, size: size))
            
            let padding: CGFloat = 24
            let bgPadding: CGFloat = 16
            let cornerRadius: CGFloat = 12
            let lineSpacing: CGFloat = 6
            
            let deviceFont = UIFont.systemFont(ofSize: 28, weight: .semibold)
            let specsFont = UIFont.systemFont(ofSize: 20, weight: .regular)
            
            let deviceSize = (deviceLine as NSString).size(withAttributes: [.font: deviceFont])
            let specsSize = (specsLine as NSString).size(withAttributes: [.font: specsFont])
            
            let boxWidth = max(deviceSize.width, specsSize.width) + bgPadding * 2
            let boxHeight = 28 + lineSpacing + 20 + bgPadding * 2
            
            let boxX = size.width - boxWidth - padding
            let boxY = size.height - boxHeight - padding
            
            let bgColor = UIColor(white: 0, alpha: 0.65)
            let path = UIBezierPath(roundedRect: CGRect(x: boxX, y: boxY, width: boxWidth, height: boxHeight), cornerRadius: cornerRadius)
            bgColor.setFill()
            path.fill()
            
            let deviceAttr: [NSAttributedString.Key: Any] = [.font: deviceFont, .foregroundColor: UIColor.white]
            let specsAttr: [NSAttributedString.Key: Any] = [.font: specsFont, .foregroundColor: UIColor.white.withAlphaComponent(0.85)]
            
            let textY = boxY + bgPadding
            (deviceLine as NSString).draw(in: CGRect(x: boxX + bgPadding, y: textY, width: boxWidth - bgPadding * 2, height: 28), withAttributes: deviceAttr)
            (specsLine as NSString).draw(in: CGRect(x: boxX + bgPadding, y: textY + 28 + lineSpacing, width: boxWidth - bgPadding * 2, height: 20), withAttributes: specsAttr)
        }
    }
}
