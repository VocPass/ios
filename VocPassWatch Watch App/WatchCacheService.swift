//
//  WatchCacheService.swift
//  VocPassWatch
//

import Foundation

class WatchCacheService {
    static let shared = WatchCacheService()

    private var defaults: UserDefaults? { UserDefaults(suiteName: kWatchAppGroupID) }

    // MARK: - Own Timetable

    func getOwnTimetable() -> TimetableData? {
        guard let data = defaults?.data(forKey: WatchCacheKey.timetable.rawValue) else { return nil }
        return try? JSONDecoder().decode(TimetableData.self, from: data)
    }

    func saveOwnTimetable(_ timetable: TimetableData) {
        guard let data = try? JSONEncoder().encode(timetable) else { return }
        defaults?.set(data, forKey: WatchCacheKey.timetable.rawValue)
    }

    // MARK: - Manual Overrides

    var manualCurriculum: [String: String] {
        guard let data = defaults?.data(forKey: WatchCacheKey.manualCurriculum.rawValue),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }

    var manualPeriodTimes: [String: PeriodTime] {
        guard let data = defaults?.data(forKey: WatchCacheKey.manualPeriodTimes.rawValue),
              let dict = try? JSONDecoder().decode([String: PeriodTime].self, from: data)
        else { return [:] }
        return dict
    }

    var manualRoomTeacher: [String: CourseExtra] {
        guard let data = defaults?.data(forKey: WatchCacheKey.manualRoomTeacher.rawValue),
              let dict = try? JSONDecoder().decode([String: CourseExtra].self, from: data)
        else { return [:] }
        return dict
    }

    // MARK: - Following

    var followedUsernames: [String] {
        get { defaults?.array(forKey: WatchCacheKey.followedUsernames.rawValue) as? [String] ?? [] }
        set { defaults?.set(newValue, forKey: WatchCacheKey.followedUsernames.rawValue) }
    }

    // MARK: - Shared Timetables (keyed by username)

    func getSharedTimetable(for username: String) -> TimetableData? {
        guard let data = defaults?.data(forKey: watchSharedTimetableKey(for: username)) else { return nil }
        return try? JSONDecoder().decode(TimetableData.self, from: data)
    }

    func saveSharedTimetable(_ timetable: TimetableData, for username: String) {
        guard let data = try? JSONEncoder().encode(timetable) else { return }
        defaults?.set(data, forKey: watchSharedTimetableKey(for: username))
    }

    // MARK: - Settings

    var periodsPerDay: Int {
        let v = defaults?.integer(forKey: WatchCacheKey.periodsPerDay.rawValue) ?? 0
        return v == 0 ? 7 : v
    }

    // MARK: - Merge Own Timetable with Manual Overrides

    func mergedEntries(for weekday: String, from timetable: TimetableData) -> [TimetableEntry] {
        var entries = timetable.entries.filter { $0.weekday == weekday }
        let manual = manualCurriculum
        let extras = manualRoomTeacher
        let periodsCount = periodsPerDay

        for i in 0..<periodsCount {
            let period = i < watchChinesePeriods.count ? watchChinesePeriods[i] : "\(i + 1)"
            let key = "\(weekday)|\(period)"

            if let subject = manual[key], !subject.isEmpty {
                let extra = extras[key]
                if let idx = entries.firstIndex(where: { $0.period == period }) {
                    entries[idx] = TimetableEntry(
                        weekday: weekday, period: period, subject: subject,
                        room: extra?.room ?? entries[idx].room,
                        teacher: extra?.teacher ?? entries[idx].teacher
                    )
                } else {
                    entries.append(TimetableEntry(
                        weekday: weekday, period: period, subject: subject,
                        room: extra?.room, teacher: extra?.teacher
                    ))
                }
            } else if let extra = extras[key],
                      let idx = entries.firstIndex(where: { $0.period == period }) {
                entries[idx] = TimetableEntry(
                    weekday: weekday, period: period, subject: entries[idx].subject,
                    room: extra.room, teacher: extra.teacher
                )
            }
        }

        return entries.sorted { periodOrder($0.period) < periodOrder($1.period) }
    }
}
