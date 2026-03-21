//
//  TimetableWidget.swift
//  VocPassWidget
//
//

import SwiftUI
import WidgetKit

// MARK: - Shared App Group Key

private let kAppGroupID = "group.com.08hans.VocPass"

// MARK: - Widget-local Model Types
// 與主 app 的 JSON 格式相容的簡化版資料型別，避免跨 target 相依。

private struct WPeriodTime: Codable {
    let startTime: String
    let endTime: String
}

private struct WTimetableEntry: Codable {
    let weekday: String
    let period: String
    let subject: String
}

private struct WTimetableData: Codable {
    let entries: [WTimetableEntry]
    let periodTimes: [String: WPeriodTime]
}

// MARK: - Schedule Slot

struct ScheduleSlot {
    let period: String
    let subject: String
    let startTime: Date
    let endTime: Date
    var isCurrent: Bool
}

// MARK: - Timeline Entry

struct TimetableWidgetEntry: TimelineEntry {
    let date: Date
    let slots: [ScheduleSlot]
    let weekdayLabel: String
    let hasTimetable: Bool
}

// MARK: - Period Constants

private let periodOrder: [String: Int] = [
    "早讀": 0,
    "一": 1, "二": 2, "三": 3, "四": 4,
    "五": 5, "六": 6, "七": 7, "八": 8, "九": 9
]

private let fallbackPeriodTimes: [String: WPeriodTime] = [
    "早讀": WPeriodTime(startTime: "07:30", endTime: "08:00"),
    "一":   WPeriodTime(startTime: "08:10", endTime: "09:00"),
    "二":   WPeriodTime(startTime: "09:10", endTime: "10:00"),
    "三":   WPeriodTime(startTime: "10:10", endTime: "11:00"),
    "四":   WPeriodTime(startTime: "11:10", endTime: "12:00"),
    "五":   WPeriodTime(startTime: "13:10", endTime: "14:00"),
    "六":   WPeriodTime(startTime: "14:10", endTime: "15:00"),
    "七":   WPeriodTime(startTime: "15:10", endTime: "16:00"),
    "八":   WPeriodTime(startTime: "16:10", endTime: "17:00"),
    "九":   WPeriodTime(startTime: "17:10", endTime: "18:00")
]

private let weekdayMap: [Int: String] = [
    1: "日", 2: "一", 3: "二", 4: "三", 5: "四", 6: "五", 7: "六"
]

// MARK: - Helpers

private func normalizePeriod(_ raw: String) -> String {
    let trimmed = raw
        .replacingOccurrences(of: "第", with: "")
        .replacingOccurrences(of: "節", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    switch trimmed {
    case "0", "０": return "早讀"
    case "1", "１": return "一"
    case "2", "２": return "二"
    case "3", "３": return "三"
    case "4", "４": return "四"
    case "5", "５": return "五"
    case "6", "６": return "六"
    case "7", "７": return "七"
    case "8", "８": return "八"
    case "9", "９": return "九"
    default: return trimmed
    }
}

private func resolvePeriodTime(for period: String, timetable: WTimetableData, manualTimes: [String: WPeriodTime]) -> WPeriodTime? {
    if let m = manualTimes[period] { return m }
    if let t = timetable.periodTimes[period] { return t }
    if let f = fallbackPeriodTimes[period] { return f }
    let n = normalizePeriod(period)
    if let m = manualTimes[n] { return m }
    if let t = timetable.periodTimes[n] { return t }
    return fallbackPeriodTimes[n]
}

private func parseTime(_ str: String, on date: Date, calendar: Calendar) -> Date? {
    let parts = str.split(separator: ":").compactMap { Int($0) }
    guard parts.count == 2 else { return nil }
    return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: date)
}

private func weekdayChineseLabel(for date: Date) -> String {
    let num = Calendar.current.component(.weekday, from: date)
    let labels = ["日", "一", "二", "三", "四", "五", "六"]
    let idx = num - 1
    guard idx >= 0 && idx < labels.count else { return "" }
    return "週\(labels[idx])"
}

// MARK: - Data Loading

private func loadTimetable() -> WTimetableData? {
    guard let defaults = UserDefaults(suiteName: kAppGroupID),
          let data = defaults.data(forKey: "cached_timetable") else { return nil }
    return try? JSONDecoder().decode(WTimetableData.self, from: data)
}

