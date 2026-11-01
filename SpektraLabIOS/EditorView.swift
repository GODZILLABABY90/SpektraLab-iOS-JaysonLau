import SwiftUI
import PhotosUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

private struct FilmPreset: Identifiable {
    let id: String
    let title: String
    let exposure: Float
    let contrast: Float
    let saturation: Float
    let warmth: Float
    let fade: Float

    static let all: [FilmPreset] = [
        .init(id: "neutral", title: "Original", exposure: 0, contrast: 1, saturation: 1, warmth: 0, fade: 0),
        .init(id: "portrait", title: "Soft Portrait", exposure: 0.12, contrast: 0.93, saturation: 0.89, warmth: 0.35, fade: 0.05),
        .init(id: "gold", title: "Golden Hour", exposure: 0.08, contrast: 1.10, saturation: 1.13, warmth: 0.65, fade: 0.04),
        .init(id: "cool", title: "Cool Negative", exposure: -0.06, contrast: 1.08, saturation: 0.91, warmth: -0.58, fade: 0.07),
        .init(id: "classic", title: "Classic Color", exposure: -0.08, contrast: 1.17, saturation: 0.81, warmth: 0.12, fade: 0.08),
        .init(id: "mono", title: "Silver Mono", exposure: 0.02, contrast: 1.22, saturation: 0, warmth: 0, fade: 0.03)
    ]
}

private enum FrameStyle: String, CaseIterable, Identifiable {
    case none = "None"
    case white = "White"
    case black = "Black"
    case instant = "Instant"
    case film35 = "35mm"
    var id: String { rawValue }
}

struct EditorView: View {
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var sourceImage: UIImage?
    @State private var previewImage: UIImage?
    @State private var presetID = "neutral"
    @State private var presetStrength = 1.0
    @State private var exposure = 0.0
    @State private var contrast = 1.0
    @State private var saturation = 1.0
    @State private var warmth = 0.0
    @State private var grain = 0.0
    @State private var vignette = 0.0
    @State private var frame: FrameStyle = .none
    @State private var isExporting = false
    @State private var status = "Import a photo to begin"
    private let renderer = FilmRenderer()

    private var preset: FilmPreset {
        FilmPreset.all.first(where: { $0.id == presetID }) ?? FilmPreset.all[0]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Group {
                        if let previewImage {
                            Image(uiImage: previewImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .accessibilityLabel("Film edit preview")
                        } else {
                            ContentUnavailableView("No photo selected", systemImage: "photo",
                                                   description: Text("Import an image to start editing."))
                                .frame(minHeight: 250)
                        }
                    }
                    .background(Color(white: 0.13))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Import photo", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("FILM LOOKS").font(.caption.weight(.bold)).tracking(2)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(FilmPreset.all) { look in
                                    Button {
                                        presetID = look.id
                                        refreshPreview()
                                    } label: {
                                        Text(look.title)
                                            .font(.subheadline.weight(.medium))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 11)
                                            .background(presetID == look.id ? Color.orange : Color(white: 0.19))
                                            .foregroundStyle(presetID == look.id ? Color.black : Color.white)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                        control("Preset strength", value: $presetStrength, range: 0...1, format: "%.0f%%", multiplier: 100)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("FILM FRAME").font(.caption.weight(.bold)).tracking(2)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(FrameStyle.allCases) { option in
                                    Button {
                                        frame = option
                                        refreshPreview()
                                    } label: {
                                        Text(option.rawValue)
                                            .font(.subheadline)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .background(frame == option ? Color.orange : Color(white: 0.19))
                                            .foregroundStyle(frame == option ? Color.black : Color.white)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("ADJUSTMENTS").font(.caption.weight(.bold)).tracking(2)
                        control("Exposure", value: $exposure, range: -2...2, format: "%.2f EV")
                        control("Contrast", value: $contrast, range: 0.5...1.8)
                        control("Saturation", value: $saturation, range: 0...2)
                        control("Warmth", value: $warmth, range: -1...1)
                        control("Grain", value: $grain, range: 0...0.7)
                        control("Vignette", value: $vignette, range: 0...1)
                    }
                    HStack {
                        Button("Reset") { reset() }
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
                    Text("Independent film-inspired prototype; not the original SpektraLab spectral engine.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
            }
            .background(Color.black)
            .foregroundStyle(.white)
            .navigationTitle("SpektraLab iOS")
            .toolbarBackground(Color.black, for: .navigationBar)
            .onChange(of: selectedPhoto) { item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else {
                        status = "Photo import failed"
                        return
                    }
                    sourceImage = image
                    status = "Photo loaded"
                    refreshPreview()
                }
            }
            .onChange(of: presetStrength) { _ in refreshPreview() }
            .onChange(of: exposure) { _ in refreshPreview() }
            .onChange(of: contrast) { _ in refreshPreview() }
            .onChange(of: saturation) { _ in refreshPreview() }
            .onChange(of: warmth) { _ in refreshPreview() }
            .onChange(of: grain) { _ in refreshPreview() }
            .onChange(of: vignette) { _ in refreshPreview() }
        }
        .preferredColorScheme(.dark)
    }

    private func control(_ title: String, value: Binding<Double>,
                         range: ClosedRange<Double>, format: String = "%.2f",
                         multiplier: Double = 1) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value.wrappedValue * multiplier))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
                .tint(.orange)
        }
    }

    private func reset() {
        presetID = "neutral"
        presetStrength = 1
        exposure = 0
        contrast = 1
        saturation = 1
        warmth = 0
        grain = 0
        vignette = 0
        frame = .none
        refreshPreview()
    }

    private func refreshPreview() {
        guard let sourceImage else { return }
        previewImage = renderer.render(sourceImage, preset: preset,
            strength: presetStrength, exposure: exposure, contrast: contrast,
            saturation: saturation, warmth: warmth, grain: grain,
            vignette: vignette, frame: frame, maxDimension: 1200)
    }

    private func exportImage() {
        guard let sourceImage else { return }
        isExporting = true
        status = "Rendering…"
        guard let output = renderer.render(sourceImage, preset: preset,
            strength: presetStrength, exposure: exposure, contrast: contrast,
            saturation: saturation, warmth: warmth, grain: grain,
            vignette: vignette, frame: frame, maxDimension: nil) else {
            status = "Render failed"
            isExporting = false
            return
        }
        UIImageWriteToSavedPhotosAlbum(output, nil, nil, nil)
        status = "Save requested; check Photos."
        isExporting = false
    }
}

