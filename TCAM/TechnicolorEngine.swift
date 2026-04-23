//
//  TechnicolorEngine.swift
//  TCAM - Balanced Color Profiles
//
//  All CIFilter objects are cached — allocated once, reused every frame.
//  `nonisolated(unsafe)` is correct here: all accesses happen exclusively on the
//  serial filterQueue owned by CameraManager, which provides the necessary mutual exclusion.

import CoreImage
import CoreImage.CIFilterBuiltins

final class TechnicolorEngine: Sendable {

    let context: CIContext = {
        CIContext(options: [
            .useSoftwareRenderer: false,
            .workingColorSpace:  CGColorSpace(name: CGColorSpace.displayP3) as Any,
            .outputColorSpace:   CGColorSpace(name: CGColorSpace.displayP3) as Any
        ])
    }()

    // MARK: - Three-Strip Filters (KEEP WARM/ORANGE SIGNATURE)
    nonisolated(unsafe) private let ccThree  = CIFilter.colorControls()
    nonisolated(unsafe) private let cmThree  = CIFilter.colorMatrix()
    nonisolated(unsafe) private let vigThree = CIFilter.vignette()

    // MARK: - Two-Strip Filters (REDUCED ORANGE)
    nonisolated(unsafe) private let cmTwo    = CIFilter.colorMatrix()
    nonisolated(unsafe) private let ccTwo    = CIFilter.colorControls()
    nonisolated(unsafe) private let vigTwo   = CIFilter.vignette()

    // MARK: - Monopack Filters (KEEP WARM/ORANGE SIGNATURE)
    nonisolated(unsafe) private let ccMono   = CIFilter.colorControls()
    nonisolated(unsafe) private let cmMono   = CIFilter.colorMatrix()
    nonisolated(unsafe) private let gamMono  = CIFilter(name: "CIGammaAdjust")
    nonisolated(unsafe) private let vigMono  = CIFilter.vignette()

    // MARK: - Vivid Filters (REDUCED ORANGE)
    nonisolated(unsafe) private let ccVivid  = CIFilter.colorControls()
    nonisolated(unsafe) private let cmVivid  = CIFilter.colorMatrix()
    nonisolated(unsafe) private let vigVivid = CIFilter.vignette()

    // MARK: - Halation (bloom) filters — cached, never re-allocated per frame
    nonisolated(unsafe) private let blurFilter   = CIFilter.gaussianBlur()
    nonisolated(unsafe) private let blurMultiply = CIFilter(name: "CIMultiplyCompositing")!
    nonisolated(unsafe) private let blurColorMat = CIFilter.colorMatrix()
    nonisolated(unsafe) private let addBlend     = CIFilter(name: "CIAdditionCompositing")!

