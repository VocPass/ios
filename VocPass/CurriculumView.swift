//
//  CurriculumView.swift
//  YKVS
//
//  Created by Hans on 2025/12/31.
//

import SwiftUI
import ActivityKit

struct CurriculumView: View {
    @EnvironmentObject var apiService: APIService
    @StateObject private var dynamicIsland = DynamicIslandService.shared
    @State private var curriculum: [String: CourseInfo] = CacheService.shared.getCachedTimetable()?.curriculum ?? [:]
    @State private var isLoading = CacheService.shared.getCachedTimetable() == nil
        && SchoolConfigManager.shared.selectedSchool?.isGuest != true
    @State private var errorMessage: String?
    @State private var isUnsupported = false

    // 分享
    @State private var showShareSheet = false

    // 匯出圖片
    @State private var showExportSheet = false
    @State private var exportImage: ExportImage?

    // 手動輸入科目
    @State private var manualCurriculum: [String: String] = CacheService.shared.manualCurriculum
    @State private var manualRoomTeacher: [String: CourseExtra] = CacheService.shared.manualRoomTeacher
    @State private var editingCell: (weekday: String, period: String)? = nil
    @State private var editText = ""

    // 節次時間
    @State private var apiPeriodTimes: [String: PeriodTime] = CacheService.shared.getCachedTimetable()?.periodTimes ?? [:]
    @State private var manualPeriodTimes: [String: PeriodTime] = CacheService.shared.manualPeriodTimes
    @State private var editingPeriod: String? = nil
    @State private var periodsPerDay: Int = CacheService.shared.periodsPerDay

    private let weekdays = ["一", "二", "三", "四", "五"]
    private let periodOrder = ["早讀", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十",
                                "十一", "十二", "十三", "十四", "十五",
                                "1", "2", "3", "4", "5", "6", "7", "8", "9", "10"]

    private var periods: [String] {
        let numericPeriods = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十",
                              "十一", "十二", "十三", "十四", "十五",
                              "1", "2", "3", "4", "5", "6", "7", "8", "9", "10"]

        // Collect all periods that actually have data
        var allDataPeriods = Set(curriculum.values.flatMap { $0.schedule.map { $0.period } })
        for key in manualCurriculum.keys {
            let parts = key.split(separator: "|")
            if parts.count == 2 { allDataPeriods.insert(String(parts[1])) }
        }

