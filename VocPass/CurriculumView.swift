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

    private let weekdays = ["一", "二", "三", "四", "五"]
    private let periods = ["一", "二", "三", "四", "五", "六", "七"]

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("載入中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    ScrollView {
                        curriculumGrid
                            .padding()
                    }
                    .refreshable {
                        await loadData(forceRefresh: true)
                    }
                }
            }
            .navigationTitle("課表")
        }
        .task {
            await loadData()
        }
    }

    // MARK: - 課表格線

    private var curriculumGrid: some View {
        VStack(spacing: 1) {
            // 標題行
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

            // 課表內容
            ForEach(periods, id: \.self) { period in
                HStack(spacing: 1) {
                    Text(period == "早讀" ? "讀" : period)
                        .frame(width: 40, height: 60)
                        .background(Color(.systemGray6))
                        .font(.caption)

                    ForEach(weekdays, id: \.self) { weekday in
                        let subject = getSubject(weekday: weekday, period: period)
                        let isNow   = isCurrentPeriod(weekday: weekday, period: period)
                        Text(subject)
                            .frame(maxWidth: .infinity, minHeight: 60)
                            .background(
                                isNow
                                    ? Color.blue.opacity(0.25)
                                    : (subject.isEmpty ? Color(.systemBackground) : randomColor(for: subject).opacity(0.2))
                            )
                            .overlay(isNow ? RoundedRectangle(cornerRadius: 2).stroke(Color.blue, lineWidth: 1.5) : nil)
                            .font(.caption2)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .background(Color(.systemGray4))
        .cornerRadius(8)
    }

    // MARK: - Dynamic Island 控制卡片

    private var dynamicIslandCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "clock.badge.fill")
                    .foregroundStyle(.blue)
                Text("即時動態")
                    .font(.headline)
                Spacer()
                Button {
                    if dynamicIsland.isActivityRunning {
                        dynamicIsland.endActivity()
                    } else {
                        let name = CacheService.shared.savedClassName.isEmpty
                            ? "我的課表"
                            : CacheService.shared.savedClassName
                        Task { await dynamicIsland.startActivity(className: name) }
                    }
                } label: {
                    Label(
                        dynamicIsland.isActivityRunning ? "停止" : "開始",
                        systemImage: dynamicIsland.isActivityRunning ? "stop.fill" : "play.fill"
                    )
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(dynamicIsland.isActivityRunning ? Color.red.opacity(0.15) : Color.blue.opacity(0.15))
                    .foregroundStyle(dynamicIsland.isActivityRunning ? .red : .blue)
                    .clipShape(Capsule())
                }
            }

            Divider()

            HStack(spacing: 16) {
                infoBlock(
                    title: "目前",
                    value: dynamicIsland.currentSubject.isEmpty ? "下課中" : dynamicIsland.currentSubject,
                    color: dynamicIsland.currentSubject.isEmpty ? .secondary : .blue
                )
                Divider().frame(height: 36)
                infoBlock(
                    title: "下一堂",
                    value: dynamicIsland.nextSubject.isEmpty ? "今天結束" : dynamicIsland.nextSubject,
                    color: dynamicIsland.nextSubject.isEmpty ? .secondary : .green
                )
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func infoBlock(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 輔助

    private func getSubject(weekday: String, period: String) -> String {
        for (subject, info) in curriculum {
            for schedule in info.schedule {
                if schedule.weekday == weekday && schedule.period == period {
                    return subject
                }
            }
        }
        return ""
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

        do {
            let timetable = try await apiService.fetchTimetableData(forceRefresh: forceRefresh)
            await MainActor.run {
                self.curriculum = timetable.curriculum
                DynamicIslandService.shared.setTimetable(timetable)
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

#Preview {
    CurriculumView()
        .environmentObject(APIService.shared)
}

