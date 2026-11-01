import SwiftUI
import PhotosUI
import Photos
import Foundation

private struct OriginalStock: Identifiable, Hashable {
    let id: String
    let name: String
    let support: String
    let recommendedPaper: String

    var chineseName: String {
        var result = name
        let brands: [(String, String)] = [
            ("Fujifilm", "富士"), ("Fuji", "富士"),
            ("Kodak", "柯达"), ("Ilford", "伊尔福"),
            ("Agfa", "爱克发"), ("CineStill", "电影卷 CineStill"),
            ("Harman", "哈曼"), ("Foma", "福马"),
            ("Rollei", "禄来"), ("Adox", "爱多士"),
            ("Konica", "柯尼卡"), ("Ferrania", "费拉尼亚"),
            ("Lomography", "乐魔"), ("Polaroid", "宝丽来")
        ]
        for (english, chinese) in brands {
            result = result.replacingOccurrences(of: english, with: chinese,
                options: [.caseInsensitive])
        }
        let key = id.lowercased()
        if support == "paper" {
            return result + " · 相纸"
        }
        if key.contains("portra") || key.contains("400h") {
            return result + " · 人像负片"
        }
        if key.contains("vision") || key.contains("500t") || key.contains("250d") {
            return result + " · 电影负片"
        }
        if key.contains("hp5") || key.contains("tri_x") || key.contains("delta") || key.contains("tmax") {
            return result + " · 黑白胶片"
        }
        return result + " · 胶片"
    }

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

private enum EditorTab: String, CaseIterable {
    case film = "胶片"
    case adjustments = "精细调整"
    case edges = "胶片边框"
    var icon: String {
        switch self {
        case .film: return "camera.filters"
        case .adjustments: return "slider.horizontal.3"
        case .edges: return "rectangle.on.rectangle"
        }
    }
}

struct OriginalEngineEditorView: View {
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var input: UIImage?
    @State private var developed: UIImage?
    @State private var stocks: [OriginalStock] = []
    @State private var filmStock = "kodak_portra_400"
    @State private var paperStock = "kodak_supra_endura"
    @State private var filmEdge = false
    @State private var edgeFormat = "135"
    @State private var exposureEV = 0.0
    @State private var grainAmount = 1.0
    @State private var halationAmount = 1.0
    @State private var magentaFilter = 0.0
    @State private var yellowFilter = 0.0
    @State private var processing = false
    @State private var exporting = false
    @State private var queuedExport = false
    @State private var activeTab: EditorTab = .film
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
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // The preview is outside the scrollable editor. It remains
                    // visible while dragging any of the darkroom controls.
                    previewPanel
                        .frame(height: max(205, min(geometry.size.height * 0.42, 370)))

                    Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                    tabBar
                    Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            switch activeTab {
                            case .film: filmPanel
                            case .adjustments: adjustmentsPanel
                            case .edges: edgesPanel
                            }
                            Text(status)
                                .font(.footnote)
                                .foregroundStyle(status.hasPrefix("失败") ? .red : .secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("原版 SpektraLab 光谱胶片引擎 · GPL-3.0-or-later")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxHeight: .infinity)

                    bottomBar
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .background(Color(red: 0.055, green: 0.055, blue: 0.065))
            .foregroundStyle(.white)
            .navigationTitle("SpektraLab")
            .navigationBarTitleDisplayMode(.inline)
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

