//
//  APIService.swift
//  YKVS
//
//  Created by Hans on 2025/12/31.
//

import Foundation
import Combine

class APIService: ObservableObject {
    static let shared = APIService()

    private let weeksPerSemester = 18

    private var vocPassAPIHost: String {
        #if DEBUG
        return "https://vocpass-dev.zeabur.app"
        #else
        return "https://vocpass.zeabur.app"
        #endif
    }

    @Published var cookies: [HTTPCookie] = []
    @Published var isLoggedIn = false

    private var cookieString: String {
        cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
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

    // MARK: - 取得目前選擇的學校（或拋出錯誤）
    private func selectedSchool() throws -> SchoolConfig {
        guard let school = SchoolConfigManager.shared.selectedSchool else {
            throw APIError.noSchoolSelected
        }
        return school
    }

    // MARK: - 以代理 API GET（cookies 直接放 Header）
    private func proxyGet<T: Decodable>(path: String,
                                        extraQueryItems: [URLQueryItem] = []) async throws -> APIResponse<T> {
        let school = try selectedSchool()

        guard !cookieString.isEmpty else {
            throw APIError.sessionExpired
        }

        guard var components = URLComponents(string: "\(vocPassAPIHost)/api/\(school.vision)/\(path)") else {
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

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard httpResponse.statusCode == 200 else {
            if let detail = String(data: data, encoding: .utf8) {
                print("❌ [API] Proxy API error (\(httpResponse.statusCode)): \(detail)")
            } else {
                print("❌ [API] Proxy API error (\(httpResponse.statusCode))")
            }
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(APIResponse<T>.self, from: data)
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

        let (data, response) = try await URLSession.shared.data(for: req)

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
        let response: APIResponse<[[MeritDemeritRecord]]> = try await proxyGet(path: "merit_demerit")

        let merits   = response.data.count > 0 ? response.data[0] : []
        let demerits = response.data.count > 1 ? response.data[1] : []
        return (merits, demerits)
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
        let response: APIResponse<[AbsenceRecord]> = try await proxyGet(path: "attendance")

        let records     = response.data
        let statistics  = computeAttendanceStatistics(from: records)
        let semesterInfo = currentSemesterInfo()

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

        let subjectAbsences: [SubjectAbsence]
        if let curriculum {
            subjectAbsences = calculateSubjectAbsences(
                curriculum: curriculum,
                absenceRecords: attendanceResult.records,
                weeksPerSemester: weeksPerSemester,
                currentSemester: attendanceResult.semesterInfo?.semester
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
                                           currentSemester: String? = nil) -> [SubjectAbsence] {
        var courseMapping: [String: String] = [:]
        for (courseName, info) in curriculum {
            for schedule in info.schedule {
                let key = "\(schedule.weekday)-\(schedule.period)"
                courseMapping[key] = courseName
            }
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
            let totalClasses = (curriculum[course]?.count ?? 0) * weeksPerSemester
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

    // MARK: - 登出
    func logout() {
        cookies = []
        isLoggedIn = false
    }
}

// MARK: - 錯誤類型
enum APIError: LocalizedError {
    case sessionExpired
    case noSchoolSelected
    case featureNotSupported

    var errorDescription: String? {
        switch self {
        case .sessionExpired:
            return "登入已過期，請重新登入"
        case .noSchoolSelected:
            return "請先選擇學校"
        case .featureNotSupported:
            return "此功能目前不支援"
        }
    }
}
