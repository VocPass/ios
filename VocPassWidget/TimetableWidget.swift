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

private struct WPeriodTime: Codable {
    let startTime: String
    let endTime: String
}

private struct WTimetableEntry: Codable {
    let weekday: String
    let period: String
    let subject: String
    let room: String?
    let teacher: String?

    // 主 app 的 TimetableEntry 會 encode `id`，這裡用可選欄位接住以避免 decode 失敗
    let id: String?

    private enum CodingKeys: String, CodingKey {
        case weekday, period, subject, room, teacher, id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weekday = try c.decode(String.self, forKey: .weekday)
        period  = try c.decode(String.self, forKey: .period)
        subject = try c.decode(String.self, forKey: .subject)
        room    = try c.decodeIfPresent(String.self, forKey: .room)
        teacher = try c.decodeIfPresent(String.self, forKey: .teacher)
        id      = try c.decodeIfPresent(String.self, forKey: .id)
    }
}

private struct WTimetableData: Codable {
    let entries: [WTimetableEntry]
    let periodTimes: [String: WPeriodTime]

    // 主 app 的 TimetableData 會 encode `curriculum`，忽略它但接住避免 decode 失敗
    private enum CodingKeys: String, CodingKey {
        case entries, periodTimes
    }
}

// MARK: - Schedule Slot

