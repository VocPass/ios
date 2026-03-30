//
//  WatchSharedTimetableView.swift
//  VocPassWatch
//

import SwiftUI

struct WatchSharedTimetableView: View {
    let username: String
    @EnvironmentObject var connectivity: WatchConnectivityManager
    private let today = currentWatchWeekday()

    private var timetable: TimetableData? { connectivity.sharedTimetables[username] }
    private var isPending: Bool { connectivity.pendingRequests.contains(username) }

    var body: some View {
        Group {
            if let timetable {
                List(watchWeekdays, id: \.self) { day in
                    let entries = entriesForDay(day, from: timetable)
                    NavigationLink {
                        DayTimetableView(day: day, entries: entries)
                    } label: {
                        DayRowLabel(day: day, isToday: day == today)
                    }
                    .listRowBackground(
                        day == today
                        ? RoundedRectangle(cornerRadius: 10)
                            .fill(Color.blue.opacity(0.25))
                        : nil
                    )
                }
            } else if isPending {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("載入中…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.clockwise.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("點擊重新載入")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .onTapGesture {
                    connectivity.requestSharedTimetable(for: username)
                }
            }
        }
        .navigationTitle("@\(username)")
        .onAppear {
            if timetable == nil {
                connectivity.requestSharedTimetable(for: username)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    connectivity.requestSharedTimetable(for: username)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isPending)
            }
        }
    }

    private func entriesForDay(_ day: String, from timetable: TimetableData) -> [TimetableEntry] {
        timetable.entries
            .filter { $0.weekday == day }
            .sorted { periodOrder($0.period) < periodOrder($1.period) }
    }
}
