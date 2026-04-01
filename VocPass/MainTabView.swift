//
//  MainTabView.swift
//  YKVS
//
//  Created by Hans on 2025/12/31.
//

import SwiftUI
import PhotosUI
import SafariServices

struct MainTabView: View {
    @EnvironmentObject var apiService: APIService
    @Binding var selectedTab: Int

    var body: some View {
        TabView(selection: $selectedTab) {
            HomePageView()
                .tabItem {
                    Label("首頁", systemImage: "house.fill")
                }
                .tag(0)

            SchoolAffairsView()
                .tabItem {
                    Label("校務", systemImage: "building.columns")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Label("設定", systemImage: "gearshape.fill")
                }
                .tag(2)
        }
    }
}

// MARK: - 首頁
struct HomePageView: View {
    @EnvironmentObject var apiService: APIService
    @ObservedObject private var vocPassAuth = VocPassAuthService.shared
    @State private var showVocPassLogin = false
    @State private var showFollowing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                if vocPassAuth.isLoggedIn, let user = vocPassAuth.currentUser {
                    // 頭像
                    if let avatarURL = user.avatarURL {
                        CachedAsyncImage(url: avatarURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(Circle())
                            default:
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 80))
                                    .foregroundStyle(.blue)
                            }
                        }
                    } else {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.blue)
                    }

                    VStack(spacing: 4) {
                        Text(user.displayName)
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("@\(user.username)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.blue)

                    Text("VocPass")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Button {
                        showVocPassLogin = true
                    } label: {
                        Label("登入 VocPass 帳號", systemImage: "person.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                NavigationLink(destination: RestaurantView()) {
                    Label("吃啥？", systemImage: "fork.knife")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)

                Button {
                    showFollowing = true
                } label: {
                    Label("不揪？", systemImage: "person.2.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.12))
                        .foregroundStyle(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 32)
                .sheet(isPresented: $showFollowing) {
                    FollowingListView()
                        .environmentObject(apiService)
                }

                Spacer()
            }
            .navigationTitle("首頁")
            .sheet(isPresented: $showVocPassLogin) {
                VocPassLoginSheet()
            }
        }
    }
}

// MARK: - 校務
struct SchoolAffairsView: View {
    @EnvironmentObject var apiService: APIService
    @StateObject private var schoolConfigManager = SchoolConfigManager.shared
    @State private var showLogin = false
    @State private var showTelephone = false

    var body: some View {
        NavigationStack {
            Group {
                if schoolConfigManager.selectedSchool == nil {
                    VStack(spacing: 16) {
                        Image(systemName: "building.columns.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.secondary)
                        Text("尚未選擇學校")
                            .font(.headline)
                        Button("選擇學校") {
                            NotificationCenter.default.post(name: .showSchoolPicker, object: nil)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        if !apiService.isLoggedIn {
                            Section {
                                Button {
                                    showLogin = true
                                } label: {
                                    HStack {
                                        Image(systemName: "person.badge.key.fill")
                                            .foregroundStyle(.blue)
                                        Text("登入學校帳號以使用校務功能")
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        let hasNotice = schoolConfigManager.selectedSchool?.notice != nil
                        let hasTelephone = schoolConfigManager.selectedSchool?.telephone.flatMap(URL.init) != nil
                        if hasNotice || hasTelephone {
                            Section {
                                if hasNotice {
                                    NavigationLink(destination: SchoolNoticeView().environmentObject(apiService)) {
                                        Label("公告", systemImage: "bell.fill")
                                    }
                                }
                                if hasTelephone {
                                    Button {
                                        showTelephone = true
                                    } label: {
                                        Label {
                                            Text("分機查詢")
                                                .foregroundStyle(.primary)
                                        } icon: {
                                            Image(systemName: "phone.fill")
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        Section {
                            NavigationLink(destination: HomeView()) {
                                Label("獎懲", systemImage: "star.fill")
                            }
                            .disabled(!apiService.isLoggedIn)
                            NavigationLink(destination: CurriculumView()) {
                                Label("課表", systemImage: "calendar")
                            }
                            .disabled(!apiService.isLoggedIn && CacheService.shared.getCachedTimetable() == nil)
                            NavigationLink(destination: AttendanceView()) {
                                Label("缺曠", systemImage: "person.badge.clock")
                            }
                            .disabled(!apiService.isLoggedIn)
                            NavigationLink(destination: ScoreView()) {
                                Label("學年成績", systemImage: "chart.bar.fill")
                            }
                            .disabled(!apiService.isLoggedIn)
                            NavigationLink(destination: ExamScoreView()) {
                                Label("考試成績", systemImage: "list.bullet.clipboard")
                            }
                            .disabled(!apiService.isLoggedIn)
                        }
                    }
                }
            }
            .navigationTitle("校務")
            .navigationDestination(isPresented: $showLogin) {
                if let school = schoolConfigManager.selectedSchool,
                   let loginURL = school.loginURL {
                    LoginView(school: school, targetURL: loginURL)
                        .environmentObject(apiService)
                }
            }
            .onChange(of: apiService.isLoggedIn) { _, loggedIn in
                if loggedIn { showLogin = false }
            }
            .sheet(isPresented: $showTelephone) {
                if let urlString = schoolConfigManager.selectedSchool?.telephone,
                   let url = URL(string: urlString) {
                    TelephoneDirectoryView(url: url)
                        .ignoresSafeArea()
                }
            }
        }
    }
}

// MARK: - 設定頁面
struct SettingsView: View {
    @EnvironmentObject var apiService: APIService
    @ObservedObject private var vocPassAuth = VocPassAuthService.shared
    @StateObject private var schoolConfigManager = SchoolConfigManager.shared
    @State private var imageCacheSize: String = "計算中…"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink(destination: VocPassAccountSettingsView()) {
                        HStack {
                            Label("VocPass 帳號", systemImage: "person.circle")
                            Spacer()
                            if vocPassAuth.isLoggedIn, let user = vocPassAuth.currentUser {
                                Text(user.displayName)
                                    .foregroundColor(.secondary)
                                    .font(.subheadline)
                            } else {
                                Text("未登入")
                                    .foregroundColor(.secondary)
                                    .font(.subheadline)
                            }
                        }
                    }

                    NavigationLink(destination: SchoolSettingsView().environmentObject(apiService)) {
                        HStack {
                            Label("學校設定", systemImage: "building.columns")
                            Spacer()
                            if let school = schoolConfigManager.selectedSchool {
                                Text(school.name)
                                    .foregroundColor(.secondary)
                                    .font(.subheadline)
                            } else {
                                Text("未選擇")
                                    .foregroundColor(.secondary)
                                    .font(.subheadline)
                            }
                        }
                    }
                }

                Section("儲存空間") {
                    HStack {
                        Label("圖片快取", systemImage: "photo.stack")
                        Spacer()
                        Text(imageCacheSize)
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                    Button(role: .destructive) {
                        Task {
                            await ImageCacheService.shared.clearCache()
                            await refreshCacheSize()
                        }
                    } label: {
                        Label("清除圖片快取", systemImage: "trash")
                    }
                }

                Section("關於") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")
                            .foregroundColor(.secondary)
                    }

                    Link(destination: URL(string: "https://github.com/VocPass")!) {
                        HStack {
                            Image(systemName: "link")
                            Text("GitHub")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Link(destination: URL(string: "https://VocPass.com")!) {
                        HStack {
                            Image(systemName: "globe")
                            Text("官網")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Link(destination: AppConfig.discordURL) {
                        HStack {
                            Image(systemName: "bubble.left.and.bubble.right")
                            Text("Discord 社群")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("回饋") {
                    Link(destination: AppConfig.forumURL) {
                        HStack {
                            Image(systemName: "exclamationmark.bubble")
                            Text("回報問題 / 功能請求")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("設定")
            .task { await refreshCacheSize() }
        }
    }

    private func refreshCacheSize() async {
        let bytes = await ImageCacheService.shared.cacheSize()
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        imageCacheSize = formatter.string(fromByteCount: bytes)
    }
}

// MARK: - VocPass 帳號設定
struct VocPassAccountSettingsView: View {
    @ObservedObject private var vocPassAuth = VocPassAuthService.shared
    @StateObject private var loginVM = VocPassLoginViewModel()

    var body: some View {
        List {
            if vocPassAuth.isLoggedIn, let user = vocPassAuth.currentUser {
                Section {
                    HStack(spacing: 12) {
                        if let avatarURL = user.avatarURL {
                            CachedAsyncImage(url: avatarURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 52, height: 52)
                                        .clipShape(Circle())
                                default:
                                    Image(systemName: "person.circle.fill")
                                        .font(.system(size: 52))
                                        .foregroundStyle(.blue)
                                }
                            }
                        } else {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 52))
                                .foregroundStyle(.blue)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName)
                                .font(.headline)
                            Text("@\(user.username)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(user.email)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    NavigationLink(destination: EditProfileView()) {
                        Label("編輯個人資料", systemImage: "pencil")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        vocPassAuth.logout()
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("登出 VocPass")
                        }
                    }
                }
            } else {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "person.circle")
                            .font(.system(size: 50))
                            .foregroundStyle(.secondary)
                        Text("尚未登入 VocPass")
                            .font(.headline)
                        Text("登入後可使用更多功能")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }

                Section {
                    Button {
                        loginVM.startLogin()
                    } label: {
                        HStack {
                            Image(systemName: "person.badge.plus")
                            Text("登入 VocPass 帳號")
                        }
                    }
                }
            }
        }
        .navigationTitle("VocPass 帳號")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 學校設定
struct SchoolSettingsView: View {
    @EnvironmentObject var apiService: APIService
    @StateObject private var dynamicIsland = DynamicIslandService.shared
    @StateObject private var schoolConfigManager = SchoolConfigManager.shared
    @State private var showCookies = false
    @State private var autoStart = CacheService.shared.autoStartDynamicIsland
    @State private var showLoginRequiredAlert = false
    @State private var weeksPerSemester = CacheService.shared.weeksPerSemester
    @State private var periodsPerDay = CacheService.shared.periodsPerDay
    @AppStorage("absence_threshold_is_half") private var absenceThresholdIsHalf = false

    var body: some View {
        List {
            Section("帳號") {
                if let school = schoolConfigManager.selectedSchool {
                    HStack {
                        Image(systemName: "building.columns")
                        Text("目前學校")
                        Spacer()
                        Text(school.name)
                            .foregroundColor(.secondary)
                    }
                }

                Button {
                    NotificationCenter.default.post(name: .showSchoolPicker, object: nil)
                } label: {
                    HStack {
                        Image(systemName: "arrow.left.arrow.right")
                        Text("切換學校")
                    }
                }

                if apiService.isLoggedIn {
                    Button(role: .destructive) {
                        apiService.logout()
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("登出學校帳號")
                        }
                    }
                }
            }

            Section {
                HStack {
                    Image(systemName: dynamicIsland.isActivityRunning
                          ? "record.circle.fill" : "record.circle")
                        .foregroundStyle(dynamicIsland.isActivityRunning ? .red : .secondary)
                    Text("即時動態狀態")
                    Spacer()
                    Text(dynamicIsland.isActivityRunning ? "進行中" : "未啟動")
                        .foregroundStyle(dynamicIsland.isActivityRunning ? .red : .secondary)
                        .font(.caption)
                }

                Toggle(isOn: $autoStart) {
                    Label("啟用即時動態", systemImage: "clock.badge.checkmark")
                }
                .onChange(of: autoStart) { _, newValue in
                    if newValue && !VocPassAuthService.shared.isLoggedIn {
                        autoStart = false
                        showLoginRequiredAlert = true
                        return
                    }
                    CacheService.shared.autoStartDynamicIsland = newValue
                    if newValue {
                        dynamicIsland.scheduleAutoStart()
                        dynamicIsland.autoStartIfNeeded()
                    } else {
                        dynamicIsland.cancelAutoStart()
                        dynamicIsland.endActivity()
                    }
                    dynamicIsland.uploadTokensToServer()
                }
                .alert("請先登入 VocPass", isPresented: $showLoginRequiredAlert) {
                    Button("確定", role: .cancel) {}
                } message: {
                    Text("啟用即時動態需要登入 VocPass 帳號。")
                }



            } header: {
                Text("即時動態 / 動態島")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("開啟後，伺服器會在上課時段透過推播自動更新動態島課表。")
                        .font(.caption)

                    if let err = dynamicIsland.lastErrorMessage, !err.isEmpty {
                        Text("錯誤：\(err)")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section {
                // Push-to-Start Token（遠端啟動用，App 啟動即可取得）
                if let startToken = dynamicIsland.pushToStartTokenHex, !startToken.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Push-to-Start Token", systemImage: "power")
                            Spacer()
                            Button {
                                UIPasteboard.general.string = startToken
                            } label: {
                                Label("複製", systemImage: "doc.on.doc")
                                    .font(.caption)
                            }
                        }
                        Text(startToken)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } else {
                    HStack {
                        Label("Push-to-Start Token", systemImage: "power")
                        Spacer()
                        ProgressView()
                    }
                }

                // Push Token（遠端更新用，Live Activity 啟動後才有）
                if dynamicIsland.isActivityRunning {
                    if let token = dynamicIsland.pushTokenHex, !token.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Push Token (更新用)", systemImage: "key.fill")
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = token
                                } label: {
                                    Label("複製", systemImage: "doc.on.doc")
                                        .font(.caption)
                                }
                            }
                            Text(token)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    } else {
                        HStack {
                            Label("Push Token (更新用)", systemImage: "key.fill")
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                // APNs Device Token（一般通知用）
                if let apnsToken = dynamicIsland.apnsDeviceTokenHex, !apnsToken.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("APNs Device Token", systemImage: "bell.fill")
                            Spacer()
                            Button {
                                UIPasteboard.general.string = apnsToken
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                        }
                        Text(apnsToken)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack {
                        Label("APNs Device Token", systemImage: "bell.fill")
                        Spacer()
                        ProgressView()
                    }
                }
            } header: {
                Text("Live Activity Tokens")
            } footer: {
                Text("Push-to-Start Token 用於遠端啟動即時動態；Push Token 在啟動後出現，用於遠端更新；APNs Device Token 用於一般通知觸發啟動。")
                    .font(.caption)
            }

            Section {
                Stepper(value: $periodsPerDay, in: 1...12) {
                    HStack {
                        Label("每天節數", systemImage: "list.number")
                        Spacer()
                        Text("\(periodsPerDay) 節")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: periodsPerDay) { _, newValue in
                    CacheService.shared.periodsPerDay = newValue
                }
            } header: {
                Text("課表")
            } footer: {
                Text("課表固定顯示的節數，即使該節無課也會顯示。預設 7 節。")
                    .font(.caption)
            }

            Section {
                Stepper(value: $weeksPerSemester, in: 10...25) {
                    HStack {
                        Label("每學期週數", systemImage: "calendar")
                        Spacer()
                        Text("\(weeksPerSemester) 週")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: weeksPerSemester) { _, newValue in
                    CacheService.shared.weeksPerSemester = newValue
                }

                Picker(selection: $absenceThresholdIsHalf) {
                    Text("1/3（33%）").tag(false)
                    Text("1/2（50%）").tag(true)
                } label: {
                    Label("扣考門檻", systemImage: "exclamationmark.triangle")
                }
            } header: {
                Text("缺曠統計")
            } footer: {
                Text("每學期週數用於計算各科缺曠百分比，預設 18 週。扣考門檻決定警告顏色的起始點。")
                    .font(.caption)
            }

            Section {
                DisclosureGroup("Cookies", isExpanded: $showCookies) {
                    if apiService.cookies.isEmpty {
                        Text("尚無 Cookies")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(apiService.cookies, id: \.name) { cookie in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(cookie.name)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text(cookie.value)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Button("複製全部 Cookies") {
                            let cookieString = apiService.cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                            UIPasteboard.general.string = cookieString
                        }
                    }
                }
            } header: {
                Text("開發者")
            }
        }
        .navigationTitle("學校設定")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 分機查詢
struct TelephoneDirectoryView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

private struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

// MARK: - 編輯個人資料
struct EditProfileView: View {
    @ObservedObject private var vocPassAuth = VocPassAuthService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var username: String = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var avatarImage: UIImage?
    @State private var imageToCrop: IdentifiableImage?
    @State private var isLoadingImage = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        ZStack(alignment: .bottomTrailing) {
                            Group {
                                if let avatarImage {
                                    Image(uiImage: avatarImage)
                                        .resizable()
                                        .scaledToFill()
                                } else if let url = vocPassAuth.currentUser?.avatarURL {
                                    CachedAsyncImage(url: url) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image.resizable().scaledToFill()
                                        default:
                                            Image(systemName: "person.circle.fill")
                                                .resizable()
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                } else {
                                    Image(systemName: "person.circle.fill")
                                        .resizable()
                                        .foregroundStyle(.blue)
                                }
                            }
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())

                            Image(systemName: "camera.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.white, .blue)
                                .offset(x: 4, y: 4)
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section("基本資料") {
                HStack {
                    Text("名稱")
                        .foregroundStyle(.secondary)
                    TextField("顯示名稱", text: $name)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("帳號")
                        .foregroundStyle(.secondary)
                    TextField("使用者名稱", text: $username)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
        }
        .navigationTitle("編輯個人資料")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("儲存") { save() }
                    .disabled(isSaving)
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            isLoadingImage = true
            errorMessage = nil
            Task {
                defer { isLoadingImage = false }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        errorMessage = "無法載入圖片"
                        return
                    }
                    guard let uiImage = UIImage(data: data) else {
                        errorMessage = "圖片格式不支援"
                        return
                    }
                    imageToCrop = IdentifiableImage(image: uiImage)
                } catch {
                    errorMessage = "圖片下載失敗，請確認網路連線後再試"
                }
            }
        }
        .fullScreenCover(item: $imageToCrop) { item in
            CropImageView(image: item.image) { cropped in
                avatarImage = cropped
            }
        }
        .onAppear {
            if let user = vocPassAuth.currentUser {
                name = user.name
                username = user.username
            }
        }
        .disabled(isSaving || isLoadingImage)
        .overlay {
            if isSaving || isLoadingImage {
                ProgressView(isLoadingImage ? "載入圖片中…" : "")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func save() {
        guard let user = vocPassAuth.currentUser else { return }
        let newName = name.trimmingCharacters(in: .whitespaces)
        let newUsername = username.trimmingCharacters(in: .whitespaces)

        let changedName: String? = newName != user.name ? newName : nil
        let changedUsername: String? = newUsername != user.username ? newUsername : nil
        let avatarData: Data? = avatarImage.flatMap { $0.jpegData(compressionQuality: 0.8) }

        guard changedName != nil || changedUsername != nil || avatarData != nil else {
            dismiss()
            return
        }

        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await vocPassAuth.updateUser(
                    name: changedName,
                    username: changedUsername,
                    avatarData: avatarData
                )
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }
}

// MARK: - 1:1 裁切視圖
struct CropImageView: View {
    let image: UIImage
    let onCrop: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var displaySize: CGFloat = 300

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                GeometryReader { geo in
                    let size = min(geo.size.width, geo.size.height)
                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .scaleEffect(scale, anchor: .center)
                            .offset(offset)
                            .clipped()

                        cropGrid(size: size)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = max(1.0, lastScale * value)
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                    let clamped = clampedOffset(offset, size: size)
                                    withAnimation(.spring(duration: 0.2)) { offset = clamped }
                                    lastOffset = clamped
                                },
                            DragGesture()
                                .onChanged { value in
                                    offset = clampedOffset(
                                        CGSize(width: lastOffset.width + value.translation.width,
                                               height: lastOffset.height + value.translation.height),
                                        size: size
                                    )
                                }
                                .onEnded { _ in lastOffset = offset }
                        )
                    )
                    .onAppear { displaySize = size }
                    .onChange(of: geo.size) { _, s in displaySize = min(s.width, s.height) }
                }
            }
            .navigationTitle("裁切照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        if let cropped = cropImage(displaySize: displaySize) {
                            onCrop(cropped)
                        }
                        dismiss()
                    }
                    .foregroundStyle(.white)
                    .fontWeight(.semibold)
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    @ViewBuilder
    private func cropGrid(size: CGFloat) -> some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: size / 3, y: 0))
                path.addLine(to: CGPoint(x: size / 3, y: size))
                path.move(to: CGPoint(x: 2 * size / 3, y: 0))
                path.addLine(to: CGPoint(x: 2 * size / 3, y: size))
                path.move(to: CGPoint(x: 0, y: size / 3))
                path.addLine(to: CGPoint(x: size, y: size / 3))
                path.move(to: CGPoint(x: 0, y: 2 * size / 3))
                path.addLine(to: CGPoint(x: size, y: 2 * size / 3))
            }
            .stroke(Color.white.opacity(0.35), lineWidth: 0.5)

            Rectangle()
                .strokeBorder(Color.white, lineWidth: 1.5)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }

    private func clampedOffset(_ offset: CGSize, size: CGFloat) -> CGSize {
        let shortSide = min(image.size.width, image.size.height)
        let totalScale = (size / shortSide) * scale
        let maxX = max(0, (image.size.width * totalScale - size) / 2)
        let maxY = max(0, (image.size.height * totalScale - size) / 2)
        return CGSize(
            width: max(-maxX, min(maxX, offset.width)),
            height: max(-maxY, min(maxY, offset.height))
        )
    }

    private func cropImage(displaySize: CGFloat) -> UIImage? {
        let outputSize: CGFloat = 512
        let factor = outputSize / displaySize
        let shortSide = min(image.size.width, image.size.height)
        let totalScale = (displaySize / shortSide) * scale
        let displayW = image.size.width * totalScale
        let displayH = image.size.height * totalScale
        let imgX = displaySize / 2 - displayW / 2 + offset.width
        let imgY = displaySize / 2 - displayH / 2 + offset.height

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outputSize, height: outputSize))
        return renderer.image { _ in
            image.draw(in: CGRect(x: imgX * factor, y: imgY * factor,
                                  width: displayW * factor, height: displayH * factor))
        }
    }
}

#Preview {
    MainTabView(selectedTab: .constant(0))
        .environmentObject(APIService.shared)
}
