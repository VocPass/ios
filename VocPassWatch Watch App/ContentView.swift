//
//  ContentView.swift
//  VocPassWatch
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    MyTimetableView()
                        .environmentObject(connectivity)
                } label: {
                    Label("我的課表", systemImage: "calendar")
                }

                NavigationLink {
                    WatchFollowingView()
                        .environmentObject(connectivity)
                } label: {
                    Label("追蹤的同學", systemImage: "person.2")
                }
            }
            .navigationTitle("VocPass")
            .onAppear {
                connectivity.requestRefresh()
            }
        }
    }
}
