//
//  OriginalSystemView.swift
//  VocPass
//
//  前往原系統：以登入後儲存的 cookie 開啟學校原本的網頁系統。
//

import SwiftUI
import WebKit

// MARK: - 前往原系統畫面
struct OriginalSystemView: View {
    let school: SchoolConfig
    let url: URL
    /// 由呼叫端提供目前登入的 cookie（例如 apiService.cookies）。
    let cookies: [HTTPCookie]

    @State private var isLoading = true

    var body: some View {
        ZStack {
            OriginalSystemWebView(
                url: url,
                school: school,
                cookies: resolvedCookies,
                isLoading: $isLoading
            )
            .ignoresSafeArea(edges: .bottom)

            if isLoading {
                ProgressView("載入中…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .navigationTitle("原系統")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 若呼叫端傳入的 cookie 為空（例如 SwiftUI 在導覽前就先建立了目的地、
    /// 快照到尚未載入的狀態），改用已持久化的 cookie 作為後備。
    private var resolvedCookies: [HTTPCookie] {
        cookies.isEmpty ? CacheService.shared.loadCookies() : cookies
    }
}

// MARK: - 帶入 cookie 的 WebView
private struct OriginalSystemWebView: UIViewRepresentable {
    let url: URL
    let school: SchoolConfig
    let cookies: [HTTPCookie]
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.load(on: webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: OriginalSystemWebView
        private var didLoad = false

        private struct UserAgentResponse: Decodable {
            let code: Int
            let message: String?
            let data: String?
        }

        init(_ parent: OriginalSystemWebView) {
            self.parent = parent
        }

        /// 先寫入儲存的 cookie，套用自訂 UA 後再載入原系統首頁。
        func load(on webView: WKWebView) {
            guard !didLoad else { return }
            didLoad = true

            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            let group = DispatchGroup()
            print("🍪 [原系統] 準備注入 \(parent.cookies.count) 個 cookie 至 \(parent.url.host ?? "?")")
            for cookie in parent.cookies {
                print("  - \(cookie.name)=\(cookie.value.prefix(20)) domain=\(cookie.domain) path=\(cookie.path)")
                group.enter()
                cookieStore.setCookie(cookie) { group.leave() }
            }

            let url = parent.url
            let school = parent.school
            // WKHTTPCookieStore 注入的 cookie 有時不會被套用到「第一個」導覽請求
            // （cookie 尚未同步到網路程序）。因此同時把 cookie 放進頂層請求的
            // Cookie header，確保伺服器第一次就能取得 session。
            let cookieHeader = Self.cookieHeader(for: parent.cookies)
            group.notify(queue: .main) { [weak webView] in
                Task { [weak webView] in
                    let userAgent = await Self.fetchUserAgent(for: school)
                    await MainActor.run {
                        guard let webView else { return }
                        if let userAgent, !userAgent.isEmpty {
                            webView.customUserAgent = userAgent
                        }
                        var request = URLRequest(url: url)
                        request.httpShouldHandleCookies = true
                        if !cookieHeader.isEmpty {
                            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
                        }
                        webView.load(request)
                    }
                }
            }
        }

        /// 依 API 相同的規則組出 Cookie header：非 ASCII 值（如中文）需 percent-encode，
        /// 否則伺服器解析到非 ASCII 字元時會截斷，導致後續 session cookie 遺失。
        private static func cookieHeader(for cookies: [HTTPCookie]) -> String {
            let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: ";, "))
            return cookies.map { cookie in
                let encoded = cookie.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? cookie.value
                return "\(cookie.name)=\(encoded)"
            }.joined(separator: "; ")
        }

        private static func fetchUserAgent(for school: SchoolConfig) async -> String? {
            guard let url = URL(string: "\(AppConfig.vocPassAPIHost)/api/\(school.vision)/ua") else {
                return nil
            }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    return nil
                }
                let decoded = try JSONDecoder().decode(UserAgentResponse.self, from: data)
                guard decoded.code == 200 else { return nil }
                return decoded.data?.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return nil
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async { self.parent.isLoading = true }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async { self.parent.isLoading = false }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.parent.isLoading = false }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.parent.isLoading = false }
        }
    }
}
