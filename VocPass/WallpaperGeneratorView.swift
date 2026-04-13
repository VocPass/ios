//
//  WallpaperGeneratorView.swift
//  VocPass
//
//  課表桌布產生器：拉取模板列表 → 編輯器（可拖動的背景／課表／文字／貼圖層）。
//

import SwiftUI
import PhotosUI
import UIKit

// MARK: - Models

struct WallpaperTemplate: Identifiable, Decodable {
    var id: String { name }
    let name: String
    let author: String
    let authorURL: String?
    let preview: String
    let images: WallpaperImages
    let top: Double      // table 距離上方的距離（百分比）
    let stickers: Int    // 預設要隨機生成的貼圖數
    let fontSize: Double?
    let fontColor: String?
    let fontFamily: String?
    let tableOpacity: Double?

    enum CodingKeys: String, CodingKey {
        case name, author
        case authorURL = "author_url"
        case preview, images, top, stickers
        case fontSize = "font_size"
        case fontColor = "font_color"
        case fontFamily = "font_family"
        case tableOpacity = "table_opacity"
    }
}

struct WallpaperTableConfig: Decodable {
    var images: [String]
    var left: Double       // 左右最小間距（原圖像素）
    var right: Double
    var topInset: Double?  // 文字格上方內縮（原圖像素）
    var bottom: Double?    // 文字格下方內縮（原圖像素）

    enum CodingKeys: String, CodingKey {
        case images, left, right
        case topInset = "top_inset"
        case bottom
    }
}

struct WallpaperImages: Decodable {
    let background: [String]
    let stickers: [String]
    let table: [String: WallpaperTableConfig]   // period count → config

    enum CodingKeys: String, CodingKey {
        case background, stickers, table
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        background = try c.decode([String].self, forKey: .background)
        stickers = try c.decode([String].self, forKey: .stickers)
        // 相容新舊格式：新格式 { images, left, right, ... }，舊格式 [String]
        if let newFormat = try? c.decode([String: WallpaperTableConfig].self, forKey: .table) {
            table = newFormat
        } else if let oldFormat = try? c.decode([String: [String]].self, forKey: .table) {
            table = oldFormat.mapValues { WallpaperTableConfig(images: $0, left: 30, right: 30, topInset: nil, bottom: nil) }
        } else {
            table = [:]
        }
    }
}

// MARK: - 模板列表

