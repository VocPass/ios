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

    private static func javaScriptStringLiteral(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
              let json = String(data: data, encoding: .utf8),
              json.count >= 2 else {
            return "''"
        }

        return String(json.dropFirst().dropLast())
    }

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
        contentController.add(context.coordinator, name: "urlTracking")

        let username = savedUsername ?? ""
        let password = savedPassword ?? ""
        let usernameFieldName = school.login.username.name
        let usernameFieldID = school.login.username.id ?? school.login.username.name
        let passwordFieldName = school.login.password.name
        let passwordFieldID = school.login.password.id ?? school.login.password.name
        let captchaFieldName = school.login.captcha.name
        let captchaFieldID = school.login.captcha.id ?? school.login.captcha.name
        let buttonClass = school.login.button.class
        let captchaImageSelector = school.login.captchaImage?.selector.isEmpty == false
            ? school.login.captchaImage?.selector ?? "captcha"
            : "captcha"
        let captchaImageType = school.login.captchaImage?.type ?? ""

        let urlTrackingScript = WKUserScript(
            source: """
            (function() {
                function trackURL(url) {
                    if (!url || typeof url !== 'string') return;
                    try {
                        var absolute = new URL(url, window.location.href).href;
                        window.webkit.messageHandlers.urlTracking.postMessage(absolute);
                    } catch(e) {
                        window.webkit.messageHandlers.urlTracking.postMessage(url);
                    }
                }

                // 攔截 fetch
                var originalFetch = window.fetch;
                window.fetch = function(input, init) {
                    var url = (typeof input === 'string') ? input : (input && input.url) ? input.url : String(input);
                    trackURL(url);
                    return originalFetch.apply(this, arguments);
                };

                // 攔截 XMLHttpRequest
                var originalOpen = XMLHttpRequest.prototype.open;
                XMLHttpRequest.prototype.open = function(method, url) {
                    trackURL(String(url));
                    return originalOpen.apply(this, arguments);
                };
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        contentController.addUserScript(urlTrackingScript)

        let script = WKUserScript(
            source: """
            (function() {
                var savedUsername = \(Self.javaScriptStringLiteral(username));
                var savedPassword = \(Self.javaScriptStringLiteral(password));
                var usernameFieldName = \(Self.javaScriptStringLiteral(usernameFieldName));
                var usernameFieldID = \(Self.javaScriptStringLiteral(usernameFieldID));
                var passwordFieldName = \(Self.javaScriptStringLiteral(passwordFieldName));
                var passwordFieldID = \(Self.javaScriptStringLiteral(passwordFieldID));
                var captchaFieldName = \(Self.javaScriptStringLiteral(captchaFieldName));
                var captchaFieldID = \(Self.javaScriptStringLiteral(captchaFieldID));
                var captchaImageSelector = \(Self.javaScriptStringLiteral(captchaImageSelector));
                var captchaImageType = \(Self.javaScriptStringLiteral(captchaImageType));
                var hasTriggeredCaptchaRecognition = false;

                function cssEscape(value) {
                    if (window.CSS && CSS.escape) return CSS.escape(value);
                    return String(value).replace(/["\\\\]/g, '\\\\$&');
                }

                function findInput(name, id) {
                    var selectors = [];
                    if (name) selectors.push('input[name="' + cssEscape(name) + '"]');
                    if (id) selectors.push('input#' + cssEscape(id), 'input[id="' + cssEscape(id) + '"]');
                    for (var i = 0; i < selectors.length; i++) {
                        var field = document.querySelector(selectors[i]);
                        if (field) return field;
                    }
                    return null;
                }

                function captchaImageCSSSelector() {
                    if (!captchaImageSelector) return '';
                    var escaped = cssEscape(captchaImageSelector);
                    if (captchaImageType === 'class') return '.' + escaped;
                    if (captchaImageType === 'id') return '#' + escaped;
                    if (captchaImageType === 'name') return '[name="' + escaped + '"]';
                    if (captchaImageSelector.charAt(0) === '.' || captchaImageSelector.charAt(0) === '#' || captchaImageSelector.charAt(0) === '[') {
                        return captchaImageSelector;
                    }
                    return '';
                }

                function findCaptchaImage() {
                    var explicitSelector = captchaImageCSSSelector();
                    if (explicitSelector) {
                        var explicit = document.querySelector(explicitSelector);
                        if (explicit) return explicit;
                    }

                    if (captchaImageSelector) {
                        var escaped = cssEscape(captchaImageSelector);
                        var guessed = document.querySelector('.' + escaped) ||
                                      document.querySelector('#' + escaped) ||
                                      document.querySelector('[name="' + escaped + '"]');
                        if (guessed) return guessed;
                    }

                    return document.querySelector('img[alt*="captcha"]') ||
                           document.querySelector('img[alt*="驗證"]') ||
                           document.querySelector('img[src*="captcha"]') ||
                           document.querySelector('img[src*="code"]');
                }

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
                    var usernameField = findInput(usernameFieldName, usernameFieldID);
                    if (usernameField && savedUsername && !usernameField.value) {
                        fillField(usernameField, savedUsername);
                    }

                    var passwordField = findInput(passwordFieldName, passwordFieldID);
                    if (passwordField && savedPassword && !passwordField.value) {
                        fillField(passwordField, savedPassword);
                    }

                    var captchaField = findInput(captchaFieldName, captchaFieldID);
                    if (captchaField && !captchaField.value && !hasTriggeredCaptchaRecognition) {
                        var captchaImage = findCaptchaImage();
                        
                        if (captchaImage) {
                            hasTriggeredCaptchaRecognition = true;
                            console.log('🔍 找到驗證碼圖片，開始自動識別...');
                            window.webkit.messageHandlers.recognizeCaptcha.postMessage({
                                selector: captchaImageSelector,
                                type: captchaImageType,
                                timestamp: Date.now()
                            });
                        }
                    }
                }
                
                window.fillCaptchaCode = function(code) {
                    var captchaField = findInput(captchaFieldName, captchaFieldID);
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
                var buttonClass = \(Self.javaScriptStringLiteral(buttonClass));
                var usernameFieldName = \(Self.javaScriptStringLiteral(usernameFieldName));
                var usernameFieldID = \(Self.javaScriptStringLiteral(usernameFieldID));
                var passwordFieldName = \(Self.javaScriptStringLiteral(passwordFieldName));
                var passwordFieldID = \(Self.javaScriptStringLiteral(passwordFieldID));
                var captchaFieldName = \(Self.javaScriptStringLiteral(captchaFieldName));
                var captchaFieldID = \(Self.javaScriptStringLiteral(captchaFieldID));

                function cssEscape(value) {
                    if (window.CSS && CSS.escape) return CSS.escape(value);
                    return String(value).replace(/["\\\\]/g, '\\\\$&');
                }

                function findInput(name, id) {
                    if (name) {
                        var byName = document.querySelector('input[name="' + cssEscape(name) + '"]');
                        if (byName) return byName;
                    }
                    if (id) {
                        return document.querySelector('input#' + cssEscape(id)) || document.querySelector('input[id="' + cssEscape(id) + '"]');
                    }
                    return null;
                }
                
                var isLoginButton = buttonClass
                    ? (target.classList.contains(buttonClass) || target.closest('.' + cssEscape(buttonClass)))
                    : (target.matches('button, input[type="submit"]') || target.closest('button, input[type="submit"]'));
                
                if (isLoginButton) {
                    var usernameField = findInput(usernameFieldName, usernameFieldID);
                    var passwordField = findInput(passwordFieldName, passwordFieldID);
                    var captchaField = findInput(captchaFieldName, captchaFieldID);
                    
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
                var buttonClass = \(Self.javaScriptStringLiteral(buttonClass));
                var usernameFieldName = \(Self.javaScriptStringLiteral(usernameFieldName));
                var usernameFieldID = \(Self.javaScriptStringLiteral(usernameFieldID));
                var passwordFieldName = \(Self.javaScriptStringLiteral(passwordFieldName));
                var passwordFieldID = \(Self.javaScriptStringLiteral(passwordFieldID));
                var captchaFieldName = \(Self.javaScriptStringLiteral(captchaFieldName));
                var captchaFieldID = \(Self.javaScriptStringLiteral(captchaFieldID));

                function cssEscape(value) {
                    if (window.CSS && CSS.escape) return CSS.escape(value);
                    return String(value).replace(/["\\\\]/g, '\\\\$&');
                }

                function findInput(root, name, id) {
                    if (name) {
                        var byName = root.querySelector('input[name="' + cssEscape(name) + '"]');
                        if (byName) return byName;
                    }
                    if (id) {
                        return root.querySelector('input#' + cssEscape(id)) || root.querySelector('input[id="' + cssEscape(id) + '"]');
                    }
                    return null;
                }
                
                var loginBtn = buttonClass ? form.querySelector('.' + cssEscape(buttonClass)) : form.querySelector('button, input[type="submit"]');
                if (!loginBtn) return;

                var usernameField = findInput(form, usernameFieldName, usernameFieldID);
                var passwordField = findInput(form, passwordFieldName, passwordFieldID);
                var captchaField = findInput(form, captchaFieldName, captchaFieldID);
                
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
            } else if message.name == "urlTracking" {
                if let url = message.body as? String {
                    recordURL(url)
                }
            } else if message.name == "recognizeCaptcha" {
                guard let webView = self.currentWebView,
                      let messageDict = message.body as? [String: Any],
                      let selector = messageDict["selector"] as? String else {
                    print("❌ [WebView] 驗證碼識別請求格式錯誤")
                    return
                }
                let selectorType = messageDict["type"] as? String
                
                print("🔍 [WebView] 收到驗證碼識別請求，選擇器: \(selector), type: \(selectorType ?? "auto")")
                
                DispatchQueue.main.async {
                    self.parent.isCaptchaRecognizing = true
                    NotificationCenter.default.post(name: .captchaRecognitionStarted, object: nil)
                }
                
                CaptchaRecognizer.shared.recognizeCaptchaFromWebView(webView, captchaSelector: selector, captchaSelectorType: selectorType) { [weak self] recognizedText in
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
                        webView.evaluateJavaScript("window.fillCaptchaCode(\(WebView.javaScriptStringLiteral(text)))") { result, error in
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

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url?.absoluteString {
                recordURL(url)
            }
            decisionHandler(.allow)
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

            recordURL(currentURL)

            injectCustomLoginScriptIfNeeded(webView: webView, currentURL: currentURL)

            startContinuousDetection(for: webView)
        }

        private func injectCustomLoginScriptIfNeeded(webView: WKWebView, currentURL: String) {
            guard !hasLoggedIn else { return }
            guard let customJs = parent.school.js, !customJs.isEmpty else {
                print("ℹ️ [WebView] 無自訂登入 JS 設定")
                return
            }

            let wrapped = """
            (function() {
                try {
                    if (sessionStorage.getItem('__vocpassCustomJsRan') === '1') {
                        return 'session_already';
                    }
                } catch (_) {}
                if (window.__vocpassCustomJsRan) { return 'window_already'; }
                var __vp_tries = 0;
                var __vp_maxTries = 60;
                function __vp_markDone() {
                    window.__vocpassCustomJsRan = true;
                    try { sessionStorage.setItem('__vocpassCustomJsRan', '1'); } catch (_) {}
                }
                function __vp_run() {
                    try {
                        (function() {
                            \(customJs)
                        })();
                        __vp_markDone();
                        return 'ok';
                    } catch (err) {
                        __vp_tries++;
                        if (__vp_tries < __vp_maxTries) {
                            setTimeout(__vp_run, 250);
                            return 'retry:' + err.message;
                        }
                        return 'giveup:' + err.message;
                    }
                }
                return __vp_run();
            })();
            """

            print("💉 [WebView] 注入自訂登入頁 JS (url=\(currentURL))")
            webView.evaluateJavaScript(wrapped) { result, error in
                if let error = error {
                    print("❌ [WebView] 自訂 JS 執行失敗: \(error)")
                } else {
                    print("✅ [WebView] 自訂 JS 結果: \(result ?? "nil")")
                }
            }
        }

        private var isCheckingLoginState = false
        private var lastCheckedContentHash: Int?
        private var visitedURLs: [String] = []

        private func recordURL(_ url: String) {
            guard !url.isEmpty, !visitedURLs.contains(url) else { return }
            visitedURLs.append(url)
            print("📌 [WebView] 記錄 URL（共 \(visitedURLs.count) 筆）: \(url)")
        }

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
                var mainHtml = (document.documentElement && document.documentElement.outerHTML) ? document.documentElement.outerHTML : '';
                var mainText = (document.body && document.body.innerText) ? document.body.innerText : '';
                var iframeHtml = '';
                var iframeText = '';
                try {
                    var frames = document.querySelectorAll('iframe, frame');
                    for (var i = 0; i < frames.length; i++) {
                        try {
                            var frameDoc = frames[i].contentDocument || frames[i].contentWindow.document;
                            if (frameDoc) {
                                iframeHtml += frameDoc.documentElement ? frameDoc.documentElement.outerHTML : '';
                                iframeText += frameDoc.body ? frameDoc.body.innerText : '';
                            }
                        } catch(e) {}
                    }
                } catch(e) {}
                return {
                    readyState: document.readyState || '',
                    html: mainHtml + iframeHtml,
                    text: mainText + iframeText
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

                if error != nil {
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
                self.logHTML(html, currentURL: currentURL)

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

                        for urlString in self.visitedURLs {
                            guard let url = URL(string: urlString),
                                  let host = url.host,
                                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                                  let queryItems = components.queryItems else { continue }

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

                        // Extract userInfo div content and add as cookie
                        let userInfoPattern = #"<div[^>]*id="userInfo"[^>]*>([^<]*)</div>"#
                        if let regex = try? NSRegularExpression(pattern: userInfoPattern),
                           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                           match.numberOfRanges > 1,
                           let range = Range(match.range(at: 1), in: html) {
                            let userInfoValue = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                            if !userInfoValue.isEmpty,
                               let host = URL(string: currentURL)?.host {
                                if let userInfoCookie = HTTPCookie(properties: [
                                    .domain: host,
                                    .path: "/",
                                    .name: "userInfo",
                                    .value: userInfoValue,
                                    .secure: "TRUE",
                                    .expires: Date().addingTimeInterval(3600 * 24 * 30)
                                ]) {
                                    if !finalCookies.contains(where: { $0.name == "userInfo" }) {
                                        finalCookies.append(userInfoCookie)
                                        webView.configuration.websiteDataStore.httpCookieStore.setCookie(userInfoCookie)
                                        print("✅ [WebView] 已從 userInfo div 提取並加入 cookie: \(userInfoValue.prefix(30))...")
                                    }
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
