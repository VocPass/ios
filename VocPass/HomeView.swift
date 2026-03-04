//
//  HomeView.swift
//  YKVS
//
//  Created by Hans on 2025/12/31.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var apiService: APIService
    @State private var merits: [MeritDemeritRecord] = []
    @State private var demerits: [MeritDemeritRecord] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

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
                    List {
                        // 獎勵區塊
                        Section {
                            if merits.isEmpty {
                                Text("無獎勵記錄")
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(merits) { record in
                                    MeritDemeritRow(record: record, isMerit: true)
                                }
                            }
                        } header: {
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                Text("獎勵 (\(merits.count))")
                            }
                        }

                        // 懲罰區塊
                        Section {
                            if demerits.isEmpty {
                                Text("無懲罰記錄")
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(demerits) { record in
                                    MeritDemeritRow(record: record, isMerit: false)
                                }
                            }
                        } header: {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text("懲罰 (\(demerits.count))")
                            }
                        }
                    }
                    .refreshable {
                        await loadData()
                    }
                }
            }
            .navigationTitle("獎懲記錄")
        }
        .task {
            await loadData()
        }
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await apiService.fetchMeritDemeritRecords()
            await MainActor.run {
                self.merits = result.merits
                self.demerits = result.demerits
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

struct MeritDemeritRow: View {
    let record: MeritDemeritRecord
    let isMerit: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(record.action)
                    .font(.headline)
                    .foregroundColor(isMerit ? .green : .red)
                Spacer()
                Text(record.year)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(record.reason)
                .font(.subheadline)
                .foregroundColor(.primary)

            HStack {
                Label(record.dateOccurred, systemImage: "calendar")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let revokedDate = record.dateRevoked {
                    Spacer()
                    Text("已銷過: \(revokedDate)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    HomeView()
        .environmentObject(APIService.shared)
}
