//
//  ClassScheduleActivityAttributes.swift
//  VocPass
//
//  即時動態 (Live Activity / Dynamic Island) 的資料定義。
//  此檔案需同時加入 VocPass 主 Target 與 VocPassWidget Extension Target。
//

import ActivityKit
import Foundation

struct ClassScheduleActivityAttributes: ActivityAttributes {

    // MARK: - 動態狀態（隨課堂變化而更新）
    public struct ContentState: Codable, Hashable {
        struct DaySlot: Codable, Hashable {
            var period: String
            var subject: String
            var startTime: Date
            var endTime: Date
        }

        var currentPeriod: String
        var currentSubject: String
        var currentStartTime: Date?
        var currentEndTime: Date?

        var nextPeriod: String
        var nextSubject: String
        var nextStartTime: Date?
        var todaySlots: [DaySlot]
    }

    var className: String
}