    private var previewPanel: some View {
        GeometryReader { area in
            ZStack {
                Color.black
                if let image = activeImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: area.size.width, height: area.size.height)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.artframe")
                            .font(.system(size: 42, weight: .ultraLight))
                            .foregroundStyle(.white.opacity(0.45))
                        Text("导入照片开始胶片冲印")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                VStack {
                    HStack {
                        Text("实时预览")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.black.opacity(0.55), in: Capsule())
                        Spacer()
                        if developed != nil {
                            Button {
                                showInput.toggle()
                            } label: {
                                Label(showInput ? "返回效果" : "对比原图",
                                      systemImage: "square.on.square")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(.black.opacity(0.65), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Spacer()
                    if processing {
                        HStack(spacing: 8) {
                            ProgressView().tint(.orange)
                            Text(exporting ? "正在导出…" : "正在更新胶片预览…")
                                .font(.caption)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.black.opacity(0.72), in: Capsule())
                    }
                }
                .padding(12)
            }
            .clipped()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(EditorTab.allCases, id: \.self) { tab in
                Button {
                    activeTab = tab
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: tab.icon).font(.system(size: 17))
                        Text(tab.rawValue).font(.caption.weight(.medium))
                    }
                    .foregroundStyle(activeTab == tab ? Color.orange : Color.white.opacity(0.64))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(activeTab == tab ? Color.orange.opacity(0.11) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private var filmPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("胶片模拟").font(.headline)
                    Text("选择胶片与相纸，照片会自动更新")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("重新显影") {
                    schedulePreview(immediate: true)
                }
                .font(.caption.weight(.semibold))
                .disabled(input == nil)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("胶片类型").font(.subheadline.weight(.semibold))
                Picker("胶片类型", selection: $filmStock) {
                    if stocks.filter({ $0.support == "film" }).isEmpty {
                        Text("柯达 Portra 400 · 人像负片").tag("kodak_portra_400")
                    } else {
                        ForEach(stocks.filter { $0.support == "film" }) { stock in
                            Text(stock.chineseName).tag(stock.id)
                        }
                    }
                }
                .pickerStyle(.menu)
                .tint(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 10) {
                Text("相纸类型").font(.subheadline.weight(.semibold))
                Picker("相纸类型", selection: $paperStock) {
                    if stocks.filter({ $0.support == "paper" }).isEmpty {
                        Text("柯达 Supra Endura · 相纸").tag("kodak_supra_endura")
                    } else {
                        ForEach(stocks.filter { $0.support == "paper" }) { stock in
                            Text(stock.chineseName).tag(stock.id)
                        }
                    }
                }
                .pickerStyle(.menu)
                .tint(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var adjustmentsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("精细调整").font(.headline)
                    Text("松开滑块后自动精确显影，预览始终固定在上方")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("重置") {
                    exposureEV = 0
                    grainAmount = 1
                    halationAmount = 1
                    magentaFilter = 0
                    yellowFilter = 0
                    schedulePreview(immediate: true)
                }
                .font(.subheadline.weight(.semibold))
                .tint(.orange)
            }
            VStack(spacing: 18) {
                darkroomSlider("曝光补偿", subtitle: "控制负片曝光 · EV",
                               value: $exposureEV, range: -2...2)
                darkroomSlider("胶片颗粒", subtitle: "原版胶片颗粒强度",
                               value: $grainAmount, range: 0...2)
                darkroomSlider("光晕效果", subtitle: "高光周围的胶片晕光",
                               value: $halationAmount, range: 0...4)
                darkroomSlider("洋红滤镜", subtitle: "洋红 ↔ 绿色",
                               value: $magentaFilter, range: -1...1)
                darkroomSlider("黄色滤镜", subtitle: "黄色 ↔ 蓝色",
                               value: $yellowFilter, range: -1...1)
            }
            .padding(14)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var edgesPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("胶片边框").font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $filmEdge) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("显示胶片边框").font(.subheadline.weight(.semibold))
                        Text("在预览与导出图片中添加边框")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tint(.orange)
                if filmEdge {
                    Divider().overlay(.white.opacity(0.15))
                    Picker("胶片画幅", selection: $edgeFormat) {
                        ForEach(edgeOptions, id: \.0) { option in
                            Text(option.1).tag(option.0)
                        }
                    }
                    .tint(.orange)
                    Text("稳定性保护：当前使用安全绘制的胶片边框。原版引擎边框待修复后再启用。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                Label("导入", systemImage: "photo.on.rectangle")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity).frame(height: 42)
            }
            .buttonStyle(.bordered)
            .tint(.white)
            Button {
                requestExport()
            } label: {
                HStack(spacing: 7) {
                    if exporting { ProgressView().tint(.black) }
                    else { Image(systemName: "square.and.arrow.down") }
                    Text(queuedExport ? "等待导出" : "保存照片")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity).frame(height: 42)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(input == nil || exporting || queuedExport)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(Color(white: 0.105))
    }

    private func darkroomSlider(_ name: String, subtitle: String,
                                value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.orange)
            }
            Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            Slider(value: value, in: range, onEditingChanged: { editing in
                if !editing { schedulePreview(immediate: true) }
            })
            .tint(.orange)
        }
    }

    private func schedulePreview(immediate: Bool = false) {
        previewRevision += 1
        let revision = previewRevision
        pendingPreview?.cancel()
        guard input != nil, !queuedExport, !exporting else { return }
        status = "调整已应用，正在刷新预览…"
        // If a native render is in flight, the revision check in its completion
        // queues exactly one new render with the latest slider values.
        guard !processing else { return }
        pendingPreview = Task { @MainActor in
            if !immediate {
                try? await Task.sleep(nanoseconds: 280_000_000)
            }
            guard !Task.isCancelled, revision == previewRevision else { return }
            develop(maxDimension: 800, saveAfter: false)
        }
    }

    private func requestExport() {
        guard input != nil, !exporting else { return }
        pendingPreview?.cancel()
        queuedExport = true
        previewRevision += 1
        if !processing {
            queuedExport = false
            develop(maxDimension: 1600, saveAfter: true)
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
                    status = saved ? "照片已成功保存到相册" : "失败：保存到相册失败（\(error?.localizedDescription ?? "未知错误")）"
                }
            })
        }
    }

