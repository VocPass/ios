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
    let api: String
    let url: URLConfig
    let login: LoginConfig
    
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
    private let apiURL = "https://raw.githubusercontent.com/HansHans135/VocPass/refs/heads/main/schools.json"
    
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
                            api: config.api,
                            url: config.url,
                            login: config.login
                        )
                    }
                    
                    self?.schools = schools
                    self?.cacheSchools(data)
                    print("✅ [SchoolConfig] 從 API 載入 \(schools.count) 所學校")
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
            
            schools = schoolsDict.map { name, config in
                SchoolConfig(
                    name: name,
                    api: config.api,
                    url: config.url,
                    login: config.login
                )
            }
            print("✅ [SchoolConfig] 從快取載入 \(schools.count) 所學校")
        } catch {
            print("❌ [SchoolConfig] 快取資料解析失敗: \(error)")
            loadDefaultSchools()
        }
    }
    
    // 預設學校配置
    private func loadDefaultSchools() {
        schools = [
            SchoolConfig(
                name: "鶯歌工商",
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
                )
            )
        ]
        print("✅ [SchoolConfig] 使用預設配置")
    }
    
    // 選擇學校
    func selectSchool(_ school: SchoolConfig) {
        selectedSchool = school
        saveSelectedSchool(school)
        print("🏫 [SchoolConfig] 已選擇學校: \(school.name)")
    }
    
    // 儲存選擇的學校
    private func saveSelectedSchool(_ school: SchoolConfig) {
        do {
            let data = try JSONEncoder().encode(school)
            UserDefaults.standard.set(data, forKey: "selected_school")
        } catch {
            print("❌ [SchoolConfig] 儲存學校失敗: \(error)")
        }
    }
    
    // 載入已選擇的學校
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
    
    // 清除選擇的學校
    func clearSelectedSchool() {
        selectedSchool = nil
        UserDefaults.standard.removeObject(forKey: "selected_school")
        print("🗑️ [SchoolConfig] 已清除選擇的學校")
    }
    
    // 檢查是否已選擇學校
    var hasSelectedSchool: Bool {
        selectedSchool != nil
    }
}

// 用於 JSON 解碼的中間結構
private struct SchoolConfigData: Codable {
    let api: String
    let url: URLConfig
    let login: LoginConfig
}
