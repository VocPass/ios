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
    @State private var showCookies = false

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

                Section("關於") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://github.com/HansHans135/VocPass")!) {
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
