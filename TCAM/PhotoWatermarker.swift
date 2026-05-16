//
//  PhotoWatermarker.swift
//  TCAM — Dark Luxury Watermark v3
//

import UIKit
import AVFoundation
import CoreLocation

final class PhotoWatermarker {
    private static let maxRenderWidth: CGFloat = 3840

    // MARK: - Filter colour palette (matches CameraView swatch colours)
    static func filterColor(for process: TechnicolorProcess) -> UIColor {
        switch process {
        case .native:     return UIColor(white: 1.0, alpha: 0.55)                          // neutral white
        case .twoStrip:   return UIColor(red: 0.85, green: 0.50, blue: 0.40, alpha: 1.0)  // warm red
        case .monopack:   return UIColor(red: 0.70, green: 0.70, blue: 0.70, alpha: 1.0)  // silver
        case .threeStrip: return UIColor(red: 0.45, green: 0.72, blue: 0.58, alpha: 1.0)  // teal-green
        default:          return UIColor(white: 0.75, alpha: 1.0)
        }
    }

    static func filterDisplayName(for process: TechnicolorProcess) -> String {
        switch process {
        case .native:     return "NATIVE"
        case .twoStrip:   return "TWO-STRIP"
        case .monopack:   return "MONOPACK"
        case .threeStrip: return "THREE-STRIP"
        default:          return process.rawValue.uppercased()
        }
    }

    // MARK: - Public entry point

    static func apply(
        to image: UIImage,
        metadata: [String: Any],
        zoomFactor: CGFloat,
        process: TechnicolorProcess,
        location: CLLocation?,
        locationString: String?,   // pre-resolved "City, Country" — pass nil to skip
        isEnabled: Bool
    ) -> UIImage {
        guard isEnabled else { return image }

        let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]

        // Focal length
        let focalStr   = formatFocalLength(for: zoomFactor)

        // Aperture
        let fNumber    = exif[kCGImagePropertyExifFNumber as String] as? Double ?? 0
        let fStr       = fNumber > 0 ? String(format: "ƒ/%.1f", fNumber) : ""

        // Shutter speed
        let expTime    = exif[kCGImagePropertyExifExposureTime as String] as? Double ?? 0
        let shutterStr = expTime > 0 ? formatShutter(expTime) : ""

