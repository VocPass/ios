//
//  ScoreView.swift
//  YKVS
//
//  Created by Hans on 2025/12/31.
//

import SwiftUI

struct ScoreView: View {
    @EnvironmentObject var apiService: APIService
    @State private var gradeData: GradeData = GradeData()
    @State private var selectedYear = 1
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isUnsupported = false
    @State private var showShareSheet = false
    @State private var exportImage: ExportImage?

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
                        // 學年選擇
                        Section {
                            Picker("學年", selection: $selectedYear) {
                                Text("一年級").tag(1)
                                Text("二年級").tag(2)
                                Text("三年級").tag(3)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: selectedYear) { _, _ in
                                Task { await loadData() }
                            }
                        }

                        // 學生資訊
                        if !gradeData.studentInfo.isEmpty {
                            Section("學生資訊") {
                                Text(gradeData.studentInfo)
                                    .font(.subheadline)
                            }
                        }

                        // 科目成績
                        Section("科目成績") {
                            if gradeData.subjects.isEmpty {
                                Text("無成績資料")
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(gradeData.subjects) { subject in
                                    SubjectGradeRow(subject: subject)
                                }
                            }
                        }

                        // 總成績
                        if !gradeData.totalScores.isEmpty {
                            Section("總成績") {
                                ForEach(orderedTotalScoreKeys(), id: \.self) { category in
                                    if let score = gradeData.totalScores[category] {
                                        TotalScoreRow(category: category, score: score)
                                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                    }
                                }
                            }
                        }

