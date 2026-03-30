//
//  WatchFollowingView.swift
//  VocPassWatch
//

import SwiftUI

struct WatchFollowingView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager

    var body: some View {
        if connectivity.followedUsernames.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "person.2.slash")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("尚無追蹤對象")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("請在 iPhone 新增")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .navigationTitle("追蹤的同學")
        } else {
            List(connectivity.followedUsernames, id: \.self) { username in
                NavigationLink {
                    WatchSharedTimetableView(username: username)
                        .environmentObject(connectivity)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.circle.fill")
                            .foregroundStyle(.blue)
                        Text("@\(username)")
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("追蹤的同學")
        }
    }
}
