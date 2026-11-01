import Foundation
import UIKit
import CoreImage

/// iOS post-development grading stage. The original macOS editor performs
/// this as a separate Layer 2 Metal pass after the spectral film/print engine.
/// This Core Image implementation keeps the stage independent and applies the
/// same edit snapshot to both the preview and the saved export. Its transfer
/// functions are not yet bit-exact with the macOS Layer 2 shader.
struct PostDevelopmentGrade: Sendable {
    var enabled = true
    var temperature = 0.0       // -100...100
    var tint = 0.0              // -100...100
    var exposure = 0.0          // -3...3 EV
    var contrast = 0.0          // -50...50
    var brightness = 0.0        // -50...50
    var saturation = 0.0        // -100...100
    var vibrance = 0.0         // -100...100
    var sharpness = 0.0        // 0...100
    var clarity = 0.0          // -100...100
    var highlights = 0.0       // -100...100
    var shadows = 0.0          // -100...100
    var blackPoint = 0.0       // 0...50
    var whitePoint = 0.0       // 0...50
    var vignette = 0.0         // -100...100, negative darkens
    var vignetteMidpoint = 50.0

    var isNeutral: Bool {
        !enabled || (temperature == 0 && tint == 0 && exposure == 0 &&
        contrast == 0 && brightness == 0 && saturation == 0 && vibrance == 0 && sharpness == 0 && clarity == 0 &&
        highlights == 0 && shadows == 0 && blackPoint == 0 &&
        whitePoint == 0 && vignette == 0)
    }
}

enum OriginalPostProcessor {
    // Reuse the context: constructing a CIContext for every preview can
    // transiently allocate substantial Metal resources on iPhone.
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func apply(_ grade: PostDevelopmentGrade, to image: UIImage) -> UIImage? {
        guard !grade.isNeutral else { return image }
        guard let cg = image.cgImage else { return nil }
        var output = CIImage(cgImage: cg)
        let extent = output.extent

        func run(_ name: String, _ parameters: [String: Any]) {
            guard let filter = CIFilter(name: name) else { return }
            filter.setValue(output, forKey: kCIInputImageKey)
            for (key, value) in parameters { filter.setValue(value, forKey: key) }
            if let next = filter.outputImage { output = next.cropped(to: extent) }
        }

        if grade.temperature != 0 || grade.tint != 0 {
            // Scan-stage channel balance; preserve alpha.
            let warm = grade.temperature / 100.0 * 0.18
            let magenta = grade.tint / 100.0 * 0.16
            run("CIColorMatrix", [
                "inputRVector": CIVector(x: 1 + warm + magenta * 0.5, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1 - magenta, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1 - warm + magenta * 0.5, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        }
        if grade.exposure != 0 {
            run("CIExposureAdjust", [kCIInputEVKey: grade.exposure])
        }
        if grade.contrast != 0 || grade.brightness != 0 || grade.saturation != 0 {
            run("CIColorControls", [
                kCIInputContrastKey: max(0.1, 1 + grade.contrast / 100),
                kCIInputBrightnessKey: grade.brightness / 200,
                kCIInputSaturationKey: max(0, 1 + grade.saturation / 100)
            ])
        }
        if grade.vibrance != 0 {
            run("CIVibrance", ["inputAmount": grade.vibrance / 100])
        }
        if grade.clarity > 0 {
            run("CIUnsharpMask", [
                "inputRadius": 2.5,
                "inputIntensity": grade.clarity / 100 * 0.9
            ])
        } else if grade.clarity < 0 {
            // Blend a small-radius blur instead of simply clamping negative
            // clarity to zero. Cropping prevents blurred edge pixels leaking.
            let blurred = output
                .clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [
                    kCIInputRadiusKey: 1.3
                ])
                .cropped(to: extent)
            if let soften = CIFilter(name: "CIDissolveTransition") {
                soften.setValue(output, forKey: kCIInputImageKey)
                soften.setValue(blurred, forKey: "inputTargetImage")
                soften.setValue(min(0.65, -grade.clarity / 100 * 0.65), forKey: "inputTime")
                if let next = soften.outputImage {
                    output = next.cropped(to: extent)
                }
            }
        }
        if grade.sharpness != 0 {
            run("CISharpenLuminance", ["inputSharpness": grade.sharpness / 100 * 1.5])
        }
        if grade.highlights != 0 || grade.shadows != 0 {
            run("CIHighlightShadowAdjust", [
                "inputHighlightAmount": min(1, max(0, 1 + grade.highlights / 100)),
                "inputShadowAmount": min(1, max(-1, grade.shadows / 100))
            ])
        }
        if grade.blackPoint != 0 || grade.whitePoint != 0 {
            let black = grade.blackPoint / 100
            let white = 1 - grade.whitePoint / 100
            let gain = 1 / max(0.1, white - black)
            let bias = -black * gain
            run("CIColorMatrix", [
                "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: gain, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: gain, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0)
            ])
        }
        if grade.vignette != 0 {
            run("CIVignette", [
                kCIInputIntensityKey: -grade.vignette / 100 * 2,
                kCIInputRadiusKey: max(0.1, grade.vignetteMidpoint / 50)
            ])
        }
        guard let result = context.createCGImage(output, from: extent) else { return nil }
        return UIImage(cgImage: result, scale: 1, orientation: .up)
    }
}
