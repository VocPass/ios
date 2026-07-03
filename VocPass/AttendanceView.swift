//
//  AttendanceView.swift
//  YKVS
//
//  Created by Hans on 2025/12/31.
//

import SwiftUI

struct AttendanceView: View {
    @EnvironmentObject var apiService: APIService
    @State private var statistics: AttendanceStatistics = AttendanceStatistics()
    @State private var subjectAbsences: [SubjectAbsence] = []
    @State private var allRecords: [AbsenceRecord] = []
    @State private var courseMapping: [String: String] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isUnsupported = false
    @AppStorage("excludeNonStandardPeriods") private var excludeNonStandardPeriods = true
    @State private var searchText = ""
    @State private var showShareSheet = false
    @State private var exportImage: ExportImage?

    private var groupedRecords: [(date: String, records: [AbsenceRecord])] {
        let filtered: [AbsenceRecord]
        if searchText.isEmpty {
            filtered = allRecords
        } else {
            let q = searchText.lowercased()
            filtered = allRecords.filter {
                $0.date.lowercased().contains(q) ||
                $0.status.contains(searchText) ||
                $0.weekday.contains(searchText) ||
                $0.period.contains(searchText) ||
                $0.academicYear.contains(searchText)
            }
        }
        let grouped = Dictionary(grouping: filtered, by: \.date)
        return grouped.keys.sorted(by: >).map { date in
            (date: date, records: grouped[date]!.sorted { ($0.period) < ($1.period) })
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("載入中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isUnsupported {
                    UnsupportedFeatureView()
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        Text(error)
                            .foregroundColor(.secondary)
                        Button("重試") {
                            Task { await loadData() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        if searchText.isEmpty {
                            // 總覽區塊
                            Section("缺曠總覽") {
                                statisticsOverview
                            }

                            // 各科缺曠
                            Section("各科缺曠統計") {
                                if subjectAbsences.isEmpty {
                                    Text("無缺曠記錄")
                                        .foregroundColor(.secondary)
                                } else {
                                    ForEach(subjectAbsences.filter { $0.truancy + $0.personalLeave > 0 }) { absence in
                                        SubjectAbsenceRow(absence: absence)
                                    }
                                }
                            }
                        }

                        // 缺曠明細
                        Section(searchText.isEmpty ? "缺曠明細" : "搜尋結果（\(groupedRecords.count) 天）") {
                            if groupedRecords.isEmpty {
                                Text(searchText.isEmpty ? "無缺曠記錄" : "找不到符合的記錄")
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(groupedRecords, id: \.date) { group in
                                    AbsenceDayRow(date: group.date, records: group.records, courseMapping: courseMapping)
                                }
                            }
                        }
                    }
                    .refreshable {
                        await loadData()
                    }
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            HStack(spacing: 4) {
                                Button {
                                    renderExport()
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                Toggle(isOn: $excludeNonStandardPeriods) {
                                    Text("僅 1~7 節")
                                        .font(.caption)
                                }
                                .toggleStyle(.button)
                                .tint(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("缺曠統計")
            .searchable(text: $searchText, prompt: "搜尋日期、類型、節次...")
        }
        .task {
            await loadData()
        }
        .onChange(of: excludeNonStandardPeriods) {
            statistics = apiService.computeAttendanceStatistics(from: allRecords, filterStandardOnly: excludeNonStandardPeriods)
        }
        #if canImport(UIKit)
        .sheet(isPresented: $showShareSheet) {
            if let image = exportImage {
                ShareSheet(image: image)
                    .presentationDetents([.medium, .large])
            }
        }
        #endif
    }

    // MARK: - Export

    private func renderExport() {
        Task {
            await ExportIconLoader.shared.preload()
            let content = IGStoryContainer(iconImage: ExportIconLoader.shared.loadedImage) {
                AttendanceExportContent(
                    statistics: statistics,
                    subjectAbsences: subjectAbsences,
                    allRecords: allRecords
                )
            }
            exportImage = content.renderToImage(
                size: IGStoryExport.size,
                scale: 1.0
            )
            showShareSheet = true
        }
    }

    private var statisticsOverview: some View {
        VStack(spacing: 16) {
            // 上學期統計
            if !statistics.firstSemester.isEmpty {
                SemesterStatCard(
                    title: "上學期",
                    data: statistics.firstSemester
                )
            }

            // 下學期統計
            if !statistics.secondSemester.isEmpty {
                SemesterStatCard(
                    title: "下學期",
                    data: statistics.secondSemester
                )
            }

            // 全部總計
            VStack(spacing: 8) {
                Text("全部合計")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    StatCard(title: "曠課", value: "\(statistics.total.truancy)", color: .red)
                    StatCard(title: "事假", value: "\(statistics.total.personalLeave)", color: .orange)
                    StatCard(title: "病假", value: "\(statistics.total.sickLeave)", color: .blue)
                    StatCard(title: "公假", value: "\(statistics.total.officialLeave)", color: .green)
                }
            }

            if !statistics.statisticsDate.isEmpty {
                Text(statistics.statisticsDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await apiService.fetchAttendanceWithCurriculum()
            await MainActor.run {
                self.allRecords = result.records
                self.courseMapping = result.courseMapping
                self.statistics = apiService.computeAttendanceStatistics(from: result.records, filterStandardOnly: excludeNonStandardPeriods)
                self.subjectAbsences = result.subjectAbsences
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

struct StatCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

// 學期統計卡片 - 顯示各學期的缺曠資料
struct SemesterStatCard: View {
    let title: String
    let data: [String: String]

    private func getValue(_ key: String) -> Int {
        return Int(data[key] ?? "0") ?? 0
    }

    private var personalLeave: Int {
        getValue("事假") + getValue("事假1")
    }

    private var sickLeave: Int {
        getValue("病假") + getValue("病假1") + getValue("病假2")
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("\(title)合計")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                StatCard(title: "曠課", value: "\(getValue("曠課"))", color: .red)
                StatCard(title: "事假", value: "\(personalLeave)", color: .orange)
                StatCard(title: "病假", value: "\(sickLeave)", color: .blue)
                StatCard(title: "公假", value: "\(getValue("公假"))", color: .green)
            }
        }
    }
}

struct SubjectAbsenceRow: View {
    let absence: SubjectAbsence
    @AppStorage("absence_threshold_is_half") private var thresholdIsHalf = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(absence.subject)
                    .font(.headline)
                Spacer()
                Text("\(absence.percentage)%")
                    .font(.caption)
                    .foregroundColor(percentageColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(percentageColor.opacity(0.1))
                    .cornerRadius(4)
            }

            HStack {
                Label("\(absence.truancy)", systemImage: "xmark.circle")
                    .font(.caption)
                    .foregroundColor(.red)
                Label("\(absence.personalLeave)", systemImage: "calendar.badge.minus")
                    .font(.caption)
                    .foregroundColor(.orange)
                Spacer()
                Text("總計: \(absence.total) / \(absence.totalClasses)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 6)
                        .cornerRadius(3)

                    Rectangle()
                        .fill(percentageColor)
                        .frame(width: geometry.size.width * CGFloat(absence.percentage) / 100, height: 6)
                        .cornerRadius(3)
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 4)
    }

    private var percentageColor: Color {
        let limit = thresholdIsHalf ? 50 : 33
        if absence.percentage >= limit { return .red }
        else if absence.percentage >= limit * 3 / 4 { return .orange }
        else if absence.percentage >= limit / 2 { return .yellow }
        else { return .green }
    }
}

struct AbsenceDayRow: View {
    let date: String
    let records: [AbsenceRecord]
    let courseMapping: [String: String]

    private static let numberMap = ["1": "一", "2": "二", "3": "三", "4": "四", "5": "五", "6": "六", "7": "七"]

    private static var currentSemesterLabel: String {
        let month = Calendar.current.component(.month, from: Date())
        return (month > 8 || month < 3) ? "上" : "下"
    }

    private func subject(for record: AbsenceRecord) -> String? {
        guard record.academicYear == Self.currentSemesterLabel else { return nil }
        let chinesePeriod = Self.numberMap[record.period] ?? record.period
        let key = "\(record.weekday)-\(chinesePeriod)"
        return courseMapping[key]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(date)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let weekday = records.first?.weekday, !weekday.isEmpty {
                    Text(weekday)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let semester = records.first?.academicYear, !semester.isEmpty {
                    Text("\(semester)學期")
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.6))
                        .cornerRadius(4)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(records) { record in
                    HStack(spacing: 4) {
                        Text(record.status)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(statusColor(record.status))
                            .cornerRadius(5)
                        VStack(alignment: .leading, spacing: 0) {
                            if let name = subject(for: record) {
                                Text(name)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                            }
                            if !record.period.isEmpty {
                                Text("第\(record.period)節")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(statusColor(record.status).opacity(0.08))
                    .cornerRadius(6)
                }
            }
            } // ScrollView
        }
        .padding(.vertical, 4)
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "曠", "曠課": return .red
        case "事", "事假": return .orange
        case "病", "病假": return .blue
        case "公", "公假": return .green
        default: return .gray
        }
    }
}

// MARK: - Attendance Export Content

struct AttendanceExportContent: View {
    let statistics: AttendanceStatistics
    let subjectAbsences: [SubjectAbsence]
    let allRecords: [AbsenceRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ExportHeader("缺曠統計",
                         subtitle: statistics.statisticsDate.isEmpty ? nil : statistics.statisticsDate)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 36) {
                    // Overview
                    ExportSectionHeader("缺曠總覽")

                    if !statistics.firstSemester.isEmpty {
                        semesterSection("上學期", data: statistics.firstSemester)
                    }

                    if !statistics.secondSemester.isEmpty {
                        semesterSection("下學期", data: statistics.secondSemester)
                    }

                    // Total
                    ExportCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("全部合計")
                                .font(.system(size: 18, weight: .semibold))
                            HStack(spacing: 16) {
                                miniStat("曠課", statistics.total.truancy, .red)
                                miniStat("事假", statistics.total.personalLeave, .orange)
                                miniStat("病假", statistics.total.sickLeave, BrandColors.blue)
                                miniStat("公假", statistics.total.officialLeave, .green)
                            }
                        }
                    }

                    // Subject absences
                    let visible = subjectAbsences.filter { $0.truancy + $0.personalLeave > 0 }
                    if !visible.isEmpty {
                        ExportSectionHeader("各科缺曠統計")
                        VStack(spacing: 10) {
                            ForEach(visible) { absence in
                                ExportCard {
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack {
                                            Text(absence.subject)
                                                .font(.system(size: 22, weight: .semibold))
                                            Spacer()
                                            Text("\(absence.percentage)%")
                                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                                                .foregroundStyle(absencePctColor(absence.percentage))
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                        .fill(absencePctColor(absence.percentage).opacity(0.1))
                                                )
                                        }
                                        HStack(spacing: 20) {
                                            Label("曠課 \(absence.truancy)", systemImage: "xmark")
                                                .font(.system(size: 16))
                                                .foregroundStyle(.red)
                                            Label("事假 \(absence.personalLeave)", systemImage: "minus")
                                                .font(.system(size: 16))
                                                .foregroundStyle(.orange)
                                            Spacer()
                                            Text("\(absence.total) / \(absence.totalClasses)")
                                                .font(.system(size: 14))
                                                .foregroundStyle(.secondary)
                                        }
                                        // Progress bar
                                        GeometryReader { geo in
                                            ZStack(alignment: .leading) {
                                                RoundedRectangle(cornerRadius: 2)
                                                    .fill(Color(.systemGray5))
                                                    .frame(height: 4)
                                                RoundedRectangle(cornerRadius: 2)
                                                    .fill(absencePctColor(absence.percentage))
                                                    .frame(width: geo.size.width * CGFloat(absence.percentage) / 100, height: 4)
                                            }
                                        }
                                        .frame(height: 4)
                                    }
                                }
                            }
                        }
                    }

                    // Recent records
                    if !allRecords.isEmpty {
                        ExportSectionHeader("近期缺曠明細")
                        let recent = Array(allRecords.prefix(12))
                        VStack(spacing: 8) {
                            ForEach(recent) { record in
                                HStack(spacing: 14) {
                                    statusBadge(record.status)

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 8) {
                                            Text(record.date)
                                                .font(.system(size: 20, weight: .medium))
                                            if !record.weekday.isEmpty {
                                                Text(record.weekday)
                                                    .font(.system(size: 16))
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Text("\(record.academicYear)學期  ·  第\(record.period)節")
                                            .font(.system(size: 14))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color(.secondarySystemBackground))
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, IGStoryExport.padding)
                .padding(.bottom, 40)
            }
        }
    }

    private func statusBadge(_ status: String) -> some View {
        let color = absenceStatusColor(status)
        return Text(status)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color)
            )
    }

    private func semesterSection(_ title: String, data: [String: String]) -> some View {
        let truancy = Int(data["曠課"] ?? "0") ?? 0
        let personal = (Int(data["事假"] ?? "0") ?? 0) + (Int(data["事假1"] ?? "0") ?? 0)
        let sick = (Int(data["病假"] ?? "0") ?? 0) + (Int(data["病假1"] ?? "0") ?? 0) + (Int(data["病假2"] ?? "0") ?? 0)
        let official = Int(data["公假"] ?? "0") ?? 0

        return ExportCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(title)合計")
                    .font(.system(size: 18, weight: .semibold))
                HStack(spacing: 16) {
                    miniStat("曠課", truancy, .red)
                    miniStat("事假", personal, .orange)
                    miniStat("病假", sick, BrandColors.blue)
                    miniStat("公假", official, .green)
                }
            }
        }
    }

    private func miniStat(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Text("\(value)")
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.08))
        )
    }

    private func absenceStatusColor(_ status: String) -> Color {
        switch status {
        case "曠", "曠課": return .red
        case "事", "事假": return .orange
        case "病", "病假": return BrandColors.blue
        case "公", "公假": return .green
        default: return .gray
        }
    }

    private func absencePctColor(_ pct: Int) -> Color {
        if pct >= 33 { return .red }
        if pct >= 24 { return .orange }
        if pct >= 16 { return .yellow }
        return .green
    }
}

#Preview {
    AttendanceView()
        .environmentObject(APIService.shared)
}
