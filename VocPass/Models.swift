//
//  Models.swift
//  YKVS
//
//  Created by Hans on 2025/12/31.
//

import Foundation

// MARK: - API 通用回應包裝器
struct APIResponse<T: Decodable>: Decodable {
    let code: Int
    let message: String
    let data: T

    enum CodingKeys: String, CodingKey {
        case code
        case message
        case data
    }

    private enum AlternateCodingKeys: String, CodingKey {
        case status
        case success
        case msg
        case detail
        case error
        case result
        case payload
    }

    init(from decoder: Decoder) throws {
        var resolvedCode = 200
        var resolvedMessage = ""
        var resolvedData: T?

        // 先嘗試標準/別名包裝格式
        if let c = try? decoder.container(keyedBy: CodingKeys.self) {
            let alt = try? decoder.container(keyedBy: AlternateCodingKeys.self)

            if let status = try? c.decodeLossyInt(forKey: .code) {
                resolvedCode = status
            } else if let alt, let status = try? alt.decodeLossyInt(forKey: .status) {
                resolvedCode = status
            } else if let alt, let success = try? alt.decodeLossyBool(forKey: .success) {
                resolvedCode = success ? 200 : 0
            }

            if let msg = try? c.decodeLossyString(forKey: .message) {
                resolvedMessage = msg
            } else if let alt, let msg = try? alt.decodeLossyString(forKey: .msg) {
                resolvedMessage = msg
            } else if let alt, let msg = try? alt.decodeLossyString(forKey: .detail) {
                resolvedMessage = msg
            } else if let alt, let msg = try? alt.decodeLossyString(forKey: .error) {
                resolvedMessage = msg
            }

            if let payload = try? c.decode(T.self, forKey: .data) {
                resolvedData = payload
            }
            if resolvedData == nil, let alt, let payload = try? alt.decode(T.self, forKey: .result) {
                resolvedData = payload
            }
            if resolvedData == nil, let alt, let payload = try? alt.decode(T.self, forKey: .payload) {
                resolvedData = payload
            }

            // 允許 payload 直接灌在同一層
            if resolvedData == nil, let payload = try? T(from: decoder) {
                resolvedData = payload
            }
        }

        // 最後退路：整包 JSON 就是資料本體
        if resolvedData == nil {
            let single = try decoder.singleValueContainer()
            resolvedData = try single.decode(T.self)
        }

        code = resolvedCode
        message = resolvedMessage
        data = resolvedData!
    }
}

// MARK: - 獎懲記錄
struct MeritDemeritRecord: Identifiable, Codable {
    let id = UUID()
    let dateOccurred: String      // 事發日期
    let dateApproved: String      // 核定日期
    let reason: String            // 事由
    let action: String            // 獎懲內容
    let dateRevoked: String?      // 销過日期
    let year: String              // 學年

    enum CodingKeys: String, CodingKey {
        case dateOccurred  = "date_occurred"
        case dateApproved  = "date_approved"
        case reason
        case action
        case dateRevoked   = "date_revoked"
        case year
    }

    private enum AlternateCodingKeys: String, CodingKey {
        case dateOccurred = "dateOccurred"
        case dateApproved = "dateApproved"
        case dateRevoked = "dateRevoked"
        case schoolYear = "school_year"
        case academicYear = "academic_year"
        case content
        case type
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let alt = try decoder.container(keyedBy: AlternateCodingKeys.self)

