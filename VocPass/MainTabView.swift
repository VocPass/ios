//
//  MainTabView.swift
//  YKVS
//
//  Created by Hans on 2025/12/31.
//

import SwiftUI

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
                    Label("不揪", systemImage: "person.2.fill")
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

                        Section {
                            NavigationLink(destination: HomeView()) {
                                Label("獎懲", systemImage: "star.fill")
                            }
                            .disabled(!apiService.isLoggedIn)
                            NavigationLink(destination: CurriculumView()) {
                                Label("課表", systemImage: "calendar")
                            }
                            .disabled(!apiService.isLoggedIn)
                            NavigationLink(destination: AttendanceView()) {
                                Label("缺曠", systemImage: "person.badge.clock")
                            }
                            .disabled(!apiService.isLoggedIn)
                            NavigationLink(destination: ScoreView()) {
                                Label("成績", systemImage: "chart.bar.fill")
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
    @State private var minutesBefore = CacheService.shared.autoStartMinutesBefore
    @State private var weeksPerSemester = CacheService.shared.weeksPerSemester

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

                Button {
                    if dynamicIsland.isActivityRunning {
                        dynamicIsland.endActivity()
                    } else {
                        Task { await dynamicIsland.startActivity() }
                    }
                } label: {
                    Label(
                        dynamicIsland.isActivityRunning ? "手動停止" : "手動啟動",
                        systemImage: dynamicIsland.isActivityRunning ? "stop.fill" : "play.fill"
                    )
                    .foregroundStyle(dynamicIsland.isActivityRunning ? .red : .blue)
                }

                Toggle(isOn: $autoStart) {
                    Label("上課前自動顯示", systemImage: "clock.badge.checkmark")
                }
                .onChange(of: autoStart) { _, newValue in
                    CacheService.shared.autoStartDynamicIsland = newValue
                    if newValue {
                        dynamicIsland.scheduleAutoStart()
                    } else {
                        dynamicIsland.cancelAutoStart()
                    }
                }

                if autoStart {
                    Stepper(value: $minutesBefore, in: 5...60, step: 5) {
                        HStack {
                            Label("提前啟動時間", systemImage: "timer")
                            Spacer()
                            Text("\(minutesBefore) 分鐘前")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: minutesBefore) { _, newValue in
                        CacheService.shared.autoStartMinutesBefore = newValue
                        dynamicIsland.scheduleAutoStart()
                    }
                }
            } header: {
                Text("即時動態 / 動態島")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("開啟後，每天第一節課前 \(minutesBefore) 分鐘自動顯示動態島課表；放學後自動結束。")
                        .font(.caption)

                    if let err = dynamicIsland.lastErrorMessage, !err.isEmpty {
                        Text("啟動失敗：\(err)")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
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
            } header: {
                Text("缺曠統計")
            } footer: {
                Text("用於計算各科缺曠百分比，預設 18 週。")
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

#Preview {
    MainTabView(selectedTab: .constant(0))
        .environmentObject(APIService.shared)
}
