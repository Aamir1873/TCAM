//
//  PhotoWatermarker.swift
//  TCAM — Dark Luxury Watermark
//

import UIKit
import AVFoundation

final class PhotoWatermarker {
    private static let maxRenderWidth: CGFloat = 3840

    static func apply(
        to image: UIImage,
        metadata: [String: Any],
        zoomFactor: CGFloat,
        isEnabled: Bool
    ) -> UIImage {
        guard isEnabled else { return image }

        let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]

        // ── Focal length ─────────────────────────────────────────────────
        let focalString = formatFocalLength(for: zoomFactor)

        // ── Aperture ─────────────────────────────────────────────────────
        let fNumber    = exif[kCGImagePropertyExifFNumber as String] as? Double ?? 0
        let fString    = fNumber > 0 ? String(format: "ƒ/%.1f", fNumber) : ""

        // ── Shutter speed ─────────────────────────────────────────────────
        let expTime     = exif[kCGImagePropertyExifExposureTime as String] as? Double ?? 0
        let shutterStr  = expTime > 0 ? formatShutter(expTime) : ""

        // ── ISO ───────────────────────────────────────────────────────────
        let isoArray   = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int] ?? []
        let isoString  = isoArray.first.map { "ISO \($0)" } ?? ""

        // ── Assemble — only non-empty parts, dot-separated ────────────────
        let parts: [String] = [focalString, fString, shutterStr, isoString]
            .filter { !$0.isEmpty }
        let specsLine = parts.joined(separator: "  ·  ")

        return render(on: image, specs: specsLine)
    }

    // MARK: - Formatters

    private static func formatShutter(_ seconds: Double) -> String {
        if seconds >= 1 { return String(format: "%.1f\"", seconds) }
        return "1/\(Int((1.0 / seconds).rounded()))s"
    }

    /// iPhone 15 Pro Max 35mm-equivalent focal lengths
    private static func formatFocalLength(for zoom: CGFloat) -> String {
        switch zoom {
        case ..<0.8:    return "13mm"   // 0.5× Ultra Wide
        case 0.8..<1.8: return "24mm"   // 1× Main
        case 1.8..<4.0: return "48mm"   // 2× Crop
        case 4.0..<7.0: return "120mm"  // 5× Tele
        default:        return "240mm"  // 10× Crop
        }
    }

    // MARK: - Renderer

    private static func render(on image: UIImage, specs: String) -> UIImage {
        let srcWidth    = image.size.width
        let renderW     = min(srcWidth, maxRenderWidth)
        let scale       = renderW / srcWidth
        let renderH     = image.size.height * scale

        // Footer height scales with image so it looks proportional at any res
        let footerH: CGFloat = renderW * 0.115   // ~11.5% of width → ~440pt @ 4K
        let totalH   = renderH + footerH

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: renderW, height: totalH),
            format: format
        )

        return renderer.image { ctx in
            let cgCtx = ctx.cgContext

            // ── Photo ─────────────────────────────────────────────────────
            image.draw(in: CGRect(x: 0, y: 0, width: renderW, height: renderH))

            // ── Dark footer ───────────────────────────────────────────────
            UIColor(white: 0.04, alpha: 1.0).setFill()
            ctx.fill(CGRect(x: 0, y: renderH, width: renderW, height: footerH))

            // Top hairline — subtle separator
            let hairlineColor = UIColor(white: 1.0, alpha: 0.10)
            hairlineColor.setFill()
            ctx.fill(CGRect(x: 0, y: renderH, width: renderW, height: max(1, renderW / 2000)))

            // ── Typography scale (proportional to image width) ────────────
            let specsSize  = renderW * 0.0220   // main specs — large & legible
            let subSize    = renderW * 0.0120   // device sub-label — clearly readable
            let brandSize  = renderW * 0.0140   // TCAM — visible on the right

            let hPad    = renderW * 0.032
            // Block of two text lines, vertically centred in footer
            let lineGap = specsSize * 0.40
            let blockH  = specsSize + lineGap + subSize
            let blockY  = renderH + (footerH - blockH) / 2

            // ── Specs line (left-aligned) ─────────────────────────────────
            let specsFont = UIFont(name: "HelveticaNeue-Light", size: specsSize)
                         ?? UIFont.systemFont(ofSize: specsSize, weight: .light)

            let specsAttrs: [NSAttributedString.Key: Any] = [
                .font:            specsFont,
                .foregroundColor: UIColor(white: 1.0, alpha: 0.90),
                .kern:            specsSize * 0.12
            ]
            let specsSz = (specs as NSString).size(withAttributes: specsAttrs)

            (specs as NSString).draw(
                in: CGRect(x: hPad, y: blockY, width: renderW - hPad * 2, height: specsSz.height),
                withAttributes: specsAttrs
            )

            // ── Sub-label: device name ────────────────────────────────────
            let subFont = UIFont(name: "HelveticaNeue-Light", size: subSize)
                       ?? UIFont.systemFont(ofSize: subSize, weight: .light)

            let subAttrs: [NSAttributedString.Key: Any] = [
                .font:            subFont,
                .foregroundColor: UIColor(white: 1.0, alpha: 0.45),
                .kern:            subSize * 0.28
            ]
            let subStr = "iPhone 15 Pro Max" as NSString
            let subSz  = subStr.size(withAttributes: subAttrs)
            let subY   = blockY + specsSz.height + lineGap

            subStr.draw(
                in: CGRect(x: hPad, y: subY, width: subSz.width, height: subSz.height),
                withAttributes: subAttrs
            )

            // ── Brand mark (right-aligned, vertically centred) ────────────
            let brandFont = UIFont(name: "HelveticaNeue-Light", size: brandSize)
                         ?? UIFont.systemFont(ofSize: brandSize, weight: .light)

            let brandAttrs: [NSAttributedString.Key: Any] = [
                .font:            brandFont,
                .foregroundColor: UIColor(white: 1.0, alpha: 0.50),
                .kern:            brandSize * 0.50
            ]
            let brandStr = "TCAM" as NSString
            let brandSz  = brandStr.size(withAttributes: brandAttrs)
            let brandX   = renderW - hPad - brandSz.width
            let brandY   = renderH + (footerH - brandSz.height) / 2

            brandStr.draw(
                in: CGRect(x: brandX, y: brandY, width: brandSz.width, height: brandSz.height),
                withAttributes: brandAttrs
            )

            // ── Corner mark — bottom-right L-bracket ──────────────────────
            let markLen: CGFloat = renderW * 0.012
            let markThk: CGFloat = max(1, renderW / 2200)
            let mx = renderW - hPad * 0.7
            let my = renderH + footerH - hPad * 0.7
            cgCtx.setStrokeColor(UIColor(white: 1.0, alpha: 0.18).cgColor)
            cgCtx.setLineWidth(markThk)
            cgCtx.move(to: CGPoint(x: mx - markLen, y: my))
            cgCtx.addLine(to: CGPoint(x: mx, y: my))
            cgCtx.addLine(to: CGPoint(x: mx, y: my - markLen))
            cgCtx.strokePath()
        }
    }
}
