//
//  CacheService.swift
//  YKVS
//
//  Created by Hans on 2025/12/31.
//

import Foundation

class CacheService {
    static let shared = CacheService()

    private let userDefaults = UserDefaults.standard
    private let cacheExpirationInterval: TimeInterval = 24 * 60 * 60 // 1 day in seconds

    // MARK: - Cache Keys
    private enum CacheKey: String {
        case curriculum = "cached_curriculum"
        case curriculumTimestamp = "cached_curriculum_timestamp"
        case timetable = "cached_timetable"
        case timetableTimestamp = "cached_timetable_timestamp"
        case examMenu = "cached_exam_menu"
        case examMenuTimestamp = "cached_exam_menu_timestamp"
        case hasSeenOnboarding = "has_seen_onboarding"
        case savedUsername = "saved_username"
        case savedPassword = "saved_password"
        case savedSchoolCode = "saved_school_code"
        case rememberCredentials = "remember_credentials"
        case autoStartDynamicIsland = "auto_start_dynamic_island"
        case autoStartMinutesBefore = "auto_start_minutes_before"
        case savedClassName = "saved_class_name"
    }

    // MARK: - Dynamic Island Settings

    var autoStartDynamicIsland: Bool {
        get { userDefaults.bool(forKey: CacheKey.autoStartDynamicIsland.rawValue) }
        set { userDefaults.set(newValue, forKey: CacheKey.autoStartDynamicIsland.rawValue) }
    }

    var autoStartMinutesBefore: Int {
        get {
            let v = userDefaults.integer(forKey: CacheKey.autoStartMinutesBefore.rawValue)
            return v == 0 ? 30 : v
        }
        set { userDefaults.set(newValue, forKey: CacheKey.autoStartMinutesBefore.rawValue) }
    }

    var savedClassName: String {
        get { userDefaults.string(forKey: CacheKey.savedClassName.rawValue) ?? "" }
        set { userDefaults.set(newValue, forKey: CacheKey.savedClassName.rawValue) }
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

    // MARK: - Exam Menu Cache
    func getCachedExamMenu() -> [ExamMenuItem]? {
        guard let timestamp = userDefaults.object(forKey: CacheKey.examMenuTimestamp.rawValue) as? Date else {
            print("📦 [Cache] No exam menu timestamp found")
            return nil
        }

        // Check if cache is expired
        if Date().timeIntervalSince(timestamp) > cacheExpirationInterval {
            print("📦 [Cache] Exam menu cache expired")
            clearExamMenuCache()
            return nil
        }

        guard let data = userDefaults.data(forKey: CacheKey.examMenu.rawValue) else {
            print("📦 [Cache] No exam menu data found")
            return nil
        }

        do {
            let examMenu = try JSONDecoder().decode([ExamMenuItem].self, from: data)
            print("📦 [Cache] Loaded exam menu from cache (\(examMenu.count) items)")
            return examMenu
        } catch {
            print("📦 [Cache] Failed to decode exam menu: \(error)")
            clearExamMenuCache()
            return nil
        }
    }

    func cacheExamMenu(_ examMenu: [ExamMenuItem]) {
        do {
            let data = try JSONEncoder().encode(examMenu)
            userDefaults.set(data, forKey: CacheKey.examMenu.rawValue)
            userDefaults.set(Date(), forKey: CacheKey.examMenuTimestamp.rawValue)
            print("📦 [Cache] Saved exam menu to cache (\(examMenu.count) items)")
        } catch {
            print("📦 [Cache] Failed to encode exam menu: \(error)")
        }
    }

    func clearExamMenuCache() {
        userDefaults.removeObject(forKey: CacheKey.examMenu.rawValue)
        userDefaults.removeObject(forKey: CacheKey.examMenuTimestamp.rawValue)
        print("📦 [Cache] Cleared exam menu cache")
    }

    // MARK: - Clear All Cache
    func clearAllCache() {
        clearCurriculumCache()
        clearTimetableCache()
        clearExamMenuCache()
        print("📦 [Cache] Cleared all cache")
    }

    // MARK: - Timetable Cache
    private let timetableParserVersion = "v3"
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
        guard let timestamp = userDefaults.object(forKey: CacheKey.timetableTimestamp.rawValue) as? Date else {
            return nil
        }
        if Date().timeIntervalSince(timestamp) > cacheExpirationInterval {
            clearTimetableCache()
            return nil
        }
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
            userDefaults.set(Date(), forKey: CacheKey.timetableTimestamp.rawValue)
            print("📦 [Cache] Saved timetable (\(timetable.entries.count) entries)")
        } catch {
            print("📦 [Cache] Failed to encode timetable: \(error)")
        }
    }

    func clearTimetableCache() {
        userDefaults.removeObject(forKey: CacheKey.timetable.rawValue)
        userDefaults.removeObject(forKey: CacheKey.timetableTimestamp.rawValue)
        print("📦 [Cache] Cleared timetable cache")
    }

    // MARK: - Cache Info
    func getCurriculumCacheAge() -> TimeInterval? {
        guard let timestamp = userDefaults.object(forKey: CacheKey.curriculumTimestamp.rawValue) as? Date else {
            return nil
        }
        return Date().timeIntervalSince(timestamp)
    }

    func getExamMenuCacheAge() -> TimeInterval? {
        guard let timestamp = userDefaults.object(forKey: CacheKey.examMenuTimestamp.rawValue) as? Date else {
            return nil
        }
        return Date().timeIntervalSince(timestamp)
    }
}