struct WallpaperTemplateListView: View {
    @State private var templates: [WallpaperTemplate] = []
    @State private var isLoading = true
    @State private var loadError: String?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        Group {
            if isLoading {
                ProgressView("載入模板⋯")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loadError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 44))
                        .foregroundStyle(.orange)
                    Text(err)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("重試") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(templates) { tpl in
                            NavigationLink(destination: WallpaperEditorView(template: tpl)) {
                                TemplateCard(template: tpl)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("課表產生器")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Link(destination: URL(string: "https://github.com/VocPass/wallpaper")!) {
                        Label("新增我的", systemImage: "plus.circle")
                    }
                    Link(destination: URL(string: "\(AppConfig.vocPassAPIHost)/creator-policy")!) {
                        Label("創作者政策", systemImage: "doc.text")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        await MainActor.run { isLoading = true; loadError = nil }
        do {
            guard let url = URL(string: "\(AppConfig.vocPassAPIHost)/api/wallpaper/curriculum") else {
                throw URLError(.badURL)
            }
            let (data, _) = try await URLSession.shared.data(from: url)
            let list: [WallpaperTemplate]
            if let direct = try? JSONDecoder().decode([WallpaperTemplate].self, from: data) {
                list = direct
            } else {
                struct Wrapper: Decodable { let data: [WallpaperTemplate] }
                list = try JSONDecoder().decode(Wrapper.self, from: data).data
            }
            await MainActor.run {
                self.templates = list
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.loadError = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

private struct TemplateCard: View {
    let template: WallpaperTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CachedAsyncImage(url: URL(string: template.preview)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                case .failure:
                    ZStack {
                        Color.gray.opacity(0.15)
                        Image(systemName: "photo").foregroundStyle(.secondary)
                    }
                default:
                    ZStack {
                        Color.gray.opacity(0.15)
                        ProgressView()
                    }
                }
            }
            .aspectRatio(9.0/19.5, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Text(template.name)
                .font(.headline)
                .lineLimit(1)
            if let urlStr = template.authorURL, let url = URL(string: urlStr) {
                Link(destination: url) {
                    Text("by \(template.author)")
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                }
            } else {
                Text("by \(template.author)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - 編輯器

private enum LayerKind {
    case background
    case table     // 包含表格圖片＋文字格（同群組）
    case sticker
}

private struct EditorLayer: Identifiable {
    var id = UUID()
    var kind: LayerKind
    var image: UIImage?            // background / table / sticker
    var sourceURLs: [String] = []  // 可切換的素材
    var sourceIndex: Int = 0
    var center: CGPoint            // 在 canvas 中的中心點
    var size: CGSize               // 顯示尺寸
    var rotation: Angle = .zero
    var subjects: [[String]] = []  // textGroup 專用：rows × 5
    var rows: Int = 0              // textGroup 專用
    var baseFontSize: CGFloat = 14 // textGroup 專用：字體大小（不隨群組縮放而改變）
    var fontColorHex: String = "#000000"  // textGroup 專用
    var fontFamily: String = "Noto"       // textGroup 專用（API 回傳的 display name）
    var tableOpacity: Double = 1.0        // table 專用：課表圖片透明度 0~1
    var tableConfig: WallpaperTableConfig? // table 專用：該節次的間距設定
}

struct WallpaperEditorView: View {
    let template: WallpaperTemplate

    @Environment(\.dismiss) private var dismiss

    @State private var layers: [EditorLayer] = []
    @State private var selectedLayerID: UUID?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var canvasSize: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var showPhotoPicker = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var photoTargetID: UUID?
    @State private var pinchBaseSize: CGSize?
    @State private var pinchLayerID: UUID?
    @State private var showImagePicker = false
    @State private var pickerTargetID: UUID?
    @State private var showTextSettings = false
    @State private var textSettingsLayerID: UUID?
    @State private var fontList: [String: String] = [:]   // display → URL
    @State private var fontRefreshTick: Int = 0           // 觸發字型載入完成後重繪
    @State private var showSavedAlert = false
    @State private var showDebugInsets = false
    @State private var currentPeriodCount: Int = 0  // 目前選用的節數（0 = 自動偵測）
    @State private var isLoadingFont = false

    var body: some View {
        GeometryReader { geo in
            let canvas = canvasRect(in: geo.size)
            ZStack {
                Color.black.ignoresSafeArea()

                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text("正在施加魔法⋯").foregroundStyle(.white)
                    }
                } else if let err = loadError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 44))
                            .foregroundStyle(.orange)
                        Text(err).foregroundStyle(.white)
                        Button("重試") { Task { await preload(canvas: canvas.size) } }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ZStack {
                        ForEach(layers) { layer in
                            layerView(layer, canvas: canvas.size)
                        }
                    }
                    .frame(width: canvas.size.width, height: canvas.size.height)
                    .clipped()
                    .background(Color.gray.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .position(x: geo.size.width / 2,
                              y: geo.size.height / 2 - 30)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedLayerID = nil }

                    VStack {
                        Spacer()
                        toolbar
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                    }
                }
            }
            .task {
                if isLoading {
                    await preload(canvas: canvasRect(in: geo.size).size)
                }
            }
        }
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    saveToPhotos()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .disabled(isLoading)
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickedItem, matching: .images)
        .onChange(of: pickedItem) { _, item in
            Task { await loadPickedPhoto(item) }
        }
        .sheet(isPresented: $showTextSettings) {
            if let id = textSettingsLayerID,
               let idx = layers.firstIndex(where: { $0.id == id }) {
                TextSettingsSheet(
                    fontSize: Binding(
                        get: { layers[idx].baseFontSize },
                        set: { layers[idx].baseFontSize = $0 }
                    ),
                    fontColorHex: Binding(
                        get: { layers[idx].fontColorHex },
                        set: { layers[idx].fontColorHex = $0 }
                    ),
                    fontFamily: Binding(
                        get: { layers[idx].fontFamily },
                        set: { newValue in
                            Task { @MainActor in
                                isLoadingFont = true
                                _ = await FontLoader.shared.load(displayName: newValue)
                                layers[idx].fontFamily = newValue
                                fontRefreshTick &+= 1
                                isLoadingFont = false
                            }
                        }
                    ),
                    fontList: fontList,
                    isLoadingFont: $isLoadingFont
                )
            }
        }
        .sheet(isPresented: $showImagePicker) {
            if let id = pickerTargetID,
               let layer = layers.first(where: { $0.id == id }) {
                ImagePickerSheet(
                    layer: layer,
                    onSelect: { urlStr in
                        setLayerImage(layerID: id, urlStr: urlStr)
                    },
                    onAddSticker: {
                        addRandomSticker()
                    }
                )
            }
        }
        .sheet(isPresented: $showDebugInsets) {
            if let id = selectedLayerID,
               let idx = layers.firstIndex(where: { $0.id == id }),
               layers[idx].kind == .table {
                DebugInsetsSheet(
                    imageSize: layers[idx].image?.size ?? .zero,
                    left: Binding(
                        get: { layers[idx].tableConfig?.left ?? 0 },
                        set: { layers[idx].tableConfig?.left = $0 }
                    ),
                    right: Binding(
                        get: { layers[idx].tableConfig?.right ?? 0 },
                        set: { layers[idx].tableConfig?.right = $0 }
                    ),
                    topInset: Binding(
                        get: { layers[idx].tableConfig?.topInset ?? 0 },
                        set: { layers[idx].tableConfig?.topInset = $0 }
                    ),
                    bottom: Binding(
                        get: { layers[idx].tableConfig?.bottom ?? 0 },
                        set: { layers[idx].tableConfig?.bottom = $0 }
                    ),
                    tableOpacity: Binding(
                        get: { layers[idx].tableOpacity },
                        set: { layers[idx].tableOpacity = $0 }
                    ),
                    availablePeriods: template.images.table.keys.compactMap { Int($0) }.sorted(),
                    currentPeriodCount: $currentPeriodCount,
                    onPeriodChange: { newCount in
                        Task { await switchPeriodCount(to: newCount) }
                    }
                )
            }
        }
        .alert("儲存完成", isPresented: $showSavedAlert) {
            Button("確定") {
                if let urlStr = template.authorURL,
                   let url = URL(string: urlStr) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("儲存完成，去支持一下作者吧")
        }
    }

    // MARK: - 版面計算

    private func canvasRect(in size: CGSize) -> CGRect {
        // 9:19.5 螢幕比例
        let safeW = min(size.width - 16, 500)
        let safeH = size.height - 120
        let aspect: CGFloat = 9.0 / 19.5
        var w = safeW
        var h = w / aspect
        if h > safeH {
            h = safeH
            w = h * aspect
        }
        return CGRect(x: 0, y: 0, width: w, height: h)
    }

    // MARK: - 預載資源

    private func preload(canvas: CGSize) async {
        await MainActor.run {
            isLoading = true
            loadError = nil
            canvasSize = canvas
        }
        do {
            // 1. background
            let bgURLs = template.images.background
            guard let firstBG = bgURLs.first, let bgURL = URL(string: firstBG) else {
                throw URLError(.badURL)
            }
            let bgImg = try await ImageCacheService.shared.image(for: bgURL)

            // 2. 決定 N（節數）
            let timetable = CacheService.shared.getCachedTimetable()
            let userMaxPeriod = computeUserMaxPeriod(timetable: timetable)
            guard let chosenKey = pickTableKey(userMaxPeriod: userMaxPeriod),
                  let tableConfig = template.images.table[chosenKey],
                  let firstTable = tableConfig.images.first,
                  let tableURL = URL(string: firstTable)
            else {
                let available = template.images.table.keys.compactMap { Int($0) }.sorted()
                let maxAvail = available.last.map { "\($0)" } ?? "?"
                throw NSError(domain: "Wallpaper", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "此模板最多支援 \(maxAvail) 節，沒有對應 \(userMaxPeriod) 節的課表模板"])
            }
            let tableURLs = tableConfig.images
            let tableImg = try await ImageCacheService.shared.image(for: tableURL)
            let rows = Int(chosenKey) ?? userMaxPeriod

            // 3. 預載所有貼圖素材
            var stickerImgs: [UIImage] = []
            for s in template.images.stickers {
                if let u = URL(string: s),
                   let img = try? await ImageCacheService.shared.image(for: u) {
                    stickerImgs.append(img)
                }
            }

            // 4. 預載其他 background / table 變體（純預熱快取）
            for s in bgURLs.dropFirst() {
                if let u = URL(string: s) { _ = try? await ImageCacheService.shared.image(for: u) }
            }
            for s in tableURLs.dropFirst() {
                if let u = URL(string: s) { _ = try? await ImageCacheService.shared.image(for: u) }
            }

            // 5. 組裝預設 layers
            let cw = canvas.width
            let ch = canvas.height
            var newLayers: [EditorLayer] = []

            // 背景：填滿整個 canvas（contain，但 scaledToFill）
            newLayers.append(EditorLayer(
                kind: .background,
                image: bgImg,
                sourceURLs: bgURLs,
                sourceIndex: 0,
                center: CGPoint(x: cw / 2, y: ch / 2),
                size: CGSize(width: cw, height: ch)
            ))

            // 課表（圖片＋文字同群組）：寬 = canvas 全寬；位置：top% 從上方
            let tableW = cw
            let tableH = tableW * (tableImg.size.height / max(1, tableImg.size.width))
            let tableTop = ch * CGFloat(template.top / 100.0)
            let tableCenter = CGPoint(x: cw / 2, y: tableTop + tableH / 2)
            let subjects = buildSubjectGrid(timetable: timetable, rows: rows)
            // 字體大小：優先使用 template.font_size，否則依初始儲存格尺寸推算
            let baseFont: CGFloat
            if let fs = template.fontSize {
                baseFont = CGFloat(fs)
            } else {
                let initLeftInset = CGFloat(tableConfig.left) * (tableW / max(1, tableImg.size.width))
                let initRightInset = CGFloat(tableConfig.right) * (tableW / max(1, tableImg.size.width))
                let initUsableW = max(0, tableW - initLeftInset - initRightInset)
                let initCellW = initUsableW / 5
                let initCellH = tableH / CGFloat(max(rows, 1))
                baseFont = max(8, min(initCellW, initCellH) * 0.32)
            }
            newLayers.append(EditorLayer(
                kind: .table,
                image: tableImg,
                sourceURLs: tableURLs,
                sourceIndex: 0,
                center: tableCenter,
                size: CGSize(width: tableW, height: tableH),
                subjects: subjects,
                rows: rows,
                baseFontSize: baseFont,
                fontColorHex: template.fontColor ?? "#000000",
                fontFamily: template.fontFamily ?? "Noto",
                tableOpacity: template.tableOpacity ?? 1.0,
                tableConfig: tableConfig
            ))

            // 隨機貼圖
            if !stickerImgs.isEmpty {
                for _ in 0..<max(0, template.stickers) {
                    let img = stickerImgs.randomElement()!
                    let baseW: CGFloat = 80
                    let baseH = baseW * (img.size.height / max(1, img.size.width))
                    let cx = CGFloat.random(in: baseW...(cw - baseW))
                    let cy = CGFloat.random(in: baseH...(ch - baseH))
                    newLayers.append(EditorLayer(
                        kind: .sticker,
                        image: img,
                        sourceURLs: template.images.stickers,
                        sourceIndex: template.images.stickers.firstIndex(where: {
                            URL(string: $0) == URL(string: template.images.stickers.first ?? "")
                        }) ?? 0,
                        center: CGPoint(x: cx, y: cy),
                        size: CGSize(width: baseW, height: baseH)
                    ))
                }
            }

            await MainActor.run {
                self.layers = newLayers
                self.currentPeriodCount = rows
                self.isLoading = false
            }

            // 拉字型列表 + 載入預設字型
            if let list = try? await FontLoader.shared.fetchList() {
                await MainActor.run { self.fontList = list }
                let defaultFamily = template.fontFamily ?? "Noto"
                if let psName = await FontLoader.shared.load(displayName: defaultFamily) {
                    await MainActor.run { 
                        self.fontRefreshTick &+= 1
                        // 觸發重新繪製：通知 layers 有更新（透過重新賦予 ID 強制刷新 UI）
                        for i in self.layers.indices {
                            if self.layers[i].kind == .table {
                                let oldID = self.layers[i].id
                                var newLayer = self.layers[i]
                                newLayer.id = UUID() // 強制重繪該圖層以便套用剛下載好的字型
                                self.layers[i] = newLayer
                                
                                if self.selectedLayerID == oldID {
                                    self.selectedLayerID = newLayer.id
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.loadError = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    // MARK: - 切換節數

    private func switchPeriodCount(to newCount: Int) async {
        let key = "\(newCount)"
        guard let tableConfig = template.images.table[key],
              let firstURL = tableConfig.images.first,
              let url = URL(string: firstURL) else { return }
        guard let tableImg = try? await ImageCacheService.shared.image(for: url) else { return }
        // 預熱其他變體
        for s in tableConfig.images.dropFirst() {
            if let u = URL(string: s) { _ = try? await ImageCacheService.shared.image(for: u) }
        }
        let timetable = CacheService.shared.getCachedTimetable()
        let subjects = buildSubjectGrid(timetable: timetable, rows: newCount)
        await MainActor.run {
            currentPeriodCount = newCount
            guard let idx = layers.firstIndex(where: { $0.kind == .table }) else { return }
            let oldLayer = layers[idx]
            let tableW = oldLayer.size.width
            let tableH = tableW * (tableImg.size.height / max(1, tableImg.size.width))
            let tableTop = canvasSize.height * CGFloat(template.top / 100.0)
            let tableCenter = CGPoint(x: canvasSize.width / 2, y: tableTop + tableH / 2)
            let baseFont: CGFloat
            if let fs = template.fontSize {
                baseFont = CGFloat(fs)
            } else {
                let initLeftInset = CGFloat(tableConfig.left) * (tableW / max(1, tableImg.size.width))
                let initRightInset = CGFloat(tableConfig.right) * (tableW / max(1, tableImg.size.width))
                let initUsableW = max(0, tableW - initLeftInset - initRightInset)
                let initCellW = initUsableW / 5
                let initCellH = tableH / CGFloat(max(newCount, 1))
                baseFont = max(8, min(initCellW, initCellH) * 0.32)
            }
            var newLayer = EditorLayer(
                kind: .table,
                image: tableImg,
                sourceURLs: tableConfig.images,
                sourceIndex: 0,
                center: tableCenter,
                size: CGSize(width: tableW, height: tableH),
                subjects: subjects,
                rows: newCount,
                baseFontSize: baseFont,
                fontColorHex: oldLayer.fontColorHex,
                fontFamily: oldLayer.fontFamily,
                tableOpacity: oldLayer.tableOpacity,
                tableConfig: tableConfig
            )
            let wasSelected = (selectedLayerID == oldLayer.id)
            layers[idx] = newLayer
            if wasSelected { selectedLayerID = newLayer.id }
            fontRefreshTick &+= 1
        }
    }

    // MARK: - 課表 helpers

    private static let chineseNum: [String: Int] = [
        "一":1,"二":2,"三":3,"四":4,"五":5,"六":6,"七":7,"八":8,
        "九":9,"十":10,"十一":11,"十二":12,"十三":13,"十四":14,"十五":15
    ]
    private static let weekdays = ["一","二","三","四","五"]
    private static let periodNames = ["一","二","三","四","五","六","七","八","九","十","十一","十二","十三","十四","十五"]

    private func computeUserMaxPeriod(timetable: TimetableData?) -> Int {
        guard let t = timetable else { return 8 }
        var maxP = 0
        for entry in t.entries {
            if let n = Self.chineseNum[entry.period] { maxP = max(maxP, n) }
            else if let n = Int(entry.period) { maxP = max(maxP, n) }
        }
        for (_, info) in t.curriculum {
            for s in info.schedule {
                if let n = Self.chineseNum[s.period] { maxP = max(maxP, n) }
                else if let n = Int(s.period) { maxP = max(maxP, n) }
            }
        }
        return maxP > 0 ? maxP : 8
    }

    /// 回傳 nil 表示超出模板支援的最大節數
    private func pickTableKey(userMaxPeriod: Int) -> String? {
        let available = template.images.table.keys.compactMap { Int($0) }.sorted()
        guard !available.isEmpty else { return nil }
        // 小於最小值 → 用最小的
        if userMaxPeriod <= available.first! { return "\(available.first!)" }
        // 剛好有對應的
        if let exact = available.first(where: { $0 == userMaxPeriod }) { return "\(exact)" }
        // 大於最大值 → 沒有對應模板
        if userMaxPeriod > available.last! { return nil }
        // 介於中間 → 取最接近且 >= 的
        if let bigger = available.first(where: { $0 >= userMaxPeriod }) { return "\(bigger)" }
        return nil
    }

    private static let placeholderSubjects = [
        "國文","英文","數學","物理","化學","生物","地科",
        "歷史","地理","公民","體育","音樂","美術","資訊",
        "健護","家政","生科","國防","輔導","社團","班會"
    ]

    private func buildSubjectGrid(timetable: TimetableData?, rows: Int, fillPlaceholder: Bool = true) -> [[String]] {
        var grid: [[String]] = Array(repeating: Array(repeating: "", count: 5), count: rows)
        if let t = timetable {
            for r in 0..<rows {
                guard r < Self.periodNames.count else { break }
                let periodKey = Self.periodNames[r]
                for (c, weekday) in Self.weekdays.enumerated() {
                    let subject = lookupSubject(t, weekday: weekday, period: periodKey)
                    grid[r][c] = subject
                }
            }
        }
        // 空格用隨機佔位科目填充
        if fillPlaceholder {
            var shuffled = Self.placeholderSubjects.shuffled()
            var idx = 0
            for r in 0..<rows {
                for c in 0..<5 {
                    if grid[r][c].isEmpty {
                        grid[r][c] = shuffled[idx % shuffled.count]
                        idx += 1
                        if idx % shuffled.count == 0 { shuffled.shuffle() }
                    }
                }
            }
        }
        return grid
    }

    private func lookupSubject(_ t: TimetableData, weekday: String, period: String) -> String {
        for (subject, info) in t.curriculum {
            for s in info.schedule {
                if s.weekday == weekday && s.period == period { return subject }
            }
        }
        for e in t.entries {
            if e.weekday == weekday && e.period == period { return e.subject }
        }
        return ""
    }

    // MARK: - Layer 視圖

    @ViewBuilder
    private func layerView(_ layer: EditorLayer, canvas: CGSize) -> some View {
        let isSelected = (selectedLayerID == layer.id)
        Group {
            switch layer.kind {
            case .background:
                if let img = layer.image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: layer.size.width, height: layer.size.height)
                        .clipped()
                }
            case .table:
                ZStack {
                    if let img = layer.image {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(width: layer.size.width, height: layer.size.height)
                            .opacity(layer.tableOpacity)
                    }
                    textGridView(layer)
                }
                .frame(width: layer.size.width, height: layer.size.height)
            case .sticker:
                if let img = layer.image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: layer.size.width, height: layer.size.height)
                }
            }
        }
        .rotationEffect(layer.rotation)
        .overlay {
            if isSelected {
                Rectangle()
                    .stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: layer.size.width + 4, height: layer.size.height + 4)
            }
        }
        .position(x: layer.center.x, y: layer.center.y)
        .gesture(
            SimultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        if let idx = layers.firstIndex(where: { $0.id == layer.id }) {
                            var l = layers[idx]
                            l.center.x += value.translation.width - dragOffset.width
                            l.center.y += value.translation.height - dragOffset.height
                            layers[idx] = l
                            dragOffset = value.translation
                            if selectedLayerID != layer.id { selectedLayerID = layer.id }
                        }
                    }
                    .onEnded { _ in dragOffset = .zero },
                MagnificationGesture()
                    .onChanged { value in
                        guard let idx = layers.firstIndex(where: { $0.id == layer.id }) else { return }
                        if pinchLayerID != layer.id {
                            pinchLayerID = layer.id
                            pinchBaseSize = layers[idx].size
                        }
                        guard let base = pinchBaseSize else { return }
                        var l = layers[idx]
                        let newW = max(20, base.width * value)
                        let newH = max(20, base.height * value)
                        l.size = CGSize(width: newW, height: newH)
                        layers[idx] = l
                        if selectedLayerID != layer.id { selectedLayerID = layer.id }
                    }
                    .onEnded { _ in
                        pinchBaseSize = nil
                        pinchLayerID = nil
                    }
            )
        )
        .onTapGesture {
            selectedLayerID = layer.id
        }
    }

    /// 將模板 JSON 中以「table 圖原始解析度」為單位的內縮值換算為畫面顯示像素。
    private func scaledInset(_ raw: Double, layer: EditorLayer) -> CGFloat {
        guard let img = layer.image, img.size.width > 0 else { return 0 }
        let scale = layer.size.width / img.size.width
        return CGFloat(raw) * scale
    }

    @ViewBuilder
    private func textGridView(_ layer: EditorLayer) -> some View {
        let rows = max(layer.rows, 1)
        let tc = layer.tableConfig
        let leftInset = scaledInset(tc?.left ?? 0, layer: layer)
        let rightInset = scaledInset(tc?.right ?? 0, layer: layer)
        let topInset = scaledInset(tc?.topInset ?? 0, layer: layer)
        let bottomInset = scaledInset(tc?.bottom ?? 0, layer: layer)
        let usableW = max(0, layer.size.width - leftInset - rightInset)
        let usableH = max(0, layer.size.height - topInset - bottomInset)
        let cellW = usableW / 5
        let cellH = usableH / CGFloat(rows)
        let fontSize = layer.baseFontSize
        let textColor = Color(hex: layer.fontColorHex)
        let psName = FontLoader.shared.postScriptName(for: layer.fontFamily)
        VStack(spacing: 0) {
            Spacer().frame(height: topInset)
            HStack(spacing: 0) {
                Spacer().frame(width: leftInset)
                VStack(spacing: 0) {
                    ForEach(0..<rows, id: \.self) { r in
                        HStack(spacing: 0) {
                            ForEach(0..<5, id: \.self) { c in
                                Text(layer.subjects[safe: r]?[safe: c] ?? "")
                                    .font(psName.map { Font.custom($0, size: fontSize) }
                                          ?? .system(size: fontSize, weight: .medium))
                                    .foregroundStyle(textColor)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.5)
                                    .frame(width: cellW, height: cellH)
                            }
                        }
                    }
                }
                Spacer().frame(width: rightInset)
            }
            Spacer().frame(height: bottomInset)
        }
        .frame(width: layer.size.width, height: layer.size.height, alignment: .top)
        .id("\(layer.fontFamily)-\(fontRefreshTick)")
    }

    // MARK: - 工具列

    @ViewBuilder
    private var toolbar: some View {
        HStack(spacing: 12) {
            if let id = selectedLayerID,
               let layer = layers.first(where: { $0.id == id }) {
                Button {
                    pickerTargetID = id
                    showImagePicker = true
                } label: {
                    Label("更換", systemImage: "photo.stack")
                }
                Button {
                    photoTargetID = id
                    showPhotoPicker = true
                } label: {
                    Label("相簿", systemImage: "photo.on.rectangle")
                }
                if layer.kind == .table {
                    Button {
                        textSettingsLayerID = id
                        showTextSettings = true
                    } label: {
                        Label("文字", systemImage: "textformat")
                    }
                    Button {
                        showDebugInsets = true
                    } label: {
                        Label("進階", systemImage: "tablecells")
                    }
                }
                if layer.kind == .sticker {
                    Button(role: .destructive) {
                        removeLayer(id: id)
                    } label: {
                        Label("刪除", systemImage: "trash")
                    }
                }
            } else {
                Spacer()
                Button {
                    addRandomSticker()
                } label: {
                    Label("新增貼圖", systemImage: "plus.circle")
                }
                Spacer()
                Button {
                    photoTargetID = nil
                    showPhotoPicker = true
                } label: {
                    Label("從相簿", systemImage: "photo.on.rectangle")
                }
                Spacer()
                Text("點選圖層即可編輯")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .foregroundStyle(.primary)
    }

    private func setLayerImage(layerID: UUID, urlStr: String) {
        guard let url = URL(string: urlStr) else { return }
        Task {
            if let img = try? await ImageCacheService.shared.image(for: url) {
                await MainActor.run {
                    if let i = layers.firstIndex(where: { $0.id == layerID }) {
                        var l = layers[i]
                        l.image = img
                        if let newIdx = l.sourceURLs.firstIndex(of: urlStr) {
                            l.sourceIndex = newIdx
                        }
                        // 維持寬度，重算高度
                        let newH = l.size.width * (img.size.height / max(1, img.size.width))
                        if l.kind != .background {
                            l.size = CGSize(width: l.size.width, height: newH)
                        }
                        layers[i] = l
                    }
                }
            }
        }
    }

    private func addRandomSticker() {
        // 優先從已有的 sticker 圖層取圖，否則從模板 URL 下載
        let existing = layers.compactMap { $0.kind == .sticker ? $0.image : nil }
        if let image = existing.randomElement() {
            appendStickerLayer(image: image)
        } else if let urlStr = template.images.stickers.randomElement(),
                  let url = URL(string: urlStr) {
            Task {
                if let image = try? await ImageCacheService.shared.image(for: url) {
                    await MainActor.run { appendStickerLayer(image: image) }
                }
            }
        }
    }

    private func appendStickerLayer(image: UIImage) {
        let baseW: CGFloat = 80
        let baseH = baseW * (image.size.height / max(1, image.size.width))
        let cx = CGFloat.random(in: baseW...(canvasSize.width - baseW))
        let cy = CGFloat.random(in: baseH...(canvasSize.height - baseH))
        layers.append(EditorLayer(
            kind: .sticker,
            image: image,
            sourceURLs: template.images.stickers,
            sourceIndex: 0,
            center: CGPoint(x: cx, y: cy),
            size: CGSize(width: baseW, height: baseH)
        ))
    }

    private func removeLayer(id: UUID) {
        layers.removeAll { $0.id == id }
        if selectedLayerID == id { selectedLayerID = nil }
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: data) else { return }
        await MainActor.run {
            if let id = photoTargetID,
               let i = layers.firstIndex(where: { $0.id == id }) {
                // 替換既有圖層
                var l = layers[i]
                l.image = img
                if l.kind != .background {
                    let newH = l.size.width * (img.size.height / max(1, img.size.width))
                    l.size = CGSize(width: l.size.width, height: newH)
                }
                layers[i] = l
            } else {
                // 新增為貼圖
                appendStickerLayer(image: img)
            }
            photoTargetID = nil
            pickedItem = nil
        }
    }

    // MARK: - 儲存

    private func saveToPhotos() {
        let renderSize = CGSize(width: 1242, height: 2688)
        let scaleX = renderSize.width / canvasSize.width
        let scaleY = renderSize.height / canvasSize.height
        let renderer = UIGraphicsImageRenderer(size: renderSize)
        let image = renderer.image { ctx in
            for layer in layers {
                let cg = ctx.cgContext
                cg.saveGState()
                let cx = layer.center.x * scaleX
                let cy = layer.center.y * scaleY
                let w = layer.size.width * scaleX
                let h = layer.size.height * scaleY
                cg.translateBy(x: cx, y: cy)
                cg.rotate(by: CGFloat(layer.rotation.radians))
                let rect = CGRect(x: -w/2, y: -h/2, width: w, height: h)
                switch layer.kind {
                case .background, .sticker:
                    layer.image?.draw(in: rect)
                case .table:
                    cg.saveGState()
                    cg.setAlpha(CGFloat(layer.tableOpacity))
                    layer.image?.draw(in: rect)
                    cg.restoreGState()
                    let imgW = layer.image?.size.width ?? layer.size.width
                    let displayScale = rect.width / max(1, imgW)
                    let canvasScale = (scaleX + scaleY) / 2
                    drawTextGrid(layer, in: rect, displayScale: displayScale, canvasScale: canvasScale)
                }
                cg.restoreGState()
            }
        }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        showSavedAlert = true
    }

    /// 在 table layer 的繪製矩形上覆蓋文字格。
    /// `displayScale` = 將 JSON 中以原圖像素為單位的 left/right 換算到目前繪製空間的比例。
    private func drawTextGrid(_ layer: EditorLayer, in rect: CGRect, displayScale: CGFloat, canvasScale: CGFloat) {
        let rows = max(layer.rows, 1)
        let tc = layer.tableConfig
        let leftInset = CGFloat(tc?.left ?? 0) * displayScale
        let rightInset = CGFloat(tc?.right ?? 0) * displayScale
        let topInset = CGFloat(tc?.topInset ?? 0) * displayScale
        let bottomInset = CGFloat(tc?.bottom ?? 0) * displayScale
        let usableW = max(0, rect.width - leftInset - rightInset)
        let usableH = max(0, rect.height - topInset - bottomInset)
        let cellW = usableW / 5
        let cellH = usableH / CGFloat(rows)
        // 字體不跟 group 縮放，僅依 canvas→render 的比例放大
        let baseFontSize = layer.baseFontSize * canvasScale
        let psName = FontLoader.shared.postScriptName(for: layer.fontFamily)
        let textColor = UIColor(hex: layer.fontColorHex)
        // 與預覽一致：最多 2 行 + minimumScaleFactor(0.5)
        let maxLines = 2
        let minScale: CGFloat = 0.5
        func makeAttrs(_ size: CGFloat) -> [NSAttributedString.Key: Any] {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.lineBreakMode = .byCharWrapping
            let font: UIFont = (psName.flatMap { UIFont(name: $0, size: size) })
                ?? UIFont.systemFont(ofSize: size, weight: .medium)
            return [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: style
            ]
        }
        for r in 0..<rows {
            for c in 0..<5 {
                let text = layer.subjects[safe: r]?[safe: c] ?? ""
                guard !text.isEmpty else { continue }
                let cellRect = CGRect(
                    x: rect.minX + leftInset + CGFloat(c) * cellW,
                    y: rect.minY + topInset + CGFloat(r) * cellH,
                    width: cellW, height: cellH
                )
                // 找到最大可接受字級：先試 baseFontSize，不合再按比例縮小到 minScale
                var size = baseFontSize
                var attrs = makeAttrs(size)
                var bounding = (text as NSString).boundingRect(
                    with: CGSize(width: cellW, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attrs,
                    context: nil
                )
                var lineHeight = (attrs[.font] as! UIFont).lineHeight
                var lineCount = max(1, Int((bounding.height / lineHeight).rounded()))
                if lineCount > maxLines || bounding.height > cellH {
                    // 逐步縮小
                    let floor = baseFontSize * minScale
                    var low = floor, high = baseFontSize
                    for _ in 0..<12 {
                        let mid = (low + high) / 2
                        let a = makeAttrs(mid)
                        let b = (text as NSString).boundingRect(
                            with: CGSize(width: cellW, height: .greatestFiniteMagnitude),
                            options: [.usesLineFragmentOrigin, .usesFontLeading],
                            attributes: a,
                            context: nil
                        )
                        let lh = (a[.font] as! UIFont).lineHeight
                        let lc = max(1, Int((b.height / lh).rounded()))
                        if lc <= maxLines && b.height <= cellH {
                            low = mid
                            size = mid; attrs = a; bounding = b; lineHeight = lh; lineCount = lc
                        } else {
                            high = mid
                        }
                    }
                    // 若仍不符，強制使用 floor
                    if bounding.height > cellH || lineCount > maxLines {
                        size = floor
                        attrs = makeAttrs(size)
                        bounding = (text as NSString).boundingRect(
                            with: CGSize(width: cellW, height: .greatestFiniteMagnitude),
                            options: [.usesLineFragmentOrigin, .usesFontLeading],
                            attributes: attrs,
                            context: nil
                        )
                    }
                }
                let drawH = min(bounding.height, cellH)
                let drawRect = CGRect(
                    x: cellRect.minX,
                    y: cellRect.midY - drawH / 2,
                    width: cellW,
                    height: drawH
                )
                (text as NSString).draw(
                    with: drawRect,
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attrs,
                    context: nil
                )
            }
        }
    }
}

// MARK: - 圖片選擇 Sheet

private struct ImagePickerSheet: View {
    let layer: EditorLayer
    let onSelect: (String) -> Void
    let onAddSticker: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var title: String {
        switch layer.kind {
        case .background: return "選擇背景"
        case .table:      return "選擇課表"
        case .sticker:    return "選擇貼圖"
        }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(layer.sourceURLs.enumerated()), id: \.offset) { idx, urlStr in
                            Button {
                                onSelect(urlStr)
                                dismiss()
                            } label: {
                                CachedAsyncImage(url: URL(string: urlStr)) { phase in
                                    switch phase {
                                    case .success(let img):
                                        img.resizable().scaledToFit()
                                    case .failure:
                                        ZStack {
                                            Color.gray.opacity(0.15)
                                            Image(systemName: "photo").foregroundStyle(.secondary)
                                        }
                                    default:
                                        ZStack {
                                            Color.gray.opacity(0.15)
                                            ProgressView()
                                        }
                                    }
                                }
                                .frame(height: 110)
                                .frame(maxWidth: .infinity)
                                .background(Color.gray.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(idx == layer.sourceIndex ? Color.accentColor : Color.clear,
                                                lineWidth: 2)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }

                if layer.kind == .sticker {
                    Divider()
                    Button {
                        onAddSticker()
                        dismiss()
                    } label: {
                        Label("新增貼圖", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 文字設定 Sheet

private struct TextSettingsSheet: View {
    @Binding var fontSize: CGFloat
    @Binding var fontColorHex: String
    @Binding var fontFamily: String
    let fontList: [String: String]
    @Binding var isLoadingFont: Bool

    @Environment(\.dismiss) private var dismiss

    private var color: Binding<Color> {
        Binding(
            get: { Color(hex: fontColorHex) },
            set: { fontColorHex = $0.toHexString() }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("字體大小") {
                    HStack {
                        Slider(value: $fontSize, in: 6...48, step: 1)
                        Text("\(Int(fontSize))")
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                Section("字體顏色") {
                    ColorPicker("選擇顏色", selection: color, supportsOpacity: false)
                    Text(fontColorHex)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("字型") {
                    if fontList.isEmpty {
                        HStack {
                            ProgressView()
                            Text("載入字型中⋯").foregroundStyle(.secondary)
                        }
                    } else {
                        let sortedNames: [String] = fontList.keys.sorted()
                        ForEach(sortedNames, id: \.self) { (name: String) in
                            Button {
                                fontFamily = name
                            } label: {
                                HStack {
                                    Text(name)
                                    Spacer()
                                    if name == fontFamily && isLoadingFont {
                                        ProgressView()
                                    } else if name == fontFamily {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .disabled(isLoadingFont)
                        }
                    }
                }
            }
            .navigationTitle("文字設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 字型載入

final class FontLoader {
    static let shared = FontLoader()
    private init() {}

    private var list: [String: String] = [:]            // display → URL
    private var psNames: [String: String] = [:]         // display → PostScript name
    private var loadingTasks: [String: Task<String?, Never>] = [:]

    func fetchList() async throws -> [String: String] {
        guard let url = URL(string: "\(AppConfig.vocPassAPIHost)/api/wallpaper/font") else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        struct Resp: Decodable { let code: Int; let data: [String: String] }
        let resp = try JSONDecoder().decode(Resp.self, from: data)
        self.list = resp.data
        return resp.data
    }

    /// 已載入則同步回傳對應的 PostScript name。
    func postScriptName(for displayName: String) -> String? {
        psNames[displayName]
    }

    /// 非同步下載並註冊字型，回傳 PostScript name。
    @discardableResult
    func load(displayName: String) async -> String? {
        if let ps = psNames[displayName] { return ps }
        if let existing = loadingTasks[displayName] { return await existing.value }
        let task = Task<String?, Never> { [weak self] in
            guard let self,
                  let urlStr = self.list[displayName],
                  let url = URL(string: urlStr) else { return nil }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let provider = CGDataProvider(data: data as CFData),
                      let cgFont = CGFont(provider) else { return nil }
                var error: Unmanaged<CFError>?
                CTFontManagerRegisterGraphicsFont(cgFont, &error)
                let ps = cgFont.postScriptName as String?
                if let ps { self.psNames[displayName] = ps }
                return ps
            } catch {
                return nil
            }
        }
        loadingTasks[displayName] = task
        let result = await task.value
        loadingTasks[displayName] = nil
        return result
    }
}

// MARK: - Color hex

extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        var val: UInt64 = 0
        Scanner(string: h).scanHexInt64(&val)
        let r, g, b, a: Double
        switch h.count {
        case 6:
            r = Double((val >> 16) & 0xFF) / 255
            g = Double((val >> 8) & 0xFF) / 255
            b = Double(val & 0xFF) / 255
            a = 1
        case 8:
            r = Double((val >> 24) & 0xFF) / 255
            g = Double((val >> 16) & 0xFF) / 255
            b = Double((val >> 8) & 0xFF) / 255
            a = Double(val & 0xFF) / 255
        default:
            r = 0; g = 0; b = 0; a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    func toHexString() -> String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X",
                      Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }
}

extension UIColor {
    convenience init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        var val: UInt64 = 0
        Scanner(string: h).scanHexInt64(&val)
        let r = CGFloat((val >> 16) & 0xFF) / 255
        let g = CGFloat((val >> 8) & 0xFF) / 255
        let b = CGFloat(val & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - 課表設定 Sheet

private struct DebugInsetsSheet: View {
    let imageSize: CGSize
    @Binding var left: Double
    @Binding var right: Double
    @Binding var topInset: Double
    @Binding var bottom: Double
    @Binding var tableOpacity: Double
    let availablePeriods: [Int]
    @Binding var currentPeriodCount: Int
    let onPeriodChange: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    private var maxX: Double { max(50, Double(imageSize.width) / 2) }
    private var maxY: Double { max(50, Double(imageSize.height) / 2) }

    private var jsonSnippet: String {
        """
        "left": \(Int(left)),
        "right": \(Int(right)),
        "top_inset": \(Int(topInset)),
        "bottom": \(Int(bottom))
        """
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("此為開發專用，若修改課表節數，資料可能發生錯誤", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Section("節數") {
                    ForEach(availablePeriods, id: \.self) { count in
                        Button {
                            if count != currentPeriodCount {
                                currentPeriodCount = count
                                onPeriodChange(count)
                            }
                        } label: {
                            HStack {
                                Text("\(count) 節")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if count == currentPeriodCount {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
                Section("課表透明度") {
                    HStack {
                        Slider(value: $tableOpacity, in: 0...1, step: 0.05)
                        Text("\(Int(tableOpacity * 100))%")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                
                Section("原圖尺寸") {
                    Text("\(Int(imageSize.width)) × \(Int(imageSize.height)) px")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                sliderRow(title: "left", value: $left, range: 0...maxX)
                sliderRow(title: "right", value: $right, range: 0...maxX)
                sliderRow(title: "top_inset", value: $topInset, range: 0...maxY)
                sliderRow(title: "bottom", value: $bottom, range: 0...maxY)
                Section("JSON") {
                    Text(jsonSnippet)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = jsonSnippet
                    } label: {
                        Label("複製", systemImage: "doc.on.doc")
                    }
                }
            }
            .navigationTitle("課表設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        Section(title) {
            HStack {
                Slider(value: value, in: range, step: 1)
                Text("\(Int(value.wrappedValue))")
                    .font(.caption.monospaced())
                    .frame(width: 50, alignment: .trailing)
            }
            Stepper("微調", value: value, in: range, step: 1)
                .labelsHidden()
        }
    }
}

// MARK: - Array safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
