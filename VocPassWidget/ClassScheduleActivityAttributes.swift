//
//  ClassScheduleActivityAttributes.swift
//  VocPassWidget
//
//

import ActivityKit
import Foundation

struct ClassScheduleActivityAttributes: ActivityAttributes {

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
