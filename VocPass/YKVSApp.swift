//
//  YKVSApp.swift
//  YKVS
//
//  Created by Hans on 2025/12/31.
//

import BackgroundTasks
import SwiftUI

@main
struct YKVSApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        SchoolConfigManager.shared.loadSchools()
        CacheService.shared.invalidateTimetableCacheIfNeeded()

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: kDIBGTaskID,
            using: nil
        ) { task in
            Task { @MainActor in
                DynamicIslandService.shared.handleBackgroundRefresh(task as! BGAppRefreshTask)
            }
        }

        if let cachedTimetable = CacheService.shared.getCachedTimetable() {
            Task { @MainActor in
                DynamicIslandService.shared.setTimetable(cachedTimetable)
            }
        } else {
            Task { @MainActor in
                DynamicIslandService.shared.reconnectIfNeeded()
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
    }

    // MARK: - Scene Phase

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        Task { @MainActor in
            let di = DynamicIslandService.shared
            switch phase {
            case .active:
                di.reconnectIfNeeded()
                if di.isActivityRunning {
                    di.updateActivity()
                    if di.currentSubject.isEmpty && di.nextSubject.isEmpty {
                        di.endActivity()
                    }
                } else {
                    di.autoStartIfNeeded()
                }
            case .background:
                di.scheduleNextBGRefresh()
            default:
                break
            }
        }
    }
}