        dateOccurred = (try? c.decodeLossyString(forKey: .dateOccurred))
            ?? (try? alt.decodeLossyString(forKey: .dateOccurred))
            ?? ""
        dateApproved = (try? c.decodeLossyString(forKey: .dateApproved))
            ?? (try? alt.decodeLossyString(forKey: .dateApproved))
            ?? ""
        reason = (try? c.decodeLossyString(forKey: .reason)) ?? ""
        action = (try? c.decodeLossyString(forKey: .action))
            ?? (try? alt.decodeLossyString(forKey: .content))
            ?? (try? alt.decodeLossyString(forKey: .type))
            ?? ""
        dateRevoked = (try? c.decodeLossyStringIfPresent(forKey: .dateRevoked))
            ?? (try? alt.decodeLossyStringIfPresent(forKey: .dateRevoked))
        year = (try? c.decodeLossyString(forKey: .year))
            ?? (try? alt.decodeLossyString(forKey: .schoolYear))
            ?? (try? alt.decodeLossyString(forKey: .academicYear))
            ?? ""
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyString(forKey key: Key) throws -> String {
        if let value = try? decode(String.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decode(Double.self, forKey: key) {
            return String(value)
        }
        if let value = try? decode(Bool.self, forKey: key) {
            return value ? "true" : "false"
        }
        throw DecodingError.typeMismatch(
            String.self,
            DecodingError.Context(codingPath: codingPath + [key], debugDescription: "Value is not convertible to String")
        )
    }

    func decodeLossyStringIfPresent(forKey key: Key) throws -> String? {
        if !contains(key) {
            return nil
        }
        if (try? decodeNil(forKey: key)) == true {
            return nil
        }
        return try decodeLossyString(forKey: key)
    }

    func decodeLossyInt(forKey key: Key) throws -> Int {
        if let value = try? decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? decode(Double.self, forKey: key) {
            return Int(value)
        }
        if let value = try? decode(String.self, forKey: key) {
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }
        if let value = try? decode(Bool.self, forKey: key) {
            return value ? 1 : 0
        }
        throw DecodingError.typeMismatch(
            Int.self,
            DecodingError.Context(codingPath: codingPath + [key], debugDescription: "Value is not convertible to Int")
        )
    }

    func decodeLossyBool(forKey key: Key) throws -> Bool {
        if let value = try? decode(Bool.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return value != 0
        }
        if let value = try? decode(String.self, forKey: key) {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes", "y", "ok", "success": return true
            default: return false
            }
        }
        throw DecodingError.typeMismatch(
            Bool.self,
            DecodingError.Context(codingPath: codingPath + [key], debugDescription: "Value is not convertible to Bool")
        )
    }

    func decodeLossyStringArray(forKey key: Key) throws -> [String] {
        if let value = try? decode([String].self, forKey: key) {
            return value
        }
        if let value = try? decode([Int].self, forKey: key) {
            return value.map(String.init)
        }
        if let value = try? decode(String.self, forKey: key) {
            let list = value
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return list
        }
        throw DecodingError.typeMismatch(
            [String].self,
            DecodingError.Context(codingPath: codingPath + [key], debugDescription: "Value is not convertible to [String]")
        )
    }

    func decodeLossyStringMap(forKey key: Key) throws -> [String: String] {
        if let map = try? decode([String: String].self, forKey: key) {
            return map
        }
        if let map = try? decode([String: Int].self, forKey: key) {
            return map.mapValues(String.init)
        }
        if let map = try? decode([String: Double].self, forKey: key) {
            return map.mapValues { String(Int($0)) }
        }
        throw DecodingError.typeMismatch(
            [String: String].self,
            DecodingError.Context(codingPath: codingPath + [key], debugDescription: "Value is not convertible to [String: String]")
        )
    }
}

// MARK: - 缺曠記錄
struct AbsenceRecord: Identifiable, Codable {
    let id = UUID()
    let academicYear: String      // 學期（上/下）
    let date: String              // 日期
    let weekday: String           // 星期
    let period: String            // 節次（1–7）
    let status: String            // 狀態（曠、事、病等）

    enum CodingKeys: String, CodingKey {
        case academicYear = "academic_term"
        case date
        case weekday
        case period
        case status       = "cell"
    }

    private enum AlternateCodingKeys: String, CodingKey {
        case academicTerm = "academicTerm"
        case semester
        case term
        case schoolSemester = "school_semester"
        case dateOccurred = "date_occurred"
        case day
        case week
        case weekDay = "week_day"
        case section
        case classPeriod = "class_period"
        case attendanceType = "attendance_type"
        case type
        case reason
        case status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let alt = try decoder.container(keyedBy: AlternateCodingKeys.self)

