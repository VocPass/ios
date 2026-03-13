//
//  OnboardingView.swift
//  YKVS
//
//  Created by Hans on 2025/12/31.
//

import SwiftUI

struct OnboardingView: View {
    @Binding var hasSeenOnboarding: Bool
    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "graduationcap.fill",
            iconColor: .blue,
            title: "歡迎使用VocPass",
            subtitle: "高職通用校務查詢系統",
            description: "快速查詢您的成績、課表、缺曠記錄等校務資訊"
        ),
        OnboardingPage(
            icon: "calendar",
            iconColor: .green,
            title: "課表查詢",
            subtitle: "隨時掌握課程安排",
            description: "查看每週課表，支援離線緩存，無需每次重新載入"
        ),
        OnboardingPage(
            icon: "chart.bar.fill",
            iconColor: .orange,
            title: "成績查詢",
            subtitle: "學年成績與考試成績",
            description: "查看各科目成績、班級排名，追蹤學習進度"
        ),
        OnboardingPage(
            icon: "clock.badge.checkmark.fill",
            iconColor: .purple,
            title: "缺曠紀錄",
            subtitle: "出勤狀態一目瞭然",
            description: "查看缺曠統計、各科目出勤率，掌握出席狀況"
        ),
        OnboardingPage(
            icon: "lock.shield.fill",
            iconColor: .indigo,
            title: "隱私保護",
            subtitle: "您的資料安全無虞",
            description: "所有帳號密碼（不含成績與憑證等資訊）皆在本地處理，不會連線到第三方伺服器，確保您的個人隱私得到完整保障。"
        ),
        OnboardingPage(
            icon: "checkmark.shield.fill",
            iconColor: .cyan,
            title: "準備開始",
            subtitle: "登入您的帳號",
            description: "使用學校帳號登入後即可開始使用所有功能"
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Page content
            TabView(selection: $currentPage) {
                ForEach(0..<pages.count, id: \.self) { index in
                    OnboardingPageView(page: pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentPage)

            // Bottom section
            VStack(spacing: 20) {
                // Page indicators
                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Circle()
                            .fill(currentPage == index ? Color.accentColor : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .animation(.easeInOut, value: currentPage)
                    }
                }

                // Buttons
                HStack(spacing: 16) {
                    if currentPage > 0 {
                        Button("上一步") {
                            withAnimation {
                                currentPage -= 1
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()

                    if currentPage < pages.count - 1 {
                        Button("下一步") {
                            withAnimation {
                                currentPage += 1
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("開始使用") {
                            CacheService.shared.hasSeenOnboarding = true
                            hasSeenOnboarding = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 30)
            .background(Color(.systemBackground))
        }
        .background(Color(.systemGroupedBackground))
    }
}

struct OnboardingPage: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let description: String
}

struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            Image(systemName: page.icon)
                .font(.system(size: 80))
                .foregroundStyle(page.iconColor)
                .padding(.bottom, 20)

            // Title
            Text(page.title)
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            // Subtitle
            Text(page.subtitle)
                .font(.title2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Description
            Text(page.description)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
        .padding()
    }
}

#Preview {
    OnboardingView(hasSeenOnboarding: .constant(false))
}