private func loadManualCurriculum() -> [String: String] {
    guard let defaults = UserDefaults(suiteName: kAppGroupID),
          let data = defaults.data(forKey: "manual_curriculum"),
          let dict = try? JSONDecoder().decode([String: String].self, from: data)
    else { return [:] }
    return dict
}

private func loadManualPeriodTimes() -> [String: WPeriodTime] {
    guard let defaults = UserDefaults(suiteName: kAppGroupID),
          let data = defaults.data(forKey: "manual_period_times"),
          let dict = try? JSONDecoder().decode([String: WPeriodTime].self, from: data)
    else { return [:] }
    return dict
}

// MARK: - Schedule Computation

private func slotsForDay(
    _ date: Date,
    timetable: WTimetableData,
    manualCurriculum: [String: String],
    manualPeriodTimes: [String: WPeriodTime]
) -> [ScheduleSlot] {
    let calendar = Calendar.current
    let weekdayNum = calendar.component(.weekday, from: date)
    let todayWeekday = weekdayMap[weekdayNum] ?? ""

    // Gather entries for today, applying manual overrides
    var periodToSubject: [String: String] = [:]
    for entry in timetable.entries where entry.weekday == todayWeekday {
        let key = "\(entry.weekday)|\(entry.period)"
        periodToSubject[entry.period] = manualCurriculum[key] ?? entry.subject
    }
    // Manual-only entries (cells added by user that don't exist in API)
    for (key, subject) in manualCurriculum {
        let parts = key.split(separator: "|")
        guard parts.count == 2,
              String(parts[0]) == todayWeekday else { continue }
        let period = String(parts[1])
        if periodToSubject[period] == nil {
            periodToSubject[period] = subject
        }
    }

    return periodToSubject
        .sorted { (periodOrder[$0.key] ?? 99) < (periodOrder[$1.key] ?? 99) }
        .compactMap { period, subject in
            guard let pt = resolvePeriodTime(for: period, timetable: timetable, manualTimes: manualPeriodTimes),
                  let start = parseTime(pt.startTime, on: date, calendar: calendar),
                  let end   = parseTime(pt.endTime,   on: date, calendar: calendar)
            else { return nil }
            return ScheduleSlot(period: period, subject: subject, startTime: start, endTime: end, isCurrent: false)
        }
}

private func displaySlots(at now: Date, allSlots: [ScheduleSlot]) -> [ScheduleSlot] {
    if let currentIdx = allSlots.firstIndex(where: { now >= $0.startTime && now < $0.endTime }) {
        var result = [ScheduleSlot]()
        var current = allSlots[currentIdx]
        current.isCurrent = true
        result.append(current)
        let upcoming = allSlots[(currentIdx + 1)...].prefix(3)
        result.append(contentsOf: upcoming)
        return result
    }
    return Array(allSlots.filter { $0.startTime > now }.prefix(4))
}

/// 從 `from` 開始往後最多查 7 天，找到有課的那天，回傳 (slots, 那天的 Date)
private func nextAvailableSlots(
    from date: Date,
    timetable: WTimetableData,
    manualCurriculum: [String: String],
    manualPeriodTimes: [String: WPeriodTime]
) -> (slots: [ScheduleSlot], day: Date) {
    let cal = Calendar.current
    for offset in 0...6 {
        guard let targetDay = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: date)) else { continue }
        let allSlots = slotsForDay(targetDay, timetable: timetable, manualCurriculum: manualCurriculum, manualPeriodTimes: manualPeriodTimes)
        let visible: [ScheduleSlot]
        if offset == 0 {
            visible = displaySlots(at: date, allSlots: allSlots)
        } else {
            visible = Array(allSlots.prefix(4))
        }
        if !visible.isEmpty { return (visible, targetDay) }
    }
    return ([], cal.startOfDay(for: date))
}

// MARK: - Timeline Provider

struct TimetableWidgetProvider: TimelineProvider {

