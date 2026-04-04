//
//  W2MResultView.swift
//  VocPass
//

import SwiftUI

struct W2MResultView: View {
    let eventID: String
    var creatorID: String? = nil   // 從列表頁傳入，或由 event.creator 補充

    @State private var event: W2MEvent?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedSlot: W2MSlot?
    @State private var focusedUserID: String?   // 正在 highlight 的人
    @State private var showAvailability = false
    @State private var showEdit = false
    @State private var showParticipants = false

    @ObservedObject private var vocPassAuth = VocPassAuthService.shared

    private let cellHeight: CGFloat = 26
    private let timeColumnWidth: CGFloat = 44

    private var times: [String] {
        (6..<24).flatMap { h in [0, 30].map { m in String(format: "%02d:%02d", h, m) } }
    }

    private var isCreator: Bool {
        guard let me = vocPassAuth.currentUser else { return false }
        // 優先用 event.creator（詳情 API），fallback 用列表頁傳進來的 creatorID
        let cid = event?.creator?.id ?? creatorID
        return cid == me.id
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("載入中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let event = event {
                GeometryReader { geo in
                    eventContent(event, totalWidth: geo.size.width)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle).foregroundStyle(.secondary)
                    Text(errorMessage ?? "無法載入活動").foregroundStyle(.secondary)
                    Button("重試") { Task { await loadEvent() } }.buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(event?.title ?? "出來玩")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    if isCreator {
                        Button { showEdit = true } label: {
                            Image(systemName: "pencil")
                        }
                    }
                    ShareLink(item: URL(string: W2MService.shared.shareURL(for: eventID))!) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .task { await loadEvent() }
        .sheet(isPresented: $showAvailability, onDismiss: {
            Task { await loadEvent() }
        }) {
            if let event = event {
                let mySlots = currentUserSlots(in: event)
                W2MAvailabilityView(eventID: eventID, dates: event.dates, initialSlots: mySlots)
            }
        }
        .sheet(isPresented: $showEdit, onDismiss: {
            Task { await loadEvent() }
        }) {
            if let event = event {
                W2MEditEventView(event: event)
            }
        }
        .sheet(isPresented: $showParticipants) {
            if let event = event {
                W2MParticipantsView(event: event)
            }
        }
    }

    // MARK: - Event Content

    @ViewBuilder
    private func eventContent(_ event: W2MEvent, totalWidth: CGFloat) -> some View {
        let dateCount = event.uniqueDates.count
        let cw = cellWidth(totalWidth: totalWidth, dateCount: dateCount)
        let needsHScroll = CGFloat(dateCount) * cw + timeColumnWidth > totalWidth
        let headerH: CGFloat = 36
        let gridH = CGFloat(times.count) * cellHeight

        VStack(spacing: 0) {
            Divider()

            W2MSyncScrollView(
                leftWidth: timeColumnWidth,
                contentHeight: gridH,
                enableHScroll: needsHScroll,
                scrollDisabled: .constant(false),
                leftContent: {
                    // 左欄：時間軸
                    timeColumn
                },
                rightContent: {
                    // 右欄：日期表頭 + 格子
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(event.uniqueDates, id: \.self) { date in
                                Text(shortDate(date))
                                    .font(.caption2).fontWeight(.semibold)
                                    .frame(width: cw, height: headerH)
                                    .lineLimit(2).multilineTextAlignment(.center)
                            }
                            if !needsHScroll { Spacer(minLength: 0) }
                        }
                        .background(Color(UIColor.secondarySystemBackground))
                        Divider()
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(event.uniqueDates, id: \.self) { date in
                                heatColumn(for: date, event: event, cellWidth: cw)
                            }
                            if !needsHScroll { Spacer(minLength: 0) }
                        }
                    }
                }
            )
            .frame(maxHeight: .infinity)

