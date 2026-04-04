//
//  W2MAvailabilityView.swift
//  VocPass
//

import SwiftUI

struct W2MAvailabilityView: View {
    let eventID: String
    let dates: [String]
    var initialSlots: [String] = []

    @Environment(\.dismiss) private var dismiss

    @State private var selectedSlots: Set<String>
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var times: [String] {
        (6..<24).flatMap { h in [0, 30].map { m in String(format: "%02d:%02d", h, m) } }
    }

    private let timeColumnWidth: CGFloat = 44
    private let cellHeight: CGFloat = 28

    init(eventID: String, dates: [String], initialSlots: [String] = []) {
        self.eventID = eventID
        self.dates = dates
        self.initialSlots = initialSlots
        _selectedSlots = State(initialValue: Set(initialSlots))
    }

    private func cellWidth(in totalWidth: CGFloat) -> CGFloat {
        max((totalWidth - timeColumnWidth) / CGFloat(max(dates.count, 1)), 56)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let cw = cellWidth(in: geo.size.width)
                let needsHScroll = CGFloat(dates.count) * cw + timeColumnWidth > geo.size.width
                let headerH: CGFloat = 36
                let gridH = CGFloat(times.count) * cellHeight

                VStack(spacing: 0) {
                    Divider()

                    ScrollView(.vertical, showsIndicators: true) {
                        HStack(alignment: .top, spacing: 0) {
                            VStack(spacing: 0) {
                                Color.clear.frame(width: timeColumnWidth, height: headerH)
                                timeAxisColumn
                            }

                            ScrollView(.horizontal, showsIndicators: needsHScroll) {
                                VStack(spacing: 0) {
                                    HStack(spacing: 0) {
                                        ForEach(dates, id: \.self) { date in
                                            Text(shortDate(date))
                                                .font(.caption2).fontWeight(.medium)
                                                .frame(width: cw, height: headerH)
                                                .lineLimit(2).multilineTextAlignment(.center)
                                        }
                                    }
                                    .background(Color(UIColor.secondarySystemBackground))
                                    Divider()
                                    HStack(alignment: .top, spacing: 0) {
                                        ForEach(dates, id: \.self) { date in
                                            dateColumn(date: date, cellWidth: cw)
                                        }
                                    }
                                }
                                .frame(width: max(CGFloat(dates.count) * cw, geo.size.width - timeColumnWidth), alignment: .leading)
                            }
                        }
                        .frame(minHeight: gridH + headerH)
                    }
                    .frame(maxHeight: .infinity)

                    if let err = errorMessage {
                        Text(err).foregroundStyle(.red).font(.caption).padding(.horizontal)
                    }
                    bottomBar
                }
            }
            .navigationTitle("選擇有空時段")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    // MARK: - 固定時間軸

    private var timeAxisColumn: some View {
        VStack(spacing: 0) {
            ForEach(times, id: \.self) { time in
                ZStack(alignment: .topTrailing) {
                    Color.clear.frame(width: timeColumnWidth, height: cellHeight)
                    if time.hasSuffix(":00") {
                        Text(time)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 4)
                            .offset(y: -1)
                    }
                }
            }
        }
    }

    private func dateColumn(date: String, cellWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(times.enumerated()), id: \.offset) { _, time in
                let label = "\(date) \(time)"
                let selected = selectedSlots.contains(label)
                Button {
                    toggleSlot(label)
                } label: {
                    Rectangle()
                        .fill(selected ? Color.green.opacity(0.7) : Color(UIColor.systemBackground))
                        .frame(width: cellWidth, height: cellHeight)
                        .overlay(alignment: .top) {
                            if time.hasSuffix(":00") {
                                Rectangle()
                                    .fill(Color(UIColor.separator).opacity(0.4))
                                    .frame(height: 0.5)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .leading) {
            Rectangle().fill(Color(UIColor.separator).opacity(0.4)).frame(width: 0.5)
        }
        .frame(width: cellWidth, height: CGFloat(times.count) * cellHeight)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text("\(selectedSlots.count) 個時段")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await saveAvailability() }
                } label: {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("儲存").fontWeight(.semibold)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
            .padding()
        }
        .background(Color(UIColor.secondarySystemBackground))
    }

    // MARK: - Helpers

    private func toggleSlot(_ label: String) {
        if selectedSlots.contains(label) { selectedSlots.remove(label) }
        else { selectedSlots.insert(label) }
    }

    private func setSlot(_ label: String, selected: Bool) {
        if selected { selectedSlots.insert(label) }
        else { selectedSlots.remove(label) }
    }

    private func shortDate(_ dateStr: String) -> String {
        let parts = dateStr.split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]) else { return dateStr }
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "zh_TW")
        var comps = DateComponents()
        comps.year = Int(parts[0]); comps.month = m; comps.day = d
        if let date = cal.date(from: comps) {
            let names = ["日","一","二","三","四","五","六"]
            return "\(m)/\(d)\n(\(names[cal.component(.weekday, from: date) - 1]))"
        }
        return "\(m)/\(d)"
    }

    private func saveAvailability() async {
        isSaving = true; errorMessage = nil
        do {
            try await W2MService.shared.submitAvailability(
                eventID: eventID,
                slots: Array(selectedSlots).sorted()
            )
            dismiss()   // 儲存完成後關閉 sheet，由 ResultView 的 onDismiss 重新載入
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
