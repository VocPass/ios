//
//  YKVSApp.swift
//  YKVS
//
//  Created by Hans on 2025/12/31.
//

import SwiftUI

@main
struct YKVSApp: App {
    init() {
        SchoolConfigManager.shared.loadSchools()
        CacheService.shared.invalidateTimetableCacheIfNeeded()

        if CacheService.shared.autoStartDynamicIsland,
           let cachedTimetable = CacheService.shared.getCachedTimetable() {
            Task { @MainActor in
                DynamicIslandService.shared.setTimetable(cachedTimetable)
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
