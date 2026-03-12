//
//  ContentView.swift
//  YKVS
//
//  Created by Hans on 2025/12/31.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var apiService = APIService.shared
    @StateObject private var schoolConfigManager = SchoolConfigManager.shared
    @State private var hasSeenOnboarding = CacheService.shared.hasSeenOnboarding
    @State private var hasSelectedSchool = SchoolConfigManager.shared.hasSelectedSchool

    var body: some View {
        Group {
            if !hasSeenOnboarding {
                OnboardingView(hasSeenOnboarding: $hasSeenOnboarding)
            } else if !hasSelectedSchool {
                SchoolSelectionView(hasSelectedSchool: $hasSelectedSchool)
            } else if apiService.isLoggedIn {
                MainTabView()
                    .environmentObject(apiService)
            } else if let school = schoolConfigManager.selectedSchool,
                      let loginURL = school.loginURL {
                LoginView(school: school, targetURL: loginURL)
                    .environmentObject(apiService)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    Text("無法載入學校配置")
                        .font(.headline)
                    Button("重新選擇學校") {
                        hasSelectedSchool = false
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .onAppear {
            if schoolConfigManager.schools.isEmpty {
                schoolConfigManager.loadSchools()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .schoolChanged)) { _ in
            hasSelectedSchool = schoolConfigManager.hasSelectedSchool
        }
    }
}

// MARK: - 登入頁面
struct LoginView: View {
    @EnvironmentObject var apiService: APIService
    let school: SchoolConfig
    let targetURL: URL

    @State private var cookies: [HTTPCookie] = []
    @State private var isLoggedIn = false
    @State private var isLoggingIn = false
    @State private var isCaptchaRecognizing = false
    @State private var lastRecognizedCaptcha: String?

    var body: some View {
        NavigationStack {
            ZStack {
                WebView(
                    url: targetURL,
                    school: school,
                    cookies: $cookies,
                    isLoggedIn: $isLoggedIn,
                    isLoggingIn: $isLoggingIn
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onReceive(NotificationCenter.default.publisher(for: .captchaRecognitionStarted)) { _ in
                    isCaptchaRecognizing = true
                    lastRecognizedCaptcha = nil
                }
                .onReceive(NotificationCenter.default.publisher(for: .captchaRecognitionCompleted)) { notification in
                    isCaptchaRecognizing = false
                    if let result = notification.object as? String {
                        lastRecognizedCaptcha = result
                    }
                }

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        CaptchaIndicatorView(
                            isRecognizing: isCaptchaRecognizing,
                            lastRecognizedText: lastRecognizedCaptcha
                        )
                        Spacer()
                    }
                    .padding(.bottom, 100)
                }

                if isLoggingIn {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("登入中...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(32)
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
                }
            }
            .navigationTitle(school.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        SchoolConfigManager.shared.clearSelectedSchool()
                        NotificationCenter.default.post(name: .schoolChanged, object: nil)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.left")
                            Text("換學校")
                        }
                        .font(.subheadline)
                    }
                }
            }
            .onChange(of: isLoggedIn) { _, newValue in
                if newValue {
                    print("🔐 [Login] 登入成功！")
                    print("🍪 [Login] Cookies 數量: \(cookies.count)")
                    for cookie in cookies {
                        print("  - \(cookie.name): \(cookie.value.prefix(20))...")
                    }
                    apiService.cookies = cookies
                    apiService.isLoggedIn = true
                }
            }
            .onChange(of: cookies) { _, newValue in
                print("🍪 [Login] Cookies 更新: \(newValue.count) 個")
                if isLoggedIn {
                    apiService.cookies = newValue
                }
            }
        }
    }
}

// MARK: - 通知名稱
extension Notification.Name {
    static let schoolChanged = Notification.Name("schoolChanged")
    static let captchaRecognitionStarted = Notification.Name("captchaRecognitionStarted")
    static let captchaRecognitionCompleted = Notification.Name("captchaRecognitionCompleted")
}

// MARK: - 不支援功能畫面
struct UnsupportedFeatureView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "nosign")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            Text("此功能不支援")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("目前選擇的學校尚未支援此功能")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
}