        academicYear = (try? c.decodeLossyString(forKey: .academicYear))
            ?? (try? alt.decodeLossyString(forKey: .academicTerm))
            ?? (try? alt.decodeLossyString(forKey: .semester))
            ?? (try? alt.decodeLossyString(forKey: .term))
            ?? (try? alt.decodeLossyString(forKey: .schoolSemester))
            ?? ""

        date = (try? c.decodeLossyString(forKey: .date))
            ?? (try? alt.decodeLossyString(forKey: .dateOccurred))
            ?? ""

        weekday = (try? c.decodeLossyString(forKey: .weekday))
            ?? (try? alt.decodeLossyString(forKey: .day))
            ?? (try? alt.decodeLossyString(forKey: .week))
            ?? (try? alt.decodeLossyString(forKey: .weekDay))
            ?? ""

        period = (try? c.decodeLossyString(forKey: .period))
            ?? (try? alt.decodeLossyString(forKey: .section))
            ?? (try? alt.decodeLossyString(forKey: .classPeriod))
            ?? ""

        status = (try? c.decodeLossyString(forKey: .status))
            ?? (try? alt.decodeLossyString(forKey: .attendanceType))
            ?? (try? alt.decodeLossyString(forKey: .type))
            ?? (try? alt.decodeLossyString(forKey: .reason))
            ?? (try? alt.decodeLossyString(forKey: .status))
            ?? ""
    }
}

// MARK: - 缺曠統計
struct AttendanceStatistics: Codable {
    var firstSemester: [String: String] = [:]
    var secondSemester: [String: String] = [:]
    var total: AttendanceTotals = AttendanceTotals()
    var statisticsDate: String = ""

    enum CodingKeys: String, CodingKey {
        case firstSemester
        case secondSemester
        case total
        case statisticsDate
    }

    private enum AlternateCodingKeys: String, CodingKey {
        case first_semester
        case second_semester
        case first
        case second
        case overall
        case totals
        case updatedAt = "updated_at"
        case generatedAt = "generated_at"
        case date
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let alt = try decoder.container(keyedBy: AlternateCodingKeys.self)

        firstSemester = (try? c.decodeLossyStringMap(forKey: .firstSemester))
            ?? (try? alt.decodeLossyStringMap(forKey: .first_semester))
            ?? (try? alt.decodeLossyStringMap(forKey: .first))
            ?? [:]

        secondSemester = (try? c.decodeLossyStringMap(forKey: .secondSemester))
            ?? (try? alt.decodeLossyStringMap(forKey: .second_semester))
            ?? (try? alt.decodeLossyStringMap(forKey: .second))
            ?? [:]

        total = (try? c.decode(AttendanceTotals.self, forKey: .total))
            ?? (try? alt.decode(AttendanceTotals.self, forKey: .overall))
            ?? (try? alt.decode(AttendanceTotals.self, forKey: .totals))
            ?? AttendanceTotals()

        statisticsDate = (try? c.decodeLossyString(forKey: .statisticsDate))
            ?? (try? alt.decodeLossyString(forKey: .updatedAt))
            ?? (try? alt.decodeLossyString(forKey: .generatedAt))
            ?? (try? alt.decodeLossyString(forKey: .date))
            ?? ""
    }
}

struct AttendanceTotals: Codable {
    var truancy: Int = 0      // 曠課
    var personalLeave: Int = 0 // 事假
    var sickLeave: Int = 0     // 病假
    var officialLeave: Int = 0 // 公假

    enum CodingKeys: String, CodingKey {
        case truancy
        case personalLeave
        case sickLeave
        case officialLeave
    }

    private enum AlternateCodingKeys: String, CodingKey {
        case truant
        case absence
        case personal_leave
        case sick_leave
        case official_leave
        case public_leave
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let alt = try decoder.container(keyedBy: AlternateCodingKeys.self)

