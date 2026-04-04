//
//  W2MService.swift
//  VocPass
//
//  「出來玩」When2meet API 服務層
//

import Foundation

enum W2MError: LocalizedError {
    case notLoggedIn
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn: return "請先登入 VocPass 帳號"
        case .serverError(let msg): return msg
        }
    }
}

class W2MService {
    static let shared = W2MService()
    private init() {}

    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }()

    private var baseURL: String { AppConfig.vocPassAPIHost }

    // MARK: - 取得活動列表（需登入）

    func fetchEvents() async throws -> W2MEventListResponse {
        guard let url = URL(string: "\(baseURL)/api/w2m/events") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        try VocPassAuthService.shared.applyAuth(to: &req)

        let (data, response) = try await urlSession.data(for: req)
        try validateResponse(response, data: data)

        struct Wrapper: Decodable {
            let code: Int
            let data: W2MEventListResponse
        }
        return try JSONDecoder().decode(Wrapper.self, from: data).data
    }

    // MARK: - 建立活動

    func createEvent(title: String, dates: [String], description: String = "") async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/w2m/events") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try VocPassAuthService.shared.applyAuth(to: &req)

        let body: [String: Any] = ["title": title, "dates": dates, "description": description]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: req)
        try validateResponse(response, data: data)

        struct Wrapper: Decodable {
            struct DataPayload: Decodable { let id: String }
            let code: Int
            let data: DataPayload
        }
        let decoded = try JSONDecoder().decode(Wrapper.self, from: data)
        return decoded.data.id
    }

    // MARK: - 編輯活動（僅 creator）

    func updateEvent(id: String, title: String?, dates: [String]?) async throws {
        guard let url = URL(string: "\(baseURL)/api/w2m/events/\(id)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try VocPassAuthService.shared.applyAuth(to: &req)

        var body: [String: Any] = [:]
        if let title { body["title"] = title }
        if let dates { body["dates"] = dates }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: req)
        try validateResponse(response, data: data)
    }

    // MARK: - 取得活動詳情（不需登入）

    func fetchEvent(id: String) async throws -> W2MEvent {
        guard let url = URL(string: "\(baseURL)/api/w2m/events/\(id)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        try? VocPassAuthService.shared.applyAuth(to: &req)   // 帶 token（若已登入），讓伺服器能識別用戶

        let (data, response) = try await urlSession.data(for: req)
        try validateResponse(response, data: data)

        struct Wrapper: Decodable {
            let code: Int
            let data: W2MEvent
        }
        return try JSONDecoder().decode(Wrapper.self, from: data).data
    }

    // MARK: - 提交可用時段

    func submitAvailability(eventID: String, slots: [String]) async throws {
        guard let url = URL(string: "\(baseURL)/api/w2m/events/\(eventID)/availability") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try VocPassAuthService.shared.applyAuth(to: &req)

        let body: [String: Any] = ["slots": slots]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: req)
        try validateResponse(response, data: data)
    }

    // MARK: - 分享連結

    func shareURL(for eventID: String) -> String {
        let host: String
        #if DEBUG
        host = "https://vocpass.com"
        #else
        host = AppConfig.vocPassAPIHost
            .replacingOccurrences(of: "http://", with: "https://")
        #endif
        return "\(host)/w2m/\(eventID)"
    }

    // MARK: - 私有

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            struct ErrBody: Decodable { let message: String? }
            let msg = (try? JSONDecoder().decode(ErrBody.self, from: data))?.message ?? "伺服器錯誤 (\(http.statusCode))"
            throw W2MError.serverError(msg)
        }
    }
}
