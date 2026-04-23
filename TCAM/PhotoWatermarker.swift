//
//  PhotoWatermarker.swift
//  TCAM - OPPO/Hasselblad Style Watermark
//

import UIKit
import AVFoundation

final class PhotoWatermarker {
    
    static func apply(to image: UIImage, meta [String: Any], isEnabled: Bool) -> UIImage {
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
        let width = image.size.width
        let footerHeight: CGFloat = 200
        let newSize = CGSize(width: width, height: image.size.height + footerHeight)
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { ctx in
            image.draw(in: CGRect(origin: .zero, size: image.size))
            
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: image.size.height, width: width, height: footerHeight))
            
            let padding: CGFloat = 40
            let startY = image.size.height + 32
            
            let modelFont = UIFont.systemFont(ofSize: 42, weight: .semibold)
            let modelText = "SHOT ON \(modelName)"
            let modelSize = (modelText as NSString).size(withAttributes: [.font: modelFont])
            
            UIColor.black.set()
            (modelText as NSString).draw(in: CGRect(x: padding, y: startY, width: modelSize.width, height: 50), withAttributes: [.font: modelFont])
            
            let brandFont = UIFont(name: "Georgia", size: 44) ?? UIFont.systemFont(ofSize: 44, weight: .bold)
            let brandSize = (brandName as NSString).size(withAttributes: [.font: brandFont])
            
            let specsFont = UIFont.monospacedSystemFont(ofSize: 22, weight: .medium)
            let specsSize = (specs as NSString).size(withAttributes: [.font: specsFont])
            
            let rightContentWidth = max(brandSize.width, specsSize.width + 32)
            let startX = width - rightContentWidth - padding
            
            UIColor.black.set()
            (brandName as NSString).draw(in: CGRect(x: startX, y: startY, width: brandSize.width, height: 50), withAttributes: [.font: brandFont])
            
            let dotColor = UIColor(hex: 0xFF6B35)
            dotColor.setFill()
            let dotY = startY + 60
            let dotRect = CGRect(x: startX, y: dotY, width: 12, height: 12)
            
            let dotPath = UIBezierPath(ovalIn: dotRect)
            dotPath.fill()
            
            UIColor.darkGray.set()
            (specs as NSString).draw(in: CGRect(x: startX + 24, y: dotY + 2, width: specsSize.width, height: 28), withAttributes: [.font: specsFont])
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