        truancy = (try? c.decodeLossyInt(forKey: .truancy))
            ?? (try? alt.decodeLossyInt(forKey: .truant))
            ?? (try? alt.decodeLossyInt(forKey: .absence))
            ?? 0
        personalLeave = (try? c.decodeLossyInt(forKey: .personalLeave))
            ?? (try? alt.decodeLossyInt(forKey: .personal_leave))
            ?? 0
        sickLeave = (try? c.decodeLossyInt(forKey: .sickLeave))
            ?? (try? alt.decodeLossyInt(forKey: .sick_leave))
            ?? 0
        officialLeave = (try? c.decodeLossyInt(forKey: .officialLeave))
            ?? (try? alt.decodeLossyInt(forKey: .official_leave))
            ?? (try? alt.decodeLossyInt(forKey: .public_leave))
            ?? 0
    }
}

// MARK: - 課表
struct CourseSchedule: Identifiable, Codable {
    let id = UUID()
    let weekday: String           // 星期幾
    let period: String            // 第幾節

    enum CodingKeys: String, CodingKey {
        case weekday, period
    }

    private enum AlternateCodingKeys: String, CodingKey {
        case day
        case week
        case weekDay = "week_day"
        case section
        case classPeriod = "class_period"
    }

    init(weekday: String, period: String) {
        self.weekday = weekday
        self.period = period
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let alt = try decoder.container(keyedBy: AlternateCodingKeys.self)

        weekday = (try? c.decodeLossyString(forKey: .weekday))
            ?? (try? alt.decodeLossyString(forKey: .day))
            ?? (try? alt.decodeLossyString(forKey: .week))
            ?? (try? alt.decodeLossyString(forKey: .weekDay))
            ?? ""
        period = (try? c.decodeLossyString(forKey: .period))
            ?? (try? alt.decodeLossyString(forKey: .section))
            ?? (try? alt.decodeLossyString(forKey: .classPeriod))
            ?? ""
    }
}

struct CourseInfo: Codable {
    let count: Int
    let schedule: [CourseSchedule]

    enum CodingKeys: String, CodingKey {
        case count
        case schedule
    }

    private enum AlternateCodingKeys: String, CodingKey {
        case credits
        case periods
        case schedules
        case timetable
    }

    init(count: Int, schedule: [CourseSchedule]) {
        self.count = count
        self.schedule = schedule
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let alt = try decoder.container(keyedBy: AlternateCodingKeys.self)

        count = (try? c.decodeLossyInt(forKey: .count))
            ?? (try? alt.decodeLossyInt(forKey: .credits))
            ?? (try? alt.decodeLossyInt(forKey: .periods))
            ?? 0

        if let s = try? c.decode([CourseSchedule].self, forKey: .schedule) {
            schedule = s
        } else if let s = try? alt.decode([CourseSchedule].self, forKey: .schedules) {
            schedule = s
        } else if let s = try? alt.decode([CourseSchedule].self, forKey: .timetable) {
            schedule = s
        } else if let single = try? c.decode(CourseSchedule.self, forKey: .schedule) {
            schedule = [single]
        } else {
            schedule = []
        }
    }
}

// MARK: - 成績
struct SubjectGrade: Identifiable, Codable {
    let id = UUID()
    let subject: String           // 科目
    let firstSemester: SemesterGrade
    let secondSemester: SemesterGrade
    let yearGrade: String         // 學年成績

    enum CodingKeys: String, CodingKey {
        case subject
        case firstSemester  = "first_semester"
        case secondSemester = "second_semester"
        case yearGrade      = "year_grade"
    }

    private enum AlternateCodingKeys: String, CodingKey {
        case annualScore = "annual_score"
    }

    init(subject: String, firstSemester: SemesterGrade, secondSemester: SemesterGrade, yearGrade: String) {
        self.subject        = subject
        self.firstSemester  = firstSemester
        self.secondSemester = secondSemester
        self.yearGrade      = yearGrade
    }

