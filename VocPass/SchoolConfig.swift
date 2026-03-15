//
//  SchoolConfig.swift
//  BSH
//
//  Created by Hans on 2026/1/11.
//

import Foundation
import Combine

// MARK: - 學校配置模型
struct SchoolConfig: Codable, Identifiable {
    var id: String { name }
    let name: String
    let vision: String
    let app: String?
    let api: String
    let url: URLConfig
    let login: LoginConfig
    let route: RouteConfig

    var loginURL: URL? {
        URL(string: api + url.login)
    }

    var loginedURL: String {
        api + url.logined
    }

    var rootURL: String {
        api + url.root
    }
}

// MARK: - 路由配置
struct RouteConfig: Codable {
    let examResults: String?

    enum CodingKeys: String, CodingKey {
        case examResults   = "exam_results"
    }
}

struct URLConfig: Codable {
    let login: String
    let logined: String
    let root: String
}

struct LoginConfig: Codable {
    let username: FieldConfig
    let password: FieldConfig
    let captcha: FieldConfig
    let captchaImage: CaptchaImageConfig?
    let button: ButtonConfig
    let successKeywords: [String]?

    init(username: FieldConfig,
         password: FieldConfig,
         captcha: FieldConfig,
         captchaImage: CaptchaImageConfig?,
         button: ButtonConfig,
         successKeywords: [String]? = nil) {
        self.username = username
        self.password = password
        self.captcha = captcha
        self.captchaImage = captchaImage
        self.button = button
        self.successKeywords = successKeywords?.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let aliasContainer = try decoder.container(keyedBy: AnyCodingKey.self)
        username = try container.decode(FieldConfig.self, forKey: .username)
        password = try container.decode(FieldConfig.self, forKey: .password)
        captcha = try container.decodeIfPresent(FieldConfig.self, forKey: .captcha) ?? FieldConfig(name: "")
        captchaImage = try? container.decode(CaptchaImageConfig.self, forKey: .captchaImage)
        button = try container.decodeIfPresent(ButtonConfig.self, forKey: .button) ?? ButtonConfig(class: "")

        func decodeStringArray(_ key: String) -> [String]? {
            guard let codingKey = AnyCodingKey(key) else { return nil }
            return try? aliasContainer.decode([String].self, forKey: codingKey)
        }

        func decodeString(_ key: String) -> String? {
            guard let codingKey = AnyCodingKey(key) else { return nil }
            return try? aliasContainer.decode(String.self, forKey: codingKey)
        }

        let keywordArray =
            (try? container.decode([String].self, forKey: .successKeywords)) ??
            decodeStringArray("success_keywords") ??
            decodeStringArray("loginSuccessKeywords") ??
            decodeStringArray("login_success_keywords")

        let keywordString =
            (try? container.decode(String.self, forKey: .successKeywords)) ??
            decodeString("success_keywords") ??
            decodeString("loginSuccessKeywords") ??
            decodeString("login_success_keywords")

        let parsedFromString = keywordString?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let parsed = (keywordArray ?? parsedFromString ?? []).filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        successKeywords = parsed.isEmpty ? nil : parsed
    }

    enum CodingKeys: String, CodingKey {
        case username, password, captcha, captchaImage, button
        case successKeywords
    }

    private struct AnyCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(_ string: String) {
            self.stringValue = string
            self.intValue = nil
        }

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            return nil
        }
    }
}

struct FieldConfig: Codable {
    let name: String

    init(name: String) {
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case name
    }
}

struct CaptchaImageConfig: Codable {
    let selector: String 
    let type: String

    init(selector: String, type: String) {
        self.selector = selector
        self.type = type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let selector = try container.decodeIfPresent(String.self, forKey: .selector) ?? ""
        let type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""

        if selector.isEmpty, type.isEmpty {
            throw DecodingError.valueNotFound(
                String.self,
                DecodingError.Context(codingPath: decoder.codingPath,
                                      debugDescription: "Empty captchaImage config")
            )
        }

        self.selector = selector
        self.type = type
    }
    