                        // 日常生活表現（若 API 無 daily_performance 則不顯示）
                        if !gradeData.dailyPerformance.isEmpty {
                            Section("日常生活表現") {
                                ForEach(orderedDailyPerformanceKeys(), id: \.self) { key in
                                    if let performance = gradeData.dailyPerformance[key],
                                       !performance.isCompletelyEmpty {
                                        DailyPerformanceRow(
                                            semesterTitle: semesterTitle(for: key),
                                            performance: performance
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .refreshable {
                        await loadData()
                    }
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                renderExport()
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                }
            }
            .navigationTitle("學年成績")
        }
        .task {
            await loadData()
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
            let yearTitle = yearTitle(for: selectedYear)
            let content = IGStoryContainer(iconImage: ExportIconLoader.shared.loadedImage) {
                ScoreExportContent(
                    gradeData: gradeData,
                    yearTitle: yearTitle
                )
            }
            exportImage = content.renderToImage(
                size: IGStoryExport.size,
                scale: 1.0
            )
            showShareSheet = true
        }
    }

    private func yearTitle(for year: Int) -> String {
        switch year {
        case 1: return "一年級"
        case 2: return "二年級"
        case 3: return "三年級"
        default: return ""
        }
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await apiService.fetchYearScore(year: selectedYear)
            await MainActor.run {
                self.gradeData = result
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

    private func orderedTotalScoreKeys() -> [String] {
        gradeData.totalScores.keys.sorted { lhs, rhs in
            lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    private func orderedDailyPerformanceKeys() -> [String] {
        let preferredOrder = ["first_semester", "second_semester"]
        let existing = Set(gradeData.dailyPerformance.keys)
        let ordered = preferredOrder.filter { existing.contains($0) }
        let remaining = existing.subtracting(preferredOrder).sorted()
        return ordered + remaining
    }

    private func semesterTitle(for key: String) -> String {
        switch key {
        case "first_semester": return "上學期"
        case "second_semester": return "下學期"
        default: return key
        }
    }
}

struct SubjectGradeRow: View {
    let subject: SubjectGrade

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(subject.subject)
                .font(.headline)

            HStack {
                VStack(alignment: .leading) {
                    Text("上學期")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        Text(subject.firstSemester.score)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(scoreColor(subject.firstSemester.score))
                        Text("(\(subject.firstSemester.credit)學分)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading) {
                    Text("下學期")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        Text(subject.secondSemester.score)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(scoreColor(subject.secondSemester.score))
                        Text("(\(subject.secondSemester.credit)學分)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing) {
                    Text("學年")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(subject.yearGrade)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(scoreColor(subject.yearGrade))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func scoreColor(_ score: String) -> Color {
        guard let scoreValue = Double(score) else { return .primary }
        let passingScore = Double(CacheService.shared.passingScore)
        switch scoreValue {
        case 90...100: return .green
        case 80..<90: return .blue
        case passingScore..<80: return .primary
        default: return .red
        }
    }
}

struct TotalScoreRow: View {
    let category: String
    let score: TotalScore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(category)
                .font(.headline)

            HStack(spacing: 12) {
                scoreCell(title: "上", value: score.firstSemester)
                scoreCell(title: "下", value: score.secondSemester)
                scoreCell(title: "學年", value: score.year, emphasize: true)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private func scoreCell(title: String, value: String, emphasize: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)

            Text(displayValue(value))
                .font(emphasize ? .headline : .subheadline)
                .fontWeight(emphasize ? .semibold : .regular)
                .monospacedDigit()
                .foregroundColor(displayColor(value, emphasize: emphasize))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func displayValue(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "—" : trimmed
    }

    private func displayColor(_ raw: String, emphasize: Bool) -> Color {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .secondary }
        return emphasize ? .primary : .primary.opacity(0.9)
    }
}

struct DailyPerformanceRow: View {
    let semesterTitle: String
    let performance: DailyPerformance

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(semesterTitle)
                .font(.headline)

            if !cleaned(performance.evaluation).isEmpty {
                textBlock(title: "日常評量", value: cleaned(performance.evaluation))
            }
            if !cleaned(performance.description).isEmpty {
                textBlock(title: "描述", value: cleaned(performance.description))
            }
            if !cleaned(performance.serviceHours).isEmpty {
                textBlock(title: "服務學習", value: cleaned(performance.serviceHours))
            }
            if !cleaned(performance.specialPerformance).isEmpty {
                textBlock(title: "特殊表現", value: cleaned(performance.specialPerformance))
            }
            if !cleaned(performance.suggestions).isEmpty {
                textBlock(title: "建議與評語", value: cleaned(performance.suggestions))
            }
            if !cleaned(performance.others).isEmpty {
                textBlock(title: "其他", value: cleaned(performance.others))
            }
        }
        .padding(.vertical, 4)
    }

    private func textBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
        }
    }

    private func cleaned(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension DailyPerformance {
    var isCompletelyEmpty: Bool {
        [evaluation, description, serviceHours, specialPerformance, suggestions, others]
            .allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

// MARK: - 考試成績頁面
struct ExamScoreView: View {
    @EnvironmentObject var apiService: APIService
    @State private var examMenu: [ExamMenuItem] = []
    @State private var selectedExam: ExamMenuItem?
    @State private var examData: ExamScoreData = ExamScoreData()
    @State private var isLoading = true
    @State private var isLoadingDetail = false
    @State private var errorMessage: String?
    @State private var isUnsupported = false
    @State private var showShareSheet = false
    @State private var exportImage: ExportImage?

    var body: some View {
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
                        Task { await loadMenu() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    // 考試選擇
                    Section("選擇考試") {
                        Picker("考試", selection: $selectedExam) {
                            Text("請選擇").tag(nil as ExamMenuItem?)
                            ForEach(examMenu) { exam in
                                Text(exam.name).tag(exam as ExamMenuItem?)
                            }
                        }
                        .onChange(of: selectedExam) { _, newValue in
                            if let exam = newValue {
                                Task { await loadExamDetail(fileName: exam.url) }
                            }
                        }
                    }

                    if isLoadingDetail {
                        Section {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        }
                    } else if selectedExam != nil {
                        // 考試資訊
                        if !examData.examInfo.isEmpty {
                            Section("考試資訊") {
                                Text(examData.examInfo)
                                    .font(.subheadline)
                            }
                        }

                        // 成績明細
                        Section("成績明細") {
                            if examData.subjects.isEmpty {
                                Text("無成績資料")
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(examData.subjects) { subject in
                                    ExamSubjectRow(subject: subject)
                                }
                            }
                        }

                        // 統計
                        Section("統計") {
                            HStack {
                                Text("總分")
                                Spacer()
                                Text(examData.summary.totalScore)
                                    .fontWeight(.semibold)
                            }
                            HStack {
                                Text("平均")
                                Spacer()
                                Text(examData.summary.averageScore)
                                    .fontWeight(.semibold)
                            }
                            HStack {
                                Text("班級排名")
                                Spacer()
                                Text(examData.summary.classRank)
                                    .fontWeight(.semibold)
                            }
                            HStack {
                                Text("科別排名")
                                Spacer()
                                Text(examData.summary.departmentRank)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            renderExport()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .disabled(selectedExam == nil)
                    }
                }
            }
        }
        .navigationTitle("考試成績")
        .task {
            await loadMenu()
        }
        .refreshable {
            await loadMenu()
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = exportImage {
                ShareSheet(image: image)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Export

    private func renderExport() {
        guard let exam = selectedExam else { return }
        Task {
            await ExportIconLoader.shared.preload()
            let content = IGStoryContainer(iconImage: ExportIconLoader.shared.loadedImage) {
                ExamScoreExportContent(
                    examData: examData,
                    examName: exam.name
                )
            }
            exportImage = content.renderToImage(
                size: IGStoryExport.size,
                scale: 1.0
            )
            showShareSheet = true
        }
    }

    private func loadMenu() async {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await apiService.fetchExamMenu()
            await MainActor.run {
                self.examMenu = result
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

    private func loadExamDetail(fileName: String) async {
        isLoadingDetail = true

        do {
            let result = try await apiService.fetchExamScore(fileName: fileName)
            await MainActor.run {
                self.examData = result
                self.isLoadingDetail = false
            }
        } catch {
            await MainActor.run {
                self.isLoadingDetail = false
            }
        }
    }
}

struct ExamSubjectRow: View {
    let subject: ExamSubjectScore

    var body: some View {
        HStack {
            Text(subject.subject)
                .font(.subheadline)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(subject.personalScore)
                    .font(.headline)
                    .foregroundColor(scoreColor)
                Text("班平均: \(subject.classAverage)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var scoreColor: Color {
        guard let score = Double(subject.personalScore) else { return .primary }
        let passingScore = Double(CacheService.shared.passingScore)
        switch score {
        case 90...100: return .green
        case 80..<90: return .blue
        case passingScore..<80: return .primary
        default: return .red
        }
    }
}

// MARK: - Score Export Content

struct ScoreExportContent: View {
    let gradeData: GradeData
    let yearTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ExportHeader("學年成績", subtitle: yearTitle)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 36) {
                    // Student Info
                    if !gradeData.studentInfo.isEmpty {
                        ExportSectionHeader("學生資訊")
                        Text(gradeData.studentInfo)
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    // Subject Grades
                    if !gradeData.subjects.isEmpty {
                        ExportSectionHeader("科目成績")
                        ForEach(gradeData.subjects) { subject in
                            ExportCard {
                                VStack(spacing: 16) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(subject.subject)
                                            .font(.system(size: 24, weight: .semibold))
                                        Spacer()
                                        Text(subject.yearGrade)
                                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                                            .foregroundStyle(exportScoreColor(subject.yearGrade))
                                    }
                                    HStack(spacing: 32) {
                                        semesterBadge("上學期", subject.firstSemester.score, subject.firstSemester.credit)
                                        semesterBadge("下學期", subject.secondSemester.score, subject.secondSemester.credit)
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }

                    // Total Scores
                    if !gradeData.totalScores.isEmpty {
                        ExportSectionHeader("總成績")
                        let keys = gradeData.totalScores.keys.sorted {
                            $0.localizedStandardCompare($1) == .orderedAscending
                        }
                        VStack(spacing: 12) {
                            ForEach(keys, id: \.self) { category in
                                if let score = gradeData.totalScores[category] {
                                    ExportCard {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(category)
                                                .font(.system(size: 20, weight: .semibold))
                                            Spacer()
                                            Text(score.firstSemester)
                                                .font(.system(size: 17, weight: .medium, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                            Text("·")
                                                .foregroundStyle(.tertiary)
                                            Text(score.secondSemester)
                                                .font(.system(size: 17, weight: .medium, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                            Text("·")
                                                .foregroundStyle(.tertiary)
                                            Text(score.year)
                                                .font(.system(size: 22, weight: .bold, design: .monospaced))
                                                .foregroundStyle(BrandColors.blue)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Daily Performance
                    if !gradeData.dailyPerformance.isEmpty {
                        ExportSectionHeader("日常生活表現")
                        let perfKeys = orderedPerfKeys()
                        ForEach(perfKeys, id: \.self) { key in
                            if let perf = gradeData.dailyPerformance[key],
                               !perf.isCompletelyEmpty {
                                ExportCard {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text(key == "first_semester" ? "上學期" : "下學期")
                                            .font(.system(size: 18, weight: .semibold))
                                        if !cleaned(perf.evaluation).isEmpty {
                                            perfRow("日常評量", cleaned(perf.evaluation))
                                        }
                                        if !cleaned(perf.description).isEmpty {
                                            perfRow("描述", cleaned(perf.description))
                                        }
                                        if !cleaned(perf.serviceHours).isEmpty {
                                            perfRow("服務學習", cleaned(perf.serviceHours))
                                        }
                                        if !cleaned(perf.specialPerformance).isEmpty {
                                            perfRow("特殊表現", cleaned(perf.specialPerformance))
                                        }
                                        if !cleaned(perf.suggestions).isEmpty {
                                            perfRow("建議與評語", cleaned(perf.suggestions))
                                        }
                                        if !cleaned(perf.others).isEmpty {
                                            perfRow("其他", cleaned(perf.others))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, IGStoryExport.padding)
                .padding(.bottom, 40)
            }
        }
    }

    private func semesterBadge(_ label: String, _ score: String, _ credit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(.systemGray))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(score)
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundStyle(exportScoreColor(score))
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("\(credit) 學分")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func orderedPerfKeys() -> [String] {
        let preferred = ["first_semester", "second_semester"]
        let existing = Set(gradeData.dailyPerformance.keys)
        return preferred.filter { existing.contains($0) } + existing.subtracting(preferred).sorted()
    }

    private func perfRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(.systemGray))
            Text(value)
                .font(.system(size: 18, weight: .regular))
        }
    }

    private func cleaned(_ text: String) -> String {
        exportCleanedHTML(text)
    }
}

// MARK: - Exam Score Export Content

struct ExamScoreExportContent: View {
    let examData: ExamScoreData
    let examName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ExportHeader("考試成績", subtitle: examName)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 36) {
                    if !examData.examInfo.isEmpty {
                        ExportSectionHeader("考試資訊")
                        Text(examData.examInfo)
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    if !examData.subjects.isEmpty {
                        ExportSectionHeader("成績明細")
                        VStack(spacing: 10) {
                            ForEach(examData.subjects) { subject in
                                ExportCard {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(subject.subject)
                                            .font(.system(size: 22, weight: .medium))
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 4) {
                                            Text(subject.personalScore)
                                                .font(.system(size: 28, weight: .bold, design: .monospaced))
                                                .foregroundStyle(exportScoreColor(subject.personalScore))
                                            Text("班平均 \(subject.classAverage)")
                                                .font(.system(size: 14))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    ExportSectionHeader("統計")
                    ExportCard {
                        VStack(spacing: 16) {
                            statRow("總分", examData.summary.totalScore)
                            Divider()
                            statRow("平均", examData.summary.averageScore)
                            Divider()
                            statRow("班級排名", examData.summary.classRank)
                            Divider()
                            statRow("科別排名", examData.summary.departmentRank)
                        }
                    }
                }
                .padding(.horizontal, IGStoryExport.padding)
                .padding(.bottom, 40)
            }
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
        }
    }
}

#Preview {
    ScoreView()
        .environmentObject(APIService.shared)
}
