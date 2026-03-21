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

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)

                Text("VocPass")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                if apiService.isLoggedIn {
                    if let school = SchoolConfigManager.shared.selectedSchool {
                        Text(school.name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Label("已登入", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                } else {
                    Text("這裡正在籌備新功能，先去校務頁面登入吧！")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .navigationTitle("首頁")
        }
    }
}

// MARK: - 校務
struct SchoolAffairsView: View {
    @EnvironmentObject var apiService: APIService
    @StateObject private var schoolConfigManager = SchoolConfigManager.shared

    var body: some View {
        if apiService.isLoggedIn {
            NavigationStack {
                List {
                    NavigationLink(destination: HomeView()) {
                        Label("獎懲", systemImage: "star.fill")
                    }
                    NavigationLink(destination: CurriculumView()) {
                        Label("課表", systemImage: "calendar")
                    }
                    NavigationLink(destination: AttendanceView()) {
                        Label("缺曠", systemImage: "person.badge.clock")
                    }
                    NavigationLink(destination: ScoreView()) {
                        Label("成績", systemImage: "chart.bar.fill")
                    }
                }
                .navigationTitle("校務")
            }
        } else if let school = schoolConfigManager.selectedSchool,
                  let loginURL = school.loginURL {
            LoginView(school: school, targetURL: loginURL)
                .environmentObject(apiService)
        } else {
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
        }
    }
}

// MARK: - 設定頁面
struct SettingsView: View {
    @EnvironmentObject var apiService: APIService
    @StateObject private var dynamicIsland = DynamicIslandService.shared
    @State private var showCookies = false
    @State private var autoStart = CacheService.shared.autoStartDynamicIsland
    @State private var minutesBefore = CacheService.shared.autoStartMinutesBefore

    var body: some View {
        NavigationStack {
            List {
                Section("帳號") {
                    if let school = SchoolConfigManager.shared.selectedSchool {
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
                                Text("登出")
                            }
                        }
                    }
                }

                // MARK: 即時動態設定
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
            .navigationTitle("設定")
        }
    }
}

#Preview {
    MainTabView(selectedTab: .constant(0))
        .environmentObject(APIService.shared)
}
