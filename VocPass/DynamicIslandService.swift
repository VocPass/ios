//
//  DynamicIslandService.swift
//  VocPass
//
//  管理課表即時動態（Live Activity / Dynamic Island）的啟動、更新、結束。
//

import ActivityKit
import BackgroundTasks
import Combine
import Foundation

let kDIBGTaskID = "com.08hans.VocPass.liveActivity"

@MainActor
final class DynamicIslandService: ObservableObject {
    static let shared = DynamicIslandService()

    // MARK: - 狀態

    @Published var isActivityRunning = false
    @Published var currentSubject: String = ""
    @Published var nextSubject: String = ""
    @Published var currentPeriod: String = ""
    @Published var lastErrorMessage: String?

    private var activity: Activity<ClassScheduleActivityAttributes>?
    private var updateTask: Task<Void, Never>?
    private var timetable: TimetableData?

    static let periodOrder: [String: Int] = [
        "早讀": 0,
        "一": 1, "二": 2, "三": 3, "四": 4,
        "五": 5, "六": 6, "七": 7, "八": 8, "九": 9
    ]

    private static let fallbackPeriodTimes: [String: PeriodTime] = [
        "早讀": PeriodTime(startTime: "07:30", endTime: "08:00"),
        "一": PeriodTime(startTime: "08:10", endTime: "09:00"),
        "二": PeriodTime(startTime: "09:10", endTime: "10:00"),
        "三": PeriodTime(startTime: "10:10", endTime: "11:00"),
        "四": PeriodTime(startTime: "11:10", endTime: "12:00"),
        "五": PeriodTime(startTime: "13:10", endTime: "14:00"),
        "六": PeriodTime(startTime: "14:10", endTime: "15:00"),
        "七": PeriodTime(startTime: "15:10", endTime: "16:00"),
        "八": PeriodTime(startTime: "16:10", endTime: "17:00"),
        "九": PeriodTime(startTime: "17:10", endTime: "18:00")
    ]

    private static let weekdayMap: [Int: String] = [
        1: "日", 2: "一", 3: "二", 4: "三", 5: "四", 6: "五", 7: "六"
    ]

    private struct Slot {
        let entry: TimetableEntry
        let start: Date
        let end: Date
    }

    // MARK: - 更新課表資料

    func setTimetable(_ data: TimetableData) {
        self.timetable = data
        reconnectIfNeeded()
        if isActivityRunning {
            updateActivity()
            if currentSubject.isEmpty && nextSubject.isEmpty {
                endActivity()
            }
        } else {
            autoStartIfNeeded()
        }
        if CacheService.shared.autoStartDynamicIsland { scheduleNextBGRefresh() }
    }

    func reconnectIfNeeded() {
        guard activity == nil else { return }
        guard let existing = Activity<ClassScheduleActivityAttributes>.activities.first(where: {
            $0.activityState == .active || $0.activityState == .stale
        }) else { return }

        activity = existing
        isActivityRunning = true
        print("⚡ [DI] 重新連接到現有 Live Activity：\(existing.id)")
        startUpdateLoop()
    }

    // MARK: - 今日時段清單

    private func todaySlots(on date: Date = Date()) -> [Slot] {
        guard let timetable else { return [] }
        let calendar = Calendar.current
        let weekdayNum = calendar.component(.weekday, from: date)
        let todayWeekday = Self.weekdayMap[weekdayNum] ?? ""

        return timetable.entries
            .filter { $0.weekday == todayWeekday }
            .sorted { (Self.periodOrder[$0.period] ?? 99) < (Self.periodOrder[$1.period] ?? 99) }
            .compactMap { entry -> Slot? in
                guard let pt = periodTime(for: entry.period, in: timetable),
                      let start = Self.parseTime(pt.startTime, on: date, calendar: calendar),
                      let end   = Self.parseTime(pt.endTime,   on: date, calendar: calendar)
                else { return nil }
                return Slot(entry: entry, start: start, end: end)
            }
    }

    private func periodTime(for period: String, in timetable: TimetableData) -> PeriodTime? {
        if let direct = timetable.periodTimes[period] { return direct }
        if let fallback = Self.fallbackPeriodTimes[period] { return fallback }

        let normalized = Self.normalizePeriod(period)
        if let fromTimetable = timetable.periodTimes[normalized] { return fromTimetable }
        return Self.fallbackPeriodTimes[normalized]
    }