    init(from decoder: Decoder) throws {
        let c    = try decoder.container(keyedBy: CodingKeys.self)
        let alt  = try decoder.container(keyedBy: AlternateCodingKeys.self)
        subject        = (try? c.decode(String.self,        forKey: .subject))        ?? ""
        firstSemester  = (try? c.decode(SemesterGrade.self, forKey: .firstSemester))  ?? SemesterGrade()
        secondSemester = (try? c.decode(SemesterGrade.self, forKey: .secondSemester)) ?? SemesterGrade()
        yearGrade      = (try? c.decode(String.self,        forKey: .yearGrade))
            ?? (try? alt.decode(String.self,                forKey: .annualScore))
            ?? ""
    }
}

struct SemesterGrade: Codable {
    let attribute: String         // 屬性
    let credit: String            // 學分
    let score: String             // 成績

    init(attribute: String = "", credit: String = "", score: String = "") {
        self.attribute = attribute
        self.credit    = credit
        self.score     = score
    }

    init(from decoder: Decoder) throws {
        let c  = try decoder.container(keyedBy: CodingKeys.self)
        let alt = try decoder.container(keyedBy: AlternateCodingKeys.self)
        attribute = (try? c.decode(String.self, forKey: .attribute))
            ?? (try? alt.decode(String.self, forKey: .type))
            ?? ""
        credit    = (try? c.decode(String.self, forKey: .credit))
            ?? (try? alt.decode(String.self, forKey: .credits))
            ?? ""
        score     = (try? c.decode(String.self, forKey: .score))     ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case attribute
        case credit
        case score
    }

    private enum AlternateCodingKeys: String, CodingKey {
        case type
        case credits
    }
}

struct TotalScore: Codable {
    let firstSemester: String
    let secondSemester: String
    let year: String

    enum CodingKeys: String, CodingKey {
        case firstSemester = "first_semester"
        case secondSemester = "second_semester"
        case year
    }

    private enum AlternateCodingKeys: String, CodingKey {
        case annual
    }

    init(firstSemester: String = "", secondSemester: String = "", year: String = "") {
        self.firstSemester = firstSemester
        self.secondSemester = secondSemester
        self.year = year
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let alt = try decoder.container(keyedBy: AlternateCodingKeys.self)
        firstSemester = (try? c.decode(String.self, forKey: .firstSemester)) ?? ""
        secondSemester = (try? c.decode(String.self, forKey: .secondSemester)) ?? ""
        year = (try? c.decode(String.self, forKey: .year))
            ?? (try? alt.decode(String.self, forKey: .annual))
            ?? ""
    }
}

struct DailyPerformance: Codable {
    let evaluation: String        // 日常生活表現評量
    let description: String       // 描述
    let serviceHours: String      // 服務學習
    let specialPerformance: String // 校內外特殊表現
    let suggestions: String       // 具體建議及評語
    let others: String            // 其他

    enum CodingKeys: String, CodingKey {
        case evaluation
        case description
        case serviceHours
        case specialPerformance
        case suggestions
        case others
    }

    private enum AlternateCodingKeys: String, CodingKey {
        case comment
        case service_hours
        case service
        case special_performance
        case special
        case suggestion
        case remarks
    }

    init(
        evaluation: String = "",
        description: String = "",
        serviceHours: String = "",
        specialPerformance: String = "",
        suggestions: String = "",
        others: String = ""
    ) {
        self.evaluation = evaluation
        self.description = description
        self.serviceHours = serviceHours
        self.specialPerformance = specialPerformance
        self.suggestions = suggestions
        self.others = others
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let alt = try decoder.container(keyedBy: AlternateCodingKeys.self)

        evaluation = (try? c.decodeLossyString(forKey: .evaluation)) ?? ""
        description = (try? c.decodeLossyString(forKey: .description))
            ?? (try? alt.decodeLossyString(forKey: .comment))
            ?? ""
        serviceHours = (try? c.decodeLossyString(forKey: .serviceHours))
            ?? (try? alt.decodeLossyString(forKey: .service_hours))
            ?? (try? alt.decodeLossyString(forKey: .service))
            ?? ""
        specialPerformance = (try? c.decodeLossyString(forKey: .specialPerformance))
            ?? (try? alt.decodeLossyString(forKey: .special_performance))
            ?? (try? alt.decodeLossyString(forKey: .special))
            ?? ""
        suggestions = (try? c.decodeLossyString(forKey: .suggestions))
            ?? (try? alt.decodeLossyString(forKey: .suggestion))
            ?? ""
        others = (try? c.decodeLossyString(forKey: .others))
            ?? (try? alt.decodeLossyString(forKey: .remarks))
            ?? ""
    }
}

struct GradeData: Codable {
    var studentInfo: String = ""
    var subjects: [SubjectGrade] = []
    var totalScores: [String: TotalScore] = [:]
    var dailyPerformance: [String: DailyPerformance] = [:]

