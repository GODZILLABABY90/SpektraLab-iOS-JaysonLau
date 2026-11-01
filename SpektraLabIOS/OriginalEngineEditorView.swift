import SwiftUI
import PhotosUI
import Photos
import Foundation
import UIKit

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

private enum OriginalMobileTheme {
    static let rail = Color(red: 45/255, green: 45/255, blue: 44/255)
    static let canvas = Color(red: 95/255, green: 95/255, blue: 95/255)
    static let ink = Color(red: 249/255, green: 247/255, blue: 243/255)
    static let muted = Color(red: 218/255, green: 216/255, blue: 212/255)
    static let accent = Color(red: 225/255, green: 169/255, blue: 95/255)
    static let line = Color(red: 181/255, green: 182/255, blue: 182/255).opacity(0.35)
}

private enum EditorTab: String, CaseIterable {
    case film = "胶片"
    case adjustments = "暗房"
    case texture = "质感"
    case edges = "片边"
    case post = "后期"
    var icon: String {
        switch self {
        case .film: return "camera.aperture"
        case .adjustments: return "slider.horizontal.3"
        case .texture: return "circle.hexagongrid"
        case .edges: return "rectangle.on.rectangle"
        case .post: return "slider.horizontal.3"
        }
    }
}

struct OriginalEngineEditorView: View {
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var input: UIImage?
    @State private var developed: UIImage?
    @State private var developedBase: UIImage?
    @State private var postGrade = PostDevelopmentGrade()
    @State private var postRevision = 0
    @State private var postProcessing = false
    @State private var showFilmLibrary = false
    @State private var showPaperLibrary = false
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
    @State private var printBrightness = 0.0
    @State private var preflash = 0.0
    @State private var lensBlur = 0.0
    @State private var scannerBlur = 0.0
    @State private var grainLayered = true
    @State private var halationScatter = 1.0
    @State private var highlightBoost = 0.0
    @State private var highlightHeadroom = 4.0
    @State private var removeAntihalation = false
    @State private var couplersActive = true
    @State private var couplersAmount = 1.0
    @State private var glareAmount = 1.0
    @State private var extendedRange = false
    @State private var scanFilm = false
    @State private var edgeView = "strip"
    @State private var edgeGate = "auto"
    @State private var edgeHoles = "white"
    @State private var edgeFog = 1.0
    @State private var edgeLeaks = 0.0
    @State private var edgeFrameNumber = 0
    @State private var exportDimension = 2048
    @State private var showExportChoices = false
    @State private var exportToShareSheet = false
    @State private var shareFile: OriginalShareFile?
    @State private var showExportDestination = false
    @State private var processing = false
    @State private var exporting = false
    @State private var queuedExport = false
    @State private var activeTab: EditorTab = .film
    @State private var renderedExposureEV = 0.0
    @State private var renderedMagenta = 0.0
    @State private var renderedYellow = 0.0
    @State private var previewRevision = 0
    @State private var pendingPreview: Task<Void, Never>?
    @State private var showInput = false
    @State private var previewZoom = false
    @State private var status = "导入照片，使用原版光谱引擎冲印"

    private let edgeOptions: [(String, String)] = [
        ("135", "135 · 35mm"), ("135_half", "135 · 半格"),
        ("120_645", "120 · 6×4.5"), ("120_6x6", "120 · 6×6"),
        ("120_6x7", "120 · 6×7"), ("120_6x8", "120 · 6×8"),
        ("120_6x9", "120 · 6×9"), ("135_xpan", "135 · XPan"),
        ("120_6x12", "120 · 6×12"), ("120_6x17", "120 · 6×17")
    ]

    private var activeImage: UIImage? {
        if showInput { return input }
        return developed ?? input
    }

