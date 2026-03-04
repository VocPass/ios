//
//  CurriculumView.swift
//  YKVS
//
//  Created by Hans on 2025/12/31.
//

import SwiftUI

struct CurriculumView: View {
    @EnvironmentObject var apiService: APIService
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
                    Text(period)
                        .frame(width: 40, height: 60)
                        .background(Color(.systemGray6))
                        .font(.caption)

                    ForEach(weekdays, id: \.self) { weekday in
                        let subject = getSubject(weekday: weekday, period: period)
                        Text(subject)
                            .frame(maxWidth: .infinity, minHeight: 60)
                            .background(subject.isEmpty ? Color(.systemBackground) : randomColor(for: subject).opacity(0.3))
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

    private func randomColor(for subject: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan, .mint, .indigo]
        let hash = abs(subject.hashValue)
        return colors[hash % colors.count]
    }

    private func loadData(forceRefresh: Bool = false) async {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await apiService.fetchCurriculum(forceRefresh: forceRefresh)
            await MainActor.run {
                self.curriculum = result
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