    private static func normalizePeriod(_ raw: String) -> String {
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

    private func computeNextStaleDate(from now: Date = Date()) -> Date? {
        let slots = todaySlots(on: now)
        if let cur = slots.first(where: { now >= $0.start && now <= $0.end }) { return cur.end }
        return slots.first { $0.start > now }?.start
    }

    // MARK: - BGTaskScheduler

    private func buildTriggers(on date: Date) -> [Date] {
        let slots = todaySlots(on: date)
        guard !slots.isEmpty else { return [] }
        let minutesBefore = TimeInterval(CacheService.shared.autoStartMinutesBefore)
        var triggers: [Date] = []
        if let first = slots.first {
            triggers.append(first.start.addingTimeInterval(-minutesBefore * 60))
        }
        for s in slots {
            triggers.append(s.start)
            triggers.append(s.end)
        }
        return triggers
    }

    private func nextBGTrigger(after now: Date) -> Date? {
        let todayTriggers = buildTriggers(on: now).filter { $0 > now }
        if let t = todayTriggers.min() { return t }

        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) else { return nil }
        let tomorrowMorning = Calendar.current.startOfDay(for: tomorrow)
        return buildTriggers(on: tomorrowMorning).min()
    }

    func scheduleNextBGRefresh(after now: Date = Date()) {
        BGTaskScheduler.shared.cancelAllTaskRequests()
        guard CacheService.shared.autoStartDynamicIsland || isActivityRunning else { return }
        guard let trigger = nextBGTrigger(after: now) else {
            print("⚡ [DI] 近期無課，不排程 BG Refresh")
            return
        }
        let req = BGAppRefreshTaskRequest(identifier: kDIBGTaskID)
        req.earliestBeginDate = trigger
        do {
            try BGTaskScheduler.shared.submit(req)
            print("⚡ [DI] BG Refresh 排程於 \(trigger)")
        } catch {
            print("⚡ [DI] BG Refresh 排程失敗：\(error)")
        }
    }

    func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        task.expirationHandler = { [weak self] in
            self?.scheduleNextBGRefresh()
            task.setTaskCompleted(success: false)
        }

        reconnectIfNeeded()

        let now = Date()
        let state = makeContentState(at: now)

