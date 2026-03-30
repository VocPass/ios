//
//  VocPassWatchApp.swift
//  VocPassWatch
//

import SwiftUI

@main
struct VocPassWatchApp: App {
    @StateObject private var connectivity = WatchConnectivityManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connectivity)
        }
    }
}
