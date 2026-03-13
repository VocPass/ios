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
    let currentStartTime: Date?
    let currentEndTime: Date?
    let nextPeriod: String
    let nextSubject: String
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
            currentStartTime: context.state.currentStartTime,
            currentEndTime: context.state.currentEndTime,
            nextPeriod: context.state.nextPeriod,
            nextSubject: context.state.nextSubject,
            nextStartTime: context.state.nextStartTime
        )
    }

    if let current = slots.first(where: { now >= $0.startTime && now < $0.endTime }) {
        let next = slots.first(where: { $0.startTime > current.endTime })
        return ResolvedScheduleState(
            currentPeriod: current.period,
            currentSubject: current.subject,
            currentStartTime: current.startTime,
            currentEndTime: current.endTime,
            nextPeriod: next?.period ?? "",
            nextSubject: next?.subject ?? "",
            nextStartTime: next?.startTime
        )
    }

    let next = slots.first(where: { $0.startTime > now })
    return ResolvedScheduleState(
        currentPeriod: "",
        currentSubject: "",
        currentStartTime: nil,
        currentEndTime: nil,
        nextPeriod: next?.period ?? "",
        nextSubject: next?.subject ?? "",
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
                    Text("第\(s.currentPeriod)節")
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

                VStack(alignment: .trailing, spacing: 4) {
                    Text("下一堂")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(s.nextSubject)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
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
        VStack(alignment: .leading, spacing: 2) {
            if s.currentSubject.isEmpty {
                Label("下課中", systemImage: "cup.and.heat.waves.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let nextStart = s.nextStartTime {
                    HStack(spacing: 2) {
                        Image(systemName: "timer")
                            .font(.system(size: 9))
                        Text(nextStart, style: .timer)
                            .font(.system(size: 11))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.green)
                }
            } else {
                Label {
                    Text("VocPass")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "book.fill")
                        .foregroundStyle(.blue)
                }
                if let endTime = s.currentEndTime {
                    HStack(spacing: 2) {
                        Image(systemName: "timer")
                            .font(.system(size: 9))
                        Text(endTime, style: .timer)
                            .font(.system(size: 11))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.orange)
                }
            }
        }
        .padding(.leading, 4)
    }
}

private struct ExpandedTrailingView: View {
    let context: ActivityViewContext<ClassScheduleActivityAttributes>

    var body: some View {
        let s = resolveScheduleState(from: context)
        VStack(alignment: .trailing, spacing: 2) {
            if s.nextSubject.isEmpty {
                Text("放學囉！")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("→ 下一堂")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(s.nextSubject)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                if let startTime = s.nextStartTime {
                    Text(startTime, style: .time)
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.trailing, 4)
    }
}

private struct ExpandedBottomView: View {
    let context: ActivityViewContext<ClassScheduleActivityAttributes>

    var body: some View {
        let s = resolveScheduleState(from: context)
        if !s.currentSubject.isEmpty,
           let endTime = s.currentEndTime {
            HStack {
                Text("第\(s.currentPeriod)節  \(s.currentSubject)")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Text(endTime, style: .time)
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("下課")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
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
        if let start = s.currentStartTime,
           let end   = s.currentEndTime {
            let total   = end.timeIntervalSince(start)
            let elapsed = min(max(Date().timeIntervalSince(start), 0), total)
            let pct     = total > 0 ? elapsed / total : 0.0
            Gauge(value: pct) {
            } currentValueLabel: {
                Image(systemName: "book.fill")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(Color.blue)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(Color.orange)
            .scaleEffect(0.7)
        } else {
                        Image(systemName: s.nextSubject.isEmpty
                  ? "checkmark.circle" : "cup.and.heat.waves.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.secondary)
        }
    }
}

// MARK: - Preview

#Preview("Notification", as: .content, using: ClassScheduleActivityAttributes(className: "訊三孝")) {
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
                endTime: Date().addingTimeInterval(12 * 60)
            ),
            .init(
                period: "四",
                subject: "選修跨班",
                startTime: Date().addingTimeInterval(22 * 60),
                endTime: Date().addingTimeInterval(70 * 60)
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
                endTime: Date().addingTimeInterval(68 * 60)
            )
        ]
    )
}
