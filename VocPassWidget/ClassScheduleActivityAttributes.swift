//
//  ClassScheduleActivityAttributes.swift
//  VocPassWidget
//
//

import ActivityKit
import Foundation

struct ClassScheduleActivityAttributes: ActivityAttributes {

    public struct ContentState: Codable, Hashable {
        var currentPeriod: String
        var currentSubject: String
        var currentStartTime: Date?
        var currentEndTime: Date?

        var nextPeriod: String
        var nextSubject: String
        var nextStartTime: Date?
    }

    var className: String
}
