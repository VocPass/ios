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
    let shareStatus: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, username, email, avatar, verified
        case emailVisibility = "email_visibility"
        case shareStatus = "share_status"
    }

    var avatarURL: URL? {
        guard let avatar = avatar, !avatar.isEmpty else { return nil }
        return URL(string: avatar)
    }

    var displayName: String {
        name.isEmpty ? username : name
    }
}

struct VocPassPublicUser: Decodable {
    let id: String
    let name: String
    let username: String
    let avatar: String?

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
                if let status = user.shareStatus {
                    CacheService.shared.isCurriculumSharing = status
                }
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
                if let status = user.shareStatus {
                    CacheService.shared.isCurriculumSharing = status
                }
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

    // MARK: - 為 URLRequest 附加 Bearer token
    func applyAuth(to request: inout URLRequest) throws {
        guard let token = authToken, !token.isEmpty else {
            throw APIError.serverMessage("請先登入 VocPass 帳號才能送出評價")
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    // MARK: - 更新使用者資料

    func updateUser(name: String?, username: String?, avatarData: Data?) async throws {
        guard let url = URL(string: "\(AppConfig.vocPassAPIHost)/api/user/") else {
            throw URLError(.badURL)
        }
        guard let token = authToken, !token.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }

        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func appendField(_ name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        if let name = name { appendField("name", value: name) }
        if let username = username { appendField("username", value: username) }

        if let avatarData = avatarData {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"avatar\"; filename=\"avatar.jpg\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(avatarData)
            body.append("\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, response) = try await urlSession.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if http.statusCode != 200 {
            struct ErrorBody: Decodable { let message: String }
            let msg = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.message ?? "更新失敗"
            throw APIError.serverMessage(msg)
        }

        let updatedUser = try await fetchMe()
        await MainActor.run { self.currentUser = updatedUser }
        print("✅ [VocPassAuth] 使用者資料已更新")
    }

    // MARK: - 取得他人公開資料

    func fetchUser(username: String) async throws -> VocPassPublicUser {
        guard let url = URL(string: "\(AppConfig.vocPassAPIHost)/api/user/\(username)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = authToken, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await urlSession.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        struct UserResponse: Decodable {
            let data: VocPassPublicUser
        }
        return try JSONDecoder().decode(UserResponse.self, from: data).data
    }

    // MARK: - 登出

    func logout() {
        authToken = nil
        currentUser = nil
        isLoggedIn = false
        print("🚪 [VocPassAuth] 已登出")
    }
}
