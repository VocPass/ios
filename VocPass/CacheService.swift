//
//  CacheService.swift
//  YKVS
//
//  Created by Hans on 2025/12/31.
//

import Foundation
import WidgetKit

let kSharedAppGroupID = "group.com.08hans.VocPass"

class CacheService {
    static let shared = CacheService()

    private let userDefaults = UserDefaults.standard
    private var sharedDefaults: UserDefaults? { UserDefaults(suiteName: kSharedAppGroupID) }
    private let cacheExpirationInterval: TimeInterval = 24 * 60 * 60 // 1 day in seconds

    // MARK: - Cache Keys
    private enum CacheKey: String {
        case curriculum = "cached_curriculum"
        case curriculumTimestamp = "cached_curriculum_timestamp"
        case timetable = "cached_timetable"
        case timetableTimestamp = "cached_timetable_timestamp"
        case hasSeenOnboarding = "has_seen_onboarding"
        case savedUsername = "saved_username"
        case savedPassword = "saved_password"
        case savedSchoolCode = "saved_school_code"
        case rememberCredentials = "remember_credentials"
        case autoStartDynamicIsland = "auto_start_dynamic_island"
        case manualCurriculum = "manual_curriculum"
        case manualPeriodTimes = "manual_period_times"
        case manualRoomTeacher = "manual_room_teacher"
        case isCurriculumSharing = "is_curriculum_sharing"
        case followedUsernames = "followed_usernames"
        case savedCookies = "saved_cookies"
        case vocPassCookies = "vocpass_auth_cookies"
        case weeksPerSemester = "weeks_per_semester"
        case periodsPerDay = "periods_per_day"
        case passingScore = "passing_score"
    }

    // MARK: - 課表顯示節數

    var periodsPerDay: Int {
        get {
            let v = userDefaults.integer(forKey: CacheKey.periodsPerDay.rawValue)
            return v == 0 ? 7 : v
        }
        set { userDefaults.set(newValue, forKey: CacheKey.periodsPerDay.rawValue) }
    }

    // MARK: - 學期週數設定

    var weeksPerSemester: Int {
        get {
            let v = userDefaults.integer(forKey: CacheKey.weeksPerSemester.rawValue)
            return v == 0 ? 18 : v
        }
        set { userDefaults.set(newValue, forKey: CacheKey.weeksPerSemester.rawValue) }
    }

    // MARK: - 及格分數設定

    var passingScore: Int {
        get {
            let v = userDefaults.integer(forKey: CacheKey.passingScore.rawValue)
            return v == 0 ? 60 : v
        }
        set { userDefaults.set(newValue, forKey: CacheKey.passingScore.rawValue) }
    }

    // MARK: - Dynamic Island Settings

    var autoStartDynamicIsland: Bool {
        get { userDefaults.bool(forKey: CacheKey.autoStartDynamicIsland.rawValue) }
        set { userDefaults.set(newValue, forKey: CacheKey.autoStartDynamicIsland.rawValue) }
    }

    // MARK: - Manual Curriculum (key = "weekday|period")

