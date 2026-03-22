//
//  APIService.swift
//  YKVS
//
//  Created by Hans on 2025/12/31.
//

import Foundation
import Combine
import WebKit

class APIService: ObservableObject {
    static let shared = APIService()

    private var weeksPerSemester: Int { CacheService.shared.weeksPerSemester }

    @Published var cookies: [HTTPCookie] = []
    @Published var isLoggedIn = false

    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        return URLSession(configuration: config)
    }()

    private struct APIErrorPayload: Decodable {
        let errorID: String?
        let message: String?

        enum CodingKeys: String, CodingKey {
            case errorID = "error_id"
            case errorId
            case message
            case detail
            case error
        }

        private static func decodeAnyString(from container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> String? {
            if let value = try? container.decode(String.self, forKey: key) {
                return value
            }
            if let value = try? container.decode(Int.self, forKey: key) {
                return String(value)
            }
            if let value = try? container.decode(Double.self, forKey: key) {
                return String(value)
            }
            if let value = try? container.decode(Bool.self, forKey: key) {
                return value ? "true" : "false"
            }
            return nil
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            errorID = Self.decodeAnyString(from: container, key: .errorID)
                ?? Self.decodeAnyString(from: container, key: .errorId)

            message = Self.decodeAnyString(from: container, key: .message)
                ?? Self.decodeAnyString(from: container, key: .detail)
                ?? Self.decodeAnyString(from: container, key: .error)
        }
    }

    private var cookieString: String {
        // Cookie header 只能是 ASCII；非 ASCII 值（如中文）需 percent-encode，
        // 否則伺服器解析到非 ASCII 字元時會截斷，導致後續 session cookies 遺失。
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: ";, "))
        return cookies.map { cookie in
            let encodedValue = cookie.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? cookie.value
            return "\(cookie.name)=\(encodedValue)"
        }.joined(separator: "; ")
    }

    private var headers: [String: String] {
        [
            "accept-encoding": "gzip, deflate, br",
            "accept-language": "zh-TW,zh;q=0.9,en;q=0.8",
            "cache-control": "no-cache",
            "cookie": cookieString,
            "user-agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
        ]
    }

    private func extractAPIErrorPayload(from data: Data) -> APIErrorPayload? {
        return try? JSONDecoder().decode(APIErrorPayload.self, from: data)
    }

    // MARK: - 取得目前選擇的學校（或拋出錯誤）
    private func selectedSchool() throws -> SchoolConfig {
        guard let school = SchoolConfigManager.shared.selectedSchool else {
            throw APIError.noSchoolSelected
        }
        return school
    }

    // MARK: - 以代理 API GET（cookies 直接放 Header）
    private func proxyGetData(path: String,
                              extraQueryItems: [URLQueryItem] = []) async throws -> Data {
        let school = try selectedSchool()

        guard !cookieString.isEmpty else {
            throw APIError.sessionExpired
        }

        guard var components = URLComponents(string: "\(AppConfig.vocPassAPIHost)/api/\(school.vision)/\(path)") else {
            throw URLError(.badURL)
        }

        var items = [URLQueryItem(name: "school_name", value: school.name)]
        items.append(contentsOf: extraQueryItems)
        components.queryItems = items

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(cookieString, forHTTPHeaderField: "Cookie")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await urlSession.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard httpResponse.statusCode == 200 else {
            if let detail = String(data: data, encoding: .utf8) {
                print("❌ [API] Proxy API error (\(httpResponse.statusCode)): \(detail)")
            } else {
                print("❌ [API] Proxy API error (\(httpResponse.statusCode))")
            }
            if httpResponse.statusCode == 404 {
                throw APIError.featureNotSupported
            }

            let payload = extractAPIErrorPayload(from: data)

            if let message = payload?.message?.trimmingCharacters(in: .whitespacesAndNewlines),
               !message.isEmpty {
                if let errorID = payload?.errorID?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !errorID.isEmpty {
                    throw APIError.serverMessage("\(message)（錯誤id: \(errorID)）")
                }
                throw APIError.serverMessage(message)
            }

            if let errorID = payload?.errorID?.trimmingCharacters(in: .whitespacesAndNewlines),
               !errorID.isEmpty {
                throw APIError.serverErrorID(errorID)
            }

            throw APIError.httpStatus(httpResponse.statusCode)
        }

        return data
    }

    private struct APIStatusResponse: Decodable {
        let code: Int?
        let message: String?
        let errorID: String?
        enum CodingKeys: String, CodingKey {
            case code, message
            case errorID = "error_id"
            case errorId
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code    = (try? c.decode(Int.self,    forKey: .code))
                   ?? { if let s = try? c.decode(String.self, forKey: .code) { return Int(s) }; return nil }()
            message = try? c.decode(String.self, forKey: .message)
            errorID = (try? c.decode(String.self, forKey: .errorID))
                ?? (try? c.decode(String.self, forKey: .errorId))
        }
    }

    private func proxyGet<T: Decodable>(path: String,
                                        extraQueryItems: [URLQueryItem] = []) async throws -> APIResponse<T> {
        let data = try await proxyGetData(path: path, extraQueryItems: extraQueryItems)


        if let raw = String(data: data, encoding: .utf8) {
            print("📦 [API] Raw JSON [\(path)] (\(data.count) bytes):")
            print(raw)
        }

        if let status = try? JSONDecoder().decode(APIStatusResponse.self, from: data) {
            let code = status.code ?? 200
            let msg  = status.message ?? ""
            print("ℹ️ [API] Status [\(path)]: code=\(code) message=\(msg)")
            if code == 404 || msg.lowercased().contains("not implemented") {
                throw APIError.featureNotSupported
            }
            if code == 401 || code == 403 {
                throw APIError.sessionExpired
            }
            if code != 200 {
                let trimmedMessage = msg.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedErrorID = status.errorID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !trimmedMessage.isEmpty {
                    if !trimmedErrorID.isEmpty {
                        throw APIError.serverMessage("\(trimmedMessage)（error_id: \(trimmedErrorID)）")
                    }
                    throw APIError.serverMessage(trimmedMessage)
                }
                if !trimmedErrorID.isEmpty {
                    throw APIError.serverErrorID(trimmedErrorID)
                }
                throw APIError.httpStatus(code)
            }
        }

        do {
            let result = try JSONDecoder().decode(APIResponse<T>.self, from: data)
            print("✅ [API] Decoded [\(path)] → code=\(result.code) message=\(result.message)")
            return result
        } catch {
            print("❌ [API] Decode failed [\(path)]: \(error)")
            throw error
        }
    }

    // MARK: - 向學校伺服器 GET HTML
    private func request(url: String) async throws -> String {
        guard SchoolConfigManager.shared.hasSelectedSchool else {
            print("❌ [API] 未選擇學校")
            throw APIError.noSchoolSelected
        }

        guard let requestURL = URL(string: url) else {
            print("❌ [API] Invalid URL: \(url)")
            throw URLError(.badURL)
        }

        print("🌐 [API] GET: \(url)")
        print("🍪 [API] Cookies: \(cookieString)...")

        var req = URLRequest(url: requestURL)
        req.httpMethod = "GET"
        for (key, value) in headers {
            req.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await urlSession.data(for: req)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ [API] No HTTP response")
            throw URLError(.badServerResponse)
        }

        print("📡 [API] Status: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            print("❌ [API] Bad status code: \(httpResponse.statusCode)")
            throw URLError(.badServerResponse)
        }

        if let html = String(data: data, encoding: .utf8) {
            print("✅ [API] Response length: \(html.count) chars (UTF-8)")
            return html
        } else if let html = String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))) {
            print("✅ [API] Response length: \(html.count) chars (Big5)")
            return html
        }

        throw URLError(.cannotDecodeContentData)
    }

    private func needsRelogin(_ html: String) -> Bool {
        return html.contains("重新登入")
    }

    // MARK: - 從系統日期推算目前學期
    private func currentSemesterInfo() -> SemesterInfo {
        let calendar = Calendar.current
        let now = Date()
        let month = calendar.component(.month, from: now)
        let year  = calendar.component(.year, from: now)
        let schoolYear = month >= 8 ? String(year - 1911) : String(year - 1912)
        let semester   = month >= 8 ? "1" : "2"
        return SemesterInfo(schoolYear: schoolYear, semester: semester)
    }

    // MARK: - 從缺曠記錄計算統計資料
    private func computeAttendanceStatistics(from records: [AbsenceRecord]) -> AttendanceStatistics {
        var stats = AttendanceStatistics()
        let typeMapping: [String: String] = [
            "曠": "曠課", "事": "事假", "病": "病假", "公": "公假"
        ]
        for record in records {
            let key = typeMapping[record.status] ?? record.status
            if record.academicYear == "上" {
                let current = Int(stats.firstSemester[key] ?? "0") ?? 0
                stats.firstSemester[key] = String(current + 1)
            } else {
                let current = Int(stats.secondSemester[key] ?? "0") ?? 0
                stats.secondSemester[key] = String(current + 1)
            }
            switch record.status {
            case "曠": stats.total.truancy += 1
            case "事": stats.total.personalLeave += 1
            case "病": stats.total.sickLeave += 1
            case "公": stats.total.officialLeave += 1
            default: break
            }
        }
        return stats
    }

    // MARK: - 獎懲記錄
    func fetchMeritDemeritRecords() async throws -> (merits: [MeritDemeritRecord], demerits: [MeritDemeritRecord]) {
        let data = try await proxyGetData(path: "merit_demerit")
        let decoder = JSONDecoder()

        if let response = try? decoder.decode(APIResponse<[[MeritDemeritRecord]]>.self, from: data) {
            let merits = response.data.count > 0 ? response.data[0] : []
            let demerits = response.data.count > 1 ? response.data[1] : []
            return (merits, demerits)
        }

        if let response = try? decoder.decode(APIResponse<[String: [MeritDemeritRecord]]>.self, from: data) {
            let map = response.data
            let merits = map["merits"]
                ?? map["merit"]
                ?? map["rewards"]
                ?? map["reward"]
                ?? map["awards"]
                ?? map["award"]
                ?? map["獎勵"]
                ?? []

            let demerits = map["demerits"]
                ?? map["demerit"]
                ?? map["punishments"]
                ?? map["punishment"]
                ?? map["penalties"]
                ?? map["penalty"]
                ?? map["懲罰"]
                ?? []

            return (merits, demerits)
        }

        if let response = try? decoder.decode(APIResponse<[MeritDemeritRecord]>.self, from: data) {
            return (response.data, [])
        }

        if let raw = String(data: data, encoding: .utf8) {
            print("❌ [API] 無法解析 merit_demerit，原始回應: \(raw)")
        }
        throw APIError.invalidResponseFormat
    }

    // MARK: - 課表
    func fetchTimetableData(classNumber: String = "212", forceRefresh: Bool = false) async throws -> TimetableData {
        if !forceRefresh, let cached = CacheService.shared.getCachedTimetable() {
            return cached
        }

        _ = classNumber
        let response: APIResponse<[String: CourseInfo]> = try await proxyGet(path: "curriculum")

        let curriculum = response.data

        // 從 curriculum 建立 TimetableEntry 列表（periodTimes 由 API 未提供，留空）
        var entries: [TimetableEntry] = []
        for (subject, info) in curriculum {
            for schedule in info.schedule {
                entries.append(TimetableEntry(weekday: schedule.weekday,
                                               period: schedule.period,
                                               subject: subject))
            }
        }

        let timetable = TimetableData(entries: entries, periodTimes: [:], curriculum: curriculum)
        CacheService.shared.cacheTimetable(timetable)
        CacheService.shared.cacheCurriculum(timetable.curriculum)
        return timetable
    }

    func fetchCurriculum(classNumber: String = "212", forceRefresh: Bool = false) async throws -> [String: CourseInfo] {
        if !forceRefresh, let cached = CacheService.shared.getCachedTimetable() {
            return cached.curriculum
        }
        let timetable = try await fetchTimetableData(classNumber: classNumber, forceRefresh: forceRefresh)
        return timetable.curriculum
    }

    // MARK: - 缺曠記錄
    func fetchAttendance() async throws -> (records: [AbsenceRecord], statistics: AttendanceStatistics, semesterInfo: SemesterInfo?) {
        print("🔄 [Attendance] 開始抓取缺曠資料...")
        let response: APIResponse<[AbsenceRecord]> = try await proxyGet(path: "attendance")

        let records     = response.data
        print("📋 [Attendance] 收到 \(records.count) 筆缺曠記錄")
        for (i, r) in records.prefix(5).enumerated() {
            print("  [\(i)] academicYear=\(r.academicYear) date=\(r.date) weekday=\(r.weekday) period=\(r.period) status=\(r.status)")
        }
        if records.count > 5 { print("  ... (省略餘下 \(records.count - 5) 筆)") }

        let statistics  = computeAttendanceStatistics(from: records)
        print("📊 [Attendance] 統計: 曠=\(statistics.total.truancy) 事=\(statistics.total.personalLeave) 病=\(statistics.total.sickLeave) 公=\(statistics.total.officialLeave)")
        let semesterInfo = currentSemesterInfo()
        print("🗓️ [Attendance] 推算學期: \(semesterInfo.schoolYear)-\(semesterInfo.semester)")

        return (records, statistics, semesterInfo)
    }

    // MARK: - 學年成績
    func fetchYearScore(year: Int = 1) async throws -> GradeData {
        let semester = min(max(year, 1), 3)
        let response: APIResponse<GradeData> = try await proxyGet(
            path: "semester_scores",
            extraQueryItems: [URLQueryItem(name: "semester", value: "\(semester)")]
        )
        return response.data
    }

    // MARK: - 考試成績選單
    func fetchExamMenu(forceRefresh: Bool = false) async throws -> [ExamMenuItem] {
        if !forceRefresh, let cached = CacheService.shared.getCachedExamMenu() {
            return cached
        }

        let school = try selectedSchool()

        let response: APIResponse<[ExamMenuItem]> = try await proxyGet(path: "exam_menu")
        guard let examResultsRoute = school.route.examResults else {
            throw APIError.featureNotSupported
        }
        let items = response.data.map { item -> ExamMenuItem in
            let path = examResultsRoute.replacingOccurrences(of: "{file_name}", with: item.url)
            return ExamMenuItem(name: item.name, url: item.url, fullURL: school.api + path)
        }

        CacheService.shared.cacheExamMenu(items)
        return items
    }

    // MARK: - 考試成績詳情（保留本地爬蟲）
    func fetchExamScore(url: String) async throws -> ExamScoreData {
        let html = try await request(url: url)

        if needsRelogin(html) {
            await MainActor.run { self.isLoggedIn = false }
            throw APIError.sessionExpired
        }

        return HTMLParser.parseExamScores(html: html)
    }

    // MARK: - 缺曠統計（結合課表）
    func fetchAttendanceWithCurriculum(classNumber: String = "212") async throws -> (statistics: AttendanceStatistics, subjectAbsences: [SubjectAbsence]) {
        async let attendanceTask = fetchAttendance()
        async let curriculumTask = fetchCurriculum(classNumber: classNumber)

        let attendanceResult = try await attendanceTask
        let curriculum = try? await curriculumTask

        let manualCurriculum = CacheService.shared.manualCurriculum
        let subjectAbsences: [SubjectAbsence]
        if let curriculum {
            subjectAbsences = calculateSubjectAbsences(
                curriculum: curriculum,
                absenceRecords: attendanceResult.records,
                weeksPerSemester: weeksPerSemester,
                currentSemester: attendanceResult.semesterInfo?.semester,
                manualCurriculum: manualCurriculum
            )
        } else {
            subjectAbsences = []
        }

        return (attendanceResult.statistics, subjectAbsences)
    }

    // MARK: - 計算各科目缺曠
    private func calculateSubjectAbsences(curriculum: [String: CourseInfo],
                                           absenceRecords: [AbsenceRecord],
                                           weeksPerSemester: Int,
                                           currentSemester: String? = nil,
                                           manualCurriculum: [String: String] = [:]) -> [SubjectAbsence] {
        var courseMapping: [String: String] = [:]
        for (courseName, info) in curriculum {
            for schedule in info.schedule {
                let key = "\(schedule.weekday)-\(schedule.period)"
                courseMapping[key] = courseName
            }
        }

        // 套用手動覆蓋：manualCurriculum key 格式為 "weekday|period"
        for (manualKey, subject) in manualCurriculum where !subject.isEmpty {
            let parts = manualKey.split(separator: "|")
            guard parts.count == 2 else { continue }
            courseMapping["\(parts[0])-\(parts[1])"] = subject
        }

        // 根據套用手動後的 courseMapping 重新統計每科的週節數
        var slotsPerCourse: [String: Int] = [:]
        for course in courseMapping.values {
            slotsPerCourse[course, default: 0] += 1
        }

        var absenceCount: [String: (truancy: Int, personalLeave: Int)] = [:]
        let numberMap = ["1": "一", "2": "二", "3": "三", "4": "四", "5": "五", "6": "六", "7": "七"]

        print("🔍 [API] 開始計算各科缺曠，當前學期: \(currentSemester ?? "全部")")

        for record in absenceRecords {
            if let semester = currentSemester {
                let chineseSemester = semester == "1" ? "上" : "下"
                if record.academicYear != chineseSemester { continue }
            }

            let chinesePeriod = numberMap[record.period] ?? record.period
            let key = "\(record.weekday)-\(chinesePeriod)"

            if let course = courseMapping[key] {
                var current = absenceCount[course] ?? (0, 0)
                if record.status == "曠" {
                    current.truancy += 1
                } else if record.status == "事" {
                    current.personalLeave += 1
                }
                absenceCount[course] = current
            }
        }

        var results: [SubjectAbsence] = []
        for (course, counts) in absenceCount {
            let totalClasses = (slotsPerCourse[course] ?? 0) * weeksPerSemester
            let total        = counts.truancy + counts.personalLeave
            let percentage   = totalClasses > 0 ? Int((Double(total) / Double(totalClasses)) * 100) : 0
            results.append(SubjectAbsence(
                subject: course,
                truancy: counts.truancy,
                personalLeave: counts.personalLeave,
                total: total,
                totalClasses: totalClasses,
                percentage: percentage
            ))
        }

        return results.sorted { $0.total > $1.total }
    }

    // MARK: - Ping（驗證 session 是否仍有效）
    func pingAndRestoreSession() async -> Bool {
        let savedCookies = CacheService.shared.loadCookies()
        guard !savedCookies.isEmpty,
              let school = SchoolConfigManager.shared.selectedSchool else {
            return false
        }

        guard var components = URLComponents(string: "\(AppConfig.vocPassAPIHost)/ping") else {
            return false
        }
        components.queryItems = [URLQueryItem(name: "school_name", value: school.name)]
        guard let url = components.url else { return false }

        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: ";, "))
        let cookieString = savedCookies.map { cookie in
            let encodedValue = cookie.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? cookie.value
            return "\(cookie.name)=\(encodedValue)"
        }.joined(separator: "; ")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(cookieString, forHTTPHeaderField: "Cookie")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (_, response) = try await urlSession.data(for: req)
            guard let http = response as? HTTPURLResponse else { return false }
            print("🏓 [API] Ping 回應: \(http.statusCode)")
            if http.statusCode == 200 {
                await MainActor.run {
                    self.cookies = savedCookies
                    self.isLoggedIn = true
                }
                return true
            }
        } catch {
            print("❌ [API] Ping 失敗: \(error.localizedDescription)")
        }
        return false
    }

    // MARK: - 登出
    func logout() {
        cookies = []
        isLoggedIn = false
        CacheService.shared.clearCookies()
        clearAllCookiesAndWebsiteData()
    }

    private func clearAllCookiesAndWebsiteData() {
        let sharedStorage = HTTPCookieStorage.shared
        sharedStorage.cookies?.forEach { sharedStorage.deleteCookie($0) }

        let dataStore = WKWebsiteDataStore.default()
        dataStore.httpCookieStore.getAllCookies { cookies in
            cookies.forEach { dataStore.httpCookieStore.delete($0) }
        }

        let allDataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().fetchDataRecords(ofTypes: allDataTypes) { records in
            WKWebsiteDataStore.default().removeData(ofTypes: allDataTypes, for: records) {
                print("🧹 [API] 已清除所有 WebView cookies 與網站資料")
            }
        }

        print("🧹 [API] 已觸發登出資料清除流程")
    }
}

// MARK: - 錯誤類型
enum APIError: LocalizedError {
    case sessionExpired
    case noSchoolSelected
    case featureNotSupported
    case invalidResponseFormat
    case serverErrorID(String)
    case serverMessage(String)
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .sessionExpired:
            return "登入已過期，請重新登入"
        case .noSchoolSelected:
            return "請先選擇學校"
        case .featureNotSupported:
            return "此功能目前不支援"
        case .invalidResponseFormat:
            return "資料格式與預期不符，請稍後再試"
        case .serverErrorID(let errorID):
            return "伺服器錯誤（error_id: \(errorID)）"
        case .serverMessage(let message):
            return message
        case .httpStatus(let status):
            return "伺服器錯誤（HTTP \(status)）"
        }
    }
}