    func placeholder(in context: Context) -> TimetableWidgetEntry {
        let now = Date()
        return TimetableWidgetEntry(
            date: now,
            slots: [
                ScheduleSlot(period: "三", subject: "資訊科技實習", startTime: now, endTime: now.addingTimeInterval(3000), isCurrent: true),
                ScheduleSlot(period: "四", subject: "選修跨班",     startTime: now.addingTimeInterval(4200), endTime: now.addingTimeInterval(7200), isCurrent: false),
                ScheduleSlot(period: "五", subject: "統整數學",     startTime: now.addingTimeInterval(8400), endTime: now.addingTimeInterval(11400), isCurrent: false),
                ScheduleSlot(period: "六", subject: "體育",         startTime: now.addingTimeInterval(12600), endTime: now.addingTimeInterval(15600), isCurrent: false)
            ],
            weekdayLabel: "週三",
            hasTimetable: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TimetableWidgetEntry) -> Void) {
        completion(makeEntry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimetableWidgetEntry>) -> Void) {
        let now = Date()
        guard let timetable = loadTimetable() else {
            let entry = TimetableWidgetEntry(date: now, slots: [], weekdayLabel: weekdayChineseLabel(for: now), hasTimetable: false)
            let nextTry = Calendar.current.date(byAdding: .hour, value: 1, to: now)!
            completion(Timeline(entries: [entry], policy: .after(nextTry)))
            return
        }

        let manualCurriculum  = loadManualCurriculum()
        let manualPeriodTimes = loadManualPeriodTimes()
        let cal = Calendar.current

        // Collect refresh boundaries: today's class start/end + midnight for each upcoming day
        let todayAllSlots = slotsForDay(now, timetable: timetable, manualCurriculum: manualCurriculum, manualPeriodTimes: manualPeriodTimes)
        var refreshDates: [Date] = [now]
        for slot in todayAllSlots {
            if slot.startTime > now { refreshDates.append(slot.startTime) }
            if slot.endTime   > now { refreshDates.append(slot.endTime) }
        }
        for offset in 1...7 {
            if let day = cal.date(byAdding: .day, value: offset, to: now) {
                refreshDates.append(cal.startOfDay(for: day))
            }
        }

        let entries = refreshDates.sorted().map { date -> TimetableWidgetEntry in
            let (slots, day) = nextAvailableSlots(from: date, timetable: timetable, manualCurriculum: manualCurriculum, manualPeriodTimes: manualPeriodTimes)
            return TimetableWidgetEntry(
                date: date,
                slots: slots,
                weekdayLabel: weekdayChineseLabel(for: day),
                hasTimetable: true
            )
        }

        let nextMidnight = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: now)!)
        completion(Timeline(entries: entries, policy: .after(nextMidnight)))
    }

    private func makeEntry(at date: Date) -> TimetableWidgetEntry {
        guard let timetable = loadTimetable() else {
            return TimetableWidgetEntry(date: date, slots: [], weekdayLabel: weekdayChineseLabel(for: date), hasTimetable: false)
        }
        let (slots, day) = nextAvailableSlots(from: date, timetable: timetable, manualCurriculum: loadManualCurriculum(), manualPeriodTimes: loadManualPeriodTimes())
        return TimetableWidgetEntry(
            date: date,
            slots: slots,
            weekdayLabel: weekdayChineseLabel(for: day),
            hasTimetable: true
        )
    }
}

// MARK: - Views