        var result: [String] = []
        // Include 早讀 only if there's actual data for it
        if allDataPeriods.contains("早讀") { result.append("早讀") }
        // Always show exactly periodsPerDay numeric periods
        result += Array(numericPeriods.prefix(periodsPerDay))
        return result
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("載入中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            if let error = errorMessage {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                    Text(error)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button("重試") {
                                        Task { await loadData(forceRefresh: true) }
                                    }
                                    .font(.caption)
                                }
                                .padding(10)
                                .background(Color.orange.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .padding(.horizontal)
                            } else if isUnsupported {
                                HStack(spacing: 8) {
                                    Image(systemName: "info.circle.fill")
                                        .foregroundStyle(.blue)
                                    Text("此學校尚未支援自動課表，可手動輸入")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(10)
                                .background(Color.blue.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .padding(.horizontal)
                            }

                            curriculumGrid
                                .padding(.horizontal)

                            VStack(spacing: 4) {
                                Text("點擊格子可手動輸入科目")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Text("可至「設定 › 學校設定」調整每天顯示節數（目前 \(periodsPerDay) 節）")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical)
                    }
                    .refreshable {
                        await loadData(forceRefresh: true)
                    }
                }
            }
            .navigationTitle("課表")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 4) {
                        Button {
                            renderExport()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Button {
                            showShareSheet = true
                        } label: {
                            Image(systemName: "person.2.wave.2")
                        }
                        Button {
                            Task { await loadData(forceRefresh: true) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(isLoading)
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                CurriculumShareSheet(onDownloaded: { timetable in
                    curriculum = timetable.curriculum
                    apiPeriodTimes = timetable.periodTimes
                })
                .environmentObject(apiService)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            #if canImport(UIKit)
            .sheet(isPresented: $showExportSheet) {
                if let image = exportImage {
                    ShareSheet(image: image)
                        .presentationDetents([.medium, .large])
                }
            }
            #endif
            .sheet(isPresented: Binding(
                get: { editingPeriod != nil },
                set: { if !$0 { editingPeriod = nil } }
            )) {
                if let period = editingPeriod {
                    PeriodTimeEditSheet(
                        period: period,
                        apiTime: apiPeriodTimes[period],
                        manualTime: manualPeriodTimes[period],
                        onSave: { newPt in
                            manualPeriodTimes[period] = newPt
                            CacheService.shared.manualPeriodTimes = manualPeriodTimes
                            refreshDynamicIslandTimes()
                            editingPeriod = nil
                        },
                        onClear: {
                            manualPeriodTimes.removeValue(forKey: period)
                            CacheService.shared.manualPeriodTimes = manualPeriodTimes
                            refreshDynamicIslandTimes()
                            editingPeriod = nil
                        },
                        onCancel: { editingPeriod = nil }
                    )
                    .presentationDetents([.height(320)])
                    .presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: Binding(
                get: { editingCell != nil },
                set: { if !$0 { editingCell = nil } }
            )) {
                if let cell = editingCell {
                    let key = manualKey(cell.weekday, cell.period)
                    CellEditSheet(
                        weekday: cell.weekday,
                        period: cell.period,
                        currentText: editText,
                        currentExtra: manualRoomTeacher[key] ?? apiExtra(weekday: cell.weekday, period: cell.period),
                        apiSubject: apiSubject(weekday: cell.weekday, period: cell.period),
                        apiExtra: apiExtra(weekday: cell.weekday, period: cell.period),
                        hasManualOverride: manualCurriculum[key] != nil || manualRoomTeacher[key] != nil,
                        onSave: { newText, newExtra in
                            manualCurriculum[key] = newText
                            CacheService.shared.manualCurriculum = manualCurriculum
                            if newExtra.room.isEmpty && newExtra.teacher.isEmpty {
                                manualRoomTeacher.removeValue(forKey: key)
                            } else {
                                manualRoomTeacher[key] = newExtra
                            }
                            CacheService.shared.manualRoomTeacher = manualRoomTeacher
                            editingCell = nil
                            DynamicIslandService.shared.uploadTokensToServer()
                        },
                        onClear: {
                            manualCurriculum.removeValue(forKey: key)
                            manualRoomTeacher.removeValue(forKey: key)
                            CacheService.shared.manualCurriculum = manualCurriculum
                            CacheService.shared.manualRoomTeacher = manualRoomTeacher
                            editingCell = nil
                            DynamicIslandService.shared.uploadTokensToServer()
                        },
                        onCancel: {
                            editingCell = nil
                        }
                    )
                    .presentationDetents([.height(360)])
                    .presentationDragIndicator(.visible)
                }
            }
        }
        .task {
            await loadData()
        }
        .onAppear {
            periodsPerDay = CacheService.shared.periodsPerDay
        }
    }

    // MARK: - 課表格線

    private var curriculumGrid: some View {
        VStack(spacing: 1) {
            HStack(spacing: 1) {
                Text("節次")
                    .frame(width: 40, height: 40)
                    .background(Color(.systemGray5))
                    .font(.caption)

                ForEach(weekdays, id: \.self) { weekday in
                    Text("週\(weekday)")
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Color(.systemGray5))
                        .font(.caption)
                }
            }

            ForEach(periods, id: \.self) { period in
                HStack(spacing: 1) {
                    Button {
                        editingPeriod = period
                    } label: {
                        VStack(spacing: 1) {
                            Text(period == "早讀" ? "讀" : period)
                                .font(.caption)
                            if let pt = effectivePeriodTime(for: period) {
                                Text(pt.startTime)
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                                Text(pt.endTime)
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 40, height: 68)
                        .background(manualPeriodTimes[period] != nil
                                    ? Color.orange.opacity(0.12)
                                    : Color(.systemGray6))
                    }
                    .buttonStyle(.plain)

                    ForEach(weekdays, id: \.self) { weekday in
                        let subject  = getSubject(weekday: weekday, period: period)
                        let extra    = getExtra(weekday: weekday, period: period)
                        let isNow    = isCurrentPeriod(weekday: weekday, period: period)
                        let isManual = manualCurriculum[manualKey(weekday, period)] != nil
                                    || manualRoomTeacher[manualKey(weekday, period)] != nil
                        let meta     = [extra.room, extra.teacher].filter { !$0.isEmpty }.joined(separator: "・")

                        Button {
                            editText = subject
                            editingCell = (weekday: weekday, period: period)
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                VStack(spacing: 2) {
                                    Text(subject.isEmpty ? " " : subject)
                                        .font(.system(size: 11, weight: isNow ? .semibold : .regular))
                                        .foregroundStyle(subject.isEmpty ? Color.clear : Color.primary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                    if !meta.isEmpty {
                                        Text(meta)
                                            .font(.system(size: 8))
                                            .foregroundStyle(isNow ? Color.blue.opacity(0.8) : Color.secondary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.center)
                                    }
                                }
                                .padding(.horizontal, 2)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, minHeight: 68)
                                .background(
                                    isNow
                                        ? Color.blue.opacity(0.18)
                                        : (subject.isEmpty
                                           ? Color(.systemBackground)
                                           : randomColor(for: subject).opacity(0.15))
                                )
                                .overlay(isNow ? RoundedRectangle(cornerRadius: 2).stroke(Color.blue, lineWidth: 1.5) : nil)

                                if isManual {
                                    Circle()
                                        .fill(Color.orange)
                                        .frame(width: 5, height: 5)
                                        .padding(3)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .background(Color(.systemGray4))
        .cornerRadius(8)
    }

    // MARK: - 輔助

    private func effectivePeriodTime(for period: String) -> PeriodTime? {
        manualPeriodTimes[period] ?? apiPeriodTimes[period]
    }

    // MARK: - Export

    private func renderExport() {
        Task {
            await ExportIconLoader.shared.preload()
            let content = IGStoryContainer(iconImage: ExportIconLoader.shared.loadedImage) {
                CurriculumExportContent(
                    curriculum: curriculum,
                    manualCurriculum: manualCurriculum,
                    manualRoomTeacher: manualRoomTeacher,
                    weekdays: weekdays,
                    periods: periods
                )
            }
            exportImage = content.renderToImage(
                size: IGStoryExport.size,
                scale: 1.0
            )
            showExportSheet = true
        }
    }

    private func refreshDynamicIslandTimes() {
        // 重新套用手動時間到 DynamicIsland，保留已有的 entries
        let cachedEntries = CacheService.shared.getCachedTimetable()?.entries ?? []
        var merged = TimetableData(entries: cachedEntries, periodTimes: apiPeriodTimes, curriculum: curriculum)
        for (period, pt) in manualPeriodTimes {
            merged.periodTimes[period] = pt
        }
        DynamicIslandService.shared.setTimetable(merged)
    }

    private func manualKey(_ weekday: String, _ period: String) -> String {
        "\(weekday)|\(period)"
    }

    private func apiSubject(weekday: String, period: String) -> String {
        for (subject, info) in curriculum {
            for schedule in info.schedule {
                if schedule.weekday == weekday && schedule.period == period {
                    return subject
                }
            }
        }
        return ""
    }

    private func apiExtra(weekday: String, period: String) -> CourseExtra {
        for (_, info) in curriculum {
            for schedule in info.schedule {
                if schedule.weekday == weekday && schedule.period == period {
                    return CourseExtra(room: schedule.room ?? "", teacher: schedule.teacher ?? "")
                }
            }
        }
        return CourseExtra(room: "", teacher: "")
    }

    private func getSubject(weekday: String, period: String) -> String {
        let key = manualKey(weekday, period)
        if let manual = manualCurriculum[key] {
            return manual
        }
        return apiSubject(weekday: weekday, period: period)
    }

    private func getExtra(weekday: String, period: String) -> CourseExtra {
        let key = manualKey(weekday, period)
        if let manual = manualRoomTeacher[key] { return manual }
        return apiExtra(weekday: weekday, period: period)
    }

    private func isCurrentPeriod(weekday: String, period: String) -> Bool {
        guard dynamicIsland.isActivityRunning else { return false }
        guard !dynamicIsland.currentPeriod.isEmpty else { return false }
        let weekdayMap: [Int: String] = [1:"日",2:"一",3:"二",4:"三",5:"四",6:"五",7:"六"]
        let today = weekdayMap[Calendar.current.component(.weekday, from: Date())] ?? ""
        return weekday == today && period == dynamicIsland.currentPeriod
    }

    private func randomColor(for subject: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan, .mint, .indigo]
        let hash = abs(subject.hashValue)
        return colors[hash % colors.count]
    }

    private func loadData(forceRefresh: Bool = false) async {
        if SchoolConfigManager.shared.selectedSchool?.isGuest == true {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = nil
                self.isUnsupported = false
            }
            return
        }

        isLoading = true
        errorMessage = nil
        isUnsupported = false

        do {
            let timetable = try await apiService.fetchTimetableData(forceRefresh: forceRefresh)
            await MainActor.run {
                self.curriculum = timetable.curriculum
                self.apiPeriodTimes = timetable.periodTimes
                var merged = timetable
                for (period, pt) in self.manualPeriodTimes {
                    merged.periodTimes[period] = pt
                }
                DynamicIslandService.shared.setTimetable(merged)
                self.isLoading = false
            }
        } catch APIError.featureNotSupported {
            await MainActor.run {
                self.isUnsupported = true
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

// MARK: - 節次時間編輯 Sheet

struct PeriodTimeEditSheet: View {
    let period: String
    let apiTime: PeriodTime?
    let manualTime: PeriodTime?
    let onSave: (PeriodTime) -> Void
    let onClear: () -> Void
    let onCancel: () -> Void

    @State private var startDate: Date
    @State private var endDate: Date

    init(period: String, apiTime: PeriodTime?, manualTime: PeriodTime?,
         onSave: @escaping (PeriodTime) -> Void,
         onClear: @escaping () -> Void,
         onCancel: @escaping () -> Void) {
        self.period = period
        self.apiTime = apiTime
        self.manualTime = manualTime
        self.onSave = onSave
        self.onClear = onClear
        self.onCancel = onCancel

        let source = manualTime ?? apiTime
        _startDate = State(initialValue: Self.parse(source?.startTime) ?? Date())
        _endDate   = State(initialValue: Self.parse(source?.endTime)   ?? Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("第\(period)節時間")
                    .font(.headline)
                Spacer()
                Button("取消", action: onCancel)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label("開始", systemImage: "play.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)
                DatePicker("", selection: $startDate, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }

            HStack {
                Label("結束", systemImage: "stop.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)
                DatePicker("", selection: $endDate, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }

            if let api = apiTime {
                Button {
                    startDate = Self.parse(api.startTime) ?? startDate
                    endDate   = Self.parse(api.endTime)   ?? endDate
                } label: {
                    Label("還原為課表資料：\(api.startTime)～\(api.endTime)", systemImage: "arrow.uturn.backward")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                if manualTime != nil {
                    Button(role: .destructive, action: onClear) {
                        Text("清除手動設定")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    onSave(PeriodTime(startTime: Self.format(startDate),
                                     endTime:   Self.format(endDate)))
                } label: {
                    Text("儲存")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
    }

    private static func parse(_ str: String?) -> Date? {
        guard let str else { return nil }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.date(from: str)
    }

    private static func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

// MARK: - 格子編輯 Sheet

struct CellEditSheet: View {
    let weekday: String
    let period: String
    @State var currentText: String
    @State var currentExtra: CourseExtra
    let apiSubject: String
    let apiExtra: CourseExtra
    let hasManualOverride: Bool
    let onSave: (String, CourseExtra) -> Void
    let onClear: () -> Void
    let onCancel: () -> Void

    @FocusState private var focusedField: Field?
    private enum Field { case subject, room, teacher }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("週\(weekday) 第\(period)節")
                    .font(.headline)
                Spacer()
                Button("取消", action: onCancel)
                    .foregroundStyle(.secondary)
            }

            TextField("科目名稱", text: $currentText)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .subject)
                .onSubmit { focusedField = .room }

            HStack(spacing: 8) {
                Label("", systemImage: "door.right.hand.closed")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                TextField("教室（選填）", text: $currentExtra.room)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .room)
                    .onSubmit { focusedField = .teacher }
            }

            HStack(spacing: 8) {
                Label("", systemImage: "person.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                TextField("教師（選填）", text: $currentExtra.teacher)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .teacher)
                    .onSubmit { onSave(currentText, currentExtra) }
            }

            let hasApiDiff = (!apiSubject.isEmpty && apiSubject != currentText)
                          || (!apiExtra.room.isEmpty && apiExtra.room != currentExtra.room)
                          || (!apiExtra.teacher.isEmpty && apiExtra.teacher != currentExtra.teacher)
            if hasApiDiff {
                Button {
                    currentText  = apiSubject
                    currentExtra = apiExtra
                } label: {
                    Label("還原為課表資料", systemImage: "arrow.uturn.backward")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                if hasManualOverride {
                    Button(role: .destructive) {
                        onClear()
                    } label: {
                        Text("清除手動設定")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    onSave(currentText, currentExtra)
                } label: {
                    Text("儲存")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .onAppear { focusedField = .subject }
    }
}

// MARK: - 課表分享 Sheet

struct CurriculumShareSheet: View {
    var onDownloaded: ((TimetableData) -> Void)? = nil

    @EnvironmentObject var apiService: APIService
    @StateObject private var vocPassAuth = VocPassAuthService.shared

    @State private var isSharing: Bool = CacheService.shared.isCurriculumSharing
    @State private var isLoadingStatus = false
    @State private var isUpdating = false
    @State private var isSyncing = false
    @State private var syncMessage: String?
    @State private var errorMessage: String?

    // 下載他人課表
    @State private var downloadUsername = ""
    @State private var isDownloading = false
    @State private var downloadMessage: String?
    @State private var downloadError: String?
    @State private var showDownloadConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 標題列
            HStack {
                Label("分享課表", systemImage: "person.2.wave.2.fill")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !vocPassAuth.isLoggedIn {
                        // 未登入 VocPass 帳號
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.badge.exclamationmark")
                                .font(.title2)
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("請先登入 VocPass 帳號")
                                    .font(.subheadline.weight(.medium))
                                Text("需要 VocPass 帳號才能使用課表分享功能。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(14)
                        .background(Color.orange.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        // 使用者資訊
                        HStack(spacing: 12) {
                            Image(systemName: "person.circle.fill")
                                .font(.title)
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(vocPassAuth.currentUser?.displayName ?? "")
                                    .font(.subheadline.weight(.medium))
                                Text("@\(vocPassAuth.currentUser?.username ?? "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Divider()

                        // 說明
                        VStack(alignment: .leading, spacing: 10) {
                            Label("如何運作？", systemImage: "info.circle.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.blue)

                            VStack(alignment: .leading, spacing: 6) {
                                BulletRow(icon: "arrow.up.to.line", text: "開啟共享後，你的課表資料將上傳至 VocPass 伺服器。")
                                BulletRow(icon: "person.badge.plus", text: "其他人可以透過你的用戶名稱（\(vocPassAuth.currentUser?.username ?? "username")）追蹤你的課表。")
                                BulletRow(icon: "lock.open", text: "關閉共享後，伺服器上的課表資料將設為私人。")
                            }
                        }

                        Divider()

                        // 開關
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("開始共享課表")
                                    .font(.subheadline.weight(.medium))
                                Text(isSharing ? "目前已開啟，課表對外可見" : "目前已關閉，課表為私人狀態")
                                    .font(.caption)
                                    .foregroundStyle(isSharing ? .green : .secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $isSharing)
                                .labelsHidden()
                                .disabled(isLoadingStatus || isUpdating)
                                .opacity(isLoadingStatus || isUpdating ? 0 : 1)
                                .onChange(of: isSharing) { _, newValue in
                                    guard !isLoadingStatus else { return }
                                    Task { await updateSharing(newValue) }
                                }
                                .overlay {
                                    if isLoadingStatus || isUpdating {
                                        ProgressView().scaleEffect(0.9)
                                    }
                                }
                        }
                        .padding(14)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        // 重新同步按鈕
                        Button {
                            Task { await resync() }
                        } label: {
                            HStack {
                                if isSyncing {
                                    ProgressView()
                                        .scaleEffect(0.85)
                                        .tint(.white)
                                } else {
                                    Label("重新同步課表至伺服器", systemImage: "arrow.triangle.2.circlepath")
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSyncing || isUpdating || isLoadingStatus)

                        if let msg = syncMessage {
                            Label(msg, systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }

                        if let err = errorMessage {
                            Label(err, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        Divider()

                        // 下載他人課表
                        VStack(alignment: .leading, spacing: 10) {
                            Label("下載他人課表", systemImage: "arrow.down.circle.fill")
                                .font(.subheadline.weight(.medium))

                            Text("輸入對方的用戶名稱，將其課表下載並覆蓋目前的課表。")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                HStack(spacing: 4) {
                                    Text("@")
                                        .foregroundStyle(.secondary)
                                        .font(.subheadline)
                                    TextField("用戶名稱", text: $downloadUsername)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .onSubmit {
                                            if !downloadUsername.trimmingCharacters(in: .whitespaces).isEmpty {
                                                showDownloadConfirm = true
                                            }
                                        }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                Button {
                                    showDownloadConfirm = true
                                } label: {
                                    if isDownloading {
                                        ProgressView().scaleEffect(0.85)
                                    } else {
                                        Image(systemName: "arrow.down.circle.fill")
                                            .font(.title2)
                                    }
                                }
                                .disabled(downloadUsername.trimmingCharacters(in: .whitespaces).isEmpty || isDownloading)
                                .tint(.blue)
                            }

                            if let msg = downloadMessage {
                                Label(msg, systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                            if let err = downloadError {
                                Label(err, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
                .padding(24)
            }
        }
        .confirmationDialog(
            "下載 @\(downloadUsername) 的課表並覆蓋目前課表？",
            isPresented: $showDownloadConfirm,
            titleVisibility: .visible
        ) {
            Button("下載並覆蓋", role: .destructive) {
                Task { await downloadCurriculum() }
            }
            Button("取消", role: .cancel) {}
        }
        .task {
            guard vocPassAuth.isLoggedIn else { return }
            isLoadingStatus = true
            do {
                let user = try await vocPassAuth.fetchMe()
                await MainActor.run {
                    if let status = user.shareStatus {
                        isSharing = status
                        CacheService.shared.isCurriculumSharing = status
                    }
                }
            } catch {
                // 保留快取值，不做任何變更
            }
            await MainActor.run { isLoadingStatus = false }
        }
    }

    private func updateSharing(_ share: Bool) async {
        isUpdating = true
        errorMessage = nil
        syncMessage = nil
        do {
            try await apiService.setCurriculumSharing(share: share)
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isSharing = !share   // rollback
            }
        }
        await MainActor.run { isUpdating = false }
    }

    private func downloadCurriculum() async {
        let target = downloadUsername.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return }
        isDownloading = true
        downloadError = nil
        downloadMessage = nil
        do {
            let timetable = try await apiService.fetchSharedCurriculum(username: target)
            CacheService.shared.cacheTimetable(timetable)
            await MainActor.run {
                downloadMessage = "已成功下載 @\(target) 的課表"
                onDownloaded?(timetable)
            }
        } catch {
            await MainActor.run { downloadError = error.localizedDescription }
        }
        await MainActor.run { isDownloading = false }
    }

    private func resync() async {
        isSyncing = true
        errorMessage = nil
        syncMessage = nil
        do {
            try await apiService.setCurriculumSharing(share: isSharing)
            await MainActor.run { syncMessage = "同步成功" }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
        await MainActor.run { isSyncing = false }
    }
}

private struct BulletRow: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Curriculum Export Content

struct CurriculumExportContent: View {
    let curriculum: [String: CourseInfo]
    let manualCurriculum: [String: String]
    let manualRoomTeacher: [String: CourseExtra]
    let weekdays: [String]
    let periods: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ExportHeader("課表", subtitle: "\(weekdays.count) 天 · \(periods.count) 節")

            gridView
                .padding(.horizontal, IGStoryExport.padding)
                .padding(.top, 12)

            Spacer(minLength: 0)
        }
    }

    private var gridView: some View {
        let labelWidth: CGFloat = 48
        let gridPadding: CGFloat = 0
        let colWidth: CGFloat = (IGStoryExport.size.width - IGStoryExport.padding * 2 - gridPadding * 2 - labelWidth) / CGFloat(weekdays.count)
        let rowHeight: CGFloat = min(84, max(68, 1500 / CGFloat(max(periods.count, 1))))

        return VStack(spacing: 1) {
            // Header
            HStack(spacing: 1) {
                // Empty corner
                Rectangle()
                    .fill(Color(.systemBackground))
                    .frame(width: labelWidth, height: 40)

                ForEach(weekdays, id: \.self) { day in
                    Text("週\(day)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: colWidth, height: 40)
                        .background(Color(.systemGray6))
                }
            }

            ForEach(periods, id: \.self) { period in
                HStack(spacing: 1) {
                    Text(period == "早讀" ? "早" : period)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: labelWidth, height: rowHeight)
                        .background(Color(.systemBackground))

                    ForEach(weekdays, id: \.self) { day in
                        let subject = getSubject(weekday: day, period: period)
                        let extra = getExtra(weekday: day, period: period)
                        let meta = [extra.room, extra.teacher]
                            .filter { !$0.isEmpty }.joined(separator: " · ")

                        VStack(spacing: 4) {
                            if !subject.isEmpty {
                                Text(subject)
                                    .font(.system(size: 14, weight: .semibold))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.primary)
                            }
                            if !meta.isEmpty {
                                Text(meta)
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(width: colWidth, height: rowHeight)
                        .background(
                            subject.isEmpty
                                ? Color(.systemBackground)
                                : subjectColor(subject).opacity(0.10)
                        )
                    }
                }
            }
        }
        .background(Color(.separator).opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
    }

    private func manualKey(_ w: String, _ p: String) -> String { "\(w)|\(p)" }

    private func apiSubject(weekday: String, period: String) -> String {
        for (subject, info) in curriculum {
            for s in info.schedule where s.weekday == weekday && s.period == period {
                return subject
            }
        }
        return ""
    }

    private func apiExtra(weekday: String, period: String) -> CourseExtra {
        for (_, info) in curriculum {
            for s in info.schedule where s.weekday == weekday && s.period == period {
                return CourseExtra(room: s.room ?? "", teacher: s.teacher ?? "")
            }
        }
        return CourseExtra(room: "", teacher: "")
    }

    private func getSubject(weekday: String, period: String) -> String {
        manualCurriculum[manualKey(weekday, period)] ?? apiSubject(weekday: weekday, period: period)
    }

    private func getExtra(weekday: String, period: String) -> CourseExtra {
        manualRoomTeacher[manualKey(weekday, period)] ?? apiExtra(weekday: weekday, period: period)
    }

    private func subjectColor(_ subject: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan, .mint, .indigo]
        return colors[abs(subject.hashValue) % colors.count]
    }
}

#Preview {
    CurriculumView()
        .environmentObject(APIService.shared)
}
