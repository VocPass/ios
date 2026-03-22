//
//  VocPassAuthService.swift
//  VocPass
//

import Foundation
import Combine

struct VocPassUser: Codable {
    let id: String
    let name: String
    let username: String
    let email: String
    let avatar: String?
    let emailVisibility: Bool
    let verified: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, username, email, avatar, verified
        case emailVisibility = "email_visibility"
    }

    var avatarURL: URL? {
        guard let avatar = avatar, !avatar.isEmpty else { return nil }
        return URL(string: avatar)
    }

    var displayName: String {
        name.isEmpty ? username : name
    }
}

class VocPassAuthService: ObservableObject {
    static let shared = VocPassAuthService()

    @Published var isLoggedIn = false
    @Published var currentUser: VocPassUser?

    private let tokenKey = "vocpass_auth_token"

    private var authToken: String? {
        get { UserDefaults.standard.string(forKey: tokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: tokenKey) }
    }

    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        return URLSession(configuration: config)
    }()

    // MARK: - OAuth callback 後呼叫（帶 token）

    func handleTokenLogin(token: String) async {
        authToken = token

        do {
            let user = try await fetchMe()
            await MainActor.run {
                self.currentUser = user
                self.isLoggedIn = true
            }
            print("✅ [VocPassAuth] 登入成功：\(user.displayName)")
        } catch {
            print("❌ [VocPassAuth] 取得使用者資料失敗: \(error)")
            authToken = nil
        }
    }

    // MARK: - 啟動時恢復 session

    func restoreSession() async {
        guard authToken != nil else { return }

        do {
            let user = try await fetchMe()
            await MainActor.run {
                self.currentUser = user
                self.isLoggedIn = true
            }
            print("✅ [VocPassAuth] 已恢復 session：\(user.displayName)")
        } catch {
            print("❌ [VocPassAuth] Session 已失效: \(error)")
            authToken = nil
        }
    }

    // MARK: - 取得使用者資料

    func fetchMe() async throws -> VocPassUser {
        guard let url = URL(string: "\(AppConfig.vocPassAuthHost)/auth/me") else {
            throw URLError(.badURL)
        }

        guard let token = authToken, !token.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await urlSession.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        if let raw = String(data: data, encoding: .utf8) {
            print("📦 [VocPassAuth] /auth/me 回應: \(raw)")
        }

        return try JSONDecoder().decode(VocPassUser.self, from: data)
    }

    // MARK: - 登出

    func logout() {
        authToken = nil
        currentUser = nil
        isLoggedIn = false
        print("🚪 [VocPassAuth] 已登出")
    }
}