struct TimetableWidgetEntryView: View {
    let entry: TimetableWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if !entry.hasTimetable {
            noDataView
        } else if entry.slots.isEmpty {
            noClassView
        } else if family == .systemSmall {
            smallView
        } else {
            scheduleView
        }
    }

    // MARK: Small widget – 只顯示目前這節（或下一節）

    private var smallView: some View {
        let current = entry.slots.first(where: { $0.isCurrent })
        let featured = current ?? entry.slots.first
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "calendar")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.blue)
                Text(entry.weekdayLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Spacer(minLength: 0)
            if let slot = featured {
                VStack(alignment: .leading, spacing: 4) {
                    Text(current != nil ? "上課中" : "下一節")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(current != nil ? .blue : .secondary)
                    Text(slot.subject)
                        .font(.system(size: 17, weight: .bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    if current != nil {
                        Label {
                            Text(slot.endTime, style: .timer)
                                .monospacedDigit()
                        } icon: {
                            Image(systemName: "timer")
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                    } else {
                        Text(slot.startTime, style: .time)
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(.green)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }

    // MARK: Schedule list

    private var scheduleView: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 7)
            VStack(spacing: 4) {
                ForEach(Array(entry.slots.prefix(4).enumerated()), id: \.offset) { _, slot in
                    SlotRowView(slot: slot)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "calendar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
            Text("課表")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            Text(entry.weekdayLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Empty states

    private var noClassView: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
            Text("近期無課")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }

    private var noDataView: some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.title2)
                .foregroundStyle(.orange)
            Text("請先開啟 VocPass")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }
}

// MARK: - Slot Row

private struct SlotRowView: View {
    let slot: ScheduleSlot

    var body: some View {
        HStack(spacing: 8) {
            Text(slot.period)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(slot.isCurrent ? .white : .secondary)
                .frame(width: 22, height: 22)
                .background(slot.isCurrent ? Color.blue : Color(.systemFill))
                .clipShape(RoundedRectangle(cornerRadius: 5))

            Text(slot.subject)
                .font(.system(size: 13, weight: slot.isCurrent ? .semibold : .regular))
                .foregroundStyle(slot.isCurrent ? .primary : Color(.label).opacity(0.7))
                .lineLimit(1)

            Spacer(minLength: 0)

            if slot.isCurrent {
                Text(slot.endTime, style: .timer)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.orange)
            } else {
                Text(slot.startTime, style: .time)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(slot.isCurrent ? Color.blue.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

// MARK: - Widget Configuration

struct TimetableWidget: Widget {
    let kind = "TimetableWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TimetableWidgetProvider()) { entry in
            TimetableWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("課表")
        .description("顯示目前這節課及即將到來的課程。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Previews

#Preview("Small – 上課中", as: .systemSmall) {
    TimetableWidget()
} timeline: {
    TimetableWidgetEntry(
        date: .now,
        slots: [
            ScheduleSlot(period: "三", subject: "資訊科技實習", startTime: .now.addingTimeInterval(-10*60), endTime: .now.addingTimeInterval(40*60),  isCurrent: true),
            ScheduleSlot(period: "四", subject: "選修跨班",     startTime: .now.addingTimeInterval(50*60),  endTime: .now.addingTimeInterval(100*60), isCurrent: false),
            ScheduleSlot(period: "五", subject: "統整數學",     startTime: .now.addingTimeInterval(120*60), endTime: .now.addingTimeInterval(170*60), isCurrent: false)
        ],
        weekdayLabel: "週三",
        hasTimetable: true
    )
}

#Preview("Medium – 上課中", as: .systemMedium) {
    TimetableWidget()
} timeline: {
    TimetableWidgetEntry(
        date: .now,
        slots: [
            ScheduleSlot(period: "三", subject: "資訊科技實習", startTime: .now.addingTimeInterval(-10*60), endTime: .now.addingTimeInterval(40*60),  isCurrent: true),
            ScheduleSlot(period: "四", subject: "選修跨班",     startTime: .now.addingTimeInterval(50*60),  endTime: .now.addingTimeInterval(100*60), isCurrent: false),
            ScheduleSlot(period: "五", subject: "統整數學",     startTime: .now.addingTimeInterval(120*60), endTime: .now.addingTimeInterval(170*60), isCurrent: false),
            ScheduleSlot(period: "六", subject: "體育",         startTime: .now.addingTimeInterval(180*60), endTime: .now.addingTimeInterval(230*60), isCurrent: false)
        ],
        weekdayLabel: "週三",
        hasTimetable: true
    )
}

#Preview("Medium – 下課中", as: .systemMedium) {
    TimetableWidget()
} timeline: {
    TimetableWidgetEntry(
        date: .now,
        slots: [
            ScheduleSlot(period: "四", subject: "選修跨班",     startTime: .now.addingTimeInterval(8*60),   endTime: .now.addingTimeInterval(58*60),  isCurrent: false),
            ScheduleSlot(period: "五", subject: "統整數學",     startTime: .now.addingTimeInterval(68*60),  endTime: .now.addingTimeInterval(118*60), isCurrent: false),
            ScheduleSlot(period: "六", subject: "體育",         startTime: .now.addingTimeInterval(128*60), endTime: .now.addingTimeInterval(178*60), isCurrent: false),
            ScheduleSlot(period: "七", subject: "英文",         startTime: .now.addingTimeInterval(188*60), endTime: .now.addingTimeInterval(238*60), isCurrent: false)
        ],
        weekdayLabel: "週三",
        hasTimetable: true
    )
}
