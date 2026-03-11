//
//  DynamicIslandService.swift
//  VocPass
//
//  管理課表即時動態（Live Activity / Dynamic Island）的啟動、更新、結束。
//

import ActivityKit
import Foundation
import Combine

@MainActor
final class DynamicIslandService: ObservableObject {
    static let shared = DynamicIslandService()

    // MARK: - 狀態

    @Published var isActivityRunning = false
    @Published var currentSubject: String = ""
    @Published var nextSubject: String = ""

    private var activity: Activity<ClassScheduleActivityAttributes>?
    private var updateTask: Task<Void, Never>?
    private var timetable: TimetableData?

    static let periodOrder: [String: Int] = [
        "早讀": 0,
        "一": 1, "二": 2, "三": 3, "四": 4,
        "五": 5, "六": 6, "七": 7, "八": 8, "九": 9
    ]

    private static let weekdayMap: [Int: String] = [
        1: "日", 2: "一", 3: "二", 4: "三", 5: "四", 6: "五", 7: "六"
    ]

    func setTimetable(_ data: TimetableData) {
        self.timetable = data
        if isActivityRunning {
            updateActivity()
        }
        if CacheService.shared.autoStartDynamicIsland {
            scheduleAutoStart()
        }
    }

    // MARK: - 自動排程：第一節課前 N 分鐘自動啟動

    private var autoStartTask: Task<Void, Never>?

