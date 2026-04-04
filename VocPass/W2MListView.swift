//
//  W2MListView.swift
//  VocPass
//
//  「出來玩」活動列表頁
//

import SwiftUI

struct W2MListView: View {
    @ObservedObject private var vocPassAuth = VocPassAuthService.shared
    @State private var eventList: W2MEventListResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showCreate = false

    var body: some View {
        mainContent
            .navigationTitle("出來玩")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(!vocPassAuth.isLoggedIn)
                }
            }
            .task {
                if vocPassAuth.isLoggedIn { await loadEvents() }
            }
            .refreshable {
                if vocPassAuth.isLoggedIn { await loadEvents() }
            }
            .sheet(isPresented: $showCreate, onDismiss: {
                Task { await loadEvents() }
            }) {
                W2MCreateEventView()
            }
    }

    @ViewBuilder
    private var mainContent: some View {
        if !vocPassAuth.isLoggedIn {
            notLoggedInView
        } else if isLoading {
            ProgressView("載入中…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = errorMessage {
            errorView(err)
        } else if let list = eventList {
            listContent(list)
        } else {
            // 初始狀態（task 尚未執行）
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - List Content

    @ViewBuilder
    private func listContent(_ list: W2MEventListResponse) -> some View {
        List {
            if !list.created.isEmpty {
                Section("我建立的") {
                    ForEach(list.created) { event in
                        NavigationLink(destination: W2MResultView(eventID: event.id, creatorID: event.creator.id)) {
                            eventRow(event)
                        }
                    }
                }
            }
            if !list.participated.isEmpty {
                Section("我參與的") {
                    ForEach(list.participated) { event in
                        NavigationLink(destination: W2MResultView(eventID: event.id, creatorID: event.creator.id)) {
                            eventRow(event)
                        }
                    }
                }
            }
            if list.created.isEmpty && list.participated.isEmpty {
                Section {
                    emptyView
                }
            }
        }
    }

    // MARK: - Event Row

    private func eventRow(_ event: W2MEventSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.title)
                .font(.headline)
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(event.dates.prefix(3).joined(separator: "、") + (event.dates.count > 3 ? "…" : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                Image(systemName: "person")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(event.creator.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("還沒有活動")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("點右上角 + 建立第一個活動")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .listRowBackground(Color.clear)
    }

    // MARK: - Not Logged In

    private var notLoggedInView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            Text("登入後才能使用出來玩")
                .font(.headline)
            Text("請先登入 VocPass 帳號")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重試") { Task { await loadEvents() } }
                .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Load

    private func loadEvents() async {
        isLoading = true
        errorMessage = nil
        do {
            eventList = try await W2MService.shared.fetchEvents()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
