//
//  ForumView.swift
//  VocPass
//

import SwiftUI
import PhotosUI

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
    @State private var showCreatePost = false

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
                    HStack(spacing: 14) {
                        if vocPassAuth.isLoggedIn {
                            Button {
                                showCreatePost = true
                            } label: {
                                Image(systemName: "plus")
                            }

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
            .sheet(isPresented: $showCreatePost) {
                ForumCreatePostSheet(school: requestSchoolName) {
                    Task { await load(reset: true) }
                }
                .environmentObject(apiService)
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
        NavigationLink {
            ForumPostDetailView(post: post)
                .environmentObject(apiService)
        } label: {
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

                    if !post.imageURLs.isEmpty {
                        ForumImageStrip(urls: post.imageURLs, maxVisible: 3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator).opacity(0.18), lineWidth: 1)
        }
    }
}

private struct ForumCreatePostSheet: View {
    @EnvironmentObject var apiService: APIService
    @Environment(\.dismiss) private var dismiss

    let school: String
    let onCreated: () -> Void

    @State private var title = ""
    @State private var content = ""
    @State private var anonymous = false
    @State private var tags: [ForumTagOption] = []
    @State private var selectedTags: Set<String> = []
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var selectedImages: [ForumSelectedImage] = []
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let maxImageBytes = 5 * 1024 * 1024

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isSubmitting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("標題") {
                    TextField("輸入文章標題", text: $title)
                }

                Section("內容") {
                    TextField("想說些什麼？", text: $content, axis: .vertical)
                        .lineLimit(6...12)
                }

                if !tags.isEmpty {
                    Section("標籤") {
                        FlowLayout(spacing: 8, lineSpacing: 8) {
                            ForEach(tags) { tag in
                                Button {
                                    toggleTag(tag.name)
                                } label: {
                                    ForumSelectableTagBadge(tag: tag, isSelected: selectedTags.contains(tag.name))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("圖片") {
                    PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 5, matching: .images) {
                        Label("選擇圖片", systemImage: "photo.on.rectangle.angled")
                    }
                    Text("最多 5 張，每張會自動壓縮到 5 MB 以下")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !selectedImages.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(selectedImages) { selectedImage in
                                    Image(uiImage: selectedImage.image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 76, height: 76)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }
                        }
                    }
                }

                Section {
                    Toggle("匿名發文", isOn: $anonymous)
                }
            }
            .navigationTitle("發文")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("送出")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
            .alert("發文失敗", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .task {
                await loadTags()
            }
            .onChange(of: selectedPhotoItems) { _, newItems in
                Task { await loadSelectedImages(from: newItems) }
            }
        }
    }

    @MainActor
    private func submit() async {
        guard canSubmit else { return }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await apiService.createForumPost(
                school: school,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                anonymous: anonymous,
                tags: Array(selectedTags),
                images: selectedImages.map { ForumImageUpload(data: $0.data, mimeType: $0.mimeType) }
            )
            dismiss()
            onCreated()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadTags() async {
        do {
            tags = try await apiService.fetchForumTags()
        } catch {
            tags = []
        }
    }

    private func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }

    @MainActor
    private func loadSelectedImages(from items: [PhotosPickerItem]) async {
        var loaded: [ForumSelectedImage] = []
        var failedCount = 0
        for item in items.prefix(5) {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                continue
            }
            if let selectedImage = ForumSelectedImage.makeCompressed(from: image, originalData: data, maxBytes: maxImageBytes) {
                loaded.append(selectedImage)
            } else {
                failedCount += 1
            }
        }
        selectedImages = loaded
        if failedCount > 0 {
            errorMessage = "\(failedCount) 張圖片無法壓縮到 5 MB 以下，請換較小的圖片"
        }
    }
}

private struct ForumSelectedImage: Identifiable {
    let id = UUID()
    let data: Data
    let mimeType: String
    let image: UIImage

    static func mimeType(for data: Data) -> String {
        data.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "image/png" : "image/jpeg"
    }

