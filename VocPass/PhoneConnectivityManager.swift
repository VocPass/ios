//
//  PhoneConnectivityManager.swift
//  VocPass
//
//  負責將課表及追蹤名單推送到 Apple Watch。
//

import Combine
import Foundation
import WatchConnectivity

// MARK: - Message Keys & Actions (iPhone side copy)

private enum MsgKey {
    static let action              = "action"
    static let username            = "username"
    static let timetableData       = "timetableData"
    static let followedUsernames   = "followedUsernames"
    static let sharedTimetableData = "sharedTimetableData"
    static let sharedUsername      = "sharedUsername"
    static let error               = "error"
}

private enum MsgAction {
    static let requestRefresh         = "requestRefresh"
    static let requestSharedTimetable = "requestSharedTimetable"
    static let pushTimetable          = "pushTimetable"
    static let pushSharedTimetable    = "pushSharedTimetable"
    static let pushFollowedUsernames  = "pushFollowedUsernames"
}

// MARK: - PhoneConnectivityManager

@MainActor
class PhoneConnectivityManager: NSObject, ObservableObject {
    static let shared = PhoneConnectivityManager()

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Push to Watch

    func pushTimetable(_ timetable: TimetableData? = nil) {
        guard WCSession.default.activationState == .activated else { return }
        let base = timetable
            ?? CacheService.shared.getCachedTimetable()
            ?? TimetableData(entries: [], periodTimes: [:], curriculum: [:])
        guard let data = try? JSONEncoder().encode(mergedTimetable(base)) else { return }

        try? WCSession.default.updateApplicationContext([
            MsgKey.timetableData: data,
            MsgKey.followedUsernames: CacheService.shared.followedUsernames
        ])
        WCSession.default.transferUserInfo([
            MsgKey.action: MsgAction.pushTimetable,
            MsgKey.timetableData: data
        ])
        syncFollowedUsernamesToAppGroup()
    }

    func pushFollowedUsernames(_ usernames: [String]) {
        guard WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo([
            MsgKey.action: MsgAction.pushFollowedUsernames,
            MsgKey.followedUsernames: usernames
        ])
        syncFollowedUsernamesToAppGroup()
    }

    func pushSharedTimetable(_ timetable: TimetableData, for username: String) {
        guard WCSession.default.activationState == .activated else { return }
        guard let data = try? JSONEncoder().encode(timetable) else { return }

        UserDefaults(suiteName: kSharedAppGroupID)?.set(data, forKey: "watch_shared_\(username)")

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(
                [MsgKey.action: MsgAction.pushSharedTimetable,
                 MsgKey.sharedUsername: username,
                 MsgKey.sharedTimetableData: data],
                replyHandler: nil, errorHandler: nil
            )
        } else {
            WCSession.default.transferUserInfo([
                MsgKey.action: MsgAction.pushSharedTimetable,
                MsgKey.sharedUsername: username,
                MsgKey.sharedTimetableData: data
            ])
        }
    }

    // MARK: - Merge manual overrides before sending to Watch

    private func mergedTimetable(_ timetable: TimetableData) -> TimetableData {
        let manualSubjects = CacheService.shared.manualCurriculum   // ["weekday|period": subject]
        let manualExtras   = CacheService.shared.manualRoomTeacher  // ["weekday|period": CourseExtra]

        var entries = timetable.entries.map { entry -> TimetableEntry in
            let key = "\(entry.weekday)|\(entry.period)"
            let subject = manualSubjects[key].flatMap { $0.isEmpty ? nil : $0 } ?? entry.subject
            let room    = manualExtras[key]?.room    ?? entry.room
            let teacher = manualExtras[key]?.teacher ?? entry.teacher
            return TimetableEntry(weekday: entry.weekday, period: entry.period,
                                  subject: subject, room: room, teacher: teacher)
        }

        // 補上手動新增但 API 沒有的節次
        for (key, subject) in manualSubjects where !subject.isEmpty {
            let parts = key.split(separator: "|")
            guard parts.count == 2 else { continue }
            let weekday = String(parts[0]), period = String(parts[1])
            if !entries.contains(where: { $0.weekday == weekday && $0.period == period }) {
                let extra = manualExtras[key]
                entries.append(TimetableEntry(weekday: weekday, period: period, subject: subject,
                                              room: extra?.room, teacher: extra?.teacher))
            }
        }

        return TimetableData(entries: entries,
                             periodTimes: timetable.periodTimes,
                             curriculum: timetable.curriculum)
    }

    // MARK: - App Group Sync

    private func syncFollowedUsernamesToAppGroup() {
        UserDefaults(suiteName: kSharedAppGroupID)?.set(
            CacheService.shared.followedUsernames,
            forKey: "followed_usernames"
        )
    }
}

// MARK: - WCSessionDelegate

extension PhoneConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in self.onActivated() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        guard let action = message[MsgKey.action] as? String else {
            replyHandler([:]); return
        }
        switch action {
        case MsgAction.requestRefresh:
            Task { @MainActor in await self.handleRefreshRequest(replyHandler: replyHandler) }
        case MsgAction.requestSharedTimetable:
            let username = message[MsgKey.username] as? String ?? ""
            Task { @MainActor in
                await self.handleSharedTimetableRequest(username: username, replyHandler: replyHandler)
            }
        default:
            replyHandler([:])
        }
    }

    // MARK: - Handlers

    @MainActor
    private func onActivated() {
        let timetable = CacheService.shared.getCachedTimetable()
            ?? TimetableData(entries: [], periodTimes: [:], curriculum: [:])
        pushTimetable(timetable)
        syncFollowedUsernamesToAppGroup()
    }

    @MainActor
    private func handleRefreshRequest(replyHandler: @escaping ([String: Any]) -> Void) async {
        let base = CacheService.shared.getCachedTimetable()
            ?? TimetableData(entries: [], periodTimes: [:], curriculum: [:])
        let merged = mergedTimetable(base)
        guard let data = try? JSONEncoder().encode(merged) else {
            replyHandler([:]); return
        }
        replyHandler([MsgKey.timetableData: data,
                      MsgKey.followedUsernames: CacheService.shared.followedUsernames])
        syncFollowedUsernamesToAppGroup()
    }

    @MainActor
    private func handleSharedTimetableRequest(username: String,
                                              replyHandler: @escaping ([String: Any]) -> Void) async {
        do {
            let timetable = try await APIService.shared.fetchSharedCurriculum(username: username)
            guard let data = try? JSONEncoder().encode(timetable) else {
                replyHandler([MsgKey.error: "encode failed"]); return
            }
            UserDefaults(suiteName: kSharedAppGroupID)?.set(data, forKey: "watch_shared_\(username)")
            replyHandler([MsgKey.sharedTimetableData: data])
        } catch {
            replyHandler([MsgKey.error: error.localizedDescription])
        }
    }
}