    func scheduleAutoStart() {
        autoStartTask?.cancel()
        guard let timetable else { return }

        let minutesBefore = TimeInterval(CacheService.shared.autoStartMinutesBefore)
        let calendar = Calendar.current
        let now = Date()
        let weekdayNum = calendar.component(.weekday, from: now)
        let weekdayMap: [Int: String] = [1:"日",2:"一",3:"二",4:"三",5:"四",6:"五",7:"六"]
        let todayWeekday = weekdayMap[weekdayNum] ?? ""

        let todayPeriods = timetable.entries.filter { $0.weekday == todayWeekday }
        guard !todayPeriods.isEmpty else {
            print("⚡ [DI] 今日無課，不排程自動啟動")
            return
        }

        let firstEntry = todayPeriods.min {
            (Self.periodOrder[$0.period] ?? 99) < (Self.periodOrder[$1.period] ?? 99)
        }
        guard let first = firstEntry,
              let pt = timetable.periodTimes[first.period],
              let firstStart = Self.parseTime(pt.startTime, on: now, calendar: calendar)
        else { return }

        let triggerTime = firstStart.addingTimeInterval(-minutesBefore * 60)

        guard triggerTime > now else {
            if firstStart > now && !isActivityRunning {
                print("⚡ [DI] 第一節即將開始，立即啟動")
                let className = CacheService.shared.savedClassName.isEmpty ? "我的課表" : CacheService.shared.savedClassName
                Task { await startActivity(className: className) }
            }
            return
        }

        let delay = triggerTime.timeIntervalSince(now)
        print("⚡ [DI] 將於 \(Int(delay/60)) 分鐘後（\(pt.startTime) 前 \(Int(minutesBefore)) 分鐘）自動啟動")

        autoStartTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            let className = CacheService.shared.savedClassName.isEmpty ? "我的課表" : CacheService.shared.savedClassName
            await startActivity(className: className)
        }
    }

    func cancelAutoStart() {
        autoStartTask?.cancel()
        autoStartTask = nil
        print("⚡ [DI] 已取消自動排程")
    }

    func startActivity(className: String) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("⚡ [DI] Live Activities 未授權")
            return
        }
        guard activity == nil else {
            print("⚡ [DI] 活動已在進行中")
            return
        }

        let attributes = ClassScheduleActivityAttributes(className: className)
        let initialState = makeContentState(at: Date())

        let newActivity = await Task.detached(priority: .userInitiated) {
            try? Activity<ClassScheduleActivityAttributes>.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: Date().addingTimeInterval(60 * 60)),
                pushType: nil
            )
        }.value

        guard let newActivity else {
            print("⚡ [DI] 無法啟動 Live Activity（request 失敗）")
            return
        }
        activity = newActivity
        isActivityRunning = true
        print("⚡ [DI] Live Activity 已啟動：\(newActivity.id)")
        startUpdateLoop()
    }

    func updateActivity() {
        guard let act = activity else { return }
        let state = makeContentState(at: Date())
        currentSubject = state.currentSubject
        nextSubject    = state.nextSubject

        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(60 * 60)
        )
        Task.detached(priority: .utility) {
            await act.update(content)
        }
        print("⚡ [DI] 已更新：\(state.currentSubject.isEmpty ? "下課中" : state.currentSubject) → \(state.nextSubject.isEmpty ? "今天結束" : state.nextSubject)")
    }

    func endActivity() {
        guard let act = activity else { return }
        activity = nil
        isActivityRunning = false
        stopUpdateLoop()
        let finalState = ClassScheduleActivityAttributes.ContentState(
            currentPeriod: "", currentSubject: "", currentStartTime: nil,
            currentEndTime: nil, nextPeriod: "", nextSubject: "", nextStartTime: nil
        )
        Task.detached(priority: .utility) {
            await act.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .after(Date().addingTimeInterval(5))
            )
        }
        print("⚡ [DI] Live Activity 已結束")
    }

    // MARK: - 定時更新

    private func startUpdateLoop() {
        stopUpdateLoop()
        updateTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await MainActor.run { self.updateActivity() }

                let comps = Calendar.current.dateComponents([.hour, .minute], from: Date())
                if (comps.hour ?? 0) >= 17 && (comps.minute ?? 0) >= 10 {
                    await MainActor.run { self.endActivity() }
                    return
                }

                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            }
        }
    }

    private func stopUpdateLoop() {
        updateTask?.cancel()
        updateTask = nil
    }


    func makeContentState(at date: Date) -> ClassScheduleActivityAttributes.ContentState {
        guard let timetable else {
            return ClassScheduleActivityAttributes.ContentState(
                currentPeriod: "", currentSubject: "", currentStartTime: nil,
                currentEndTime: nil, nextPeriod: "", nextSubject: "", nextStartTime: nil
            )
        }

        let calendar = Calendar.current
        let weekdayNum = calendar.component(.weekday, from: date)
        let todayWeekday = Self.weekdayMap[weekdayNum] ?? ""

        let todayEntries = timetable.entries
            .filter { $0.weekday == todayWeekday }
            .sorted { (Self.periodOrder[$0.period] ?? 99) < (Self.periodOrder[$1.period] ?? 99) }

        struct Slot {
            let entry: TimetableEntry
            let start: Date
            let end: Date
        }
        let slots: [Slot] = todayEntries.compactMap { entry in
            guard let pt = timetable.periodTimes[entry.period],
                  let start = Self.parseTime(pt.startTime, on: date, calendar: calendar),
                  let end   = Self.parseTime(pt.endTime,   on: date, calendar: calendar)
            else { return nil }
            return Slot(entry: entry, start: start, end: end)
        }

        let current = slots.first { date >= $0.start && date <= $0.end }

        let afterCurrent = current.map { c in slots.first { $0.start > c.end } } ?? slots.first { $0.start > date }

        currentSubject = current?.entry.subject ?? ""
        nextSubject    = afterCurrent?.entry.subject ?? ""

        return ClassScheduleActivityAttributes.ContentState(
            currentPeriod:    current?.entry.period  ?? "",
            currentSubject:   current?.entry.subject ?? "",
            currentStartTime: current?.start,
            currentEndTime:   current?.end,
            nextPeriod:       afterCurrent?.entry.period  ?? "",
            nextSubject:      afterCurrent?.entry.subject ?? "",
            nextStartTime:    afterCurrent?.start
        )
    }
    
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
