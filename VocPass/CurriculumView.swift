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
    @State private var curriculum: [String: CourseInfo] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isUnsupported = false

    // 手動輸入科目
    @State private var manualCurriculum: [String: String] = CacheService.shared.manualCurriculum
    @State private var editingCell: (weekday: String, period: String)? = nil
    @State private var editText = ""

    // 節次時間
    @State private var apiPeriodTimes: [String: PeriodTime] = [:]
    @State private var manualPeriodTimes: [String: PeriodTime] = CacheService.shared.manualPeriodTimes
    @State private var editingPeriod: String? = nil

    private let weekdays = ["一", "二", "三", "四", "五"]
    private let periodOrder = ["早讀", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十",
                                "1", "2", "3", "4", "5", "6", "7", "8", "9", "10"]
    private let defaultPeriods = ["一", "二", "三", "四", "五", "六", "七", "八"]

    private var periods: [String] {
        var all: [String] = []
        all += curriculum.values.flatMap { $0.schedule.map { $0.period } }
        for key in manualCurriculum.keys {
            let parts = key.split(separator: "|")
            if parts.count == 2 { all.append(String(parts[1])) }
        }
        let unique = Array(Set(all)).filter { !$0.isEmpty }
        if unique.isEmpty { return defaultPeriods }
        return unique.sorted { a, b in
            let ia = periodOrder.firstIndex(of: a) ?? Int.max
            let ib = periodOrder.firstIndex(of: b) ?? Int.max
            if ia != Int.max || ib != Int.max { return ia < ib }
            return (Int(a) ?? 0) < (Int(b) ?? 0)
        }
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

                            Text("點擊格子可手動輸入科目")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
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
                    Button {
                        Task { await loadData(forceRefresh: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
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
                    CellEditSheet(
                        weekday: cell.weekday,
                        period: cell.period,
                        currentText: editText,
                        apiSubject: apiSubject(weekday: cell.weekday, period: cell.period),
                        hasManualOverride: manualCurriculum[manualKey(cell.weekday, cell.period)] != nil,
                        onSave: { newText in
                            let key = manualKey(cell.weekday, cell.period)
                            manualCurriculum[key] = newText
                            CacheService.shared.manualCurriculum = manualCurriculum
                            editingCell = nil
                        },
                        onClear: {
                            let key = manualKey(cell.weekday, cell.period)
                            manualCurriculum.removeValue(forKey: key)
                            CacheService.shared.manualCurriculum = manualCurriculum
                            editingCell = nil
                        },
                        onCancel: {
                            editingCell = nil
                        }
                    )
                    .presentationDetents([.height(280)])
                    .presentationDragIndicator(.visible)
                }
            }
        }
        .task {
            await loadData()
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
                        .frame(width: 40, height: 60)
                        .background(manualPeriodTimes[period] != nil
                                    ? Color.orange.opacity(0.12)
                                    : Color(.systemGray6))
                    }
                    .buttonStyle(.plain)

                    ForEach(weekdays, id: \.self) { weekday in
                        let subject = getSubject(weekday: weekday, period: period)
                        let isNow   = isCurrentPeriod(weekday: weekday, period: period)
                        let isManual = manualCurriculum[manualKey(weekday, period)] != nil

                        Button {
                            editText = subject
                            editingCell = (weekday: weekday, period: period)
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Text(subject)
                                    .frame(maxWidth: .infinity, minHeight: 60)
                                    .background(
                                        isNow
                                            ? Color.blue.opacity(0.25)
                                            : (subject.isEmpty
                                               ? Color(.systemBackground)
                                               : randomColor(for: subject).opacity(0.2))
                                    )
                                    .overlay(isNow ? RoundedRectangle(cornerRadius: 2).stroke(Color.blue, lineWidth: 1.5) : nil)
                                    .font(.caption2)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)

                                if isManual {
                                    Circle()
                                        .fill(Color.orange)
                                        .frame(width: 5, height: 5)
                                        .padding(4)
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

    private func refreshDynamicIslandTimes() {
        // 重新套用手動時間到 DynamicIsland
        var merged = TimetableData(entries: [], periodTimes: apiPeriodTimes, curriculum: curriculum)
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

    private func getSubject(weekday: String, period: String) -> String {
        let key = manualKey(weekday, period)
        if let manual = manualCurriculum[key] {
            return manual
        }
        return apiSubject(weekday: weekday, period: period)
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
    let apiSubject: String
    let hasManualOverride: Bool
    let onSave: (String) -> Void
    let onClear: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("週\(weekday) 第\(period)節")
                    .font(.headline)
                Spacer()
                Button("取消", action: onCancel)
                    .foregroundStyle(.secondary)
            }

            TextField("輸入科目名稱", text: $currentText)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit { onSave(currentText) }

            if !apiSubject.isEmpty && apiSubject != currentText {
                Button {
                    currentText = apiSubject
                } label: {
                    Label("還原為課表資料：\(apiSubject)", systemImage: "arrow.uturn.backward")
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
                    onSave(currentText)
                } label: {
                    Text("儲存")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .onAppear { isFocused = true }
    }
}

#Preview {
    CurriculumView()
        .environmentObject(APIService.shared)
}
