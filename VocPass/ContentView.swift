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
    @State private var isCheckingSession = true
    @State private var selectedTab = 0
    @State private var showSchoolPicker = false
    @State private var schoolPickerDismissed = false
    @State private var deepLinkEventID: W2MDeepLinkTarget?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if isCheckingSession {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !hasSeenOnboarding {
                OnboardingView(hasSeenOnboarding: $hasSeenOnboarding)
            } else {
                MainTabView(selectedTab: $selectedTab)
                    .environmentObject(apiService)
                    .sheet(isPresented: .init(
                        get: { (!hasSelectedSchool && !schoolPickerDismissed) || showSchoolPicker },
                        set: { if !$0 { showSchoolPicker = false; schoolPickerDismissed = true } }
                    )) {
                        SchoolSelectionView(hasSelectedSchool: $hasSelectedSchool) {
                            selectedTab = 1
                        }
                    }
                    .sheet(item: $deepLinkEventID) { target in
                        NavigationStack {
                            W2MResultView(eventID: target.id)
                        }
                    }
            }
        }
        .onOpenURL { url in
            // vocpass://w2m/<event_id>
            guard url.scheme == "vocpass",
                  url.host == "w2m",
                  let id = url.pathComponents.dropFirst().first, !id.isEmpty else { return }
            deepLinkEventID = W2MDeepLinkTarget(id: id)
        }
        .onAppear {
            if schoolConfigManager.schools.isEmpty {
                schoolConfigManager.loadSchools()
            }
            Task {
                await VocPassAuthService.shared.restoreSession()
                await MainActor.run { isCheckingSession = false }
                // Ping 在背景執行，不阻擋 UI
                if hasSeenOnboarding && hasSelectedSchool {
                    await apiService.pingAndRestoreSession()
                    CacheService.shared.syncTimetableToWidget()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .schoolChanged)) { _ in
            hasSelectedSchool = schoolConfigManager.hasSelectedSchool
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSchoolPicker)) { _ in
            schoolPickerDismissed = false
            showSchoolPicker = true
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                CacheService.shared.syncTimetableToWidget()
            }
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
                    CacheService.shared.saveCookies(cookies)
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

// MARK: - Deep Link Helper

struct W2MDeepLinkTarget: Identifiable {
    let id: String
}

// MARK: - 通知名稱
extension Notification.Name {
    static let schoolChanged = Notification.Name("schoolChanged")
    static let showSchoolPicker = Notification.Name("showSchoolPicker")
    static let captchaRecognitionStarted = Notification.Name("captchaRecognitionStarted")
    static let captchaRecognitionCompleted = Notification.Name("captchaRecognitionCompleted")
    static let openW2MEvent = Notification.Name("openW2MEvent")
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
