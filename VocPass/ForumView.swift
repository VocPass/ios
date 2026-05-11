//
//  ForumView.swift
//  VocPass
//

import SwiftUI

private enum ForumScope: String, CaseIterable, Identifiable {
    case currentSchool
    case all

    var id: String { rawValue }
    var title: String {
        switch self {
        case .currentSchool: return "本校"
        case .all: return "全部"
        }
    }
}

struct ForumView: View {
    @EnvironmentObject var apiService: APIService
    @ObservedObject private var vocPassAuth = VocPassAuthService.shared
    @StateObject private var schoolConfigManager = SchoolConfigManager.shared

    @State private var posts: [ForumPost] = []
    @State private var selectedScope: ForumScope = .currentSchool
    @State private var page = 1
    @State private var totalPages = 1
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var showLogin = false

    private var selectedSchoolName: String? {
        schoolConfigManager.selectedSchool?.name
    }

    private var requestSchoolName: String {
        switch selectedScope {
        case .currentSchool:
            return selectedSchoolName ?? "all"
        case .all:
            return "all"
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && posts.isEmpty {
                    ProgressView("載入中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, posts.isEmpty {
                    ContentUnavailableView {
                        Label("載入失敗", systemImage: "exclamationmark.bubble")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("重試") {
                            Task { await load(reset: true) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if posts.isEmpty {
                    ContentUnavailableView("目前沒有文章", systemImage: "bubble.left.and.text.bubble.right")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(posts) { post in
                                NavigationLink {
                                    ForumPostDetailView(post: post)
                                        .environmentObject(apiService)
                                } label: {
                                    ForumPostRow(post: post)
                                }
                                .buttonStyle(.plain)
                                .task {
                                    await loadMoreIfNeeded(currentPost: post)
                                }
                            }

                            if isLoadingMore {
                                ProgressView()
                                    .padding(.vertical, 12)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .refreshable {
                        await load(reset: true)
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("論壇")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Picker("範圍", selection: $selectedScope) {
                        ForEach(ForumScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                    .disabled(selectedSchoolName == nil)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if vocPassAuth.isLoggedIn {
                        Image(systemName: "person.crop.circle.fill")
                            .foregroundStyle(.blue)
                    } else {
                        Button {
                            showLogin = true
                        } label: {
                            Image(systemName: "person.badge.key")
                        }
                    }
                }
            }
            .onAppear {
                if selectedSchoolName == nil {
                    selectedScope = .all
                }
            }
            .onChange(of: selectedScope) { _, _ in
                Task { await load(reset: true) }
            }
            .onChange(of: selectedSchoolName) { _, newValue in
                if newValue == nil {
                    selectedScope = .all
                }
                Task { await load(reset: true) }
            }
            .task {
                if posts.isEmpty {
                    await load(reset: true)
                }
            }
            .sheet(isPresented: $showLogin) {
                VocPassLoginSheet()
            }
        }
    }

    @MainActor
    private func load(reset: Bool) async {
        if reset {
            page = 1
            totalPages = 1
            posts = []
            isLoading = true
            errorMessage = nil
        } else {
            guard page < totalPages, !isLoadingMore else { return }
            page += 1
            isLoadingMore = true
        }

        defer {
            isLoading = false
            isLoadingMore = false
        }

        do {
            let result = try await apiService.fetchForumPosts(school: requestSchoolName, page: page)
            totalPages = max(result.totalPages, 1)
            if reset {
                posts = result.forums
            } else {
                posts.append(contentsOf: result.forums)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMoreIfNeeded(currentPost: ForumPost) async {
        guard currentPost.id == posts.last?.id, page < totalPages else { return }
        await load(reset: false)
    }
}

private struct ForumPostRow: View {
    let post: ForumPost

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ForumAvatar(user: post.user, anonymous: post.anonymous, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(post.anonymous ? "匿名" : (post.user?.displayName ?? "未知用戶"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    HStack(spacing: 6) {
                        if !post.school.isEmpty {
                            Text(post.school)
                        }
                        if !post.created.isEmpty {
                            Text(ForumDateFormatter.display(post.created))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Text(post.title)
                .font(.headline)
                .foregroundStyle(.primary)

            if !post.content.isEmpty {
                Text(post.content)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.8))
                Text("\(post.likes.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator).opacity(0.18), lineWidth: 1)
        }
    }
}

struct ForumPostDetailView: View {
    @EnvironmentObject var apiService: APIService
    @ObservedObject private var vocPassAuth = VocPassAuthService.shared

    @State private var post: ForumPost
    @State private var messages: [ForumMessage] = []
    @State private var totalPages = 1
    @State private var page = 1
    @State private var isLoadingMessages = false
    @State private var actionError: String?
    @State private var showLogin = false

    init(post: ForumPost) {
        _post = State(initialValue: post)
    }

    private var likedByMe: Bool {
        guard let userID = vocPassAuth.currentUser?.id else { return false }
        return post.likes.contains(userID)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        ForumAvatar(user: post.user, anonymous: post.anonymous, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(post.anonymous ? "匿名" : (post.user?.displayName ?? "未知用戶"))
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(ForumDateFormatter.display(post.created))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(post.title)
                        .font(.title3)
                        .fontWeight(.semibold)

                    if !post.content.isEmpty {
                        Text(post.content)
                            .font(.body)
                            .textSelection(.enabled)
                    }

                    Button {
                        Task { await toggleLike() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: likedByMe ? "heart.fill" : "heart")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(likedByMe ? Color.red : Color.secondary)
                            Text("\(post.likes.count)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(likedByMe ? Color.red.opacity(0.12) : Color(.tertiarySystemGroupedBackground))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 6)
            }

            Section("留言") {
                if isLoadingMessages && messages.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if messages.isEmpty {
                    Text("目前沒有留言")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(messages) { message in
                        ForumMessageRow(message: message)
                    }

                    if page < totalPages {
                        Button("載入更多") {
                            Task { await loadMessages(reset: false) }
                        }
                    }
                }
            }
        }
        .navigationTitle("文章")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await loadMessages(reset: true)
        }
        .task {
            await loadMessages(reset: true)
        }
        .alert("操作失敗", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .sheet(isPresented: $showLogin) {
            VocPassLoginSheet()
        }
    }

    @MainActor
    private func loadMessages(reset: Bool) async {
        if reset {
            page = 1
            totalPages = 1
            messages = []
        } else {
            guard page < totalPages else { return }
            page += 1
        }

        isLoadingMessages = true
        defer { isLoadingMessages = false }

        do {
            let result = try await apiService.fetchForumMessages(postID: post.likeTargetID, page: page)
            totalPages = max(result.totalPages, 1)
            if reset {
                messages = result.forums
            } else {
                messages.append(contentsOf: result.forums)
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func toggleLike() async {
        guard let userID = vocPassAuth.currentUser?.id else {
            showLogin = true
            return
        }

        let shouldLike = !likedByMe
        var updatedLikes = post.likes
        if shouldLike {
            updatedLikes.append(userID)
        } else {
            updatedLikes.removeAll { $0 == userID }
        }

        let oldPost = post
        post = ForumPostSnapshot.copy(from: post, likes: updatedLikes)

        do {
            try await apiService.setForumPostLike(postID: post.likeTargetID, liked: shouldLike)
        } catch {
            post = oldPost
            actionError = error.localizedDescription
        }
    }
}

private struct ForumMessageRow: View {
    let message: ForumMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForumAvatar(user: message.user, anonymous: message.anonymous, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(message.anonymous ? "匿名" : (message.user?.displayName ?? "未知用戶"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    if !message.created.isEmpty {
                        Text(ForumDateFormatter.display(message.created))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(message.content)
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ForumAvatar: View {
    let user: ForumUser?
    let anonymous: Bool
    let size: CGFloat

    var body: some View {
        ZStack {
            if !anonymous, let avatarURL = user?.avatarURL {
                CachedAsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .foregroundStyle(.blue)
                    }
                }
            } else {
                Image(systemName: anonymous ? "person.fill.questionmark" : "person.circle.fill")
                    .resizable()
                    .foregroundStyle(anonymous ? Color.secondary : Color.blue)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

private enum ForumDateFormatter {
    static func display(_ value: String) -> String {
        guard let date = parse(value) else { return value }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_Hant_TW")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private static func parse(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) {
            return date
        }

        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["yyyy-MM-dd HH:mm:ss.SSS'Z'", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", "yyyy-MM-dd'T'HH:mm:ss'Z'"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }
}

private enum ForumPostSnapshot {
    static func copy(from post: ForumPost, likes: [String]) -> ForumPost {
        ForumPost(
            id: post.id,
            post: post.post,
            school: post.school,
            title: post.title,
            content: post.content,
            anonymous: post.anonymous,
            likes: likes,
            user: post.user,
            created: post.created,
            updated: post.updated
        )
    }
}
