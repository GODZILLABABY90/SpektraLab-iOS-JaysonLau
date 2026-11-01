import SwiftUI
import PhotosUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

struct EditorView: View {
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var sourceImage: UIImage?
    @State private var previewImage: UIImage?
    @State private var exposure: Double = 0
    @State private var contrast: Double = 1
    @State private var saturation: Double = 1
    @State private var warmth: Double = 0
    @State private var grain: Double = 0
    @State private var isExporting = false
    @State private var status = "Select an image to begin"
    private let renderer = FilmPreviewRenderer()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Group {
                        if let previewImage {
                            Image(uiImage: previewImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .accessibilityLabel("Edited image preview")
                        } else {
                            ContentUnavailableView("No photo selected", systemImage: "photo",
                                                   description: Text("Import a photo to start editing."))
                                .frame(minHeight: 280)
                        }
                    }
                    .background(Color.black.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Import photo", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    VStack(spacing: 14) {
                        control("Exposure", value: $exposure, range: -2...2, format: "%.2f EV")
                        control("Contrast", value: $contrast, range: 0.5...1.8, format: "%.2f")
                        control("Saturation", value: $saturation, range: 0...2, format: "%.2f")
                        control("Warmth", value: $warmth, range: -1...1, format: "%.2f")
                        control("Grain (preview)", value: $grain, range: 0...0.6, format: "%.2f")
                    }
                    .disabled(sourceImage == nil)

                    HStack {
                        Button("Reset") { reset() }
                            .disabled(sourceImage == nil)
                        Spacer()
                        Button {
                            exportImage()
                        } label: {
                            Label("Save to Photos", systemImage: "square.and.arrow.down")
                        }
                        .disabled(sourceImage == nil || isExporting)
                    }
                    .buttonStyle(.bordered)

                    Text(status).font(.footnote).foregroundStyle(.secondary)
                    Text("Prototype: Core Image controls only. Original SpektraLab spectral engine is not yet ported.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("SpektraLab iOS")
            .onChange(of: selectedPhoto) { item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else {
                        status = "Unable to import this photo"
                        return
                    }
                    sourceImage = image
                    status = "Photo loaded"
                    refreshPreview()
                }
            }
            .onChange(of: exposure) { _ in refreshPreview() }
            .onChange(of: contrast) { _ in refreshPreview() }
            .onChange(of: saturation) { _ in refreshPreview() }
            .onChange(of: warmth) { _ in refreshPreview() }
            .onChange(of: grain) { _ in refreshPreview() }
        }
    }

    private func control(_ name: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(name)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private func reset() {
        exposure = 0
        contrast = 1
        saturation = 1
        warmth = 0
        grain = 0
        refreshPreview()
    }

    private func refreshPreview() {
        guard let sourceImage else { return }
        previewImage = renderer.render(sourceImage, exposure: exposure,
                                       contrast: contrast, saturation: saturation,
                                       warmth: warmth, grain: grain,
                                       maxDimension: 1400)
    }

    private func exportImage() {
        guard let sourceImage else { return }
        isExporting = true
        status = "Rendering full resolution…"
        let output = renderer.render(sourceImage, exposure: exposure,
                                     contrast: contrast, saturation: saturation,
                                     warmth: warmth, grain: grain,
                                     maxDimension: nil)
        guard let output else {
            status = "Render failed"
            isExporting = false
            return
        }
        UIImageWriteToSavedPhotosAlbum(output, nil, nil, nil)
        status = "Save requested. Check Photos and grant permission if prompted."
        isExporting = false
    }
}

final class FilmPreviewRenderer {
    private let context = CIContext()

    func render(_ image: UIImage, exposure: Double, contrast: Double,
                saturation: Double, warmth: Double, grain: Double,
                maxDimension: CGFloat?) -> UIImage? {
        guard var input = CIImage(image: image) else { return nil }
        if let maxDimension {
            let scale = min(1, maxDimension / max(input.extent.width, input.extent.height))
            if scale < 1 {
                input = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }
        }

        let exposureFilter = CIFilter.exposureAdjust()
        exposureFilter.inputImage = input
        exposureFilter.ev = Float(exposure)
        guard let exposed = exposureFilter.outputImage else { return nil }

        let color = CIFilter.colorControls()
        color.inputImage = exposed
        color.contrast = Float(contrast)
        color.saturation = Float(saturation)
        guard let colored = color.outputImage else { return nil }

        let temperature = CIFilter.temperatureAndTint()
        temperature.inputImage = colored
        temperature.neutral = CIVector(x: 6500, y: 0)
        temperature.targetNeutral = CIVector(x: 6500 - warmth * 2000, y: 0)
        guard var result = temperature.outputImage else { return nil }

        if grain > 0 {
            let noise = CIFilter.randomGenerator().outputImage?
                .cropped(to: result.extent)
            if let noise {
                let monochrome = CIFilter.colorMatrix()
                monochrome.inputImage = noise
                monochrome.rVector = CIVector(x: 0.333, y: 0.333, z: 0.333, w: 0)
                monochrome.gVector = monochrome.rVector
                monochrome.bVector = monochrome.rVector
                monochrome.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
                monochrome.biasVector = CIVector(x: -0.5, y: -0.5, z: -0.5, w: 1)
                if let gray = monochrome.outputImage {
                    let addition = CIFilter.additionCompositing()
                    let amplitude = CIFilter.colorMatrix()
                    amplitude.inputImage = gray
                    let amount = CGFloat(grain) * 0.13
                    amplitude.rVector = CIVector(x: amount, y: 0, z: 0, w: 0)
                    amplitude.gVector = CIVector(x: 0, y: amount, z: 0, w: 0)
                    amplitude.bVector = CIVector(x: 0, y: 0, z: amount, w: 0)
                    amplitude.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
                    amplitude.biasVector = CIVector(x: 0, y: 0, z: 0, w: 1)
                    addition.inputImage = amplitude.outputImage
                    addition.backgroundImage = result
                    result = addition.outputImage?.cropped(to: result.extent) ?? result
                }
            }
        }

        guard let cgImage = context.createCGImage(result, from: result.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
    }
}
