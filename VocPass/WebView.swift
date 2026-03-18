//
//  WebView.swift
//  YKVS
//
//  Created by Hans on 2025/12/31.
//

import SwiftUI
import WebKit
import Vision

struct WebView: UIViewRepresentable {
    let url: URL
    let school: SchoolConfig
    @Binding var cookies: [HTTPCookie]
    @Binding var isLoggedIn: Bool
    @Binding var isLoggingIn: Bool
    
    @State private var isCaptchaRecognizing = false
    @State private var lastRecognizedCaptcha: String?

    private var savedUsername: String? { CacheService.shared.savedUsername }
    private var savedPassword: String? { CacheService.shared.savedPassword }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let contentController = configuration.userContentController
        contentController.add(context.coordinator, name: "formSubmit")
        contentController.add(context.coordinator, name: "saveCredentials")
        contentController.add(context.coordinator, name: "recognizeCaptcha")

        let username = savedUsername ?? ""
        let password = savedPassword ?? ""
        let usernameFieldName = school.login.username.name
        let passwordFieldName = school.login.password.name
        let captchaFieldName = school.login.captcha.name
        let buttonClass = school.login.button.class
        let captchaImageSelector = school.login.captchaImage?.selector.isEmpty == false
            ? school.login.captchaImage?.selector ?? "captcha"
            : "captcha"

