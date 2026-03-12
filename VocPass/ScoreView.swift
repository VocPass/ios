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
                    }
                    .refreshable {
                        await loadData()
                    }
                }
            }
            .navigationTitle("學年成績")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: ExamScoreView()) {
                        Image(systemName: "list.bullet.clipboard")
                    }
                }
            }
        }
        .task {
            await loadData()
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
        let preferredOrder = [
            "補前平均",
            "學科平均",
            "智育成績",
            "體育成績",
            "實習成績",
            "軍訓成績",
            "實得學分",
            "實得累計",
            "學期名次"
        ]

        let existing = Set(gradeData.totalScores.keys)
        let ordered = preferredOrder.filter { existing.contains($0) }
        let remaining = existing.subtracting(preferredOrder).sorted()
        return ordered + remaining
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
        switch scoreValue {
        case 90...100: return .green
        case 80..<90: return .blue
        case 60..<80: return .primary
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
                                Task { await loadExamDetail(url: exam.fullURL) }
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
            }
        }
        .navigationTitle("考試成績")
        .task {
            await loadMenu()
        }
        .refreshable {
            await loadMenu(forceRefresh: true)
        }
    }

    private func loadMenu(forceRefresh: Bool = false) async {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await apiService.fetchExamMenu(forceRefresh: forceRefresh)
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

    private func loadExamDetail(url: String) async {
        isLoadingDetail = true

        do {
            let result = try await apiService.fetchExamScore(url: url)
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
        switch score {
        case 90...100: return .green
        case 80..<90: return .blue
        case 60..<80: return .primary
        default: return .red
        }
    }
}

#Preview {
    ScoreView()
        .environmentObject(APIService.shared)
}