            if let slot = selectedSlot {
                slotDetailBar(slot, event: event)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Divider()
            bottomActionBar(event)
        }
    }

    private func cellWidth(totalWidth: CGFloat, dateCount: Int) -> CGFloat {
        let natural = (totalWidth - timeColumnWidth) / CGFloat(max(dateCount, 1))
        return dateCount <= 5 ? max(natural, 52) : 64
    }

    // MARK: - Header（保留供舊呼叫，實際已不使用）
    private func headerRow(_ event: W2MEvent, cellWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: timeColumnWidth, height: 36)
            ForEach(event.uniqueDates, id: \.self) { date in
                Text(shortDate(date))
                    .font(.caption2).fontWeight(.semibold)
                    .frame(width: cellWidth, height: 36)
                    .lineLimit(2).multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
        }
        .background(Color(UIColor.secondarySystemBackground))
    }

    // MARK: - Time Column

    private var timeColumn: some View {
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

    // MARK: - Heat Column

    private func heatColumn(for date: String, event: W2MEvent, cellWidth: CGFloat) -> some View {
        // 若有 focused user，取得他在這欄的 slots
        let focusedSlots: Set<String>? = focusedUserID.flatMap { uid in
            event.availability.first(where: { $0.user.id == uid }).map { Set($0.slots) }
        }

        return VStack(spacing: 0) {
            ForEach(times, id: \.self) { time in
                let slot = W2MSlot(dateString: date, timeString: time)
                let count = event.slotCount(for: slot)
                let ratio = Double(count) / Double(event.maxCount)
                let isSlotSelected = selectedSlot == slot
                let isFocused = focusedSlots?.contains(slot.label) ?? false

                ZStack {
                    cellBackground(ratio: ratio, count: count, slotSelected: isSlotSelected, focused: isFocused, hasFocusedUser: focusedSlots != nil)
                    if time.hasSuffix(":00") {
                        VStack {
                            Divider().background(Color(UIColor.separator).opacity(0.5))
                            Spacer()
                        }
                    }
                    if !isSlotSelected {
                        if let focusedSlots, focusedSlots.contains(slot.label) {
                            // focused 模式：顯示打勾
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                        } else if focusedSlots == nil && count > 0 {
                            // 正常熱力圖：顯示人數
                            Text("\(count)")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(ratio > 0.45 ? .white : Color(UIColor.label))
                        }
                    }
                    if isSlotSelected {
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(Color.blue, lineWidth: 2)
                    }
                }
                .frame(width: cellWidth, height: cellHeight)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        if focusedUserID != nil {
                            // focused 模式下點格子清除 focus
                            focusedUserID = nil
                            selectedSlot = nil
                        } else {
                            selectedSlot = (selectedSlot == slot) ? nil : slot
                        }
                    }
                }
            }
        }
        .overlay(alignment: .leading) {
            Rectangle().fill(Color(UIColor.separator).opacity(0.4)).frame(width: 0.5)
        }
    }

    private func cellBackground(ratio: Double, count: Int, slotSelected: Bool, focused: Bool, hasFocusedUser: Bool) -> Color {
        if slotSelected { return Color.blue.opacity(0.15) }
        if hasFocusedUser {
            // focused 模式：有空=藍，沒空=灰底
            return focused
                ? Color(hue: 0.6, saturation: 0.7, brightness: 0.9)
                : Color(UIColor.systemBackground)
        }
        // 正常熱力圖
        if count == 0 { return Color(UIColor.systemBackground) }
        let saturation = 0.30 + ratio * 0.70
        let brightness = 1.0 - ratio * 0.35
        return Color(hue: 142/360, saturation: saturation, brightness: brightness)
    }

    // MARK: - Slot Detail Bar

    private func slotDetailBar(_ slot: W2MSlot, event: W2MEvent) -> some View {
        let entries = event.availability.filter { $0.slots.contains(slot.label) }
        let focusedEntry = focusedUserID.flatMap { uid in
            entries.first(where: { $0.user.id == uid }) ?? event.availability.first(where: { $0.user.id == uid })
        }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(slot.dateString) \(slot.timeString)")
                    .font(.caption).fontWeight(.semibold)
                Spacer()
                Text("\(entries.count) 人有空")
                    .font(.caption).foregroundStyle(entries.isEmpty ? Color.secondary : Color.green)
                    .fontWeight(.semibold)
                // 點 ✕ 關閉
                Button { withAnimation { selectedSlot = nil; focusedUserID = nil } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.secondary)
                }
            }
            if entries.isEmpty {
                Text("沒有人有空").font(.caption2).foregroundStyle(.secondary)
            } else {
                // 可點擊的人名標籤
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(entries, id: \.user.id) { entry in
                            let isFocused = focusedUserID == entry.user.id
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    focusedUserID = isFocused ? nil : entry.user.id
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    if let url = entry.user.avatarURL {
                                        CachedAsyncImage(url: url) { phase in
                                            if case .success(let img) = phase {
                                                img.resizable().scaledToFill()
                                                    .frame(width: 16, height: 16).clipShape(Circle())
                                            } else {
                                                Circle().fill(Color.secondary.opacity(0.3))
                                                    .frame(width: 16, height: 16)
                                            }
                                        }
                                    }
                                    Text(entry.user.displayName)
                                        .font(.caption2).fontWeight(.medium)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(isFocused ? Color.blue : Color(UIColor.tertiarySystemBackground))
                                .foregroundStyle(isFocused ? Color.white : Color.primary)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if let focusedEntry {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("正在查看：\(focusedEntry.user.displayName)")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Text("\(focusedEntry.slots.count) 個時段：\(focusedEntry.slots.sorted().prefix(4).joined(separator: "、"))\(focusedEntry.slots.count > 4 ? "…" : "")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(UIColor.secondarySystemBackground))
    }

    // MARK: - Bottom Action Bar

    private func bottomActionBar(_ event: W2MEvent) -> some View {
        let mySlots = currentUserSlots(in: event)

        return HStack {
            // 參與者資訊，點擊展開完整名單
            Button {
                showParticipants = true
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(event.availability.count) 人已填寫")
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundStyle(.primary)
                    if !event.availability.isEmpty {
                        let names = event.availability.map(\.user.displayName).sorted().prefix(3)
                        Text(names.joined(separator: "、") + (event.availability.count > 3 ? "…" : ""))
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if vocPassAuth.isLoggedIn {
                Button { showAvailability = true } label: {
                    Text(mySlots.isEmpty ? "填寫我的時段" : "編輯我的時段").fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("登入後可填寫").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
    }

    // MARK: - Helpers

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

    private func loadEvent() async {
        isLoading = true; errorMessage = nil
        do { event = try await W2MService.shared.fetchEvent(id: eventID) }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    private func currentUserSlots(in event: W2MEvent) -> [String] {
        guard let user = vocPassAuth.currentUser else { return [] }
        let identifiers = Set([
            user.id,
            user.username,
            user.name,
            user.displayName
        ].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })

        return event.availability.first(where: { entry in
            let candidates = [entry.user.id, entry.user.name, entry.user.displayName]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            return candidates.contains(where: identifiers.contains)
        })?.slots ?? []
    }
}

// MARK: - 編輯活動 Sheet（僅 creator）

struct W2MEditEventView: View {
    let event: W2MEvent
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var selectedDates: Set<DateComponents> = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    private static let df: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    init(event: W2MEvent) {
        self.event = event
        _title = State(initialValue: event.title)
        // 把現有日期轉成 DateComponents
        let cal = Calendar.current
        let initial: Set<DateComponents> = Set(event.dates.compactMap { str -> DateComponents? in
            guard let date = W2MEditEventView.df.date(from: str) else { return nil }
            return cal.dateComponents([.year, .month, .day], from: date)
        })
        _selectedDates = State(initialValue: initial)
    }

    private var sortedDates: [String] {
        selectedDates
            .compactMap { Calendar.current.date(from: $0) }
            .sorted()
            .map { W2MEditEventView.df.string(from: $0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("活動名稱") {
                    TextField("活動名稱", text: $title)
                }
                Section {
                    MultiDatePicker("選擇日期", selection: $selectedDates)
                } header: {
                    Text("日期（可多選）")
                } footer: {
                    if !selectedDates.isEmpty {
                        Text("已選 \(selectedDates.count) 天：\(sortedDates.prefix(3).joined(separator: "、"))\(selectedDates.count > 3 ? "…" : "")")
                            .foregroundStyle(.secondary)
                    }
                }
                if let err = errorMessage {
                    Section {
                        Text(err).foregroundStyle(.red).font(.subheadline)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("編輯活動")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await saveEdit() }
                    } label: {
                        if isSaving { ProgressView().controlSize(.small) }
                        else { Text("儲存") }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || selectedDates.isEmpty || isSaving)
                }
            }
        }
    }

    private func saveEdit() async {
        isSaving = true; errorMessage = nil
        do {
            try await W2MService.shared.updateEvent(
                id: event.id,
                title: title.trimmingCharacters(in: .whitespaces),
                dates: sortedDates
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

// MARK: - 參與者名單 Sheet

struct W2MParticipantsView: View {
    let event: W2MEvent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if event.availability.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.3").font(.largeTitle).foregroundStyle(.secondary)
                        Text("還沒有人填寫").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(event.availability, id: \.user.id) { entry in
                        HStack(spacing: 12) {
                            // 頭像
                            if let url = entry.user.avatarURL {
                                CachedAsyncImage(url: url) { phase in
                                    if case .success(let img) = phase {
                                        img.resizable().scaledToFill()
                                            .frame(width: 36, height: 36).clipShape(Circle())
                                    } else {
                                        Circle().fill(Color.secondary.opacity(0.2))
                                            .frame(width: 36, height: 36)
                                            .overlay(Image(systemName: "person").foregroundStyle(.secondary))
                                    }
                                }
                            } else {
                                Circle().fill(Color.secondary.opacity(0.2))
                                    .frame(width: 36, height: 36)
                                    .overlay(Image(systemName: "person").foregroundStyle(.secondary))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.user.displayName).font(.subheadline).fontWeight(.medium)
                                Text("\(entry.slots.count) 個時段有空")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("已填寫（\(event.availability.count) 人）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
