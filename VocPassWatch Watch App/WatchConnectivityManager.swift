//
//  WatchConnectivityManager.swift
//  VocPassWatch
//

import Combine
import Foundation
import WatchConnectivity

// MARK: - Message Keys (共用於 iOS & Watch)

enum WatchMessageKey {
    static let action              = "action"
    static let username            = "username"
    static let timetableData       = "timetableData"
    static let followedUsernames   = "followedUsernames"
    static let sharedTimetableData = "sharedTimetableData"
    static let sharedUsername      = "sharedUsername"
    static let error               = "error"
}

enum WatchAction {
    static let requestRefresh         = "requestRefresh"
    static let requestSharedTimetable = "requestSharedTimetable"
    static let pushTimetable          = "pushTimetable"
    static let pushSharedTimetable    = "pushSharedTimetable"
    static let pushFollowedUsernames  = "pushFollowedUsernames"
}

// MARK: - WatchConnectivityManager (Watch side)

@MainActor
class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published var ownTimetable: TimetableData?
    @Published var followedUsernames: [String] = []
    @Published var sharedTimetables: [String: TimetableData] = [:]
    @Published var pendingRequests: Set<String> = []   // usernames being fetched

    private override init() {
        super.init()
        // Load cached data immediately
        ownTimetable = WatchCacheService.shared.getOwnTimetable()
        followedUsernames = WatchCacheService.shared.followedUsernames
        for username in followedUsernames {
            if let t = WatchCacheService.shared.getSharedTimetable(for: username) {
                sharedTimetables[username] = t
            }
        }
        activateSession()
    }

    private func activateSession() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Request Data from Phone

    func requestRefresh() {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            [WatchMessageKey.action: WatchAction.requestRefresh],
            replyHandler: { [weak self] reply in
                Task { @MainActor in
                    self?.handleApplicationContext(reply)
                }
            },
            errorHandler: nil
        )
    }

    func requestSharedTimetable(for username: String) {
        pendingRequests.insert(username)
        guard WCSession.default.isReachable else {
            pendingRequests.remove(username)
            return
        }
        WCSession.default.sendMessage(
            [WatchMessageKey.action: WatchAction.requestSharedTimetable,
             WatchMessageKey.username: username],
            replyHandler: { [weak self] reply in
                Task { @MainActor in
                    self?.handleSharedTimetableReply(reply, username: username)
                }
            },
            errorHandler: { [weak self] _ in
                Task { @MainActor in
                    self?.pendingRequests.remove(username)
                }
            }
        )
    }

    // MARK: - Handle Incoming Data

    private func handleApplicationContext(_ context: [String: Any]) {
        if let data = context[WatchMessageKey.timetableData] as? Data,
           let timetable = try? JSONDecoder().decode(TimetableData.self, from: data) {
            ownTimetable = timetable
            WatchCacheService.shared.saveOwnTimetable(timetable)
        }
        if let usernames = context[WatchMessageKey.followedUsernames] as? [String] {
            followedUsernames = usernames
            WatchCacheService.shared.followedUsernames = usernames
        }
    }

    private func handleUserInfo(_ info: [String: Any]) {
        if let action = info[WatchMessageKey.action] as? String {
            switch action {
            case WatchAction.pushTimetable:
                if let data = info[WatchMessageKey.timetableData] as? Data,
                   let timetable = try? JSONDecoder().decode(TimetableData.self, from: data) {
                    ownTimetable = timetable
                    WatchCacheService.shared.saveOwnTimetable(timetable)
                }
            case WatchAction.pushSharedTimetable:
                if let username = info[WatchMessageKey.sharedUsername] as? String,
                   let data = info[WatchMessageKey.sharedTimetableData] as? Data,
                   let timetable = try? JSONDecoder().decode(TimetableData.self, from: data) {
                    sharedTimetables[username] = timetable
                    WatchCacheService.shared.saveSharedTimetable(timetable, for: username)
                    pendingRequests.remove(username)
                }
            case WatchAction.pushFollowedUsernames:
                if let usernames = info[WatchMessageKey.followedUsernames] as? [String] {
                    followedUsernames = usernames
                    WatchCacheService.shared.followedUsernames = usernames
                }
            default:
                break
            }
        }
    }

    private func handleSharedTimetableReply(_ reply: [String: Any], username: String) {
        pendingRequests.remove(username)
        guard let data = reply[WatchMessageKey.sharedTimetableData] as? Data,
              let timetable = try? JSONDecoder().decode(TimetableData.self, from: data)
        else { return }
        sharedTimetables[username] = timetable
        WatchCacheService.shared.saveSharedTimetable(timetable, for: username)
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {}

    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.handleApplicationContext(applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in
            self.handleUserInfo(userInfo)
        }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        replyHandler([:])
    }
}