    enum CodingKeys: String, CodingKey {
        case studentInfo      = "student_info"
        case subjects
        case totalScores      = "total_scores"
        case dailyPerformance = "daily_performance"
    }

    private enum AlternateCodingKeys: String, CodingKey {
        case subjectScores = "subject_scores"
    }

    init(studentInfo: String = "",
         subjects: [SubjectGrade] = [],
         totalScores: [String: TotalScore] = [:],
         dailyPerformance: [String: DailyPerformance] = [:]) {
        self.studentInfo      = studentInfo
        self.subjects         = subjects
        self.totalScores      = totalScores
        self.dailyPerformance = dailyPerformance
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let alt = try decoder.container(keyedBy: AlternateCodingKeys.self)
        studentInfo      = (try? c.decode(String.self,                  forKey: .studentInfo))      ?? ""
        subjects         = (try? c.decode([SubjectGrade].self,          forKey: .subjects))
            ?? (try? alt.decode([SubjectGrade].self,                    forKey: .subjectScores))
            ?? []
        totalScores      = (try? c.decode([String: TotalScore].self,    forKey: .totalScores))      ?? [:]
        dailyPerformance = (try? c.decode([String: DailyPerformance].self, forKey: .dailyPerformance)) ?? [:]
    }
}

// MARK: - 考試成績
struct ExamMenuItem: Identifiable, Codable, Hashable {
    let id = UUID()
    let name: String
    let url: String       // file_name (e.g. grade_chart_all.asp)
    let fullURL: String   // 完整對學校伺服器的 URL

    enum CodingKeys: String, CodingKey {
        case name, url
    }

    init(name: String, url: String, fullURL: String) {
        self.name    = name
        self.url     = url
        self.fullURL = fullURL
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name    = (try? c.decode(String.self, forKey: .name)) ?? ""
        url     = (try? c.decode(String.self, forKey: .url))  ?? ""
        fullURL = ""
    }
}

struct ExamSubjectScore: Identifiable, Codable {
    let id = UUID()
    let subject: String
    let personalScore: String
    let classAverage: String

    enum CodingKeys: String, CodingKey {
        case subject, personalScore, classAverage
    }

    private enum AlternateCodingKeys: String, CodingKey {
        case name
        case score
        case studentScore = "student_score"
        case personal_score
        case avg
        case classAvg = "class_avg"
        case class_average
    }

    init(subject: String, personalScore: String, classAverage: String) {
        self.subject = subject
        self.personalScore = personalScore
        self.classAverage = classAverage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let alt = try decoder.container(keyedBy: AlternateCodingKeys.self)

        subject = (try? c.decodeLossyString(forKey: .subject))
            ?? (try? alt.decodeLossyString(forKey: .name))
            ?? ""
        personalScore = (try? c.decodeLossyString(forKey: .personalScore))
            ?? (try? alt.decodeLossyString(forKey: .score))
            ?? (try? alt.decodeLossyString(forKey: .studentScore))
            ?? (try? alt.decodeLossyString(forKey: .personal_score))
            ?? ""
        classAverage = (try? c.decodeLossyString(forKey: .classAverage))
            ?? (try? alt.decodeLossyString(forKey: .avg))
            ?? (try? alt.decodeLossyString(forKey: .classAvg))
            ?? (try? alt.decodeLossyString(forKey: .class_average))
            ?? ""
    }
}

struct ExamSummary: Codable {
    let totalScore: String
    let averageScore: String
    let classRank: String
    let departmentRank: String

