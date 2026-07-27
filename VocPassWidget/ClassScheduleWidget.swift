//
//  ClassScheduleWidget.swift
//  VocPassWidget
//
//  Dynamic Island / Live Activity 的顯示介面。
//

import ActivityKit
import SwiftUI
import WidgetKit

private struct ResolvedScheduleState {
    let currentPeriod: String
    let currentSubject: String
    let currentRoom: String
    let currentTeacher: String
    let currentStartTime: Date?
    let currentEndTime: Date?
    let nextPeriod: String
    let nextSubject: String
    let nextRoom: String
    let nextTeacher: String
    let nextStartTime: Date?
}

private func resolveScheduleState(
    from context: ActivityViewContext<ClassScheduleActivityAttributes>
) -> ResolvedScheduleState {
    let now = Date()
    let slots = context.state.todaySlots.sorted { $0.startTime < $1.startTime }

    guard !slots.isEmpty else {
        return ResolvedScheduleState(
            currentPeriod: context.state.currentPeriod,
            currentSubject: context.state.currentSubject,
            currentRoom: "",
            currentTeacher: "",
            currentStartTime: context.state.currentStartTime,
            currentEndTime: context.state.currentEndTime,
            nextPeriod: context.state.nextPeriod,
            nextSubject: context.state.nextSubject,
            nextRoom: "",
            nextTeacher: "",
            nextStartTime: context.state.nextStartTime
        )
    }

    if let current = slots.first(where: { now >= $0.startTime && now < $0.endTime }) {
        let next = slots.first(where: { $0.startTime > current.endTime })
        return ResolvedScheduleState(
            currentPeriod: current.period,
            currentSubject: current.subject,
            currentRoom: current.room,
            currentTeacher: current.teacher,
            currentStartTime: current.startTime,
            currentEndTime: current.endTime,
            nextPeriod: next?.period ?? "",
            nextSubject: next?.subject ?? "",
            nextRoom: next?.room ?? "",
            nextTeacher: next?.teacher ?? "",
            nextStartTime: next?.startTime
        )
    }

    let next = slots.first(where: { $0.startTime > now })
    return ResolvedScheduleState(
        currentPeriod: "",
        currentSubject: "",
        currentRoom: "",
        currentTeacher: "",
        currentStartTime: nil,
        currentEndTime: nil,
        nextPeriod: next?.period ?? "",
        nextSubject: next?.subject ?? "",
        nextRoom: next?.room ?? "",
        nextTeacher: next?.teacher ?? "",
        nextStartTime: next?.startTime
    )
}

// MARK: - 即時動態 Widget

struct ClassScheduleWidgetLiveActivity: Widget {
    static let kind = "ClassScheduleWidget"

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClassScheduleActivityAttributes.self) { context in
            ClassScheduleLockScreenBanner(context: context)
                .activityBackgroundTint(Color(.systemBackground).opacity(0.95))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeadingView(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailingView(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottomView(context: context)
                }
            } compactLeading: {
                CompactLeadingView(context: context)
            } compactTrailing: {
                CompactTrailingView(context: context)
            } minimal: {
                MinimalView(context: context)
            }
            .keylineTint(.blue)
        }
    }
}

// MARK: - 鎖定螢幕橫幅

private struct ClassScheduleLockScreenBanner: View {
    let context: ActivityViewContext<ClassScheduleActivityAttributes>