struct ScheduleSlot {
    let period: String
    let subject: String
    let startTime: Date
    let endTime: Date
    var isCurrent: Bool
    let room: String
    let teacher: String
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
    guard let defaults = UserDefaults(suiteName: kAppGroupID) else {
        print("🔲 [Widget] ⚠️ 無法取得 App Group UserDefaults")
        return nil
    }
    defaults.synchronize()
    guard let data = defaults.data(forKey: "cached_timetable") else {
        print("🔲 [Widget] 沒有找到 cached_timetable 資料")
        return nil
    }
    do {
        let result = try JSONDecoder().decode(WTimetableData.self, from: data)
        print("🔲 [Widget] 成功載入課表（\(result.entries.count) 筆）")
        return result
    } catch {
        print("🔲 [Widget] 課表 decode 失敗: \(error)")
        return nil
    }
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

private struct WCourseExtra: Codable {
    let room: String
    let teacher: String
}

private func loadManualRoomTeacher() -> [String: WCourseExtra] {
    guard let defaults = UserDefaults(suiteName: kAppGroupID),
          let data = defaults.data(forKey: "manual_room_teacher"),
          let dict = try? JSONDecoder().decode([String: WCourseExtra].self, from: data)
    else { return [:] }
    return dict
}

// MARK: - Schedule Computation

private func slotsForDay(
    _ date: Date,
    timetable: WTimetableData,
    manualCurriculum: [String: String],
    manualPeriodTimes: [String: WPeriodTime],
    manualRoomTeacher: [String: WCourseExtra] = [:]
) -> [ScheduleSlot] {
    let calendar = Calendar.current
    let weekdayNum = calendar.component(.weekday, from: date)
    let todayWeekday = weekdayMap[weekdayNum] ?? ""

    // Gather entries for today, applying manual overrides
    var periodToEntry: [String: (subject: String, room: String, teacher: String)] = [:]
    for entry in timetable.entries where entry.weekday == todayWeekday {
        let key = "\(entry.weekday)|\(entry.period)"
        let rt  = manualRoomTeacher[key]
        periodToEntry[entry.period] = (
            subject: manualCurriculum[key] ?? entry.subject,
            room:    rt?.room    ?? entry.room    ?? "",
            teacher: rt?.teacher ?? entry.teacher ?? ""
        )
    }
    // Manual-only entries — Chinese period labels first to win time-slot deduplication
    let chinesePeriodOrder = ["早讀","一","二","三","四","五","六","七","八","九","十",
                              "十一","十二","十三","十四","十五"]
    let sortedManualKeys = manualCurriculum.keys.sorted { a, b in
        let pa = String(a.split(separator: "|").last ?? "")
        let pb = String(b.split(separator: "|").last ?? "")
        let ia = chinesePeriodOrder.firstIndex(of: pa) ?? Int.max
        let ib = chinesePeriodOrder.firstIndex(of: pb) ?? Int.max
        return ia < ib
    }
    for key in sortedManualKeys {
        guard let subject = manualCurriculum[key] else { continue }
        let parts = key.split(separator: "|")
        guard parts.count == 2,
              String(parts[0]) == todayWeekday else { continue }
        let period = String(parts[1])
        guard !period.isEmpty, periodToEntry[period] == nil else { continue }
        let rt = manualRoomTeacher[key]
        periodToEntry[period] = (subject: subject, room: rt?.room ?? "", teacher: rt?.teacher ?? "")
    }

    // Build slots, deduplicating by startTime to eliminate stale Arabic-numeral period entries
    var seenStartTimes = Set<Date>()
    return periodToEntry
        .sorted { (periodOrder[$0.key] ?? 99) < (periodOrder[$1.key] ?? 99) }
        .compactMap { period, info -> ScheduleSlot? in
            guard !period.isEmpty,
                  let pt = resolvePeriodTime(for: period, timetable: timetable, manualTimes: manualPeriodTimes),
                  let start = parseTime(pt.startTime, on: date, calendar: calendar),
                  let end   = parseTime(pt.endTime,   on: date, calendar: calendar)
            else { return nil }
            guard seenStartTimes.insert(start).inserted else { return nil }
            return ScheduleSlot(period: period, subject: info.subject,
                                startTime: start, endTime: end, isCurrent: false,
                                room: info.room, teacher: info.teacher)
        }
}

private func displaySlots(at now: Date, allSlots: [ScheduleSlot], maxCount: Int = 6) -> [ScheduleSlot] {
    if let currentIdx = allSlots.firstIndex(where: { now >= $0.startTime && now < $0.endTime }) {
        var result = [ScheduleSlot]()
        var current = allSlots[currentIdx]
        current.isCurrent = true
        result.append(current)
        let upcoming = allSlots[(currentIdx + 1)...].prefix(maxCount - 1)
        result.append(contentsOf: upcoming)
        return result
    }
    return Array(allSlots.filter { $0.startTime > now }.prefix(maxCount))
}

private func nextAvailableSlots(
    from date: Date,
    timetable: WTimetableData,
    manualCurriculum: [String: String],
    manualPeriodTimes: [String: WPeriodTime],
    manualRoomTeacher: [String: WCourseExtra] = [:],
    maxCount: Int = 6
) -> (slots: [ScheduleSlot], day: Date) {
    let cal = Calendar.current
    for offset in 0...6 {
        guard let targetDay = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: date)) else { continue }
        let allSlots = slotsForDay(targetDay, timetable: timetable, manualCurriculum: manualCurriculum,
                                   manualPeriodTimes: manualPeriodTimes, manualRoomTeacher: manualRoomTeacher)
        let visible: [ScheduleSlot]
        if offset == 0 {
            visible = displaySlots(at: date, allSlots: allSlots, maxCount: maxCount)
        } else {
            visible = Array(allSlots.prefix(maxCount))
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
                ScheduleSlot(period: "三", subject: "資訊科技實習", startTime: now, endTime: now.addingTimeInterval(3000), isCurrent: true, room: "", teacher: ""),
                ScheduleSlot(period: "四", subject: "選修跨班",     startTime: now.addingTimeInterval(4200), endTime: now.addingTimeInterval(7200), isCurrent: false, room: "", teacher: ""),
                ScheduleSlot(period: "五", subject: "統整數學",     startTime: now.addingTimeInterval(8400), endTime: now.addingTimeInterval(11400), isCurrent: false, room: "", teacher: ""),
                ScheduleSlot(period: "六", subject: "體育",         startTime: now.addingTimeInterval(12600), endTime: now.addingTimeInterval(15600), isCurrent: false, room: "", teacher: "")
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
        let timetable = loadTimetable() ?? WTimetableData(entries: [], periodTimes: [:])
        let manualCurriculum  = loadManualCurriculum()
        let manualPeriodTimes = loadManualPeriodTimes()
        let manualRoomTeacher = loadManualRoomTeacher()

        guard !timetable.entries.isEmpty || !manualCurriculum.isEmpty else {
            let entry = TimetableWidgetEntry(date: now, slots: [], weekdayLabel: weekdayChineseLabel(for: now), hasTimetable: false)
            let nextTry = Calendar.current.date(byAdding: .hour, value: 1, to: now)!
            completion(Timeline(entries: [entry], policy: .after(nextTry)))
            return
        }
        let cal = Calendar.current

        // Collect refresh boundaries: today's class start/end + midnight for each upcoming day
        let todayAllSlots = slotsForDay(now, timetable: timetable, manualCurriculum: manualCurriculum,
                                        manualPeriodTimes: manualPeriodTimes, manualRoomTeacher: manualRoomTeacher)
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
            let (slots, day) = nextAvailableSlots(from: date, timetable: timetable, manualCurriculum: manualCurriculum,
                                                  manualPeriodTimes: manualPeriodTimes, manualRoomTeacher: manualRoomTeacher,
                                                  maxCount: 6)
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
        let timetable = loadTimetable() ?? WTimetableData(entries: [], periodTimes: [:])
        let manualCurriculum = loadManualCurriculum()
        guard !timetable.entries.isEmpty || !manualCurriculum.isEmpty else {
            return TimetableWidgetEntry(date: date, slots: [], weekdayLabel: weekdayChineseLabel(for: date), hasTimetable: false)
        }
        let (slots, day) = nextAvailableSlots(from: date, timetable: timetable,
                                              manualCurriculum: manualCurriculum,
                                              manualPeriodTimes: loadManualPeriodTimes(),
                                              manualRoomTeacher: loadManualRoomTeacher(),
                                              maxCount: 6)
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

    // MARK: Small widge

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
                VStack(alignment: .leading, spacing: 3) {
                    Text(current != nil ? "上課中" : "下一節")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(current != nil ? .blue : .secondary)
                    Text(slot.subject)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    let meta = [slot.room, slot.teacher].filter { !$0.isEmpty }.joined(separator: "・")
                    if !meta.isEmpty {
                        Text(meta)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
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
                            .font(.system(size: 12).monospacedDigit())
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
        let maxSlots = family == .systemLarge ? 6 : 4
        return VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 7)
            VStack(spacing: 3) {
                ForEach(Array(entry.slots.prefix(maxSlots).enumerated()), id: \.offset) { _, slot in
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
        HStack(spacing: 6) {
            Text(slot.period)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(slot.isCurrent ? .white : .secondary)
                .frame(width: 20, height: 20)
                .background(slot.isCurrent ? Color.blue : Color(.systemFill))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 0) {
                Text(slot.subject)
                    .font(.system(size: 12, weight: slot.isCurrent ? .semibold : .regular))
                    .foregroundStyle(slot.isCurrent ? .primary : Color(.label).opacity(0.75))
                    .lineLimit(1)
                let meta = [slot.room, slot.teacher].filter { !$0.isEmpty }.joined(separator: "・")
                if !meta.isEmpty {
                    Text(meta)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if slot.isCurrent {
                Text(slot.endTime, style: .timer)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 36, alignment: .trailing)
            } else {
                Text(slot.startTime, style: .time)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 36, alignment: .trailing)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(slot.isCurrent ? Color.blue.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
            ScheduleSlot(period: "三", subject: "資訊科技實習", startTime: .now.addingTimeInterval(-10*60), endTime: .now.addingTimeInterval(40*60),  isCurrent: true,  room: "電腦教室", teacher: ""),
            ScheduleSlot(period: "四", subject: "選修跨班",     startTime: .now.addingTimeInterval(50*60),  endTime: .now.addingTimeInterval(100*60), isCurrent: false, room: "", teacher: ""),
            ScheduleSlot(period: "五", subject: "統整數學",     startTime: .now.addingTimeInterval(120*60), endTime: .now.addingTimeInterval(170*60), isCurrent: false, room: "", teacher: "")
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
            ScheduleSlot(period: "三", subject: "資訊科技實習", startTime: .now.addingTimeInterval(-10*60), endTime: .now.addingTimeInterval(40*60),  isCurrent: true,  room: "電腦教室", teacher: "王老師"),
            ScheduleSlot(period: "四", subject: "選修跨班",     startTime: .now.addingTimeInterval(50*60),  endTime: .now.addingTimeInterval(100*60), isCurrent: false, room: "", teacher: ""),
            ScheduleSlot(period: "五", subject: "統整數學",     startTime: .now.addingTimeInterval(120*60), endTime: .now.addingTimeInterval(170*60), isCurrent: false, room: "", teacher: ""),
            ScheduleSlot(period: "六", subject: "體育",         startTime: .now.addingTimeInterval(180*60), endTime: .now.addingTimeInterval(230*60), isCurrent: false, room: "操場", teacher: "")
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
            ScheduleSlot(period: "四", subject: "選修跨班",     startTime: .now.addingTimeInterval(8*60),   endTime: .now.addingTimeInterval(58*60),  isCurrent: false, room: "", teacher: ""),
            ScheduleSlot(period: "五", subject: "統整數學",     startTime: .now.addingTimeInterval(68*60),  endTime: .now.addingTimeInterval(118*60), isCurrent: false, room: "", teacher: ""),
            ScheduleSlot(period: "六", subject: "體育",         startTime: .now.addingTimeInterval(128*60), endTime: .now.addingTimeInterval(178*60), isCurrent: false, room: "操場", teacher: ""),
            ScheduleSlot(period: "七", subject: "英文",         startTime: .now.addingTimeInterval(188*60), endTime: .now.addingTimeInterval(238*60), isCurrent: false, room: "", teacher: "")
        ],
        weekdayLabel: "週三",
        hasTimetable: true
    )
}