    enum CodingKeys: String, CodingKey {
        case totalScore
        case averageScore
        case classRank
        case departmentRank
    }

    private enum AlternateCodingKeys: String, CodingKey {
        case total
        case average
        case class_rank
        case department_rank
        case rank
    }

    init(totalScore: String = "", averageScore: String = "", classRank: String = "", departmentRank: String = "") {
        self.totalScore = totalScore
        self.averageScore = averageScore
        self.classRank = classRank
        self.departmentRank = departmentRank
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let alt = try decoder.container(keyedBy: AlternateCodingKeys.self)

        totalScore = (try? c.decodeLossyString(forKey: .totalScore))
            ?? (try? alt.decodeLossyString(forKey: .total))
            ?? ""
        averageScore = (try? c.decodeLossyString(forKey: .averageScore))
            ?? (try? alt.decodeLossyString(forKey: .average))
            ?? ""
        classRank = (try? c.decodeLossyString(forKey: .classRank))
            ?? (try? alt.decodeLossyString(forKey: .class_rank))
            ?? (try? alt.decodeLossyString(forKey: .rank))
            ?? ""
        departmentRank = (try? c.decodeLossyString(forKey: .departmentRank))
            ?? (try? alt.decodeLossyString(forKey: .department_rank))
            ?? ""
    }
}

struct StudentInfo: Codable {
    let studentId: String
    let name: String
    let className: String

    enum CodingKeys: String, CodingKey {
        case studentId
        case name
        case className
    }

    private enum AlternateCodingKeys: String, CodingKey {
        case student_id
        case studentNo = "student_no"
        case id
        case fullName = "full_name"
        case class_name
        case classNo = "class_no"
        case homeroom
    }

    init(studentId: String = "", name: String = "", className: String = "") {
        self.studentId = studentId
        self.name = name
        self.className = className
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let alt = try decoder.container(keyedBy: AlternateCodingKeys.self)

        studentId = (try? c.decodeLossyString(forKey: .studentId))
            ?? (try? alt.decodeLossyString(forKey: .student_id))
            ?? (try? alt.decodeLossyString(forKey: .studentNo))
            ?? (try? alt.decodeLossyString(forKey: .id))
            ?? ""
        name = (try? c.decodeLossyString(forKey: .name))
            ?? (try? alt.decodeLossyString(forKey: .fullName))
            ?? ""
        className = (try? c.decodeLossyString(forKey: .className))
            ?? (try? alt.decodeLossyString(forKey: .class_name))
            ?? (try? alt.decodeLossyString(forKey: .classNo))
            ?? (try? alt.decodeLossyString(forKey: .homeroom))
            ?? ""
    }
}

struct ExamScoreData: Codable {
    var studentInfo: StudentInfo = StudentInfo(studentId: "", name: "", className: "")
    var examInfo: String = ""
    var subjects: [ExamSubjectScore] = []
    var summary: ExamSummary = ExamSummary(totalScore: "", averageScore: "", classRank: "", departmentRank: "")
}

// MARK: - 學期資訊
struct SemesterInfo: Codable {
    let schoolYear: String
    let semester: String
}

// MARK: - 課表時間表

struct PeriodTime: Codable, Equatable, Hashable {
    let startTime: String
    let endTime: String
}

struct TimetableEntry: Codable, Identifiable {
    let id: UUID
    let weekday: String
    let period: String
    let subject: String

    init(weekday: String, period: String, subject: String) {
        self.id = UUID()
        self.weekday = weekday
        self.period = period
        self.subject = subject
    }

    enum CodingKeys: String, CodingKey {
        case id, weekday, period, subject
    }