    // Lightweight display-only feedback while the physical spectral render
    // catches up. It is zeroed after the new original-engine frame arrives.
    private var liveBrightness: Double {
        showInput ? 0 : (exposureEV - renderedExposureEV) * 0.14
    }
    private var liveTint: Color {
        guard !showInput else { return .white }
        let m = magentaFilter - renderedMagenta
        let y = yellowFilter - renderedYellow
        func channel(_ x: Double) -> Double { min(1, max(0.60, x)) }
        return Color(red: channel(1 + m * 0.13 + y * 0.08),
                     green: channel(1 - m * 0.16 + y * 0.08),
                     blue: channel(1 + m * 0.10 - y * 0.18))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    headerBar
                    OriginalMobileTheme.line.frame(height: 1)
                    // The preview is outside the scrollable editor. It remains
                    // visible while dragging any of the darkroom controls.
                    previewPanel
                        .frame(height: max(205, min(geometry.size.height * 0.42, 370)))

                    OriginalMobileTheme.line.frame(height: 1)
                    tabBar
                    OriginalMobileTheme.line.frame(height: 1)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            switch activeTab {
                            case .film: filmPanel
                            case .adjustments: adjustmentsPanel
                            case .texture: texturePanel
                            case .edges: edgesPanel
                            case .post: postPanel
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
            .background(OriginalMobileTheme.rail)
            .foregroundStyle(OriginalMobileTheme.ink)
            .toolbar(.hidden, for: .navigationBar)
            .preferredColorScheme(.dark)
            .sheet(isPresented: $showFilmLibrary) {
                OriginalStockLibrary(stocks: stocks.filter { $0.support == "film" },
                                     selection: $filmStock, title: "FILM · 胶片")
            }
            .sheet(isPresented: $showPaperLibrary) {
                OriginalStockLibrary(stocks: stocks.filter { $0.support == "paper" },
                                     selection: $paperStock, title: "PRINT · 相纸")
            }
            .sheet(item: $shareFile) { file in
                OriginalShareSheet(url: file.url)
            }
            .confirmationDialog("选择导出位置", isPresented: $showExportDestination,
                                titleVisibility: .visible) {
                Button("保存到照片") {
                    exportToShareSheet = false
                    showExportChoices = true
                }
                Button("分享到其他 App / 存储到文件") {
                    exportToShareSheet = true
                    showExportChoices = true
                }
                Button("取消", role: .cancel) {}
            }
            .confirmationDialog("选择导出像素", isPresented: $showExportChoices,
                                titleVisibility: .visible) {
                ForEach([1024, 2048, 3072, 4096], id: \.self) { pixels in
                    Button("最长边 \(pixels) px\(pixels == 2048 ? " · 推荐" : "")") {
                        exportDimension = pixels
                        requestExport()
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("按最长边输出，保持照片原始比例；不会放大小于所选尺寸的照片。4096 px 可能占用较多内存。")
            }
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
            .onChange(of: printBrightness) { _ in schedulePreview() }
            .onChange(of: preflash) { _ in schedulePreview() }
            .onChange(of: lensBlur) { _ in schedulePreview() }
            .onChange(of: scannerBlur) { _ in schedulePreview() }
            .onChange(of: grainLayered) { _ in schedulePreview() }
            .onChange(of: halationScatter) { _ in schedulePreview() }
            .onChange(of: highlightBoost) { _ in schedulePreview() }
            .onChange(of: highlightHeadroom) { _ in schedulePreview() }
            .onChange(of: removeAntihalation) { _ in schedulePreview() }
            .onChange(of: couplersActive) { _ in schedulePreview() }
            .onChange(of: couplersAmount) { _ in schedulePreview() }
            .onChange(of: glareAmount) { _ in schedulePreview() }
            .onChange(of: extendedRange) { _ in schedulePreview() }
            .onChange(of: scanFilm) { _ in schedulePreview() }
            .onChange(of: edgeView) { _ in schedulePreview() }
            .onChange(of: edgeGate) { _ in schedulePreview() }
            .onChange(of: edgeHoles) { _ in schedulePreview() }
            .onChange(of: edgeFog) { _ in schedulePreview() }
            .onChange(of: edgeLeaks) { _ in schedulePreview() }
            .onChange(of: edgeFrameNumber) { _ in schedulePreview() }
            .onChange(of: postGrade.enabled) { _ in refreshPostGrade() }
            .onChange(of: postGrade.temperature) { _ in refreshPostGrade() }
            .onChange(of: postGrade.tint) { _ in refreshPostGrade() }
            .onChange(of: postGrade.exposure) { _ in refreshPostGrade() }
            .onChange(of: postGrade.contrast) { _ in refreshPostGrade() }
            .onChange(of: postGrade.brightness) { _ in refreshPostGrade() }
            .onChange(of: postGrade.saturation) { _ in refreshPostGrade() }
            .onChange(of: postGrade.highlights) { _ in refreshPostGrade() }
            .onChange(of: postGrade.shadows) { _ in refreshPostGrade() }
            .onChange(of: postGrade.blackPoint) { _ in refreshPostGrade() }
            .onChange(of: postGrade.whitePoint) { _ in refreshPostGrade() }
            .onChange(of: postGrade.vignette) { _ in refreshPostGrade() }
            .onChange(of: postGrade.vignetteMidpoint) { _ in refreshPostGrade() }
            .onChange(of: pickedPhoto) { item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self),
                          let photo = UIImage(data: data) else {
                        status = "失败：无法读取照片"
                        return
                    }
                    input = photo
                    developed = nil
                    developedBase = nil
                    postRevision += 1
                    showInput = false
                    previewZoom = false
                    status = "照片已导入，正在生成预览…"
                    schedulePreview()
                }
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("SpektraLab")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .tracking(-0.5)
                Text("SPECTRAL DARKROOM")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(OriginalMobileTheme.muted)
            }
            Spacer(minLength: 4)
            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: 38, height: 38)
                    .background(OriginalMobileTheme.canvas.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("导入照片")
            Button { showExportDestination = true } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: 38, height: 38)
                    .background(OriginalMobileTheme.canvas.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(input == nil || exporting || queuedExport)
            .accessibilityLabel("导出照片")
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(OriginalMobileTheme.rail)
    }

    private var previewPanel: some View {
        GeometryReader { area in
            ZStack {
                OriginalMobileTheme.canvas
                if let image = activeImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .brightness(liveBrightness)
                        .colorMultiply(liveTint)
                        .scaleEffect(previewZoom ? 2.0 : 1.0)
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
                        Text("CANVAS · \(processing ? "DEVELOPING" : "PREVIEW")")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.black.opacity(0.55), in: Capsule())
                        Spacer()
                        if activeImage != nil {
                            Button {
                                previewZoom.toggle()
                            } label: {
                                Label(previewZoom ? "适合屏幕" : "放大颗粒",
                                      systemImage: previewZoom ? "arrow.down.right.and.arrow.up.left" : "plus.magnifyingglass")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 9).padding(.vertical, 6)
                                    .background(.black.opacity(0.65), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
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
                            ProgressView().tint(OriginalMobileTheme.accent)
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
                    .foregroundStyle(activeTab == tab ? OriginalMobileTheme.ink : OriginalMobileTheme.muted.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(activeTab == tab ? OriginalMobileTheme.canvas.opacity(0.42) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(OriginalMobileTheme.rail)
    }

    private var filmPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("FILM & PRINT", systemImage: "camera.aperture").font(.headline)
                    Text("原版胶片与相纸配置")
                        .font(.caption).foregroundStyle(OriginalMobileTheme.muted)
                }
                Spacer()
                Button { schedulePreview(immediate: true) } label: { Label("重新显影", systemImage: "arrow.clockwise") }
                    .font(.caption.weight(.medium))
                    .tint(OriginalMobileTheme.accent)
                    .disabled(input == nil)
            }
            .padding(.bottom, 14)

            railDivider
            Text("FILM · 胶片").font(.caption.weight(.semibold))
                .foregroundStyle(OriginalMobileTheme.muted)
                .padding(.vertical, 9)
            Button { showFilmLibrary = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 20, weight: .light))
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(stocks.first(where: { $0.id == filmStock })?.chineseName ?? filmStock)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                        Text("点按查看全部原版胶片")
                            .font(.caption2).foregroundStyle(OriginalMobileTheme.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .foregroundStyle(OriginalMobileTheme.ink)
                .padding(14)
                .background(OriginalMobileTheme.canvas.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 15)

            railDivider
            Text("PRINT · 相纸").font(.caption.weight(.semibold))
                .foregroundStyle(OriginalMobileTheme.muted)
                .padding(.vertical, 9)
            Button { showPaperLibrary = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 20, weight: .light))
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(stocks.first(where: { $0.id == paperStock })?.chineseName ?? paperStock)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                        Text("点按查看全部原版相纸")
                            .font(.caption2).foregroundStyle(OriginalMobileTheme.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .foregroundStyle(OriginalMobileTheme.ink)
                .padding(14)
                .background(OriginalMobileTheme.canvas.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .disabled(scanFilm)
            .opacity(scanFilm ? 0.45 : 1)
            .padding(.bottom, 15)
            railDivider
            Text("选中的胶片和相纸由原版光谱引擎处理；切换胶片时自动匹配其推荐相纸。")
                .font(.caption2)
                .foregroundStyle(OriginalMobileTheme.muted)
                .padding(.top, 12)
        }
    }

    private var adjustmentsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("暗房 · 影调与色彩", systemImage: "slider.horizontal.3").font(.headline)
                Spacer()
                Button("重置") {
                    exposureEV = 0; printBrightness = 0; preflash = 0
                    magentaFilter = 0; yellowFilter = 0
                    lensBlur = 0; scannerBlur = 0
                    extendedRange = false; scanFilm = false
                    schedulePreview(immediate: true)
                }
                .font(.caption.weight(.semibold)).tint(OriginalMobileTheme.accent)
            }
            Text("参考原版的负片曝光、放大机与扫描参数")
                .font(.caption).foregroundStyle(.secondary)
            VStack(spacing: 17) {
                darkroomSlider("相机曝光", subtitle: "负片曝光补偿 · EV",
                               value: $exposureEV, range: -3...3)
                darkroomSlider("相纸亮度", subtitle: "放大机曝光补偿 · EV",
                               value: $printBrightness, range: -3...3)
                darkroomSlider("洋红滤镜", subtitle: "洋红 ↔ 绿色 · ±40 CC",
                               value: $magentaFilter, range: -1...1)
                darkroomSlider("黄色滤镜", subtitle: "黄色 ↔ 蓝色 · ±40 CC",
                               value: $yellowFilter, range: -1...1)
                darkroomSlider("相纸预闪", subtitle: "提升暗部层次 · 0–0.03",
                               value: $preflash, range: 0...0.03)
            }
            .padding(14)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            VStack(spacing: 17) {
                darkroomSlider("镜头柔化", subtitle: "拍摄镜头模糊 · µm",
                               value: $lensBlur, range: 0...40)
                darkroomSlider("扫描柔化", subtitle: "扫描仪镜头模糊",
                               value: $scannerBlur, range: 0...10)
                Toggle("扩展动态范围", isOn: $extendedRange).tint(OriginalMobileTheme.accent)
                Toggle("直接扫描底片", isOn: $scanFilm).tint(OriginalMobileTheme.accent)
            }
            .padding(14)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var texturePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("胶片质感 · 原版物理模型", systemImage: "circle.hexagongrid").font(.headline)
                Spacer()
                Button("重置") {
                    grainAmount = 1; halationAmount = 1
                    grainLayered = true; halationScatter = 1
                    highlightBoost = 0; highlightHeadroom = 4
                    removeAntihalation = false; couplersActive = true
                    couplersAmount = 1; glareAmount = 1
                    schedulePreview(immediate: true)
                }
                .font(.caption.weight(.semibold)).tint(OriginalMobileTheme.accent)
            }
            Text("颗粒与光晕由原版光谱引擎生成；请放大照片观察细节")
                .font(.caption).foregroundStyle(.secondary)
            VStack(spacing: 17) {
                Label("颗粒", systemImage: "circle.hexagongrid.fill").font(.subheadline.weight(.semibold))
                darkroomSlider("胶片颗粒强度", subtitle: "0 为关闭 · 1 为原版胶片默认",
                               value: $grainAmount, range: 0...2)
                Toggle("彩色胶片分层颗粒", isOn: $grainLayered).tint(OriginalMobileTheme.accent)
            }
            .padding(14)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            VStack(spacing: 17) {
                Text("光晕与散射").font(.subheadline.weight(.semibold))
                darkroomSlider("胶片光晕", subtitle: "背反射光晕强度 · 0–4",
                               value: $halationAmount, range: 0...4)
                darkroomSlider("乳剂散射", subtitle: "乳剂内部光散射 · 0–1",
                               value: $halationScatter, range: 0...1)
                darkroomSlider("高光光晕增强", subtitle: "为被裁切的亮部恢复光能 · EV",
                               value: $highlightBoost, range: 0...8)
                darkroomSlider("高光余量", subtitle: "主要影响无防光晕层的电影胶片",
                               value: $highlightHeadroom, range: 0...8)
                Toggle("移除防光晕层", isOn: $removeAntihalation).tint(OriginalMobileTheme.accent)
            }
            .padding(14)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            VStack(spacing: 17) {
                Text("色层与相纸雾化").font(.subheadline.weight(.semibold))
                Toggle("色层耦合", isOn: $couplersActive).tint(OriginalMobileTheme.accent)
                darkroomSlider("色层耦合强度", subtitle: "影响胶片的颜色分离",
                               value: $couplersAmount, range: 0...1.5)
                darkroomSlider("相纸雾化", subtitle: "暗房散射光 · 0–30",
                               value: $glareAmount, range: 0...30)
            }
            .padding(14)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // Original desktop layout: the right-hand Parameters rail separates
    // Pre-Dev (camera/film) and Post-Dev (the scanned print). On iPhone
    // these become adjacent editor tabs with the same section order.
    private var postPanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PARAMETERS · POST-DEV").font(.headline)
                    Text("白平衡 → 曝光 → 色调 → 暗角")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("重置") { postGrade = PostDevelopmentGrade() }
                    .font(.caption.weight(.semibold))
                    .tint(OriginalMobileTheme.accent)
            }
            Toggle("启用后期调色", isOn: $postGrade.enabled)
                .tint(OriginalMobileTheme.accent)
            railDivider
            Text("WHITE BALANCE · 白平衡").font(.caption.weight(.semibold))
                .foregroundStyle(OriginalMobileTheme.muted)
            darkroomSlider("色温偏移", subtitle: "蓝色 ↔ 琥珀", value: $postGrade.temperature, range: -100...100)
            darkroomSlider("色调偏移", subtitle: "绿色 ↔ 洋红", value: $postGrade.tint, range: -100...100)
            railDivider
            Text("EXPOSURE · 曝光").font(.caption.weight(.semibold))
                .foregroundStyle(OriginalMobileTheme.muted)
            darkroomSlider("曝光", subtitle: "输出扫描曝光 · EV", value: $postGrade.exposure, range: -3...3)
            darkroomSlider("对比度", subtitle: "输出扫描对比度", value: $postGrade.contrast, range: -50...50)
            darkroomSlider("亮度", subtitle: "输出扫描亮度", value: $postGrade.brightness, range: -50...50)
            darkroomSlider("饱和度", subtitle: "输出扫描饱和度", value: $postGrade.saturation, range: -100...100)
            railDivider
            Text("TONE · 明暗层次").font(.caption.weight(.semibold))
                .foregroundStyle(OriginalMobileTheme.muted)
            darkroomSlider("高光", subtitle: "高光细节", value: $postGrade.highlights, range: -100...100)
            darkroomSlider("阴影", subtitle: "阴影细节", value: $postGrade.shadows, range: -100...100)
            darkroomSlider("黑场", subtitle: "黑点位置", value: $postGrade.blackPoint, range: 0...50)
            darkroomSlider("白场", subtitle: "白点位置", value: $postGrade.whitePoint, range: 0...50)
            railDivider
            Text("VIGNETTE · 暗角").font(.caption.weight(.semibold))
                .foregroundStyle(OriginalMobileTheme.muted)
            darkroomSlider("暗角强度", subtitle: "负值暗角 · 正值提亮", value: $postGrade.vignette, range: -100...100)
            darkroomSlider("暗角中点", subtitle: "影响范围", value: $postGrade.vignetteMidpoint, range: 0...100)
            Text("iOS 后期处理已连接预览与导出。当前采用 Core Image 实现，原版 Metal 调色着色器仍待逐项对齐。")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var railDivider: some View {
        OriginalMobileTheme.line.frame(height: 1).padding(.vertical, 3)
    }

