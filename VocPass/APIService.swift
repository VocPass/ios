//
//  APIService.swift
//  YKVS
//
//  Created by Hans on 2025/12/31.
//

import Foundation
import WebKit
import Combine

class APIService: ObservableObject {
    static let shared = APIService()

    private let weeksPerSemester = 18
    
    private var baseURL: String {
        guard let selectedSchool = SchoolConfigManager.shared.selectedSchool else {
            return "https://eschool.ykvs.ntpc.edu.tw/online/"
        }
        return selectedSchool.api + "/online/"
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

    // MARK: - 網路請求
    private func request(url: String) async throws -> String {
        // 檢查是否已選擇學校
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

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

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
            print("📄 [API] HTML Preview: \(html)")
            return html
        } else if let html = String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))) {
            print("✅ [API] Response length: \(html.count) chars (Big5)")
            print("📄 [API] HTML Preview: \(html)")
            return html
        }

        throw URLError(.cannotDecodeContentData)
    }

    private func needsRelogin(_ html: String) -> Bool {
        return html.contains("重新登入")
    }

    // MARK: - 獎懲記錄
    func fetchMeritDemeritRecords() async throws -> (merits: [MeritDemeritRecord], demerits: [MeritDemeritRecord]) {
        let url = "\(baseURL)selection_student/moralculture_%20bonuspenalty.asp"
        let html = try await request(url: url)

        if needsRelogin(html) {
            await MainActor.run { self.isLoggedIn = false }
            throw APIError.sessionExpired
        }

        return HTMLParser.parseMeritDemeritRecords(html: html)
    }

    // MARK: - 課表
    func fetchCurriculum(classNumber: String = "212", forceRefresh: Bool = false) async throws -> [String: CourseInfo] {
        if !forceRefresh, let cached = CacheService.shared.getCachedCurriculum() {
            return cached
        }

        let url = "\(baseURL)student/school_class_tabletime.asp?teacher_classnumber=\(classNumber)"
        let html = try await request(url: url)

        if needsRelogin(html) {
            await MainActor.run { self.isLoggedIn = false }
            throw APIError.sessionExpired
        }

        let result = HTMLParser.parseWeeklyCurriculum(html: html)

        CacheService.shared.cacheCurriculum(result)

        return result
    }

    // MARK: - 缺曠記錄
    func fetchAttendance() async throws -> (records: [AbsenceRecord], statistics: AttendanceStatistics, semesterInfo: SemesterInfo?) {
        let url = "\(baseURL)selection_student/absentation_skip_school.asp"
        let html = try await request(url: url)

        if needsRelogin(html) {
            await MainActor.run { self.isLoggedIn = false }
            throw APIError.sessionExpired
        }

        let records = HTMLParser.parseAbsenceRecords(html: html)
        let statistics = HTMLParser.parseAttendanceStatistics(html: html)
        let semesterInfo = HTMLParser.extractSemesterInfo(html: html)

        return (records, statistics, semesterInfo)
    }

    // MARK: - 學年成績
    func fetchYearScore(year: Int = 1) async throws -> GradeData {
        let yearCodes = ["1": "%A4%40", "2": "%A4G", "3": "%A4T", "4": "%A5%7C"]
        let yearCode = yearCodes["\(year)"] ?? "%A4%40"

        let url = "\(baseURL)selection_student/year_accomplishment.asp?action=selection_underside_year&year_class=\(yearCode)&number=\(year)"
        let html = try await request(url: url)

        if needsRelogin(html) {
            await MainActor.run { self.isLoggedIn = false }
            throw APIError.sessionExpired
        }

        return HTMLParser.parseGradeData(html: html)
    }

    // MARK: - 考試成績選單
    func fetchExamMenu(forceRefresh: Bool = false) async throws -> [ExamMenuItem] {
        if !forceRefresh, let cached = CacheService.shared.getCachedExamMenu() {
            return cached
        }

        let url = "\(baseURL)selection_student/student_subjects_number.asp?action=open_window_frame"
        let html = try await request(url: url)

        if needsRelogin(html) {
            await MainActor.run { self.isLoggedIn = false }
            throw APIError.sessionExpired
        }

        let result = HTMLParser.parseExamMenu(html: html, baseURL: baseURL)

        CacheService.shared.cacheExamMenu(result)

        return result
    }

    // MARK: - 考試成績詳情
    func fetchExamScore(url: String) async throws -> ExamScoreData {
        let html = try await request(url: url)

        if needsRelogin(html) {
            await MainActor.run { self.isLoggedIn = false }
            throw APIError.sessionExpired
        }

        return HTMLParser.parseExamScores(html: html)
    }

    // MARK: - 缺曠統計 (結合課表)
    func fetchAttendanceWithCurriculum(classNumber: String = "212") async throws -> (statistics: AttendanceStatistics, subjectAbsences: [SubjectAbsence]) {
        async let attendanceTask = fetchAttendance()
        async let curriculumTask = fetchCurriculum(classNumber: classNumber)

        let (attendanceResult, curriculum) = try await (attendanceTask, curriculumTask)
        
        let subjectAbsences = calculateSubjectAbsences(
            curriculum: curriculum,
            absenceRecords: attendanceResult.records,
            weeksPerSemester: weeksPerSemester,
            currentSemester: attendanceResult.semesterInfo?.semester
        )

        return (attendanceResult.statistics, subjectAbsences)
    }

    // MARK: - 計算各科目缺曠
    private func calculateSubjectAbsences(curriculum: [String: CourseInfo], absenceRecords: [AbsenceRecord], weeksPerSemester: Int, currentSemester: String? = nil) -> [SubjectAbsence] {
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
        print("🔍 [API] 總缺曠記錄數: \(absenceRecords.count)")
        
        for record in absenceRecords {
            if let semester = currentSemester {
                let chineseSemester = semester == "1" ? "上" : "下"
                if record.academicYear != chineseSemester {
                    continue
                }
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
        
        print("🔍 [API] 各科缺曠統計: \(absenceCount)")

        var results: [SubjectAbsence] = []
        for (course, counts) in absenceCount {
            let totalClasses = (curriculum[course]?.count ?? 0) * weeksPerSemester
            let total = counts.truancy + counts.personalLeave
            let percentage = totalClasses > 0 ? Int((Double(total) / Double(totalClasses)) * 100) : 0

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
    case parseError
    case networkError
    case noSchoolSelected

    var errorDescription: String? {
        switch self {
        case .sessionExpired:
            return "登入已過期，請重新登入"
        case .parseError:
            return "資料解析錯誤"
        case .networkError:
            return "網路連線錯誤"
        case .noSchoolSelected:
            return "請先選擇學校"
        }
    }
}