    var manualCurriculum: [String: String] {
        get {
            guard let data = userDefaults.data(forKey: CacheKey.manualCurriculum.rawValue),
                  let dict = try? JSONDecoder().decode([String: String].self, from: data)
            else { return [:] }
            return dict
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                userDefaults.set(data, forKey: CacheKey.manualCurriculum.rawValue)
                sharedDefaults?.set(data, forKey: CacheKey.manualCurriculum.rawValue)
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    var manualPeriodTimes: [String: PeriodTime] {
        get {
            guard let data = userDefaults.data(forKey: CacheKey.manualPeriodTimes.rawValue),
                  let dict = try? JSONDecoder().decode([String: PeriodTime].self, from: data)
            else { return [:] }
            return dict
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                userDefaults.set(data, forKey: CacheKey.manualPeriodTimes.rawValue)
                sharedDefaults?.set(data, forKey: CacheKey.manualPeriodTimes.rawValue)
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    // MARK: - Curriculum Sharing

    var isCurriculumSharing: Bool {
        get { userDefaults.bool(forKey: CacheKey.isCurriculumSharing.rawValue) }
        set { userDefaults.set(newValue, forKey: CacheKey.isCurriculumSharing.rawValue) }
    }

    // MARK: - 追蹤名單
    var followedUsernames: [String] {
        get { userDefaults.array(forKey: CacheKey.followedUsernames.rawValue) as? [String] ?? [] }
        set {
            userDefaults.set(newValue, forKey: CacheKey.followedUsernames.rawValue)
            // 同步到 App Group 供 Watch 讀取
            sharedDefaults?.set(newValue, forKey: CacheKey.followedUsernames.rawValue)
        }
    }

    // MARK: - Manual Room/Teacher (key = "weekday|period")

    var manualRoomTeacher: [String: CourseExtra] {
        get {
            guard let data = userDefaults.data(forKey: CacheKey.manualRoomTeacher.rawValue),
                  let dict = try? JSONDecoder().decode([String: CourseExtra].self, from: data)
            else { return [:] }
            return dict
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                userDefaults.set(data, forKey: CacheKey.manualRoomTeacher.rawValue)
                sharedDefaults?.set(data, forKey: CacheKey.manualRoomTeacher.rawValue)
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    // MARK: - Onboarding
    var hasSeenOnboarding: Bool {
        get { userDefaults.bool(forKey: CacheKey.hasSeenOnboarding.rawValue) }
        set { userDefaults.set(newValue, forKey: CacheKey.hasSeenOnboarding.rawValue) }
    }

    // MARK: - Login Credentials
    var rememberCredentials: Bool {
        get { userDefaults.bool(forKey: CacheKey.rememberCredentials.rawValue) }
        set { userDefaults.set(newValue, forKey: CacheKey.rememberCredentials.rawValue) }
    }

    var savedUsername: String? {
        get { userDefaults.string(forKey: CacheKey.savedUsername.rawValue) }
        set { userDefaults.set(newValue, forKey: CacheKey.savedUsername.rawValue) }
    }

    var savedPassword: String? {
        get { userDefaults.string(forKey: CacheKey.savedPassword.rawValue) }
        set { userDefaults.set(newValue, forKey: CacheKey.savedPassword.rawValue) }
    }

    var savedSchoolCode: String? {
        get { userDefaults.string(forKey: CacheKey.savedSchoolCode.rawValue) }
        set { userDefaults.set(newValue, forKey: CacheKey.savedSchoolCode.rawValue) }
    }

    func saveLoginCredentials(username: String, password: String, schoolCode: String?) {
        savedUsername = username
        savedPassword = password
        savedSchoolCode = schoolCode
        rememberCredentials = true
        print("🔑 [Cache] 已儲存登入憑證")
    }

    func clearLoginCredentials() {
        savedUsername = nil
        savedPassword = nil
        savedSchoolCode = nil
        rememberCredentials = false
        print("🔑 [Cache] 已清除登入憑證")
    }

    // MARK: - Cookies Persistence
    func saveCookies(_ cookies: [HTTPCookie]) {
        let props = cookies.compactMap { $0.properties }
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: props, requiringSecureCoding: false) {
            userDefaults.set(data, forKey: CacheKey.savedCookies.rawValue)
            print("🍪 [Cache] 已儲存 \(cookies.count) 個 cookies")
        }
    }

    func loadCookies() -> [HTTPCookie] {
        guard let data = userDefaults.data(forKey: CacheKey.savedCookies.rawValue),
              let props = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? [[HTTPCookiePropertyKey: Any]] else {
            return []
        }
        let cookies = props.compactMap { HTTPCookie(properties: $0) }
        print("🍪 [Cache] 載入 \(cookies.count) 個 cookies")
        return cookies
    }

    func clearCookies() {
        userDefaults.removeObject(forKey: CacheKey.savedCookies.rawValue)
        print("🍪 [Cache] 已清除 cookies")
    }

    // MARK: - VocPass Auth Cookies
    func saveVocPassCookies(_ cookies: [HTTPCookie]) {
        let props = cookies.compactMap { $0.properties }
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: props, requiringSecureCoding: false) {
            userDefaults.set(data, forKey: CacheKey.vocPassCookies.rawValue)
            print("🍪 [Cache] 已儲存 \(cookies.count) 個 VocPass cookies")
        }
    }

    func loadVocPassCookies() -> [HTTPCookie] {
        guard let data = userDefaults.data(forKey: CacheKey.vocPassCookies.rawValue),
              let props = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? [[HTTPCookiePropertyKey: Any]] else {
            return []
        }
        let cookies = props.compactMap { HTTPCookie(properties: $0) }
        print("🍪 [Cache] 載入 \(cookies.count) 個 VocPass cookies")
        return cookies
    }

    func clearVocPassCookies() {
        userDefaults.removeObject(forKey: CacheKey.vocPassCookies.rawValue)
        print("🍪 [Cache] 已清除 VocPass cookies")
    }

    // MARK: - Curriculum Cache
    func getCachedCurriculum() -> [String: CourseInfo]? {
        guard let timestamp = userDefaults.object(forKey: CacheKey.curriculumTimestamp.rawValue) as? Date else {
            print("📦 [Cache] No curriculum timestamp found")
            return nil
        }

        // Check if cache is expired
        if Date().timeIntervalSince(timestamp) > cacheExpirationInterval {
            print("📦 [Cache] Curriculum cache expired")
            clearCurriculumCache()
            return nil
        }

        guard let data = userDefaults.data(forKey: CacheKey.curriculum.rawValue) else {
            print("📦 [Cache] No curriculum data found")
            return nil
        }

        do {
            let curriculum = try JSONDecoder().decode([String: CourseInfo].self, from: data)
            print("📦 [Cache] Loaded curriculum from cache (\(curriculum.count) courses)")
            return curriculum
        } catch {
            print("📦 [Cache] Failed to decode curriculum: \(error)")
            clearCurriculumCache()
            return nil
        }
    }

    func cacheCurriculum(_ curriculum: [String: CourseInfo]) {
        do {
            let data = try JSONEncoder().encode(curriculum)
            userDefaults.set(data, forKey: CacheKey.curriculum.rawValue)
            userDefaults.set(Date(), forKey: CacheKey.curriculumTimestamp.rawValue)
            print("📦 [Cache] Saved curriculum to cache (\(curriculum.count) courses)")
        } catch {
            print("📦 [Cache] Failed to encode curriculum: \(error)")
        }
    }

    func clearCurriculumCache() {
        userDefaults.removeObject(forKey: CacheKey.curriculum.rawValue)
        userDefaults.removeObject(forKey: CacheKey.curriculumTimestamp.rawValue)
        print("📦 [Cache] Cleared curricul3um cache")
    }

    // MARK: - Clear All Cache
    func clearAllCache() {
        clearCurriculumCache()
        clearTimetableCache()
        print("📦 [Cache] Cleared all cache")
    }

    // MARK: - Timetable Cache
    private let timetableParserVersion = "v4"
    private let timetableParserVersionKey = "timetable_parser_version"

    func invalidateTimetableCacheIfNeeded() {
        let stored = userDefaults.string(forKey: timetableParserVersionKey) ?? ""
        if stored != timetableParserVersion {
            clearTimetableCache()
            userDefaults.set(timetableParserVersion, forKey: timetableParserVersionKey)
            print("📦 [Cache] Parser 版本更新（\(stored) → \(timetableParserVersion)），已清除舊課表快取")
        }
    }

    func getCachedTimetable() -> TimetableData? {
        guard let data = userDefaults.data(forKey: CacheKey.timetable.rawValue) else { return nil }
        do {
            let timetable = try JSONDecoder().decode(TimetableData.self, from: data)
            print("📦 [Cache] Loaded timetable (\(timetable.entries.count) entries, \(timetable.periodTimes.count) period times)")
            return timetable
        } catch {
            print("📦 [Cache] Failed to decode timetable: \(error)")
            clearTimetableCache()
            return nil
        }
    }

    func cacheTimetable(_ timetable: TimetableData) {
        do {
            let data = try JSONEncoder().encode(timetable)
            userDefaults.set(data, forKey: CacheKey.timetable.rawValue)
            sharedDefaults?.set(data, forKey: CacheKey.timetable.rawValue)
            sharedDefaults?.synchronize()
            WidgetCenter.shared.reloadAllTimelines()
            print("📦 [Cache] Saved timetable (\(timetable.entries.count) entries, \(data.count) bytes to widget)")
        } catch {
            print("📦 [Cache] Failed to encode timetable: \(error)")
        }
    }

    func clearTimetableCache() {
        userDefaults.removeObject(forKey: CacheKey.timetable.rawValue)
        print("📦 [Cache] Cleared timetable cache")
    }

    // MARK: - Widget Sync

    /// 將已快取的課表同步到 App Group 共享容器，讓 widget 可以讀取。
    func syncTimetableToWidget() {
        guard let shared = sharedDefaults else {
            print("📦 [Cache] ⚠️ 無法取得 App Group UserDefaults，Widget 同步失敗")
            return
        }
        guard let data = userDefaults.data(forKey: CacheKey.timetable.rawValue) else {
            print("📦 [Cache] 沒有課表資料可同步到 Widget")
            return
        }
        shared.set(data, forKey: CacheKey.timetable.rawValue)

        if let manualData = userDefaults.data(forKey: CacheKey.manualCurriculum.rawValue) {
            shared.set(manualData, forKey: CacheKey.manualCurriculum.rawValue)
        }
        if let periodData = userDefaults.data(forKey: CacheKey.manualPeriodTimes.rawValue) {
            shared.set(periodData, forKey: CacheKey.manualPeriodTimes.rawValue)
        }
        if let rtData = userDefaults.data(forKey: CacheKey.manualRoomTeacher.rawValue) {
            shared.set(rtData, forKey: CacheKey.manualRoomTeacher.rawValue)
        }

        shared.synchronize()
        WidgetCenter.shared.reloadAllTimelines()
        print("📦 [Cache] 已同步課表到 Widget（\(data.count) bytes）")
    }

    // MARK: - Cache Info
    func getCurriculumCacheAge() -> TimeInterval? {
        guard let timestamp = userDefaults.object(forKey: CacheKey.curriculumTimestamp.rawValue) as? Date else {
            return nil
        }
        return Date().timeIntervalSince(timestamp)
    }

}