    init() {
        // ─────────────────────────────────────────────────────────────
        // THREE-STRIP: Keep signature warm/orange Technicolor look ✅
        // ─────────────────────────────────────────────────────────────
        ccThree.saturation = 1.55; ccThree.brightness = 0.02; ccThree.contrast = 1.12
        cmThree.rVector    = CIVector(x: 1.18,  y: 0.0,   z: -0.05, w: 0)
        cmThree.gVector    = CIVector(x: 0.0,   y: 0.92,  z: 0.04,  w: 0)
        cmThree.bVector    = CIVector(x: 0.0,   y: 0.0,   z: 0.88,  w: 0)
        cmThree.aVector    = CIVector(x: 0,     y: 0,     z: 0,     w: 1)
        cmThree.biasVector = CIVector(x: 0.015, y: 0.01,  z: 0.0,   w: 0)  // Subtle warm bias
        vigThree.intensity = 0.45; vigThree.radius = 1.6

        // ─────────────────────────────────────────────────────────────
        // TWO-STRIP: REDUCED ORANGE — more neutral, cyan-leaning vintage
        // ─────────────────────────────────────────────────────────────
        cmTwo.rVector    = CIVector(x: 1.05,  y: 0.02,  z: 0.0,   w: 0)   // ↓ Red boost
        cmTwo.gVector    = CIVector(x: 0.02,  y: 0.98,  z: -0.02, w: 0)   // ↑ Green fidelity
        cmTwo.bVector    = CIVector(x: -0.02, y: -0.02, z: 1.12,  w: 0)   // ↑ Blue for balance
        cmTwo.aVector    = CIVector(x: 0,     y: 0,     z: 0,     w: 1)
        cmTwo.biasVector = CIVector(x: -0.01, y: 0.0,   z: 0.015, w: 0)   // Slight cyan bias (counteracts orange)
        ccTwo.saturation = 1.15; ccTwo.brightness = 0.0; ccTwo.contrast = 1.05  // ↓ Saturation
        vigTwo.intensity = 0.5; vigTwo.radius = 1.5

        // ─────────────────────────────────────────────────────────────
        // MONOPACK: Keep warm/orange signature ✅
        // ─────────────────────────────────────────────────────────────
        ccMono.saturation = 1.25; ccMono.brightness = 0.03; ccMono.contrast = 1.05
        cmMono.rVector    = CIVector(x: 1.08, y: 0.0,  z: 0.0, w: 0)
        cmMono.gVector    = CIVector(x: 0.0,  y: 1.0,  z: 0.0, w: 0)
        cmMono.bVector    = CIVector(x: 0.0,  y: 0.0,  z: 0.9, w: 0)
        cmMono.aVector    = CIVector(x: 0,    y: 0,    z: 0,   w: 1)
        cmMono.biasVector = CIVector(x: 0.03, y: 0.02, z: 0.0, w: 0)  // Warm bias preserved
        gamMono?.setValue(0.88, forKey: "inputPower")
        vigMono.intensity = 0.35; vigMono.radius = 1.8

        // ─────────────────────────────────────────────────────────────
        // VIVID: REDUCED ORANGE — punchy but color-accurate
        // ─────────────────────────────────────────────────────────────
        ccVivid.saturation = 1.85; ccVivid.brightness = 0.0; ccVivid.contrast = 1.12  // ↓ Saturation from 2.1
        cmVivid.rVector    = CIVector(x: 1.12,  y: 0.0,   z: 0.0,   w: 0)   // ↓ Red channel boost
        cmVivid.gVector    = CIVector(x: 0.0,   y: 1.08,  z: 0.0,   w: 0)   // ↑ Green for balance
        cmVivid.bVector    = CIVector(x: 0.0,   y: 0.0,   z: 1.15,  w: 0)   // ↑ Blue for cool balance
        cmVivid.aVector    = CIVector(x: 0,     y: 0,     z: 0,     w: 1)
        cmVivid.biasVector = CIVector(x: -0.005, y: 0.005, z: 0.01, w: 0)  // Neutral-to-cool bias
        vigVivid.intensity = 0.25; vigVivid.radius = 2.2

        // Halation setup (shared)
        blurFilter.radius = 12
        blurColorMat.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
    }

    func apply(_ process: TechnicolorProcess, to image: CIImage) -> CIImage {
        switch process {
        case .threeStrip: threeStrip(image)
        case .twoStrip:   twoStrip(image)
        case .monopack:   monopack(image)
        case .vivid:      vivid(image)
        }
    }

    // MARK: - Private Process Methods

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
        return halation(img, amount: 0.10)  // Slightly reduced halation for cleaner look
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

    private func vivid(_ image: CIImage) -> CIImage {
        ccVivid.inputImage = image
        var img = ccVivid.outputImage ?? image
        cmVivid.inputImage = img;  img = cmVivid.outputImage  ?? img
        vigVivid.inputImage = img; img = vigVivid.outputImage ?? img
        return halation(img, amount: 0.12)  // Balanced halation
    }

    /// Additive halation (bloom) glow.
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
