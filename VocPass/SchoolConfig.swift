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
    let meritDemerit: String?   // 獎懲記錄
    let curriculum: String?     // 課表（JSON key: attendance）
    let absentation: String?    // 缺曠記錄
    let examMenu: String?       // 考試選單
    let examResults: String?    // 考試成績（含 {file_name} 變數）
    let semesterScores: String? // 學年成績（含 {year_class}、{number} 變數）

    enum CodingKeys: String, CodingKey {
        case meritDemerit  = "merit_demerit"
        case curriculum    = "attendance"
        case absentation
        case examMenu      = "exam_menu"
        case examResults   = "exam_results"
        case semesterScores = "semester_scores"
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
}

struct FieldConfig: Codable {
    let name: String
}

struct CaptchaImageConfig: Codable {
    let selector: String 
    let type: String
    
    enum CodingKeys: String, CodingKey {
        case selector, type
    }
}

struct ButtonConfig: Codable {
    let `class`: String
    
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
    private let apiURL = "https://raw.githubusercontent.com/VocPass/ios/refs/heads/main/schools.json"

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
            meritDemerit: "/online/selection_student/moralculture_%20bonuspenalty.asp",
            curriculum: "/online/student/absentation_skip_school.asp",
            absentation: "/online/selection_student/absentation_skip_school.asp",
            examMenu: "/online/selection_student/student_subjects_number.asp?action=open_window_frame",
            examResults: "/online/selection_student/{file_name}",
            semesterScores: "/online/selection_student/year_accomplishment.asp?action=selection_underside_year&year_class={year_class}&number={number}"
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