private final class FilmRenderer {
    private let context = CIContext()

    func render(_ image: UIImage, preset: FilmPreset, strength: Double,
                exposure: Double, contrast: Double, saturation: Double,
                warmth: Double, grain: Double, vignette: Double,
                frame: FrameStyle, maxDimension: CGFloat?) -> UIImage? {
        guard var input = CIImage(image: image) else { return nil }
        if let maxDimension {
            let scale = min(1, maxDimension / max(input.extent.width, input.extent.height))
            if scale < 1 {
                input = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }
        }

        let amount = Float(strength)
        let ev = CIFilter.exposureAdjust()
        ev.inputImage = input
        ev.ev = Float(exposure) + preset.exposure * amount
        guard let exposed = ev.outputImage else { return nil }

        let colors = CIFilter.colorControls()
        colors.inputImage = exposed
        colors.contrast = Float(contrast) * (1 + (preset.contrast - 1) * amount)
        colors.saturation = Float(saturation) * (1 + (preset.saturation - 1) * amount)
        guard let colored = colors.outputImage else { return nil }

        let temp = CIFilter.temperatureAndTint()
        temp.inputImage = colored
        temp.neutral = CIVector(x: 6500, y: 0)
        temp.targetNeutral = CIVector(x: 6500 - CGFloat(Float(warmth) + preset.warmth * amount) * 1800, y: 0)
        guard var output = temp.outputImage else { return nil }

        let fade = CGFloat(preset.fade * amount)
        if fade > 0 {
            let tone = CIFilter.colorControls()
            tone.inputImage = output
            tone.brightness = Float(fade * 0.12)
            tone.contrast = Float(1 - fade * 0.45)
            output = tone.outputImage ?? output
        }

        if vignette > 0 {
            let v = CIFilter.vignette()
            v.inputImage = output
            v.intensity = Float(vignette * 1.5)
            v.radius = Float(min(output.extent.width, output.extent.height) * 0.6)
            output = v.outputImage ?? output
        }

        if grain > 0, let noise = CIFilter.randomGenerator().outputImage?.cropped(to: output.extent) {
            let gray = CIFilter.colorMatrix()
            gray.inputImage = noise
            let a = CGFloat(grain) * 0.18 / 3
            gray.rVector = CIVector(x: a, y: a, z: a, w: 0)
            gray.gVector = gray.rVector
            gray.bVector = gray.rVector
            gray.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
            gray.biasVector = CIVector(x: -CGFloat(grain) * 0.09, y: -CGFloat(grain) * 0.09,
                                      z: -CGFloat(grain) * 0.09, w: 1)
            let add = CIFilter.additionCompositing()
            add.inputImage = gray.outputImage
            add.backgroundImage = output
            output = add.outputImage?.cropped(to: output.extent) ?? output
        }

        guard let cg = context.createCGImage(output, from: output.extent) else { return nil }
        let result = UIImage(cgImage: cg)
        return addFrame(result, style: frame)
    }

    private func addFrame(_ image: UIImage, style: FrameStyle) -> UIImage {
        guard style != .none else { return image }
        let width = image.size.width
        let height = image.size.height
        let inset = max(12, width * (style == .instant ? 0.07 : 0.045))
        let bottom = style == .instant ? inset * 3.0 : inset
        let film35 = style == .film35
        let canvas = CGSize(width: width + inset * 2,
                            height: height + inset + bottom + (film35 ? inset * 1.3 : 0))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        return renderer.image { ctx in
            let bg: UIColor = (style == .white || style == .instant) ? .white : .black
            bg.setFill()
            ctx.fill(CGRect(origin: .zero, size: canvas))
            let top = inset + (film35 ? inset * 0.65 : 0)
            image.draw(in: CGRect(x: inset, y: top, width: width, height: height))
            if film35 {
                UIColor(white: 0.92, alpha: 1).setFill()
                let hole = inset * 0.34
                let spacing = max(hole * 2.3, width / 14)
                for x in stride(from: inset, through: canvas.width - inset - hole, by: spacing) {
                    ctx.fill(CGRect(x: x, y: inset * 0.25, width: hole, height: hole * 0.65))
                    ctx.fill(CGRect(x: x, y: top + height + inset * 0.22,
                                    width: hole, height: hole * 0.65))
                }
            }
        }
    }
}
