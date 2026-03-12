//
//  ClassScheduleWidget.swift
//  VocPassWidget
//
//  Dynamic Island / Live Activity 的顯示介面。
//

import ActivityKit
import SwiftUI
import WidgetKit

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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text(context.state.currentSubject.isEmpty ? "下課中" : context.state.currentSubject)
                        .font(.headline)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "book.closed.fill")
                        .foregroundStyle(.blue)
                }
                if !context.state.currentPeriod.isEmpty {
                    Text("第\(context.state.currentPeriod)節")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let endTime = context.state.currentEndTime {
                    HStack(spacing: 2) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text(endTime, style: .time)
                            .font(.caption)
                        Text("下課")
                            .font(.caption)
                    }
                    .foregroundStyle(.orange)
                }
            }

            Spacer()

            if !context.state.nextSubject.isEmpty {
                Divider().frame(height: 44)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("下一堂")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(context.state.nextSubject)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if let startTime = context.state.nextStartTime {
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
        VStack(alignment: .leading, spacing: 2) {
            if context.state.currentSubject.isEmpty {
                Label("下課中", systemImage: "cup.and.heat.waves.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                if let endTime = context.state.currentEndTime {
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
        VStack(alignment: .trailing, spacing: 2) {
            if context.state.nextSubject.isEmpty {
                Text("放學囉！")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("→ 下一堂")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(context.state.nextSubject)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                if let startTime = context.state.nextStartTime {
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
        if !context.state.currentSubject.isEmpty,
           let endTime = context.state.currentEndTime {
            HStack {
                Text("第\(context.state.currentPeriod)節  \(context.state.currentSubject)")
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
        Image(systemName: context.state.currentSubject.isEmpty
              ? "cup.and.heat.waves.fill" : "book.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(context.state.currentSubject.isEmpty ? Color.secondary : Color.blue)
            .padding(.leading, 4)
    }
}

private struct CompactTrailingView: View {
    let context: ActivityViewContext<ClassScheduleActivityAttributes>

    var body: some View {
        if let end = context.state.currentEndTime {
            Text(end, style: .timer)
                .frame(maxWidth: .minimum(50, 50), alignment: .leading)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.orange)
                .padding(.trailing, 4)
        } else if let nextStart = context.state.nextStartTime {
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
        if let start = context.state.currentStartTime,
           let end   = context.state.currentEndTime {
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
            Image(systemName: context.state.nextSubject.isEmpty
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
        nextStartTime: Date().addingTimeInterval(22 * 60)
    )
    ClassScheduleActivityAttributes.ContentState(
        currentPeriod: "",
        currentSubject: "",
        currentStartTime: nil,
        currentEndTime: nil,
        nextPeriod: "五",
        nextSubject: "統整數學",
        nextStartTime: Date().addingTimeInterval(18 * 60)
    )
}
