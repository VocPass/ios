//
//  W2MModels.swift
//  VocPass
//
//  「出來玩」When2meet 功能資料模型
//

import Foundation

// MARK: - API 回傳：活動列表

struct W2MEventListResponse: Decodable {
    let created: [W2MEventSummary]
    let participated: [W2MEventSummary]
}

struct W2MEventSummary: Identifiable, Decodable {
    let id: String
    let title: String
    let description: String
    let dates: [String]
    let creator: W2MUserInfo
}

struct W2MUserInfo: Decodable {
    let id: String
    let name: String
    let avatar: String?

    var avatarURL: URL? {
        guard let avatar, !avatar.isEmpty else { return nil }
        return URL(string: avatar)
    }

    var displayName: String { name.isEmpty ? id : name }
}

// MARK: - API 回傳：活動詳情

struct W2MEvent: Identifiable, Decodable {
    let id: String
    let title: String
    let slots: [String]            // ["2026-04-10 09:00", ...]
    let availability: [W2MUserAvailability]
    let creator: W2MUserInfo?

    // 從 availability 推算日期列表
    var dates: [String] {
        var seen = Set<String>()
        return slots.compactMap { s in
            let date = String(s.split(separator: " ")[0])
            return seen.insert(date).inserted ? date : nil
        }
    }

    var uniqueDates: [String] { dates }

    var uniqueTimes: [String] {
        var seen = Set<String>()
        return slots.compactMap { s in
            let parts = s.split(separator: " ")
            guard parts.count == 2 else { return nil }
            let time = String(parts[1])
            return seen.insert(time).inserted ? time : nil
        }
    }

    // availability 轉成 [username: [slot]] 字典方便查詢
    var availabilityMap: [String: [String]] {
        Dictionary(uniqueKeysWithValues: availability.map { ($0.user.displayName, $0.slots) })
    }

    func slotCount(for slot: W2MSlot) -> Int {
        availability.filter { $0.slots.contains(slot.label) }.count
    }

    func usersAvailable(for slot: W2MSlot) -> [String] {
        availability.filter { $0.slots.contains(slot.label) }.map(\.user.displayName).sorted()
    }

    var maxCount: Int {
        let m = slots.map { s -> Int in
            let parts = s.split(separator: " ")
            guard parts.count == 2 else { return 0 }
            let slot = W2MSlot(dateString: String(parts[0]), timeString: String(parts[1]))
            return slotCount(for: slot)
        }.max() ?? 0
        return m == 0 ? 1 : m
    }
}

struct W2MUserAvailability: Decodable, Identifiable {
    var id: String { user.id }
    let user: W2MUserInfo
    let slots: [String]
}

// MARK: - 本地用模型

struct W2MSlot: Hashable {
    let dateString: String  // "2026-04-10"
    let timeString: String  // "09:00"

    var label: String { "\(dateString) \(timeString)" }

    static func allSlots(for dates: [String]) -> [W2MSlot] {
        var slots: [W2MSlot] = []
        for date in dates {
            for hour in 0..<24 {
                for half in [0, 30] {
                    let time = String(format: "%02d:%02d", hour, half)
                    slots.append(W2MSlot(dateString: date, timeString: time))
                }
            }
        }
        return slots
    }
}
