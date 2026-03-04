//
//  Models.swift
//  YKVS
//
//  Created by Hans on 2025/12/31.
//

import Foundation

// MARK: - 獎懲記錄
struct MeritDemeritRecord: Identifiable, Codable {
    let id = UUID()
    let dateOccurred: String      // 事發日期
    let dateApproved: String      // 核定日期
    let reason: String            // 事由
    let action: String            // 獎懲內容
    let dateRevoked: String?      // 銷過日期
    let year: String              // 學年

    enum CodingKeys: String, CodingKey {
        case dateOccurred, dateApproved, reason, action, dateRevoked, year
    }
}

// MARK: - 缺曠記錄
struct AbsenceRecord: Identifiable, Codable {
    let id = UUID()
    let academicYear: String      // 學年
    let date: String              // 日期
    let weekday: String           // 星期
    let period: String            // 節次
    let status: String            // 狀態 (曠、事、病等)

    enum CodingKeys: String, CodingKey {
        case academicYear, date, weekday, period, status
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
        case subject, firstSemester, secondSemester, yearGrade
    }
}

struct SemesterGrade: Codable {
    let attribute: String         // 屬性
    let credit: String            // 學分
    let score: String             // 成績
}

struct TotalScore: Codable {
    let firstSemester: String
    let secondSemester: String
    let year: String
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
}

// MARK: - 考試成績
struct ExamMenuItem: Identifiable, Codable, Hashable {
    let id = UUID()
    let name: String
    let url: String
    let fullURL: String

    enum CodingKeys: String, CodingKey {
        case name, url, fullURL
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