    var body: some View {
        let s = resolveScheduleState(from: context)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text(s.currentSubject.isEmpty ? "下課中" : s.currentSubject)
                        .font(.headline)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "book.closed.fill")
                        .foregroundStyle(.blue)
                }
                if !s.currentPeriod.isEmpty {
                    let meta = [s.currentPeriod.isEmpty ? "" : "第\(s.currentPeriod)節",
                                s.currentRoom, s.currentTeacher]
                        .filter { !$0.isEmpty }.joined(separator: "・")
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let endTime = s.currentEndTime {
                    HStack(spacing: 2) {
                        Image(systemName: "timer")
                            .font(.caption2)
                        Text(endTime, style: .timer)
                            .font(.caption)
                            .monospacedDigit()
                        Text("後下課")
                            .font(.caption)
                    }
                    .foregroundStyle(.orange)
                } else if let nextStart = s.nextStartTime {
                    HStack(spacing: 2) {
                        Image(systemName: "hourglass")
                            .font(.caption2)
                        Text(nextStart, style: .timer)
                            .font(.caption)
                            .monospacedDigit()
                        Text("後上課")
                            .font(.caption)
                    }
                    .foregroundStyle(.green)
                }
            }

            Spacer()

            if !s.nextSubject.isEmpty {
                Divider().frame(height: 44)

                VStack(alignment: .trailing, spacing: 3) {
                    Text("下一堂")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(s.nextSubject)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    let nextMeta = [s.nextRoom, s.nextTeacher].filter { !$0.isEmpty }.joined(separator: "・")
                    if !nextMeta.isEmpty {
                        Text(nextMeta)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let startTime = s.nextStartTime {
                        Text(startTime, style: .time)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            } else {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("今日課程")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("已結束")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Dynamic Island 展開視圖

private struct ExpandedLeadingView: View {
    let context: ActivityViewContext<ClassScheduleActivityAttributes>

    var body: some View {
        let s = resolveScheduleState(from: context)
        let inClass = !s.currentSubject.isEmpty
        HStack(spacing: 7) {
            Image(systemName: inClass ? "book.fill" : "cup.and.heat.waves.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(inClass ? Color.blue : Color.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(inClass ? "上課中" : "下課中")
                    .font(.system(size: 13, weight: .bold))
                if inClass, !s.currentPeriod.isEmpty {
                    Text("第\(s.currentPeriod)節")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.leading, 6)
    }
}

private struct ExpandedTrailingView: View {
    let context: ActivityViewContext<ClassScheduleActivityAttributes>

    var body: some View {
        let s = resolveScheduleState(from: context)
        VStack(alignment: .trailing, spacing: 1) {
            if let end = s.currentEndTime {
                Text("距下課")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(end, style: .timer)
                    .font(.system(size: 19, weight: .bold).monospacedDigit())
                    .foregroundStyle(.orange)
                    .frame(maxWidth: 74, alignment: .trailing)
            } else if let nextStart = s.nextStartTime {
                Text("距上課")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(nextStart, style: .timer)
                    .font(.system(size: 19, weight: .bold).monospacedDigit())
                    .foregroundStyle(.green)
                    .frame(maxWidth: 74, alignment: .trailing)
            } else {
                Text("放學囉")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.trailing, 6)
    }
}

private struct ExpandedBottomView: View {
    let context: ActivityViewContext<ClassScheduleActivityAttributes>

    var body: some View {
        let s = resolveScheduleState(from: context)
        VStack(spacing: 7) {
            if !s.currentSubject.isEmpty {
                // 當節課（主角）：大科目名 + 進度條
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.currentSubject)
                            .font(.system(size: 23, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        let meta = [s.currentRoom, s.currentTeacher]
                            .filter { !$0.isEmpty }.joined(separator: " · ")
                        if !meta.isEmpty {
                            Text(meta)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    if !s.nextSubject.isEmpty {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("下一堂")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text(s.nextSubject)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            if let ns = s.nextStartTime {
                                Text(ns, style: .time)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
                if let start = s.currentStartTime, let end = s.currentEndTime {
                    VStack(spacing: 3) {
                        ProgressView(timerInterval: start...end, countsDown: false) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                        .progressViewStyle(.linear)
                        .tint(.orange)
                        HStack {
                            Text(start, style: .time)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(end, style: .time)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else if !s.nextSubject.isEmpty {
                // 下課中：預告下一堂
                HStack(spacing: 10) {
                    Image(systemName: "clock.badge.checkmark.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("即將上課 · \(s.nextSubject)")
                            .font(.system(size: 17, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        let meta = [s.nextRoom, s.nextTeacher]
                            .filter { !$0.isEmpty }.joined(separator: " · ")
                        if !meta.isEmpty {
                            Text(meta)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    if let ns = s.nextStartTime {
                        Text(ns, style: .time)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.green)
                    }
                }
            } else {
                Text("今日課程已結束")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .padding(.bottom, 6)
    }
}

// MARK: - Dynamic Island 緊湊視圖

private struct CompactLeadingView: View {
    let context: ActivityViewContext<ClassScheduleActivityAttributes>

    var body: some View {
        let s = resolveScheduleState(from: context)
        Image(systemName: s.currentSubject.isEmpty
              ? "cup.and.heat.waves.fill" : "book.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(s.currentSubject.isEmpty ? Color.secondary : Color.blue)
            .padding(.leading, 4)
    }
}

private struct CompactTrailingView: View {
    let context: ActivityViewContext<ClassScheduleActivityAttributes>

    var body: some View {
        let s = resolveScheduleState(from: context)
        if let end = s.currentEndTime {
            Text(end, style: .timer)
                .frame(maxWidth: .minimum(50, 50), alignment: .leading)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.orange)
                .padding(.trailing, 4)
        } else if let nextStart = s.nextStartTime {
            Text(nextStart, style: .timer)
                .frame(maxWidth: .minimum(50, 50), alignment: .leading)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.green)
                .padding(.trailing, 4)
        }
    }
}

// MARK: - Dynamic Island 最小化視圖

private struct MinimalView: View {
    let context: ActivityViewContext<ClassScheduleActivityAttributes>

    var body: some View {
        let s = resolveScheduleState(from: context)
        if s.currentStartTime != nil, s.currentEndTime != nil {
            Image(systemName: "book.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.blue)
        } else {
            Image(systemName: s.nextSubject.isEmpty
                  ? "checkmark.circle" : "cup.and.heat.waves.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.secondary)
        }
    }
}

// MARK: - Preview

#Preview("Notification", as: .content, using: ClassScheduleActivityAttributes()) {
    ClassScheduleWidgetLiveActivity()
} contentStates: {
    ClassScheduleActivityAttributes.ContentState(
        currentPeriod: "三",
        currentSubject: "作業系統實習",
        currentStartTime: Date().addingTimeInterval(-20 * 60),
        currentEndTime: Date().addingTimeInterval(12 * 60),
        nextPeriod: "四",
        nextSubject: "選修跨班",
        nextStartTime: Date().addingTimeInterval(22 * 60),
        todaySlots: [
            .init(
                period: "三",
                subject: "作業系統實習",
                startTime: Date().addingTimeInterval(-20 * 60),
                endTime: Date().addingTimeInterval(12 * 60),
                room: "", teacher: ""
            ),
            .init(
                period: "四",
                subject: "選修跨班",
                startTime: Date().addingTimeInterval(22 * 60),
                endTime: Date().addingTimeInterval(70 * 60),
                room: "", teacher: ""
            )
        ]
    )
    ClassScheduleActivityAttributes.ContentState(
        currentPeriod: "",
        currentSubject: "",
        currentStartTime: nil,
        currentEndTime: nil,
        nextPeriod: "五",
        nextSubject: "統整數學",
        nextStartTime: Date().addingTimeInterval(18 * 60),
        todaySlots: [
            .init(
                period: "五",
                subject: "統整數學",
                startTime: Date().addingTimeInterval(18 * 60),
                endTime: Date().addingTimeInterval(68 * 60),
                room: "", teacher: ""
            )
        ]
    )
}