    enum CodingKeys: String, CodingKey {
        case selector, type
    }
}

struct ButtonConfig: Codable {
    let `class`: String

    init(class: String) {
        self.class = `class`
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.class = try container.decodeIfPresent(String.self, forKey: .class) ?? ""
    }
    
    enum CodingKeys: String, CodingKey {
        case `class` = "class"
    }
}

// MARK: - 學校配置管理器
class SchoolConfigManager: ObservableObject {
    static let shared = SchoolConfigManager()
    
    @Published var schools: [SchoolConfig] = []
    @Published var selectedSchool: SchoolConfig?
    @Published var isLoading = false
    @Published var error: String?
    
    // 遠端 API URL
    private let apiURL: String = AppConfig.vocPassAPIHost + "/school"

    private var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
    
    private init() {
        loadSelectedSchool()
    }
    
    // 從遠端 API 載入學校配置
    func loadSchools() {
        guard let url = URL(string: apiURL) else {
            print("❌ [SchoolConfig] 無效的 API URL")
            loadDefaultSchools()
            return
        }
        
        isLoading = true
        error = nil
        
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    print("❌ [SchoolConfig] 網路錯誤: \(error.localizedDescription)")
                    self?.error = "無法連線至伺服器"
                    self?.loadCachedSchools()
                    return
                }
                
                guard let data = data else {
                    print("❌ [SchoolConfig] 無資料")
                    self?.error = "無法取得學校資料"
                    self?.loadCachedSchools()
                    return
                }
                
