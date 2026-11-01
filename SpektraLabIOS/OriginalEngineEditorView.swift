import SwiftUI
import PhotosUI
import Photos
import Foundation

private struct OriginalStock: Identifiable, Hashable {
    let id: String
    let name: String
    let support: String
    let recommendedPaper: String

    static func load() -> [OriginalStock] {
        guard let folder = Bundle.main.url(forResource: "OriginalEngineResources", withExtension: nil)?
            .appendingPathComponent("profiles", isDirectory: true),
              let urls = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        return urls.compactMap { url -> OriginalStock? in
            guard url.pathExtension.lowercased() == "json",
                  let data = try? Data(contentsOf: url),
                  let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let info = dictionary["info"] as? [String: Any],
                  let id = info["stock"] as? String,
                  let name = info["name"] as? String,
                  let support = info["support"] as? String,
                  support == "film" || support == "paper" else { return nil }
            return OriginalStock(id: id, name: name, support: support,
                                 recommendedPaper: info["target_print"] as? String ?? "")
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

struct OriginalEngineEditorView: View {
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var input: UIImage?
    @State private var developed: UIImage?
    @State private var stocks: [OriginalStock] = []
    @State private var filmStock = "kodak_portra_400"
    @State private var paperStock = "kodak_portra_endura"
    @State private var filmEdge = false
    @State private var edgeFormat = "135"
    @State private var exposureEV = 0.0
    @State private var grainAmount = 1.0
    @State private var halationAmount = 1.0
    @State private var magentaFilter = 0.0
    @State private var yellowFilter = 0.0
    @State private var processing = false
    @State private var previewRevision = 0
    @State private var pendingPreview: Task<Void, Never>?
    @State private var showInput = false
    @State private var status = "导入照片，使用原版光谱引擎冲印"

    private let edgeOptions: [(String, String)] = [
        ("135", "35mm"), ("135_half", "半格"),
        ("120_645", "120 · 645"), ("120_6x6", "120 · 6×6"),
        ("120_6x7", "120 · 6×7"), ("120_6x8", "120 · 6×8"),
        ("120_6x9", "120 · 6×9")
    ]

    private var activeImage: UIImage? {
        if showInput { return input }
        return developed ?? input
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 19) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(white: 0.1))
                        if let image = activeImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            ContentUnavailableView("选择一张照片", systemImage: "photo",
                                description: Text("从相册导入，使用原版胶片与相纸模型模拟显影"))
                                .frame(minHeight: 290)
                        }
                    }
                    .frame(minHeight: 230)
                    .overlay(alignment: .topTrailing) {
                        if developed != nil {
                            Button(showInput ? "原图" : "显影结果") {
                                showInput.toggle()
                            }
                            .font(.caption.weight(.medium))
                            .padding(8)
                            .background(.black.opacity(0.72))
                            .clipShape(Capsule())
                            .padding(12)
                        }
                    }

                    PhotosPicker(selection: $pickedPhoto, matching: .images) {
                        Label("导入照片", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Text("ORIGINAL FILM & PRINT")
                        .font(.caption.weight(.semibold)).tracking(2)
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 15) {
                        Picker("胶片", selection: $filmStock) {
                            if stocks.filter({ $0.support == "film" }).isEmpty {
                                Text("Kodak Portra 400").tag("kodak_portra_400")
                            } else {
                                ForEach(stocks.filter { $0.support == "film" }) { stock in
                                    Text(stock.name).tag(stock.id)
                                }
                            }
                        }
                        Picker("相纸", selection: $paperStock) {
                            if stocks.filter({ $0.support == "paper" }).isEmpty {
                                Text("Kodak Portra Endura").tag("kodak_portra_endura")
                            } else {
                                ForEach(stocks.filter { $0.support == "paper" }) { stock in
                                    Text(stock.name).tag(stock.id)
                                }
                            }
                        }
                        Toggle("原版 Film Edge 胶片边缘", isOn: $filmEdge)
                            .tint(.orange)
                        if filmEdge {
                            Picker("胶片画幅", selection: $edgeFormat) {
                                ForEach(edgeOptions, id: \.0) { option in
                                    Text(option.1).tag(option.0)
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 12))

                    Text("DARKROOM ADJUSTMENTS")
                        .font(.caption.weight(.semibold)).tracking(2)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 10) {
                        darkroomSlider("相机曝光", value: $exposureEV, range: -2...2)
                        darkroomSlider("真实胶片颗粒", value: $grainAmount, range: 0...2)
                        darkroomSlider("胶片光晕 Halation", value: $halationAmount, range: 0...4)
                        darkroomSlider("放大机洋红滤镜", value: $magentaFilter, range: -1...1)
                        darkroomSlider("放大机黄色滤镜", value: $yellowFilter, range: -1...1)
                    }
                    .padding(14)
                    .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 12))

