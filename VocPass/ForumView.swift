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
    @State private var reportingContext: ReportContext?
    @State private var adminInfo: ForumAdminInfo?
    @State private var isLoadingAdminInfo = false

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
            VStack(spacing: 0) {
                scopePicker
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(.systemGroupedBackground))

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
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                if selectedScope == .currentSchool, let selectedSchoolName {
                                    ForumSchoolAdminHeader(
                                        schoolName: selectedSchoolName,
                                        adminInfo: adminInfo,
                                        isLoading: isLoadingAdminInfo,
                                        applyURL: moderatorApplyURL(for: selectedSchoolName)
                                    )
                                }

                                if posts.isEmpty {
                                    ContentUnavailableView("目前沒有文章", systemImage: "bubble.left.and.text.bubble.right")
                                        .padding(.vertical, 48)
                                } else {
                                    ForEach(posts) { post in
                                        ForumPostRow(
                                            post: post,
                                            showPinned: selectedScope == .currentSchool,
                                            onReport: { reportingContext = ReportContext(forumPostID: post.likeTargetID) }
                                        )
                                        .environmentObject(apiService)
                                        .task {
                                            await loadMoreIfNeeded(currentPost: post)
                                        }
                                    }

                                    if isLoadingMore {
                                        ProgressView()
                                            .padding(.vertical, 12)
                                    }
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
            }
            .navigationTitle("論壇")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if vocPassAuth.isLoggedIn {
                        if let currentUser = vocPassAuth.currentUser {
                            NavigationLink {
                                ForumUserPostsView(user: ForumUserSnapshot.from(currentUser))
                                    .environmentObject(apiService)
                            } label: {
                                ForumAvatar(user: ForumUserSnapshot.from(currentUser), anonymous: false, size: 30)
                            }
                        }
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
                Task {
                    await load(reset: true)
                    await loadAdminInfoIfNeeded()
                }
            }
            .onChange(of: selectedSchoolName) { _, newValue in
                if newValue == nil {
                    selectedScope = .all
                }
                Task {
                    await load(reset: true)
                    await loadAdminInfoIfNeeded()
                }
            }
            .task {
                if posts.isEmpty {
                    await load(reset: true)
                }
                await loadAdminInfoIfNeeded()
            }
            .sheet(isPresented: $showLogin) {
                VocPassLoginSheet()
            }
            .sheet(item: $reportingContext) { context in
                ReportSheet(context: context)
                    .environmentObject(apiService)
            }
        }
    }

    private var scopePicker: some View {
        Picker("範圍", selection: $selectedScope) {
            ForEach(ForumScope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .disabled(selectedSchoolName == nil)
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

    @MainActor
    private func loadAdminInfoIfNeeded() async {
        guard selectedScope == .currentSchool, let selectedSchoolName else {
            adminInfo = nil
            isLoadingAdminInfo = false
            return
        }

        isLoadingAdminInfo = true
        defer { isLoadingAdminInfo = false }

        do {
            adminInfo = try await apiService.fetchForumAdminInfo(school: selectedSchoolName)
        } catch {
            adminInfo = nil
        }
    }

    private func moderatorApplyURL(for schoolName: String) -> URL {
        var components = URLComponents(url: AppConfig.forumURL.appending(path: "admin/apply"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "school", value: schoolName)]
        return components?.url ?? AppConfig.forumURL
    }
}

private struct ForumPostRow: View {
    @EnvironmentObject var apiService: APIService
    let post: ForumPost
    let showPinned: Bool
    let onReport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ForumUserLink(user: post.user, anonymous: post.anonymous) {
                    ForumAvatar(user: post.user, anonymous: post.anonymous, size: 36)
                }
                .environmentObject(apiService)

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

                Menu {
                    Button(role: .destructive, action: onReport) {
                        Label("檢舉文章", systemImage: "flag")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                }
            }

            NavigationLink {
                ForumPostDetailView(post: post)
                    .environmentObject(apiService)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        if showPinned && post.pin {
                            Label("置頂", systemImage: "pin.fill")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.orange)
                        }

                        Text(post.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }

                    if !post.tags.isEmpty {
                        ForumTagCloud(tags: post.tags)
                    }

                    if !post.content.isEmpty {
                        Text(post.content)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

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

private struct ForumSchoolAdminHeader: View {
    let schoolName: String
    let adminInfo: ForumAdminInfo?
    let isLoading: Bool
    let applyURL: URL

    private var displayName: String {
        adminInfo?.school.isEmpty == false ? adminInfo?.school ?? schoolName : schoolName
    }

    private var moderatorCount: Int {
        adminInfo?.admin.count ?? 0
    }

    var body: some View {
        HStack(spacing: 12) {
            ForumSchoolIcon(url: adminInfo?.iconURL)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.mini)
                    }

                    Text("\(moderatorCount) 位版主")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Link(destination: applyURL) {
                Label("申請", systemImage: "person.badge.plus")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.blue.opacity(0.12))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
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

private struct ForumSchoolIcon: View {
    let url: URL?

    var body: some View {
        ZStack {
            if let url {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Image(systemName: "building.columns.fill")
                            .resizable()
                            .scaledToFit()
                            .padding(10)
                            .foregroundStyle(.blue)
                    }
                }
            } else {
                Image(systemName: "building.columns.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(10)
                    .foregroundStyle(.blue)
            }
        }
        .frame(width: 46, height: 46)
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
    @State private var reportingContext: ReportContext?

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
                        ForumUserLink(user: post.user, anonymous: post.anonymous) {
                            ForumAvatar(user: post.user, anonymous: post.anonymous, size: 40)
                        }
                        .environmentObject(apiService)
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

                    if !post.tags.isEmpty {
                        ForumTagCloud(tags: post.tags)
                    }

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
                        ForumMessageRow(
                            message: message,
                            onReport: { reportingContext = ReportContext(forumMessageID: message.id) }
                        )
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        reportingContext = ReportContext(forumPostID: post.likeTargetID)
                    } label: {
                        Label("檢舉文章", systemImage: "flag")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
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
        .sheet(item: $reportingContext) { context in
            ReportSheet(context: context)
                .environmentObject(apiService)
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
    @EnvironmentObject var apiService: APIService
    let message: ForumMessage
    let onReport: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForumUserLink(user: message.user, anonymous: message.anonymous) {
                ForumAvatar(user: message.user, anonymous: message.anonymous, size: 32)
            }
            .environmentObject(apiService)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(message.anonymous ? "匿名" : (message.user?.displayName ?? "未知用戶"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Menu {
                        Button(role: .destructive, action: onReport) {
                            Label("檢舉留言", systemImage: "flag")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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

private struct ForumUserLink<Label: View>: View {
    @EnvironmentObject var apiService: APIService
    let user: ForumUser?
    let anonymous: Bool
    @ViewBuilder let label: () -> Label

    var body: some View {
        if !anonymous, let user {
            NavigationLink {
                ForumUserPostsView(user: user)
                    .environmentObject(apiService)
            } label: {
                label()
            }
            .buttonStyle(.plain)
        } else {
            label()
        }
    }
}

private struct ForumUserPostsView: View {
    @EnvironmentObject var apiService: APIService

    let user: ForumUser
    @State private var posts: [ForumPost] = []
    @State private var page = 1
    @State private var totalPages = 1
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var reportingContext: ReportContext?

    var body: some View {
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
                ContentUnavailableView("目前沒有文章", systemImage: "doc.text")
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(posts) { post in
                            ForumPostRow(
                                post: post,
                                showPinned: false,
                                onReport: { reportingContext = ReportContext(forumPostID: post.likeTargetID) }
                            )
                            .environmentObject(apiService)
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
        .navigationTitle(user.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if posts.isEmpty {
                await load(reset: true)
            }
        }
        .sheet(item: $reportingContext) { context in
            ReportSheet(context: context)
                .environmentObject(apiService)
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
            let result = try await apiService.fetchForumUserPosts(userID: user.id, page: page)
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
                Image(systemName: anonymous ? "person.crop.circle.fill" : "person.circle.fill")
                    .resizable()
                    .foregroundStyle(anonymous ? Color(.systemGray2) : Color.blue)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

private struct ForumTagCloud: View {
    let tags: [ForumTag]

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(tags) { tag in
                ForumTagBadge(tag: tag)
            }
        }
    }
}

private struct ForumTagBadge: View {
    let tag: ForumTag

    private var color: Color {
        Color(hex: tag.colorHex) ?? .secondary
    }

    var body: some View {
        Text(tag.name)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(readableTextColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(Color(.separator).opacity(0.18), lineWidth: 1)
            }
    }

    private var readableTextColor: Color {
        guard let components = color.rgbComponents else {
            return .primary
        }
        let luminance = (0.299 * components.red) + (0.587 * components.green) + (0.114 * components.blue)
        return luminance > 0.62 ? .black : .white
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(proposal: proposal, subviews: subviews)
        return CGSize(
            width: proposal.width ?? rows.map(\.width).max() ?? 0,
            height: rows.map(\.height).reduce(0, +) + CGFloat(max(rows.count - 1, 0)) * lineSpacing
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews) {
            var x = bounds.minX
            for item in row.items {
                item.subview.place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private func rows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var current = Row()

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if current.width + size.width + (current.items.isEmpty ? 0 : spacing) > maxWidth,
               !current.items.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.add(subview: subview, size: size, spacing: spacing)
        }

        if !current.items.isEmpty {
            rows.append(current)
        }
        return rows
    }

    private struct Row {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0

        mutating func add(subview: LayoutSubview, size: CGSize, spacing: CGFloat) {
            if !items.isEmpty {
                width += spacing
            }
            items.append(Item(subview: subview, size: size))
            width += size.width
            height = max(height, size.height)
        }
    }

    private struct Item {
        let subview: LayoutSubview
        let size: CGSize
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

private extension Color {
    init?(hex: String?) {
        guard let hex else { return nil }
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }

        guard cleaned.count == 6,
              let value = Int(cleaned, radix: 16) else {
            return nil
        }

        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self = Color(red: red, green: green, blue: blue)
    }

    var rgbComponents: (red: Double, green: Double, blue: Double)? {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        return (Double(red), Double(green), Double(blue))
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
            pin: post.pin,
            tags: post.tags,
            likes: likes,
            user: post.user,
            created: post.created,
            updated: post.updated
        )
    }
}

private enum ForumUserSnapshot {
    static func from(_ user: VocPassUser) -> ForumUser {
        ForumUser(id: user.id, name: user.name, username: user.username, avatar: user.avatarURL?.absoluteString ?? user.avatar)
    }
}