    private func develop(maxDimension: Int, saveAfter: Bool) {
        guard let source = input, !processing else { return }
        processing = true
        exporting = saveAfter
        let revisionAtStart = previewRevision
        status = saveAfter ? "正在生成高清照片…" : "正在使用原版光谱引擎显影…"
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
            let nativeMessage = NSMutableString(string: "")
            // Native overscan has caused device crashes. Keep the original
            // film/paper render and compose a safe border after rendering.
            let renderedImage = OriginalFilmRenderer.renderImageWithoutThrow(
                source, filmStock: film, printStock: paper,
                enableEdge: false, edgeFormat: format,
                exposureEV: exposure, grainAmount: grain, halationAmount: halation,
                magenta: magenta, yellow: yellow,
                maxDimension: maxDimension, errorMessage: nativeMessage)
            let result = renderedImage.flatMap {
                edges ? Self.safeFilmBorder($0, format: format, filmName: film) : $0
            }
            let renderFailure = nativeMessage.length > 0 ? (nativeMessage as String) : nil
            DispatchQueue.main.async {
                processing = false
                exporting = false
                if queuedExport {
                    queuedExport = false
                    develop(maxDimension: 1600, saveAfter: true)
                    return
                }
                if !saveAfter && revisionAtStart != previewRevision {
                    schedulePreview(immediate: true)
                    return
                }
                if let result {
                    developed = result
                    showInput = false
                    if saveAfter {
                        status = "渲染完成，正在保存到相册…"
                        saveToPhotos(result)
                    } else {
                        status = "预览已更新"
                    }
                } else {
                    status = "失败：" + (renderFailure ?? "原版引擎无法完成显影")
                }
                // A parameter edit made during export still gets a new preview.
                if saveAfter && revisionAtStart != previewRevision {
                    schedulePreview()
                }
            }
        }
    }

    // Safe, CPU-drawn border until the upstream overscan Metal path can be
    // diagnosed on a physical iPhone. Not represented as the original border.
    private static func safeFilmBorder(_ image: UIImage, format: String,
                                       filmName: String) -> UIImage {
        let width = image.size.width
        let height = image.size.height
        let landscape = width >= height
        let band = max(24, min(width, height) * 0.095)
        let canvas = landscape ? CGSize(width: width, height: height + band * 2)
                               : CGSize(width: width + band * 2, height: height)
        let photoRect = landscape ? CGRect(x: 0, y: band, width: width, height: height)
                                  : CGRect(x: band, y: 0, width: width, height: height)
        let settings = UIGraphicsImageRendererFormat.default()
        settings.scale = 1
        settings.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvas, format: settings)
        return renderer.image { _ in
            UIColor(red: 0.085, green: 0.075, blue: 0.065, alpha: 1).setFill()
            UIRectFill(CGRect(origin: .zero, size: canvas))
            image.draw(in: photoRect)
            if format.hasPrefix("135") {
                let length = landscape ? width : height
                let count = max(4, Int(length / 42))
                let holeLong = max(9, band * 0.42)
                let holeShort = max(6, band * 0.26)
                UIColor(white: 0.76, alpha: 1).setFill()
                for i in 0..<count {
                    let along = (CGFloat(i) + 0.5) * length / CGFloat(count)
                    for side in 0..<2 {
                        let rect: CGRect
                        if landscape {
                            rect = CGRect(x: along - holeLong / 2,
                                          y: side == 0 ? (band - holeShort) / 2
                                                       : band + height + (band - holeShort) / 2,
                                          width: holeLong, height: holeShort)
                        } else {
                            rect = CGRect(x: side == 0 ? (band - holeShort) / 2
                                                       : band + width + (band - holeShort) / 2,
                                          y: along - holeLong / 2,
                                          width: holeShort, height: holeLong)
                        }
                        UIBezierPath(roundedRect: rect, cornerRadius: holeShort * 0.2).fill()
                    }
                }
            }
        }
    }
}
