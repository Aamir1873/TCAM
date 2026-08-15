//
//  TechnicolorEngine.swift
//  TCAM
//

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import Metal
import UIKit

final class TechnicolorEngine: Sendable {

    private let filterLock = NSLock()
    private let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)!

    let context: CIContext = {
        guard let device = MTLCreateSystemDefaultDevice() else {
            preconditionFailure("TCAM requires a Metal-capable device")
        }
        return CIContext(mtlDevice: device, options: [
            .useSoftwareRenderer: false,
            .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3) as Any,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.displayP3) as Any,
            .cacheIntermediates: false
        ])
    }()

    nonisolated(unsafe) private let ccThree  = CIFilter.colorControls()
    nonisolated(unsafe) private let cmThree  = CIFilter.colorMatrix()
    nonisolated(unsafe) private let vigThree = CIFilter.vignette()

    nonisolated(unsafe) private let cmTwo    = CIFilter.colorMatrix()
    nonisolated(unsafe) private let ccTwo    = CIFilter.colorControls()
    nonisolated(unsafe) private let vigTwo   = CIFilter.vignette()

    nonisolated(unsafe) private let ccMono   = CIFilter.colorControls()
    nonisolated(unsafe) private let cmMono   = CIFilter.colorMatrix()
    nonisolated(unsafe) private let gamMono  = CIFilter(name: "CIGammaAdjust")
    nonisolated(unsafe) private let vigMono  = CIFilter.vignette()

    nonisolated(unsafe) private let ccCine   = CIFilter.colorControls()
    nonisolated(unsafe) private let cmCine   = CIFilter.colorMatrix()
    nonisolated(unsafe) private let vigCine  = CIFilter.vignette()

    nonisolated(unsafe) private let blurFilter   = CIFilter.gaussianBlur()
    nonisolated(unsafe) private let blurColorMat = CIFilter.colorMatrix()
    nonisolated(unsafe) private let addBlend     = CIFilter(name: "CIAdditionCompositing")!

    init() {
        // THREE-STRIP
        ccThree.saturation = 1.55; ccThree.brightness = 0.02; ccThree.contrast = 1.12
        cmThree.rVector    = CIVector(x: 1.18,  y: 0.0,   z: -0.05, w: 0)
        cmThree.gVector    = CIVector(x: 0.0,   y: 0.92,  z: 0.04,  w: 0)
        cmThree.bVector    = CIVector(x: 0.0,   y: 0.0,   z: 0.88,  w: 0)
        cmThree.aVector    = CIVector(x: 0,     y: 0,     z: 0,     w: 1)
        cmThree.biasVector = CIVector(x: 0.015, y: 0.01,  z: 0.0,   w: 0)
        vigThree.intensity = 0.45; vigThree.radius = 1.6

        // TWO-STRIP
        cmTwo.rVector    = CIVector(x: 1.05,  y: 0.02,  z: 0.0,   w: 0)
        cmTwo.gVector    = CIVector(x: 0.02,  y: 0.98,  z: -0.02, w: 0)
        cmTwo.bVector    = CIVector(x: -0.02, y: -0.02, z: 1.12,  w: 0)
        cmTwo.aVector    = CIVector(x: 0,     y: 0,     z: 0,     w: 1)
        cmTwo.biasVector = CIVector(x: -0.01, y: 0.0,   z: 0.015, w: 0)
        ccTwo.saturation = 1.15; ccTwo.brightness = 0.0; ccTwo.contrast = 1.05
        vigTwo.intensity = 0.5; vigTwo.radius = 1.5

        // MONOPACK
        ccMono.saturation = 1.25; ccMono.brightness = 0.03; ccMono.contrast = 1.05
        cmMono.rVector    = CIVector(x: 1.08, y: 0.0,  z: 0.0, w: 0)
        cmMono.gVector    = CIVector(x: 0.0,  y: 1.0,  z: 0.0, w: 0)
        cmMono.bVector    = CIVector(x: 0.0,  y: 0.0,  z: 0.9, w: 0)
        cmMono.aVector    = CIVector(x: 0,    y: 0,    z: 0,   w: 1)
        cmMono.biasVector = CIVector(x: 0.03, y: 0.02, z: 0.0, w: 0)
        gamMono?.setValue(0.88, forKey: "inputPower")
        vigMono.intensity = 0.35; vigMono.radius = 1.8

        // CINEMATIC - Blue/Green boosted, Orange muted
        ccCine.saturation = 1.1; ccCine.brightness = 0.02; ccCine.contrast = 1.08
        cmCine.rVector    = CIVector(x: 0.85,  y: 0.06,  z: 0.0,  w: 0)  // Mute reds/oranges (keep some green in red channel)
        cmCine.gVector    = CIVector(x: 0.06,  y: 1.15,  z: 0.06, w: 0)  // Boost greens (add slight bleed from R/B)
        cmCine.bVector    = CIVector(x: 0.0,   y: 0.05,  z: 1.18, w: 0)  // Boost blues (add slight green bleed)
        cmCine.aVector    = CIVector(x: 0,     y: 0,     z: 0,    w: 1)
        cmCine.biasVector = CIVector(x: 0.02,  y: 0.03,  z: 0.04, w: 0)  // Add cool tint
        vigCine.intensity = 0.4; vigCine.radius = 1.7

        // Halation setup
        blurFilter.radius = 12
        blurColorMat.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
    }

    func apply(_ process: TechnicolorProcess, to image: CIImage) -> CIImage {
        filterLock.lock()
        defer { filterLock.unlock() }
        return applyUnlocked(process, to: image)
    }

    func render(_ process: TechnicolorProcess, image: CIImage) -> CGImage? {
        filterLock.lock()
        defer { filterLock.unlock() }
        let filtered = toneMap(applyUnlocked(process, to: image))
        return context.createCGImage(filtered, from: filtered.extent)
    }

    func sourceImage(from data: Data, isRaw: Bool) -> CIImage? {
        if isRaw, let rawFilter = CIFilter(imageData: data, options: nil) {
            return rawFilter.outputImage
        }
        return CIImage(data: data)
    }

    func jpegData(from image: UIImage, quality: CGFloat = 0.98) -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        filterLock.lock()
        defer { filterLock.unlock() }
        let image = CIImage(cgImage: cgImage, options: [
            .colorSpace: displayP3
        ])
        return context.jpegRepresentation(
            of: image,
            colorSpace: displayP3,
            options: [
                kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality
            ]
        )
    }

    private func applyUnlocked(_ process: TechnicolorProcess, to image: CIImage) -> CIImage {
        switch process {
        case .cinematic:  cinematic(image)
        case .threeStrip: threeStrip(image)
        case .twoStrip:   twoStrip(image)
        case .monopack:   monopack(image)
        }
    }

    private func threeStrip(_ image: CIImage) -> CIImage {
        ccThree.inputImage = image
        var img = ccThree.outputImage ?? image
        cmThree.inputImage = img;  img = cmThree.outputImage  ?? img
        vigThree.inputImage = img; img = vigThree.outputImage ?? img
        return halation(img, amount: 0.08)
    }

    private func twoStrip(_ image: CIImage) -> CIImage {
        cmTwo.inputImage = image
        var img = cmTwo.outputImage ?? image
        ccTwo.inputImage = img;  img = ccTwo.outputImage  ?? img
        vigTwo.inputImage = img; img = vigTwo.outputImage ?? img
        return halation(img, amount: 0.10)
    }

    private func monopack(_ image: CIImage) -> CIImage {
        ccMono.inputImage = image
        var img = ccMono.outputImage ?? image
        cmMono.inputImage = img; img = cmMono.outputImage ?? img
        if let gam = gamMono {
            gam.setValue(img, forKey: kCIInputImageKey)
            img = gam.outputImage ?? img
        }
        vigMono.inputImage = img; img = vigMono.outputImage ?? img
        return halation(img, amount: 0.06)
    }

    private func cinematic(_ image: CIImage) -> CIImage {
        ccCine.inputImage = image
        var img = ccCine.outputImage ?? image
        cmCine.inputImage = img; img = cmCine.outputImage ?? img
        vigCine.inputImage = img; img = vigCine.outputImage ?? img
        return halation(img, amount: 0.05)
    }

    private func toneMap(_ image: CIImage) -> CIImage {
        let toneMap = CIFilter.highlightShadowAdjust()
        toneMap.inputImage = image
        toneMap.shadowAmount = 0.15
        toneMap.highlightAmount = 0.85
        return toneMap.outputImage ?? image
    }

    private func halation(_ image: CIImage, amount: Float) -> CIImage {
        blurFilter.inputImage = image
        guard let blurred = blurFilter.outputImage else { return image }
        blurColorMat.inputImage = blurred
        blurColorMat.aVector    = CIVector(x: 0, y: 0, z: 0, w: CGFloat(amount))
        guard let scaledBloom = blurColorMat.outputImage else { return image }
        addBlend.setValue(image,       forKey: kCIInputImageKey)
        addBlend.setValue(scaledBloom, forKey: kCIInputBackgroundImageKey)
        return addBlend.outputImage ?? image
    }
}
