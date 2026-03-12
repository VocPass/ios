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
                    .refreshable {
                        await loadData()
                    }
                }
            }
            .navigationTitle("缺曠統計")
        }
        .task {
            await loadData()
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
                self.statistics = result.statistics
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
        switch absence.percentage {
        case 0..<10: return .green
        case 10..<20: return .yellow
        case 20..<30: return .orange
        default: return .red
        }
    }
}

#Preview {
    AttendanceView()
        .environmentObject(APIService.shared)
}
