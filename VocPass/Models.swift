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
}

// MARK: - 缺曠統計
struct AttendanceStatistics: Codable {
    var firstSemester: [String: String] = [:]
    var secondSemester: [String: String] = [:]
    var total: AttendanceTotals = AttendanceTotals()
    var statisticsDate: String = ""
}

struct AttendanceTotals: Codable {
    var truancy: Int = 0      // 曠課
    var personalLeave: Int = 0 // 事假
    var sickLeave: Int = 0     // 病假
    var officialLeave: Int = 0 // 公假
}

// MARK: - 課表
struct CourseSchedule: Identifiable, Codable {
    let id = UUID()
    let weekday: String           // 星期幾
    let period: String            // 第幾節

    enum CodingKeys: String, CodingKey {
        case weekday, period
    }
}

struct CourseInfo: Codable {
    let count: Int
    let schedule: [CourseSchedule]
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
}

struct ExamSummary: Codable {
    let totalScore: String
    let averageScore: String
    let classRank: String
    let departmentRank: String
}

struct StudentInfo: Codable {
    let studentId: String
    let name: String
    let className: String
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
}

struct TimetableData: Codable {
    var entries: [TimetableEntry]
    var periodTimes: [String: PeriodTime]
    var curriculum: [String: CourseInfo]
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
}