        let script = WKUserScript(
            source: """
            (function() {
                var savedUsername = '\(username)';
                var savedPassword = '\(password)';
                var usernameFieldName = '\(usernameFieldName)';
                var passwordFieldName = '\(passwordFieldName)';
                var captchaFieldName = '\(captchaFieldName)';
                var captchaImageSelector = '\(captchaImageSelector)';
                var hasTriggeredCaptchaRecognition = false;

                function getNativeValueSetter(element) {
                    var prototype = Object.getPrototypeOf(element);
                    var descriptor = prototype ? Object.getOwnPropertyDescriptor(prototype, 'value') : null;
                    return descriptor && descriptor.set ? descriptor.set : null;
                }

                function dispatchFieldEvents(field, previousValue) {
                    field.dispatchEvent(new Event('input', { bubbles: true }));
                    if (previousValue !== field.value) {
                        field.dispatchEvent(new Event('change', { bubbles: true }));
                    }
                    field.dispatchEvent(new Event('blur', { bubbles: true }));
                }

                function fillField(field, newValue) {
                    if (!field || !newValue) return false;

                    var oldValue = field.value || '';
                    field.focus();

                    var setter = getNativeValueSetter(field);
                    if (setter) {
                        // Some pages only detect required fields after value transitions.
                        setter.call(field, '');
                        field.dispatchEvent(new Event('input', { bubbles: true }));
                        setter.call(field, newValue);
                    } else {
                        field.value = '';
                        field.dispatchEvent(new Event('input', { bubbles: true }));
                        field.value = newValue;
                    }

                    dispatchFieldEvents(field, oldValue);
                    return true;
                }

                function fillCredentials() {
                    var usernameField = document.querySelector('input[name="' + usernameFieldName + '"]') || document.querySelector('input[id="' + usernameFieldName + '"]');
                    if (usernameField && savedUsername && !usernameField.value) {
                        fillField(usernameField, savedUsername);
                    }

                    var passwordField = document.querySelector('input[name="' + passwordFieldName + '"]') || document.querySelector('input[id="' + passwordFieldName + '"]');
                    if (passwordField && savedPassword && !passwordField.value) {
                        fillField(passwordField, savedPassword);
                    }

                    var captchaField = captchaFieldName
                        ? (document.querySelector('input[name="' + captchaFieldName + '"]') || document.querySelector('input[id="' + captchaFieldName + '"]'))
                        : null;
                    if (captchaField && !captchaField.value && !hasTriggeredCaptchaRecognition) {
                        var captchaImage = document.querySelector('.' + captchaImageSelector) ||
                                          document.querySelector('#' + captchaImageSelector) ||
                                          document.querySelector('[name="' + captchaImageSelector + '"]') ||
                                          document.querySelector('img[alt*="captcha"]') ||
                                          document.querySelector('img[alt*="驗證"]') ||
                                          document.querySelector('img[src*="captcha"]') ||
                                          document.querySelector('img[src*="code"]');
                        
                        if (captchaImage) {
                            hasTriggeredCaptchaRecognition = true;
                            console.log('🔍 找到驗證碼圖片，開始自動識別...');
                            window.webkit.messageHandlers.recognizeCaptcha.postMessage({
                                selector: captchaImageSelector,
                                timestamp: Date.now()
                            });
                        }
                    }
                }
                
                window.fillCaptchaCode = function(code) {
                    var captchaField = captchaFieldName
                        ? (document.querySelector('input[name="' + captchaFieldName + '"]') || document.querySelector('input[id="' + captchaFieldName + '"]'))
                        : null;
                    if (captchaField) {
                        fillField(captchaField, code);
                        console.log('✅ 已自動填寫驗證碼: ' + code);
                        return true;
                    }
                    return false;
                };

                if (document.readyState === 'complete') {
                    fillCredentials();
                } else {
                    window.addEventListener('load', fillCredentials);
                }
                setTimeout(fillCredentials, 500);
                setTimeout(fillCredentials, 1000);
                setTimeout(fillCredentials, 2000);
            })();

            document.addEventListener('click', function(e) {
                var target = e.target;
                var buttonClass = '\(buttonClass)';
                var usernameFieldName = '\(usernameFieldName)';
                var passwordFieldName = '\(passwordFieldName)';
                var captchaFieldName = '\(captchaFieldName)';
                
                var isLoginButton = buttonClass
                    ? (target.classList.contains(buttonClass) || target.closest('.' + buttonClass))
                    : (target.matches('button, input[type="submit"]') || target.closest('button, input[type="submit"]'));
                
                if (isLoginButton) {
                    var usernameField = document.querySelector('input[name="' + usernameFieldName + '"]') || document.querySelector('input[id="' + usernameFieldName + '"]');
                    var passwordField = document.querySelector('input[name="' + passwordFieldName + '"]') || document.querySelector('input[id="' + passwordFieldName + '"]');
                    var captchaField = captchaFieldName
                        ? (document.querySelector('input[name="' + captchaFieldName + '"]') || document.querySelector('input[id="' + captchaFieldName + '"]'))
                        : null;
                    
                    var username = usernameField ? usernameField.value : '';
                    var password = passwordField ? passwordField.value : '';
                    var captcha = captchaField ? captchaField.value : '';

                    if (captchaField && (!captcha || captcha.trim() === '')) {
                        return;
                    }

                    if (username || password) {
                        window.webkit.messageHandlers.saveCredentials.postMessage({
                            username: username,
                            password: password
                        });
                    }

                    window.webkit.messageHandlers.formSubmit.postMessage('login_clicked');
                }
            }, true);

            document.addEventListener('submit', function(e) {
                var form = e.target;
                var buttonClass = '\(buttonClass)';
                var usernameFieldName = '\(usernameFieldName)';
                var passwordFieldName = '\(passwordFieldName)';
                var captchaFieldName = '\(captchaFieldName)';
                
                var loginBtn = form.querySelector('.' + buttonClass);
                if (!loginBtn) return;

                var usernameField = form.querySelector('input[name="' + usernameFieldName + '"]') || form.querySelector('input[id="' + usernameFieldName + '"]');
                var passwordField = form.querySelector('input[name="' + passwordFieldName + '"]') || form.querySelector('input[id="' + passwordFieldName + '"]');
                var captchaField = form.querySelector('input[name="' + captchaFieldName + '"]') || form.querySelector('input[id="' + captchaFieldName + '"]');
                
                var username = usernameField ? usernameField.value : '';
                var password = passwordField ? passwordField.value : '';
                var captcha = captchaField ? captchaField.value : '';

                if (!captcha || captcha.trim() === '') {
                    return;
                }

                if (username || password) {
                    window.webkit.messageHandlers.saveCredentials.postMessage({
                        username: username,
                        password: password
                    });
                }

                window.webkit.messageHandlers.formSubmit.postMessage('form_submitted');
            }, true);
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        contentController.addUserScript(script)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.currentWebView = webView
        webView.load(URLRequest(url: url))

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: WebView
        private var hasLoggedIn = false
        var currentWebView: WKWebView?

        private let defaultLoginSuccessKeywords = [
            "登出", "logout"
        ]

        private var loginSuccessKeywords: [String] {
            let fromAPI = parent.school.login.successKeywords?.filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            } ?? []
            return fromAPI.isEmpty ? defaultLoginSuccessKeywords : fromAPI
        }

        init(_ parent: WebView) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "formSubmit" {
                print("📝 [WebView] 偵測到表單提交/按鈕點擊")
                DispatchQueue.main.async {
                    self.parent.isLoggingIn = true
                }
            } else if message.name == "saveCredentials" {
                if let credentials = message.body as? [String: String] {
                    let username = credentials["username"] ?? ""
                    let password = credentials["password"] ?? ""

                    if !username.isEmpty || !password.isEmpty {
                        print("🔑 [WebView] 儲存登入憑證 - 帳號: \(username.prefix(3))***")
                        CacheService.shared.saveLoginCredentials(
                            username: username,
                            password: password,
                            schoolCode: nil
                        )
                    }
                }
            } else if message.name == "recognizeCaptcha" {
                guard let webView = self.currentWebView,
                      let messageDict = message.body as? [String: Any],
                      let selector = messageDict["selector"] as? String else {
                    print("❌ [WebView] 驗證碼識別請求格式錯誤")
                    return
                }
                
                print("🔍 [WebView] 收到驗證碼識別請求，選擇器: \(selector)")
                
                DispatchQueue.main.async {
                    self.parent.isCaptchaRecognizing = true
                    NotificationCenter.default.post(name: .captchaRecognitionStarted, object: nil)
                }
                
                CaptchaRecognizer.shared.recognizeCaptchaFromWebView(webView, captchaSelector: selector) { [weak self] recognizedText in
                    DispatchQueue.main.async {
                        self?.parent.isCaptchaRecognizing = false
                        
                        guard let text = recognizedText, !text.isEmpty else {
                            print("❌ [WebView] 驗證碼識別失敗或結果為空")
                            NotificationCenter.default.post(name: .captchaRecognitionCompleted, object: nil)
                            return
                        }
                        
                        print("✅ [WebView] 驗證碼識別成功: \(text)")
                        self?.parent.lastRecognizedCaptcha = text
                        NotificationCenter.default.post(name: .captchaRecognitionCompleted, object: text)
                        
                        // 自動填寫識別到的驗證碼
                        webView.evaluateJavaScript("window.fillCaptchaCode('\(text)')") { result, error in
                            if let error = error {
                                print("❌ [WebView] 填寫驗證碼失敗: \(error)")
                            } else if let success = result as? Bool, success {
                                print("✅ [WebView] 驗證碼自動填寫成功")
                            }
                        }
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            guard let currentURL = webView.url?.absoluteString.lowercased() else { return }
            print("🔄 [WebView] 開始載入: \(currentURL)")

            let loginPath = parent.school.url.login.lowercased()
            if !currentURL.contains(loginPath) && !hasLoggedIn {
                DispatchQueue.main.async {
                    self.parent.isLoggingIn = true
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let currentURL = webView.url?.absoluteString else { return }
            print("🌐 [WebView] 載入完成: \(currentURL)")

            startContinuousDetection(for: webView)
        }

        private var isCheckingLoginState = false
        private var lastCheckedContentHash: Int?

        private func startContinuousDetection(for webView: WKWebView) {
            guard !isCheckingLoginState else { return }
            isCheckingLoginState = true
            inspectLoginStatePeriodic(webView: webView)
        }

        private func inspectLoginStatePeriodic(webView: WKWebView) {
            if hasLoggedIn {
                isCheckingLoginState = false
                return
            }

            let currentURL = webView.url?.absoluteString ?? ""

            let pageStateScript = """
            (function() {
                return {
                    readyState: document.readyState || '',
                    html: (document.documentElement && document.documentElement.outerHTML) ? document.documentElement.outerHTML : '',
                    text: (document.body && document.body.innerText) ? document.body.innerText : ''
                };
            })();
            """

            webView.evaluateJavaScript(pageStateScript) { [weak self] result, error in
                guard let self = self else { return }

                defer {
                    if !self.hasLoggedIn {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                            self?.inspectLoginStatePeriodic(webView: webView)
                        }
                    } else {
                        self.isCheckingLoginState = false
                    }
                }

                if let error = error {
                    return
                }

                guard let payload = result as? [String: Any] else { return }

                let readyState = (payload["readyState"] as? String ?? "").lowercased()
                let html = payload["html"] as? String ?? ""
                let text = payload["text"] as? String ?? ""

                let contentHash = html.hashValue ^ text.hashValue
                if self.lastCheckedContentHash == contentHash {
                    return
                }
                self.lastCheckedContentHash = contentHash

                if readyState != "complete" && readyState != "interactive" {
                    return
                }

                print("🧾 [WebView] 開始登入關鍵字偵測（readyState=\(readyState)）")

                let searchableText = "\(text)\n\(html)".lowercased()
                let matchedKeyword = self.loginSuccessKeywords.first {
                    searchableText.contains($0.lowercased())
                }

                if let matchedKeyword = matchedKeyword {
                    print("✅ [WebView] 偵測到登入成功關鍵字: \(matchedKeyword)，等待 cookies 載入...")

                    self.hasLoggedIn = true

                    webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                        guard let self = self else { return }
                        var finalCookies = cookies

                        if let url = URL(string: currentURL),
                           let host = url.host,
                           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                           let queryItems = components.queryItems {

                            for item in queryItems {
                                if let newCookie = HTTPCookie(properties: [
                                    .domain: host,
                                    .path: "/",
                                    .name: item.name,
                                    .value: item.value ?? "",
                                    .secure: "TRUE",
                                    .expires: Date().addingTimeInterval(3600 * 24 * 30)
                                ]) {
                                    if !finalCookies.contains(where: { $0.name == newCookie.name }) {
                                        finalCookies.append(newCookie)
                                    }
                                    webView.configuration.websiteDataStore.httpCookieStore.setCookie(newCookie)
                                }
                            }
                        }

                        print("🍪 [WebView] 登入成功頁面 cookies 數量: \(finalCookies.count)")
                        for cookie in finalCookies {
                            print("  - \(cookie.name): \(cookie.value.prefix(30))...")
                        }

                        DispatchQueue.main.async {
                            self.parent.cookies = finalCookies
                            self.parent.isLoggingIn = false
                            self.parent.isLoggedIn = true
                            print("🔐 [WebView] 登入狀態已設定為 true")
                        }
                    }
                } else {
                    webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                        DispatchQueue.main.async {
                            self.parent.cookies = cookies
                            let loginPath = self.parent.school.url.login.lowercased()
                            if currentURL.lowercased().contains(loginPath) {
                                self.parent.isLoggingIn = false
                            }
                        }
                    }
                }
            }
        }

        private func logHTML(_ html: String, currentURL: String) {
            print("🧾 [WebView][HTML] ===== BEGIN URL: \(currentURL) =====")
            print("🧾 [WebView][HTML] 長度: \(html.count) chars")

            if html.isEmpty {
                print("🧾 [WebView][HTML] (empty)")
            } else {
                let chunkSize = 4000
                var startIndex = html.startIndex
                var chunkNumber = 1

                while startIndex < html.endIndex {
                    let endIndex = html.index(startIndex, offsetBy: chunkSize, limitedBy: html.endIndex) ?? html.endIndex
                    let chunk = String(html[startIndex..<endIndex])
                    print("🧾 [WebView][HTML][\(chunkNumber)] \(chunk)")
                    startIndex = endIndex
                    chunkNumber += 1
                }
            }

            print("🧾 [WebView][HTML] ===== END URL: \(currentURL) =====")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("❌ [WebView] 載入失敗: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.parent.isLoggingIn = false
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("❌ [WebView] 載入過程失敗: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.parent.isLoggingIn = false
            }
        }
    }
}