                    Button {
                        develop(maxDimension: 1800, saveAfter: false)
                    } label: {
                        HStack {
                            if processing { ProgressView().tint(.black) }
                            Text("使用原版引擎显影")
                            Spacer()
                            Image(systemName: "camera.filters")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(input == nil || processing)

                    Button {
                        develop(maxDimension: 2048, saveAfter: true)
                    } label: {
                        Label("安全导出到相册（最长边 2048px）",
                              systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(input == nil || processing)

                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(status.hasPrefix("失败") ? .red : .secondary)
                    Text("原版 SpektraLab C++ / Metal 引擎 · 81 波长光谱模拟 · GPL-3.0-or-later")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .background(.black)
            .foregroundStyle(.white)
            .navigationTitle("SpektraLab")
            .preferredColorScheme(.dark)
            .onAppear {
                stocks = OriginalStock.load()
                if !stocks.contains(where: { $0.id == filmStock && $0.support == "film" }),
                   let first = stocks.first(where: { $0.support == "film" }) {
                    filmStock = first.id
                }
                if !stocks.contains(where: { $0.id == paperStock && $0.support == "paper" }),
                   let first = stocks.first(where: { $0.support == "paper" }) {
                    paperStock = first.id
                }
            }
            .onChange(of: filmStock) { newStock in
                if let recommended = stocks.first(where: { $0.id == newStock })?.recommendedPaper,
                   stocks.contains(where: { $0.id == recommended && $0.support == "paper" }) {
                    paperStock = recommended
                }
                schedulePreview()
            }
            .onChange(of: paperStock) { _ in schedulePreview() }
            .onChange(of: filmEdge) { _ in schedulePreview() }
            .onChange(of: edgeFormat) { _ in schedulePreview() }
            .onChange(of: exposureEV) { _ in schedulePreview() }
            .onChange(of: grainAmount) { _ in schedulePreview() }
            .onChange(of: halationAmount) { _ in schedulePreview() }
            .onChange(of: magentaFilter) { _ in schedulePreview() }
            .onChange(of: yellowFilter) { _ in schedulePreview() }
            .onChange(of: pickedPhoto) { item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self),
                          let photo = UIImage(data: data) else {
                        status = "失败：无法读取照片"
                        return
                    }
                    input = photo
                    developed = nil
                    showInput = false
                    status = "照片已导入，正在生成预览…"
                    schedulePreview()
                }
            }
        }
    }

    private func darkroomSlider(_ name: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(name)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: value, in: range).tint(.orange)
        }
    }

    private func schedulePreview() {
        developed = nil
        previewRevision += 1
        let revision = previewRevision
        pendingPreview?.cancel()
        guard input != nil else { return }
        pendingPreview = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, revision == previewRevision else { return }
            if !processing { develop(maxDimension: 1000, saveAfter: false) }
        }
    }

    private func schedulePreviewAfterStaleRender() {
        pendingPreview?.cancel()
        pendingPreview = Task { @MainActor in
            guard input != nil else { return }
            develop(maxDimension: 1000, saveAfter: false)
        }
    }

    private func saveToPhotos(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { authorization in
            guard authorization == .authorized || authorization == .limited else {
                DispatchQueue.main.async { status = "失败：未获得照片保存权限" }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }, completionHandler: { saved, error in
                DispatchQueue.main.async {
                    status = saved ? "照片已成功保存到相册" : "失败：保存到相册失败（\\(error?.localizedDescription ?? "未知错误")）"
                }
            })
        }
    }

    private func develop(maxDimension: Int, saveAfter: Bool) {
        guard let source = input, !processing else { return }
        if saveAfter {
            pendingPreview?.cancel()
            previewRevision += 1
        }
        processing = true
        let revisionAtStart = previewRevision
        status = "正在调用原版光谱渲染引擎…"
        let film = filmStock
        let paper = paperStock
        let edges = filmEdge
        let format = edgeFormat
        let exposure = exposureEV
        let grain = grainAmount
        let halation = halationAmount
        let magenta = magentaFilter
        let yellow = yellowFilter
        DispatchQueue.global(qos: .userInitiated).async {
            var failureMessage: String?
            var renderedImage: UIImage?
            do {
                renderedImage = try OriginalFilmRenderer.renderImage(
                source, filmStock: film, printStock: paper,
                enableEdge: edges, edgeFormat: format,
                exposureEV: exposure, grainAmount: grain, halationAmount: halation,
                magenta: magenta, yellow: yellow,
                maxDimension: maxDimension)
            } catch {
                failureMessage = error.localizedDescription
            }
            let result = renderedImage
            let renderFailure = failureMessage
            DispatchQueue.main.async {
                processing = false
                if revisionAtStart != previewRevision {
                    schedulePreviewAfterStaleRender()
                    return
                }
                if let result {
                    developed = result
                    showInput = false
                    if saveAfter {
                        status = "渲染完成，正在保存到相册…"
                        saveToPhotos(result)
                    } else {
                        status = "原版胶片 / 相纸渲染完成"
                    }
                } else {
                    status = "失败：" + (renderFailure ?? "原版引擎无法完成显影")
                }
            }
        }
    }
}