    private var edgesPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Film Edge · 原版胶片片边").font(.headline)
            Text("沿用原版的片门、齿孔、底片边码和光漏参数。启用时按胶片画幅比例居中裁剪照片。")
                .font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 15) {
                Toggle("开启原版 Film Edge", isOn: $filmEdge).tint(OriginalMobileTheme.accent)
                if filmEdge {
                    Picker("胶片格式", selection: $edgeFormat) {
                        ForEach(edgeOptions, id: \.0) { option in
                            Text(option.1).tag(option.0)
                        }
                    }
                    .tint(OriginalMobileTheme.accent)
                    Picker("呈现方式", selection: $edgeView) {
                        Text("整条胶片 · Strip").tag("strip")
                        Text("归档片门 · Filed").tag("filed")
                    }
                    .tint(OriginalMobileTheme.accent)
                    Picker("片门形状", selection: $edgeGate) {
                        Text("自动").tag("auto")
                        Text("直角").tag("square")
                        Text("圆角").tag("rounded")
                        Text("耳形").tag("eared")
                        Text("肩形").tag("shouldered")
                        Text("切角").tag("kicked")
                    }
                    .tint(OriginalMobileTheme.accent)
                    Picker("齿孔颜色", selection: $edgeHoles) {
                        Text("亮色").tag("white")
                        Text("暗色").tag("black")
                    }
                    .tint(OriginalMobileTheme.accent)
                    darkroomSlider("底片灰雾", subtitle: "原版片边灰雾强度",
                                   value: $edgeFog, range: 0...4)
                    darkroomSlider("边缘漏光", subtitle: "原版漏光强度",
                                   value: $edgeLeaks, range: 0...4)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("画格编号")
                            Spacer()
                            Text(edgeFrameNumber == 0 ? "自动" : String(edgeFrameNumber))
                                .foregroundStyle(OriginalMobileTheme.accent)
                        }
                        Slider(value: Binding(get: { Double(edgeFrameNumber) },
                                              set: { edgeFrameNumber = Int($0.rounded()) }),
                               in: 0...99, step: 1)
                            .tint(OriginalMobileTheme.accent)
                    }
                    Text("原版片边仍需实机稳定性验证。如开启后闪退，请记录机型和崩溃日志。")
                        .font(.caption).foregroundStyle(OriginalMobileTheme.accent)
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Image(systemName: processing ? "circle.dotted" : "camera.aperture")
                .font(.system(size: 12))
                .foregroundStyle(OriginalMobileTheme.accent)
            Text(status)
                .font(.system(size: 11))
                .foregroundStyle(status.hasPrefix("失败") ? Color.red : OriginalMobileTheme.muted)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let input {
                Text("\(Int(input.size.width)) × \(Int(input.size.height))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(OriginalMobileTheme.muted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(OriginalMobileTheme.rail)
        .overlay(alignment: .top) { OriginalMobileTheme.line.frame(height: 1) }
    }

    private func darkroomSlider(_ name: String, subtitle: String,
                                value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 9) {
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 100, alignment: .leading)
                    .lineLimit(2)
                Slider(value: value, in: range, onEditingChanged: { editing in
                    if !editing && activeTab != .post { schedulePreview(immediate: true) }
                })
                .tint(OriginalMobileTheme.accent)
                Button {
                    value.wrappedValue = min(max(0, range.lowerBound), range.upperBound)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11))
                        .frame(width: 28, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("重置" + name)
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.system(size: 11, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(OriginalMobileTheme.ink)
                    .frame(width: 44, alignment: .trailing)
            }
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(OriginalMobileTheme.muted.opacity(0.7))
                .padding(.leading, 100)
        }
        .frame(minHeight: 46)
    }

    private func refreshPostGrade() {
        postRevision += 1
        let revision = postRevision
        guard let base = developedBase else { return }
        let grade = postGrade
        postProcessing = true
        DispatchQueue.global(qos: .userInitiated).async {
            let image = OriginalPostProcessor.apply(grade, to: base)
            DispatchQueue.main.async {
                guard revision == postRevision else { return }
                postProcessing = false
                if let image { developed = image }
                else { status = "失败：后期调色处理失败" }
            }
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
            develop(maxDimension: 1400, saveAfter: false)
        }
    }

    private func requestExport() {
        guard input != nil, !exporting else { return }
        pendingPreview?.cancel()
        queuedExport = true
        previewRevision += 1
        if !processing {
            queuedExport = false
            develop(maxDimension: exportDimension, saveAfter: true)
        }
    }

    private func shareExport(_ image: UIImage) {
        // Keep the full-resolution rendered pixels in a lossless file rather
        // than letting UIActivityViewController choose a lossy representation.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpektraLabExports", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
            guard let png = image.pngData() else {
                status = "失败：无法编码导出 PNG"
                return
            }
            let url = directory.appendingPathComponent(UUID().uuidString + ".png")
            try png.write(to: url, options: .atomic)
            shareFile = OriginalShareFile(url: url)
            status = "高清 PNG 已生成，请选择保存位置"
        } catch {
            status = "失败：无法写入导出文件（\(error.localizedDescription)）"
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
        let exportGrade = postGrade
        let shareAfter = exportToShareSheet
        let grainFactor: Double
        switch film {
        case "kodak_tri_x_400": grainFactor = 1.70
        case "ilford_hp5_plus_400": grainFactor = 1.49
        case "kodak_tmax_100": grainFactor = 0.74
        case "fujifilm_neopan_acros_100_ii": grainFactor = 0.64
        default: grainFactor = 1
        }
        let gateLongMM: Double
        switch format {
        case "135_half": gateLongMM = 24
        case "120_645", "120_6x6": gateLongMM = 56
        case "120_6x7": gateLongMM = 69.5
        case "120_6x8": gateLongMM = 76
        case "120_6x9": gateLongMM = 84
        case "135_xpan": gateLongMM = 65
        case "120_6x12": gateLongMM = 112
        case "120_6x17": gateLongMM = 168
        default: gateLongMM = 36
        }
        let isMonochrome = ["tri_x", "tmax", "hp5", "delta", "acros", "pan_f", "fp4"]
            .contains(where: { film.lowercased().contains($0) })
        // Keys and ranges match the upstream original FilmParams.wire schema.
        // A single dictionary is captured with the render snapshot, so a slider
        // cannot mutate parameters halfway through a native render.
        let options: [String: Any] = [
            "print_exposure": pow(2.0, -printBrightness),
            "preflash_exposure": preflash,
            "lens_blur_um": lensBlur,
            "scanner_lens_blur": scannerBlur,
            "grain_sublayers_active": grainLayered && !isMonochrome,
            "film_format_mm": edges ? gateLongMM : 36,
            "grain_amount": min(2, grain * grainFactor),
            "halation_scatter_amount": halationScatter,
            "halation_boost_ev": highlightBoost,
            "halation_headroom_ev": highlightHeadroom,
            "antihalation_removed": removeAntihalation,
            "dir_couplers_active": couplersActive,
            "dir_couplers_amount": couplersAmount,
            "glare_amount": glareAmount,
            "extended_dynamic_range": extendedRange,
            "scan_film": scanFilm,
            "overscan_active": edges,
            "overscan_format": format,
            "overscan_mode": edgeView,
            "overscan_gate": edgeGate,
            "overscan_holes": edgeHoles,
            "overscan_fog": edgeFog,
            "overscan_leaks": edgeLeaks,
            "overscan_frame_number": edgeFrameNumber,
            "overscan_edge_text": stocks.first(where: { $0.id == film })?.name.uppercased() ?? ""
        ]
        DispatchQueue.global(qos: .userInitiated).async {
            let nativeMessage = NSMutableString(string: "")
            // Original engine performs film, paper, grain, halation and overscan.
            let renderedImage = OriginalFilmRenderer.renderImageWithoutThrow(
                source, filmStock: film, printStock: paper,
                enableEdge: edges, edgeFormat: format,
                exposureEV: exposure, grainAmount: grain, halationAmount: halation,
                magenta: magenta, yellow: yellow,
                maxDimension: maxDimension, options: options,
                errorMessage: nativeMessage)
            // Export and preview must both use the same post-development
            // stage. Preview applies the latest grade after native completion.
            let result = saveAfter ? renderedImage.flatMap {
                OriginalPostProcessor.apply(exportGrade, to: $0)
            } : renderedImage
            let renderFailure = nativeMessage.length > 0 ? (nativeMessage as String) : nil
            DispatchQueue.main.async {
                processing = false
                exporting = false
                if queuedExport {
                    queuedExport = false
                    develop(maxDimension: exportDimension, saveAfter: true)
                    return
                }
                if !saveAfter && revisionAtStart != previewRevision {
                    schedulePreview(immediate: true)
                    return
                }
                if let result {
                    if !saveAfter {
                        developedBase = result
                        refreshPostGrade()
                    }
                    renderedExposureEV = exposure
                    renderedMagenta = magenta
                    renderedYellow = yellow
                    showInput = false
                    if saveAfter {
                        if shareAfter {
                            status = "渲染完成，正在生成 PNG…"
                            shareExport(result)
                        } else {
                            status = "渲染完成，正在保存到相册…"
                            saveToPhotos(result)
                        }
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

}

private struct OriginalStockLibrary: View {
    let stocks: [OriginalStock]
    @Binding var selection: String
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var matches: [OriginalStock] {
        guard !query.isEmpty else { return stocks }
        return stocks.filter {
            $0.chineseName.localizedCaseInsensitiveContains(query) ||
            $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(matches) { stock in
                        Button {
                            selection = stock.id
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(stock.chineseName)
                                        .font(.subheadline.weight(selection == stock.id ? .semibold : .regular))
                                    Text(stock.id)
                                        .font(.caption2)
                                        .opacity(0.7)
                                }
                                Spacer(minLength: 8)
                                if selection == stock.id {
                                    Image(systemName: "checkmark")
                                        .font(.subheadline.weight(.bold))
                                }
                            }
                            .foregroundStyle(selection == stock.id ? OriginalMobileTheme.rail : OriginalMobileTheme.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(selection == stock.id ? OriginalMobileTheme.ink : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        OriginalMobileTheme.line.frame(height: 0.5)
                    }
                }
                .padding(.horizontal, 12)
            }
            .background(OriginalMobileTheme.rail)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }.tint(OriginalMobileTheme.accent)
                }
            }
            .searchable(text: $query, prompt: "搜索胶片名称或型号")
            .preferredColorScheme(.dark)
        }
    }
}

private struct OriginalShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct OriginalShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