        if isActivityRunning {
            if state.currentSubject.isEmpty && state.nextSubject.isEmpty {
                endActivity()
            } else {
                updateActivity()
            }
            scheduleNextBGRefresh(after: now)
            task.setTaskCompleted(success: true)
        } else if CacheService.shared.autoStartDynamicIsland
                    && (!state.currentSubject.isEmpty || !state.nextSubject.isEmpty) {
            let name = CacheService.shared.savedClassName.isEmpty
                ? "我的課表" : CacheService.shared.savedClassName
            Task {
                await self.startActivity(className: name)
                self.scheduleNextBGRefresh(after: now)
                task.setTaskCompleted(success: true)
            }
        } else {
            scheduleNextBGRefresh(after: now)
            task.setTaskCompleted(success: true)
        }
    }

    // MARK: - 自動排程（公開介面）

    func scheduleAutoStart() { scheduleNextBGRefresh() }

    func cancelAutoStart() {
        BGTaskScheduler.shared.cancelAllTaskRequests()
        print("⚡ [DI] 已取消自動排程")
    }

    func autoStartIfNeeded() {
        guard CacheService.shared.autoStartDynamicIsland else { return }
        guard !isActivityRunning, activity == nil else { return }
        guard timetable != nil else { return }

        let now = Date()
        let slots = todaySlots(on: now)
        guard !slots.isEmpty,
              let firstStart = slots.first?.start,
              let lastEnd = slots.last?.end else { return }

        let minutesBefore = TimeInterval(CacheService.shared.autoStartMinutesBefore)
        let autoStartTime = firstStart.addingTimeInterval(-minutesBefore * 60)

        guard now >= autoStartTime && now <= lastEnd else { return }

        let name = CacheService.shared.savedClassName.isEmpty
            ? "我的課表" : CacheService.shared.savedClassName
        print("⚡ [DI] 自動啟動 Live Activity")
        Task { await self.startActivity(className: name) }
    }

    // MARK: - 啟動即時動態

    func startActivity(className: String) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastErrorMessage = "系統未允許 Live Activities，請到「設定 > Face ID 與密碼 > 即時動態」開啟。"
            print("⚡ [DI] Live Activities 未授權")
            return
        }
        guard activity == nil else {
            lastErrorMessage = nil
            print("⚡ [DI] 活動已在進行中")
            return
        }

        for old in Activity<ClassScheduleActivityAttributes>.activities {
            await old.end(nil, dismissalPolicy: .immediate)
        }

        let attributes = ClassScheduleActivityAttributes(className: className)
        let state = makeContentState(at: Date())

        do {
            let newActivity = try Activity<ClassScheduleActivityAttributes>.request(
                attributes: attributes,
                content: ActivityContent(
                    state: state,
                    staleDate: computeNextStaleDate()
                ),
                pushType: nil
            )
            activity = newActivity
            isActivityRunning = true
            lastErrorMessage = nil
            print("⚡ [DI] Live Activity 已啟動：\(newActivity.id)")
            startUpdateLoop()
            scheduleNextBGRefresh()
        } catch {
            lastErrorMessage = error.localizedDescription
            print("⚡ [DI] 無法啟動 Live Activity：\(error)")
        }
    }

    // MARK: - 更新即時動態

    func updateActivity() {
        guard let act = activity else { return }
        let state = makeContentState(at: Date())
        currentSubject = state.currentSubject
        nextSubject    = state.nextSubject
        currentPeriod  = state.currentPeriod
        let content = ActivityContent(state: state, staleDate: computeNextStaleDate())
        Task { @MainActor in
            await act.update(content)
        }
        print("⚡ [DI] 已更新：\(state.currentSubject.isEmpty ? "下課中" : state.currentSubject) → \(state.nextSubject.isEmpty ? "今天結束" : state.nextSubject)")
    }

    // MARK: - 結束即時動態

    func endActivity() {
        guard let act = activity else { return }
        activity = nil
        isActivityRunning = false
        stopUpdateLoop()
        scheduleNextBGRefresh()
        let finalState = ClassScheduleActivityAttributes.ContentState(
            currentPeriod: "", currentSubject: "", currentStartTime: nil,
            currentEndTime: nil, nextPeriod: "", nextSubject: "", nextStartTime: nil,
            todaySlots: []
        )
        Task { @MainActor in
            await act.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
        print("⚡ [DI] Live Activity 已結束")
    }

    // MARK: - 定時更新迴圈

    private func startUpdateLoop() {
        stopUpdateLoop()
        updateTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await MainActor.run { self.updateActivity() }

                let schoolDone = await MainActor.run {
                    self.currentSubject.isEmpty && self.nextSubject.isEmpty
                }
                if schoolDone {
                    await MainActor.run { self.endActivity() }
                    return
                }

                let sleepSeconds: TimeInterval = await MainActor.run {
                    if let stale = self.computeNextStaleDate() {
                        let interval = stale.timeIntervalSince(Date()) + 1
                        return min(max(interval, 5), 60)
                    }
                    return 30
                }
                try? await Task.sleep(nanoseconds: UInt64(sleepSeconds * 1_000_000_000))
            }
        }
    }

    private func stopUpdateLoop() {
        updateTask?.cancel()
        updateTask = nil
    }

    // MARK: - 計算目前 / 下一堂課的 ContentState

    func makeContentState(at date: Date) -> ClassScheduleActivityAttributes.ContentState {
        let slots = todaySlots(on: date)
        guard !slots.isEmpty else {
            return ClassScheduleActivityAttributes.ContentState(
                currentPeriod: "", currentSubject: "", currentStartTime: nil,
                currentEndTime: nil, nextPeriod: "", nextSubject: "", nextStartTime: nil,
                todaySlots: []
            )
        }

        let current = slots.first { date >= $0.start && date < $0.end }

        let afterCurrent: Slot?
        if let c = current {
            afterCurrent = slots.first { $0.start > c.end }
        } else {
            afterCurrent = slots.first { $0.start > date }
        }

        let daySlots = slots.map {
            ClassScheduleActivityAttributes.ContentState.DaySlot(
                period: $0.entry.period,
                subject: $0.entry.subject,
                startTime: $0.start,
                endTime: $0.end
            )
        }

        return ClassScheduleActivityAttributes.ContentState(
            currentPeriod:    current?.entry.period  ?? "",
            currentSubject:   current?.entry.subject ?? "",
            currentStartTime: current?.start,
            currentEndTime:   current?.end,
            nextPeriod:       afterCurrent?.entry.period  ?? "",
            nextSubject:      afterCurrent?.entry.subject ?? "",
            nextStartTime:    afterCurrent?.start,
            todaySlots:       daySlots
        )
    }

    // MARK: - 工具：將 "HH:MM" 轉成指定日期對應的 Date

    private static func parseTime(_ timeStr: String, on date: Date, calendar: Calendar) -> Date? {
        let parts = timeStr.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        var comps = calendar.dateComponents([.year, .month, .day], from: date)
        comps.hour   = parts[0]
        comps.minute = parts[1]
        comps.second = 0
        return calendar.date(from: comps)
    }
}