        // ISO
        let isoArray   = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int] ?? []
        let isoStr     = isoArray.first.map { "ISO \($0)" } ?? ""

        let parts      = [focalStr, fStr, shutterStr, isoStr].filter { !$0.isEmpty }
        let specsLine  = parts.joined(separator: "  ·  ")

        // Determine if image is landscape (width > height)
        let isLandscape = image.size.width > image.size.height

        return render(
            on: image,
            specs: specsLine,
            locationString: locationString,
            process: process,
            isLandscape: isLandscape
        )
    }

    // MARK: - Formatters

    private static func formatShutter(_ seconds: Double) -> String {
        if seconds >= 1 { return String(format: "%.1f\"", seconds) }
        return "1/\(Int((1.0 / seconds).rounded()))s"
    }

    private static func formatFocalLength(for zoom: CGFloat) -> String {
        switch zoom {
        case ..<0.8:    return "13mm"
        case 0.8..<1.8: return "24mm"
        case 1.8..<4.0: return "48mm"
        case 4.0..<7.0: return "120mm"
        default:        return "240mm"
        }
    }

    // MARK: - Renderer

    private static func render(
        on image: UIImage,
        specs: String,
        locationString: String?,
        process: TechnicolorProcess,
        isLandscape: Bool
    ) -> UIImage {
        let srcWidth  = image.size.width
        let renderW   = min(srcWidth, maxRenderWidth)
        let scale     = renderW / srcWidth
        let renderH   = image.size.height * scale

        // Taller footer — 16% of width gives generous room for 3 rows + right column
        let footerH: CGFloat = renderW * 0.160
        let totalH            = renderH + footerH

        let format        = UIGraphicsImageRendererFormat()
        format.scale      = 1.0
        let renderer      = UIGraphicsImageRenderer(
            size: CGSize(width: renderW, height: totalH),
            format: format
        )

        return renderer.image { ctx in
            let cgCtx = ctx.cgContext

            // ── Photo ─────────────────────────────────────────────────────
            image.draw(in: CGRect(x: 0, y: 0, width: renderW, height: renderH))

            // ── Footer background ─────────────────────────────────────────
            UIColor(white: 0.04, alpha: 1.0).setFill()
            ctx.fill(CGRect(x: 0, y: renderH, width: renderW, height: footerH))

            // Top hairline
            UIColor(white: 1.0, alpha: 0.12).setFill()
            ctx.fill(CGRect(x: 0, y: renderH, width: renderW, height: max(2, renderW / 1500)))

            // ── Type scale ────────────────────────────────────────────────
            let specsSize  = renderW * 0.0270   // main specs — largest
            let subSize    = renderW * 0.0155   // device + location row
            let filterSize = renderW * 0.0145   // filter name on right
            let brandSize  = renderW * 0.0190   // TCAM wordmark

            let hPad       = renderW * 0.036
            let vPad       = footerH * 0.18     // top margin inside footer

            // Determine watermark side based on orientation
            // Landscape photos: watermark on left; Portrait photos: watermark on right
            let watermarkOnLeft = isLandscape

            // ── LEFT COLUMN (specs) ───────────────────────────────────────
            let leftColumnX: CGFloat = hPad

            // Row 1 — specs
            let specsFont  = UIFont(name: "HelveticaNeue-Light", size: specsSize)
                          ?? UIFont.systemFont(ofSize: specsSize, weight: .light)
            let specsAttrs: [NSAttributedString.Key: Any] = [
                .font:            specsFont,
                .foregroundColor: UIColor(white: 1.0, alpha: 0.92),
                .kern:            specsSize * 0.10
            ]
            let specsSz = (specs as NSString).size(withAttributes: specsAttrs)
            let specsY  = renderH + vPad

            (specs as NSString).draw(
                in: CGRect(x: leftColumnX, y: specsY, width: renderW * 0.72, height: specsSz.height),
                withAttributes: specsAttrs
            )

            // Row 2 — "iPhone 15 Pro Max  ·  City, Country"
            let subFont  = UIFont(name: "HelveticaNeue-Light", size: subSize)
                        ?? UIFont.systemFont(ofSize: subSize, weight: .light)

            var subParts = ["iPhone 15 Pro Max"]
            if let loc = locationString, !loc.isEmpty { subParts.append(loc) }
            let subLine  = subParts.joined(separator: "  ·  ")

            let subAttrs: [NSAttributedString.Key: Any] = [
                .font:            subFont,
                .foregroundColor: UIColor(white: 1.0, alpha: 0.48),
                .kern:            subSize * 0.22
            ]
            let subSz   = (subLine as NSString).size(withAttributes: subAttrs)
            let subY    = specsY + specsSz.height + specsSize * 0.35

            (subLine as NSString).draw(
                in: CGRect(x: leftColumnX, y: subY, width: renderW * 0.72, height: subSz.height),
                withAttributes: subAttrs
            )

            // ── RIGHT COLUMN ──────────────────────────────────────────────
            // Vertically centred in the footer, position depends on orientation

            let rightCentreY = renderH + footerH * 0.5

            // TCAM wordmark
            let brandFont  = UIFont(name: "HelveticaNeue-Thin", size: brandSize)
                          ?? UIFont.systemFont(ofSize: brandSize, weight: .thin)
            let brandAttrs: [NSAttributedString.Key: Any] = [
                .font:            brandFont,
                .foregroundColor: UIColor(white: 1.0, alpha: 0.65),
                .kern:            brandSize * 0.55
            ]
            let brandStr  = "TCAM" as NSString
            let brandSz   = brandStr.size(withAttributes: brandAttrs)

            // Filter name (coloured, below TCAM)
            let filterFont  = UIFont(name: "HelveticaNeue-Light", size: filterSize)
                           ?? UIFont.systemFont(ofSize: filterSize, weight: .light)
            let filterColor  = PhotoWatermarker.filterColor(for: process)
            let filterName   = PhotoWatermarker.filterDisplayName(for: process)
            let filterAttrs: [NSAttributedString.Key: Any] = [
                .font:            filterFont,
                .foregroundColor: filterColor,
                .kern:            filterSize * 0.40
            ]
            let filterStr  = filterName as NSString
            let filterSz   = filterStr.size(withAttributes: filterAttrs)

            // Stack TCAM + filter, centre the block vertically
            let gap        = brandSize * 0.30
            let blockH     = brandSz.height + gap + filterSz.height
            let blockTop   = rightCentreY - blockH / 2

            // Position brand/filter column based on orientation
            let brandX     = watermarkOnLeft ? renderW - hPad - brandSz.width : hPad + renderW * 0.24
            brandStr.draw(
                in: CGRect(x: brandX, y: blockTop, width: brandSz.width, height: brandSz.height),
                withAttributes: brandAttrs
            )

            let filterX    = watermarkOnLeft ? renderW - hPad - filterSz.width : hPad + renderW * 0.24
            filterStr.draw(
                in: CGRect(x: filterX, y: blockTop + brandSz.height + gap,
                           width: filterSz.width, height: filterSz.height),
                withAttributes: filterAttrs
            )

            // ── Vertical rule between columns ─────────────────────────────
            let ruleX      = watermarkOnLeft ? renderW * 0.76 : renderW * 0.24
            let ruleTop    = renderH + footerH * 0.20
            let ruleBot    = renderH + footerH * 0.80
            cgCtx.setStrokeColor(UIColor(white: 1.0, alpha: 0.10).cgColor)
            cgCtx.setLineWidth(max(1, renderW / 2000))
            cgCtx.move(to: CGPoint(x: ruleX, y: ruleTop))
            cgCtx.addLine(to: CGPoint(x: ruleX, y: ruleBot))
            cgCtx.strokePath()

            // ── Corner mark ───────────────────────────────────────────────
            let markLen = renderW * 0.014
            let markThk = max(1.5, renderW / 1800)
            let mx      = watermarkOnLeft ? renderW - hPad * 0.65 : hPad * 0.65 + markLen
            let my      = renderH + footerH - hPad * 0.65
            cgCtx.setStrokeColor(UIColor(white: 1.0, alpha: 0.20).cgColor)
            cgCtx.setLineWidth(markThk)
            if watermarkOnLeft {
                // Right corner mark (standard L shape)
                cgCtx.move(to: CGPoint(x: mx - markLen, y: my))
                cgCtx.addLine(to: CGPoint(x: mx, y: my))
                cgCtx.addLine(to: CGPoint(x: mx, y: my - markLen))
            } else {
                // Left corner mark (mirrored L shape)
                cgCtx.move(to: CGPoint(x: mx, y: my))
                cgCtx.addLine(to: CGPoint(x: mx - markLen, y: my))
                cgCtx.addLine(to: CGPoint(x: mx - markLen, y: my - markLen))
            }
            cgCtx.strokePath()
        }
    }
}