                do {
                    let decoder = JSONDecoder()
                    let schoolsDict = try decoder.decode([String: SchoolConfigData].self, from: data)
                    
                    let schools = schoolsDict.map { name, config in
                        SchoolConfig(
                            name: name,
                            vision: config.vision,
                            app: config.app,
                            api: config.api,
                            url: config.url,
                            login: config.login,
                            route: config.route
                        )
                    }

                    let filteredSchools = schools.filter { school in
                        self?.isSchoolVersionSupported(requiredVersion: school.app) ?? true
                    }

                    self?.schools = filteredSchools
                    self?.cacheSchools(data)
                    if let currentName = self?.selectedSchool?.name,
                       let updated = filteredSchools.first(where: { $0.name == currentName }) {
                        self?.selectedSchool = updated
                        self?.saveSelectedSchool(updated)
                    }
                    print("✅ [SchoolConfig] 從 API 載入 \(filteredSchools.count) 所學校（App \(self?.currentAppVersion ?? "0")）")
                } catch {
                    print("❌ [SchoolConfig] 解析 JSON 失敗: \(error)")
                    self?.error = "資料格式錯誤"
                    self?.loadCachedSchools()
                }
            }
        }
        task.resume()
    }
    
    // 快取學校資料
    private func cacheSchools(_ data: Data) {
        UserDefaults.standard.set(data, forKey: "cached_schools")
        UserDefaults.standard.set(Date(), forKey: "cached_schools_timestamp")
        print("📦 [SchoolConfig] 已快取學校資料")
    }
    
    // 載入快取的學校資料
    private func loadCachedSchools() {
        guard let data = UserDefaults.standard.data(forKey: "cached_schools") else {
            print("📦 [SchoolConfig] 無快取資料，使用預設配置")
            loadDefaultSchools()
            return
        }
        
        do {
            let decoder = JSONDecoder()
            let schoolsDict = try decoder.decode([String: SchoolConfigData].self, from: data)
            
            let mappedSchools = schoolsDict.map { name, config in
                SchoolConfig(
                    name: name,
                    vision: config.vision,
                    app: config.app,
                    api: config.api,
                    url: config.url,
                    login: config.login,
                    route: config.route
                )
            }
            schools = mappedSchools.filter { school in
                isSchoolVersionSupported(requiredVersion: school.app)
            }
            print("✅ [SchoolConfig] 從快取載入 \(schools.count) 所學校（App \(currentAppVersion)）")
        } catch {
            print("❌ [SchoolConfig] 快取資料解析失敗: \(error)")
            loadDefaultSchools()
        }
    }
    
    // 預設學校配置
    private func loadDefaultSchools() {
        let defaultRoute = RouteConfig(
            examResults: "/online/selection_student/{file_name}"
        )
        schools = [
            SchoolConfig(
                name: "鶯歌工商",
                vision: "v1",
                app: nil,
                api: "https://eschool.ykvs.ntpc.edu.tw",
                url: URLConfig(
                    login: "/auth/Online",
                    logined: "/online/student/frames.asp",
                    root: "/"
                ),
                login: LoginConfig(
                    username: FieldConfig(name: "LoginName"),
                    password: FieldConfig(name: "PassString"),
                    captcha: FieldConfig(name: "ShCaptchaGenCode"),
                    captchaImage: CaptchaImageConfig(selector: "captcha-image", type: "class"),
                    button: ButtonConfig(class: "loginBtnAdjust")
                ),
                route: defaultRoute
            )
        ]
        print("✅ [SchoolConfig] 使用預設配置")
    }
    
    func selectSchool(_ school: SchoolConfig) {
        selectedSchool = school
        saveSelectedSchool(school)
        print("🏫 [SchoolConfig] 已選擇學校: \(school.name)")
    }
    
    private func saveSelectedSchool(_ school: SchoolConfig) {
        do {
            let data = try JSONEncoder().encode(school)
            UserDefaults.standard.set(data, forKey: "selected_school")
        } catch {
            print("❌ [SchoolConfig] 儲存學校失敗: \(error)")
        }
    }
    
    func loadSelectedSchool() {
        guard let data = UserDefaults.standard.data(forKey: "selected_school") else {
            return
        }
        
        do {
            selectedSchool = try JSONDecoder().decode(SchoolConfig.self, from: data)
            print("✅ [SchoolConfig] 載入已選擇學校: \(selectedSchool?.name ?? "無")")
        } catch {
            print("❌ [SchoolConfig] 載入學校失敗: \(error)")
        }
    }
    
    func clearSelectedSchool() {
        selectedSchool = nil
        UserDefaults.standard.removeObject(forKey: "selected_school")
        print("🗑️ [SchoolConfig] 已清除選擇的學校")
    }
    
    var hasSelectedSchool: Bool {
        selectedSchool != nil
    }

    private func isSchoolVersionSupported(requiredVersion: String?) -> Bool {
        guard let requiredVersion, !requiredVersion.isEmpty else {
            return true
        }

        return compareVersion(currentAppVersion, requiredVersion) >= 0
    }

    private func compareVersion(_ lhs: String, _ rhs: String) -> Int {
        let leftParts = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let rightParts = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let maxCount = max(leftParts.count, rightParts.count)

        for i in 0..<maxCount {
            let left = i < leftParts.count ? leftParts[i] : 0
            let right = i < rightParts.count ? rightParts[i] : 0

            if left < right { return -1 }
            if left > right { return 1 }
        }

        return 0
    }
}

private struct SchoolConfigData: Codable {
    let vision: String
    let app: String?
    let api: String
    let url: URLConfig
    let login: LoginConfig
    let route: RouteConfig

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        vision = try container.decode(String.self, forKey: .vision)
        api = try container.decode(String.self, forKey: .api)
        url = try container.decode(URLConfig.self, forKey: .url)
        login = try container.decode(LoginConfig.self, forKey: .login)
        route = try container.decode(RouteConfig.self, forKey: .route)

        if let appString = try? container.decode(String.self, forKey: .app) {
            app = appString
        } else if let appDouble = try? container.decode(Double.self, forKey: .app) {
            app = String(appDouble)
        } else if let appInt = try? container.decode(Int.self, forKey: .app) {
            app = String(appInt)
        } else {
            app = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case vision
        case app
        case api
        case url
        case login
        case route
    }
}
