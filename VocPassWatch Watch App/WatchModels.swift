//
//  WatchModels.swift
//  VocPassWatch
//

import Foundation

// MARK: - 課表模型（與 iOS 端同步）

struct PeriodTime: Codable, Equatable, Hashable {
    let startTime: String
    let endTime: String
}

struct TimetableEntry: Codable, Identifiable {
    let id: UUID
    let weekday: String
    let period: String
    let subject: String
    let room: String?
    let teacher: String?

    init(weekday: String, period: String, subject: String,
         room: String? = nil, teacher: String? = nil) {
        self.id = UUID()
        self.weekday = weekday
        self.period = period
        self.subject = subject
        self.room = room
        self.teacher = teacher
    }
}

struct CourseSchedule: Codable {
    let weekday: String
    let period: String
    let start: String?
    let end: String?
    let room: String?
    let teacher: String?
}

struct CourseInfo: Codable {
    let count: Int
    let schedule: [CourseSchedule]
}

struct CourseExtra: Codable {
    var room: String
    var teacher: String
}

struct TimetableData: Codable {
    var entries: [TimetableEntry]
    var periodTimes: [String: PeriodTime]
    var curriculum: [String: CourseInfo]
}

// MARK: - Watch App Group Keys

let kWatchAppGroupID = "group.me.hans0805.VocPass"

enum WatchCacheKey: String {
    case timetable           = "cached_timetable"
    case manualCurriculum    = "manual_curriculum"
    case manualPeriodTimes   = "manual_period_times"
    case manualRoomTeacher   = "manual_room_teacher"
    case followedUsernames   = "followed_usernames"
    case periodsPerDay       = "periods_per_day"
}

func watchSharedTimetableKey(for username: String) -> String {
    "watch_shared_\(username)"
}

// MARK: - Ordered Weekdays & Periods

let watchWeekdays = ["一", "二", "三", "四", "五"]
let watchChinesePeriods = ["一","二","三","四","五","六","七","八","九","十"]

func currentWatchWeekday() -> String {
    let weekday = Calendar.current.component(.weekday, from: Date())
    switch weekday {
    case 2: return "一"
    case 3: return "二"
    case 4: return "三"
    case 5: return "四"
    case 6: return "五"
    default: return "一"
    }
}

func periodOrder(_ period: String) -> Int {
    watchChinesePeriods.firstIndex(of: period) ?? 99
}
