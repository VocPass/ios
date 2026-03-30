//
//  ContentView.swift
//  VocPassWatch
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @State private var isSyncing = false

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

                // 手動同步按鈕
                Button {
                    guard !isSyncing else { return }
                    isSyncing = true
                    connectivity.requestRefresh()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        isSyncing = false
                    }
                } label: {
                    HStack {
                        if isSyncing {
                            ProgressView()
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(.blue)
                        }
                        Text(isSyncing ? "同步中…" : "從 iPhone 同步")
                            .foregroundStyle(isSyncing ? .secondary : .primary)
                    }
                }
                .disabled(isSyncing)
            }
            .navigationTitle("VocPass")
            .onAppear {
                connectivity.requestRefresh()
            }
        }
    }
}