    private enum AlternateCodingKeys: String, CodingKey {
        case day
        case weekDay = "week_day"
        case section
        case classPeriod = "class_period"
        case course
        case courseName = "course_name"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let alt = try decoder.container(keyedBy: AlternateCodingKeys.self)

        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        weekday = (try? c.decodeLossyString(forKey: .weekday))
            ?? (try? alt.decodeLossyString(forKey: .day))
            ?? (try? alt.decodeLossyString(forKey: .weekDay))
            ?? ""
        period = (try? c.decodeLossyString(forKey: .period))
            ?? (try? alt.decodeLossyString(forKey: .section))
            ?? (try? alt.decodeLossyString(forKey: .classPeriod))
            ?? ""
        subject = (try? c.decodeLossyString(forKey: .subject))
            ?? (try? alt.decodeLossyString(forKey: .course))
            ?? (try? alt.decodeLossyString(forKey: .courseName))
            ?? ""
    }
}

struct TimetableData: Codable {
    var entries: [TimetableEntry]
    var periodTimes: [String: PeriodTime]
    var curriculum: [String: CourseInfo]

    enum CodingKeys: String, CodingKey {
        case entries
        case periodTimes
        case curriculum
    }

    private enum AlternateCodingKeys: String, CodingKey {
        case timetable
        case periods
        case classes
    }

    init(entries: [TimetableEntry], periodTimes: [String: PeriodTime], curriculum: [String: CourseInfo]) {
        self.entries = entries
        self.periodTimes = periodTimes
        self.curriculum = curriculum
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let alt = try decoder.container(keyedBy: AlternateCodingKeys.self)

        entries = (try? c.decode([TimetableEntry].self, forKey: .entries))
            ?? (try? alt.decode([TimetableEntry].self, forKey: .timetable))
            ?? []
        periodTimes = (try? c.decode([String: PeriodTime].self, forKey: .periodTimes))
            ?? (try? alt.decode([String: PeriodTime].self, forKey: .periods))
            ?? [:]
        curriculum = (try? c.decode([String: CourseInfo].self, forKey: .curriculum))
            ?? (try? alt.decode([String: CourseInfo].self, forKey: .classes))
            ?? [:]
    }
}

// MARK: - 科目缺曠統計
struct SubjectAbsence: Identifiable, Codable {
    let id = UUID()
    let subject: String
    let truancy: Int              // 曠課
    let personalLeave: Int        // 事假
    let total: Int                // 總計
    let totalClasses: Int         // 總節數
    let percentage: Int           // 缺曠百分比

    enum CodingKeys: String, CodingKey {
        case subject, truancy, personalLeave, total, totalClasses, percentage
    }

    private enum AlternateCodingKeys: String, CodingKey {
        case course
        case name
        case truant
        case personal_leave
        case sum
        case total_classes
        case rate
    }

    init(subject: String, truancy: Int, personalLeave: Int, total: Int, totalClasses: Int, percentage: Int) {
        self.subject = subject
        self.truancy = truancy
        self.personalLeave = personalLeave
        self.total = total
        self.totalClasses = totalClasses
        self.percentage = percentage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let alt = try decoder.container(keyedBy: AlternateCodingKeys.self)

        subject = (try? c.decodeLossyString(forKey: .subject))
            ?? (try? alt.decodeLossyString(forKey: .course))
            ?? (try? alt.decodeLossyString(forKey: .name))
            ?? ""
        truancy = (try? c.decodeLossyInt(forKey: .truancy))
            ?? (try? alt.decodeLossyInt(forKey: .truant))
            ?? 0
        personalLeave = (try? c.decodeLossyInt(forKey: .personalLeave))
            ?? (try? alt.decodeLossyInt(forKey: .personal_leave))
            ?? 0
        total = (try? c.decodeLossyInt(forKey: .total))
            ?? (try? alt.decodeLossyInt(forKey: .sum))
            ?? (truancy + personalLeave)
        totalClasses = (try? c.decodeLossyInt(forKey: .totalClasses))
            ?? (try? alt.decodeLossyInt(forKey: .total_classes))
            ?? 0
        percentage = (try? c.decodeLossyInt(forKey: .percentage))
            ?? (try? alt.decodeLossyInt(forKey: .rate))
            ?? (totalClasses > 0 ? Int((Double(total) / Double(totalClasses)) * 100) : 0)
    }
}
