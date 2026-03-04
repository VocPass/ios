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
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
