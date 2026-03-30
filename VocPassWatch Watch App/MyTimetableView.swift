//
//  MyTimetableView.swift
//  VocPassWatch
//

import SwiftUI

// MARK: - 選擇星期

struct MyTimetableView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager
    private let today = currentWatchWeekday()

    var body: some View {
        Group {
            if let timetable = connectivity.ownTimetable {
                List(watchWeekdays, id: \.self) { day in
                    let entries = WatchCacheService.shared.mergedEntries(for: day, from: timetable)
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
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("請在 iPhone 開啟 VocPass")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .navigationTitle("我的課表")
    }
}

// MARK: - 日期列

struct DayRowLabel: View {
    let day: String
    let isToday: Bool

    private let dayNames = ["一": "星期一", "二": "星期二", "三": "星期三", "四": "星期四", "五": "星期五"]

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isToday ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 32, height: 32)
                Text(day)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(dayNames[day] ?? "週\(day)")
                .font(.body)
                .fontWeight(isToday ? .semibold : .regular)
            if isToday {
                Spacer()
                Text("今天")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 單日全螢幕課表

struct DayTimetableView: View {
    let day: String
    let entries: [TimetableEntry]
    private let dayNames = ["一": "星期一", "二": "星期二", "三": "星期三", "四": "星期四", "五": "星期五"]

    var body: some View {
        Group {
            if entries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "sun.horizon")
                        .font(.system(size: 32))
                        .foregroundStyle(.orange.opacity(0.7))
                    Text("這天沒有課")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                List(entries) { entry in
                    DayEntryCard(entry: entry)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
                .listStyle(.carousel)
            }
        }
        .navigationTitle(dayNames[day] ?? "週\(day)")
    }
}

// MARK: - 課程卡片

struct DayEntryCard: View {
    let entry: TimetableEntry

    var accentColor: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .mint]
        let hash = abs(entry.subject.hashValue)
        return colors[hash % colors.count]
    }

    var body: some View {
        HStack(spacing: 8) {
            // 左側色條
            RoundedRectangle(cornerRadius: 3)
                .fill(accentColor)
                .frame(width: 4)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.subject)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                    Spacer()
                    Text("第\(entry.period)節")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let teacher = entry.teacher, !teacher.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "person.fill")
                            .font(.caption2)
                            .foregroundStyle(accentColor.opacity(0.8))
                        Text(teacher)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let room = entry.room, !room.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "mappin")
                            .font(.caption2)
                            .foregroundStyle(accentColor.opacity(0.8))
                        Text(room)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(accentColor.opacity(0.12))
        )
    }
}