    static func makeCompressed(from image: UIImage, originalData: Data, maxBytes: Int) -> ForumSelectedImage? {
        if originalData.count <= maxBytes {
            return ForumSelectedImage(data: originalData, mimeType: mimeType(for: originalData), image: image)
        }

        var workingImage = image.resizedToFit(maxDimension: 2048)
        let dimensionScales: [CGFloat] = [1, 0.85, 0.7, 0.55, 0.4]
        let qualities: [CGFloat] = [0.85, 0.75, 0.65, 0.55, 0.45, 0.35, 0.25]

        for scale in dimensionScales {
            if scale < 1 {
                workingImage = image.resizedToFit(maxDimension: 2048 * scale)
            }
            for quality in qualities {
                guard let data = workingImage.jpegData(compressionQuality: quality) else { continue }
                if data.count <= maxBytes {
                    return ForumSelectedImage(data: data, mimeType: "image/jpeg", image: workingImage)
                }
            }
        }

        return nil
    }
}

private extension UIImage {
    func resizedToFit(maxDimension: CGFloat) -> UIImage {
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension, longestSide > 0 else { return self }

        let scale = maxDimension / longestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

private struct ForumSelectableTagBadge: View {
    let tag: ForumTagOption
    let isSelected: Bool

    private var color: Color {
        Color(hex: tag.colorHex) ?? .blue
    }

    var body: some View {
        Text(tag.name)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(isSelected ? readableTextColor : color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? color : color.opacity(0.12))
            .clipShape(Capsule())
    }

    private var readableTextColor: Color {
        guard let components = color.rgbComponents else {
            return .white
        }
        let luminance = (0.299 * components.red) + (0.587 * components.green) + (0.114 * components.blue)
        return luminance > 0.62 ? .black : .white
    }
}

private struct ForumImageStrip: View {
    let urls: [URL]
    let maxVisible: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(urls.prefix(maxVisible).enumerated()), id: \.offset) { _, url in
                ForumRemoteImage(url: url)
                    .frame(width: 82, height: 82)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if urls.count > maxVisible {
                Text("+\(urls.count - maxVisible)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(width: 42, height: 82)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}

private struct ForumImageGrid: View {
    let urls: [URL]

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(urls.enumerated()), id: \.offset) { _, url in
                ForumRemoteImage(url: url)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

private struct ForumRemoteImage: View {
    let url: URL

    var body: some View {
        CachedAsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                ZStack {
                    Color(.tertiarySystemGroupedBackground)
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .clipped()
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
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var vocPassAuth = VocPassAuthService.shared

    @State private var post: ForumPost
    @State private var messages: [ForumMessage] = []
    @State private var totalPages = 1
    @State private var page = 1
    @State private var isLoadingMessages = false
    @State private var actionError: String?
    @State private var showLogin = false
    @State private var reportingContext: ReportContext?
    @State private var newMessage = ""
    @State private var newMessageAnonymous = false
    @State private var isSubmittingMessage = false
    @State private var showDeletePostConfirmation = false
    @State private var deletingMessage: ForumMessage?

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

                    if !post.imageURLs.isEmpty {
                        ForumImageGrid(urls: post.imageURLs)
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

            Section("發留言") {
                TextField("輸入留言", text: $newMessage, axis: .vertical)
                    .lineLimit(2...5)

                Toggle("匿名留言", isOn: $newMessageAnonymous)

                Button {
                    Task { await submitMessage() }
                } label: {
                    if isSubmittingMessage {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else {
                        Label("送出留言", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .disabled(newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmittingMessage)
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
                            likedByMe: messageLikedByMe(message),
                            onLike: { Task { await toggleMessageLike(message) } },
                            onDelete: { deletingMessage = message },
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
                        showDeletePostConfirmation = true
                    } label: {
                        Label("刪除文章", systemImage: "trash")
                    }

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
        .confirmationDialog("確定刪除這篇文章？", isPresented: $showDeletePostConfirmation, titleVisibility: .visible) {
            Button("刪除文章", role: .destructive) {
                Task { await deletePost() }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog(
            "確定刪除這則留言？",
            isPresented: Binding(
                get: { deletingMessage != nil },
                set: { if !$0 { deletingMessage = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("刪除留言", role: .destructive) {
                if let message = deletingMessage {
                    deletingMessage = nil
                    Task { await deleteMessage(message) }
                }
            }
            Button("取消", role: .cancel) {
                deletingMessage = nil
            }
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

    private func messageLikedByMe(_ message: ForumMessage) -> Bool {
        guard let userID = vocPassAuth.currentUser?.id else { return false }
        return message.likes.contains(userID)
    }

    @MainActor
    private func deletePost() async {
        guard vocPassAuth.isLoggedIn else {
            showLogin = true
            return
        }

        do {
            try await apiService.deleteForumPost(postID: post.likeTargetID)
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func deleteMessage(_ message: ForumMessage) async {
        guard vocPassAuth.isLoggedIn else {
            showLogin = true
            return
        }

        let oldMessages = messages
        messages.removeAll { $0.id == message.id }

        do {
            try await apiService.deleteForumMessage(messageID: message.id)
        } catch {
            messages = oldMessages
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func toggleMessageLike(_ message: ForumMessage) async {
        guard let userID = vocPassAuth.currentUser?.id else {
            showLogin = true
            return
        }

        let shouldLike = !message.likes.contains(userID)
        var updatedLikes = message.likes
        if shouldLike {
            updatedLikes.append(userID)
        } else {
            updatedLikes.removeAll { $0 == userID }
        }

        let oldMessages = messages
        messages = messages.map { current in
            current.id == message.id
                ? ForumMessageSnapshot.copy(from: current, likes: updatedLikes)
                : current
        }

        do {
            try await apiService.setForumMessageLike(messageID: message.id, liked: shouldLike)
        } catch {
            messages = oldMessages
            actionError = error.localizedDescription
        }
    }

    @MainActor
    private func submitMessage() async {
        guard vocPassAuth.isLoggedIn else {
            showLogin = true
            return
        }

        let content = newMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isSubmittingMessage else { return }

        isSubmittingMessage = true
        defer { isSubmittingMessage = false }

        do {
            try await apiService.createForumMessage(
                postID: post.likeTargetID,
                content: content,
                anonymous: newMessageAnonymous
            )
            newMessage = ""
            newMessageAnonymous = false
            await loadMessages(reset: true)
        } catch {
            actionError = error.localizedDescription
        }
    }
}

private struct ForumMessageRow: View {
    @EnvironmentObject var apiService: APIService
    let message: ForumMessage
    let likedByMe: Bool
    let onLike: () -> Void
    let onDelete: () -> Void
    let onReport: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForumUserLink(user: message.user, anonymous: message.anonymous) {
                ForumAvatar(user: message.user, anonymous: message.anonymous, size: 32)
            }
            .environmentObject(apiService)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(message.anonymous ? "匿名" : (message.user?.displayName ?? "未知用戶"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    if !message.created.isEmpty {
                        Text(ForumDateFormatter.display(message.created))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Menu {
                        Button(role: .destructive, action: onDelete) {
                            Label("刪除留言", systemImage: "trash")
                        }

                        Button(role: .destructive, action: onReport) {
                            Label("檢舉留言", systemImage: "flag")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 24)
                    }
                }

                Text(message.content)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onLike) {
                    HStack(spacing: 5) {
                        Image(systemName: likedByMe ? "heart.fill" : "heart")
                            .font(.caption)
                            .foregroundStyle(likedByMe ? Color.red : Color.secondary)
                        Text("\(message.likes.count)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(likedByMe ? Color.red.opacity(0.12) : Color(.tertiarySystemGroupedBackground))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ForumUserLink<Label: View>: View {
    @EnvironmentObject var apiService: APIService
    let user: ForumUser?
    let anonymous: Bool
    @ViewBuilder let label: () -> Label
    @State private var isShowingUserPosts = false

    var body: some View {
        if !anonymous, let user {
            Button {
                isShowingUserPosts = true
            } label: {
                label()
            }
            .buttonStyle(.plain)
            .navigationDestination(isPresented: $isShowingUserPosts) {
                ForumUserPostsView(user: user)
                    .environmentObject(apiService)
            }
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
            images: post.images,
            likes: likes,
            user: post.user,
            created: post.created,
            updated: post.updated
        )
    }
}

private enum ForumMessageSnapshot {
    static func copy(from message: ForumMessage, likes: [String]) -> ForumMessage {
        ForumMessage(
            id: message.id,
            content: message.content,
            anonymous: message.anonymous,
            user: message.user,
            created: message.created,
            likes: likes
        )
    }
}

private enum ForumUserSnapshot {
    static func from(_ user: VocPassUser) -> ForumUser {
        ForumUser(id: user.id, name: user.name, username: user.username, avatar: user.avatarURL?.absoluteString ?? user.avatar)
    }
}
