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
    let cookies: [HTTPCookie]

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true

    var body: some View {
        ZStack {
            OriginalSystemWebView(
                url: url,
                school: school,
                cookies: cookies,
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
            for cookie in parent.cookies {
                group.enter()
                cookieStore.setCookie(cookie) { group.leave() }
            }

            let url = parent.url
            let school = parent.school
            group.notify(queue: .main) { [weak webView] in
                Task { [weak webView] in
                    let userAgent = await Self.fetchUserAgent(for: school)
                    await MainActor.run {
                        guard let webView else { return }
                        if let userAgent, !userAgent.isEmpty {
                            webView.customUserAgent = userAgent
                        }
                        webView.load(URLRequest(url: url))
                    }
                }
            }
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
