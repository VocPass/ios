//
//  MainTabView.swift
//  YKVS
//
//  Created by Hans on 2025/12/31.
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var apiService: APIService

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("獎懲", systemImage: "star.fill")
                }

            CurriculumView()
                .tabItem {
                    Label("課表", systemImage: "calendar")
                }

            AttendanceView()
                .tabItem {
                    Label("缺曠", systemImage: "person.badge.clock")
                }

            ScoreView()
                .tabItem {
                    Label("成績", systemImage: "chart.bar.fill")
                }

            SettingsView()
                .tabItem {
                    Label("設定", systemImage: "gearshape.fill")
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
    @State private var className = CacheService.shared.savedClassName

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
                        SchoolConfigManager.shared.clearSelectedSchool()
                        apiService.logout()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.left.arrow.right")
                            Text("切換學校")
                        }
                    }
                    
                    Button(role: .destructive) {
                        apiService.logout()
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("登出")
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
                            let name = className.isEmpty ? "我的課表" : className
                            Task { await dynamicIsland.startActivity(className: name) }
                        }
                    } label: {
                        Label(
                            dynamicIsland.isActivityRunning ? "手動停止" : "手動啟動",
                            systemImage: dynamicIsland.isActivityRunning ? "stop.fill" : "play.fill"
                        )
                        .foregroundStyle(dynamicIsland.isActivityRunning ? .red : .blue)
                    }

                    // 自動啟動開關
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

                    HStack {
                        Label("班級名稱", systemImage: "person.3")
                        Spacer()
                        TextField("例：訊三孝", text: $className)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                            .onSubmit {
                                CacheService.shared.savedClassName = className
                            }
                            .onChange(of: className) { _, newValue in
                                CacheService.shared.savedClassName = newValue
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
    MainTabView()
        .environmentObject(APIService.shared)
}
