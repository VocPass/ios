//
//  SchoolNoticeView.swift
//  VocPass
//

import SwiftUI
import SafariServices

struct SchoolNoticeView: View {
    @EnvironmentObject var apiService: APIService
    @State private var notices: [NoticeItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedNotice: NoticeItem?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("載入中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                    Text(error)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("重試") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if notices.isEmpty {
                ContentUnavailableView("尚無公告", systemImage: "bell.slash")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(notices) { notice in
                    NoticeRowView(notice: notice) {
                        selectedNotice = notice
                    }
                }
                .refreshable { await load() }
                .sheet(item: $selectedNotice) { item in
                    if let url = URL(string: item.link) {
                        SafariView(url: url)
                            .ignoresSafeArea()
                    }
                }
            }
        }
        .navigationTitle("公告")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        await MainActor.run { isLoading = true; errorMessage = nil }
        do {
            let result = try await apiService.fetchNotices()
            await MainActor.run {
                self.notices = result
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

private struct NoticeRowView: View {
    let notice: NoticeItem
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(notice.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                HStack(spacing: 12) {
                    Label(notice.publisher, systemImage: "person.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(notice.date, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(notice.views, systemImage: "eye")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
