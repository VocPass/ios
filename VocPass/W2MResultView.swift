//
//  W2MResultView.swift
//  VocPass
//

import SwiftUI

struct W2MResultView: View {
    let eventID: String
    var creatorID: String? = nil

    @State private var event: W2MEvent?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedSlot: W2MSlot?
    @State private var focusedUserID: String?
    @State private var showAvailability = false
    @State private var showEdit = false
    @State private var showParticipants = false
    @State private var showUserDetail: W2MUserAvailability?

    @ObservedObject private var vocPassAuth = VocPassAuthService.shared

    private let cellHeight: CGFloat = 26
    private let timeColumnWidth: CGFloat = 44
    private let headerHeight: CGFloat = 36

    private var times: [String] {
        (6..<24).flatMap { h in [0, 30].map { m in String(format: "%02d:%02d", h, m) } }
    }

    private var isCreator: Bool {
        guard let me = vocPassAuth.currentUser else { return false }
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
                W2MParticipantsView(event: event) { entry in
                    showParticipants = false
                    // 短延遲讓 sheet dismiss 完再開新 sheet
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        focusedUserID = entry.user.id
                        showUserDetail = entry
                    }
                }
            }
        }
        .sheet(item: $showUserDetail) { entry in
            if let event = event {
                W2MUserDetailView(entry: entry, event: event)
            }
        }
    }

    // MARK: - Event Content

    @ViewBuilder
    private func eventContent(_ event: W2MEvent, totalWidth: CGFloat) -> some View {
        let dateCount = event.uniqueDates.count
        let cw = cellWidth(totalWidth: totalWidth, dateCount: dateCount)
        let totalContentWidth = CGFloat(dateCount) * cw
        let needsHScroll = totalContentWidth + timeColumnWidth > totalWidth
        let gridH = CGFloat(times.count) * cellHeight
        let rightTotalH = headerHeight + 1 + gridH

        VStack(spacing: 0) {
            Divider()

            W2MSyncScrollView(
                leftWidth: timeColumnWidth,
                contentHeight: rightTotalH,
                rightContentWidth: totalContentWidth,
                enableHScroll: needsHScroll,
                scrollDisabled: .constant(false),
                leftContent: {
                    VStack(spacing: 0) {
                        Color.clear.frame(width: timeColumnWidth, height: headerHeight + 1)
                        timeColumn
                    }
                },
                rightContent: {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(event.uniqueDates, id: \.self) { date in
                                Text(shortDate(date))
                                    .font(.caption2).fontWeight(.semibold)
                                    .frame(width: cw, height: headerHeight)
                                    .lineLimit(2).multilineTextAlignment(.center)
                            }
                        }
                        .background(Color(UIColor.secondarySystemBackground))
                        Divider()
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(event.uniqueDates, id: \.self) { date in
                                heatColumn(for: date, event: event, cellWidth: cw)
                            }
                        }
                    }
                }
            )
            .frame(maxHeight: .infinity)

            if let slot = selectedSlot {
                slotDetailBar(slot, event: event)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let uid = focusedUserID,
                      let entry = event.availability.first(where: { $0.user.id == uid }) {
                focusedUserBar(entry)
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
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                        } else if focusedSlots == nil && count > 0 {
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
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        selectedSlot = (selectedSlot == slot) ? nil : slot
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
            return focused
                ? Color(hue: 0.6, saturation: 0.7, brightness: 0.9)
                : Color(UIColor.systemBackground)
        }
        if count == 0 { return Color(UIColor.systemBackground) }
        let saturation = 0.30 + ratio * 0.70
        let brightness = 1.0 - ratio * 0.35
        return Color(hue: 142/360, saturation: saturation, brightness: brightness)
    }

    // MARK: - Slot Detail Bar

    private func slotDetailBar(_ slot: W2MSlot, event: W2MEvent) -> some View {
        let entries = event.availability.filter { $0.slots.contains(slot.label) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(slot.dateString) \(slot.timeString)")
                    .font(.caption).fontWeight(.semibold)
                Spacer()
                Text("\(entries.count) 人有空")
                    .font(.caption).foregroundStyle(entries.isEmpty ? Color.secondary : Color.green)
                    .fontWeight(.semibold)
                Button { withAnimation { selectedSlot = nil; focusedUserID = nil } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.secondary)
                }
            }
            if entries.isEmpty {
                Text("沒有人有空").font(.caption2).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(entries, id: \.user.id) { entry in
                            let isFocused = focusedUserID == entry.user.id
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    if isFocused {
                                        focusedUserID = nil
                                    } else {
                                        focusedUserID = entry.user.id
                                    }
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
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(UIColor.secondarySystemBackground))
    }

    // MARK: - Focused User Bar

    private func focusedUserBar(_ entry: W2MUserAvailability) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("正在查看：\(entry.user.displayName)")
                    .font(.caption).fontWeight(.semibold)
                Text("\(entry.slots.count) 個時段有空")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showUserDetail = entry
            } label: {
                Text("詳細")
                    .font(.caption).fontWeight(.medium)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            Button {
                withAnimation { focusedUserID = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.secondary)
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
        return event.availability.first(where: { $0.user.id == user.id })?.slots ?? []
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

// MARK: - 參與者名單（點人查看時段）

struct W2MParticipantsView: View {
    let event: W2MEvent
    var onSelectUser: ((W2MUserAvailability) -> Void)?
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
                        Button {
                            if let onSelectUser {
                                onSelectUser(entry)
                            }
                        } label: {
                            HStack(spacing: 12) {
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
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
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

// MARK: - 用戶時段詳細頁（時間表格式顯示某人有空的時段）

struct W2MUserDetailView: View {
    let entry: W2MUserAvailability
    let event: W2MEvent
    @Environment(\.dismiss) private var dismiss

    private let cellHeight: CGFloat = 22
    private let timeColWidth: CGFloat = 44
    private let dateColWidth: CGFloat = 56

    private var times: [String] {
        (6..<24).flatMap { h in [0, 30].map { m in String(format: "%02d:%02d", h, m) } }
    }

    private var slotSet: Set<String> { Set(entry.slots) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 用戶資訊
                    HStack(spacing: 12) {
                        if let url = entry.user.avatarURL {
                            CachedAsyncImage(url: url) { phase in
                                if case .success(let img) = phase {
                                    img.resizable().scaledToFill()
                                        .frame(width: 48, height: 48).clipShape(Circle())
                                } else {
                                    Circle().fill(Color.secondary.opacity(0.2))
                                        .frame(width: 48, height: 48)
                                        .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
                                }
                            }
                        } else {
                            Circle().fill(Color.secondary.opacity(0.2))
                                .frame(width: 48, height: 48)
                                .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.user.displayName)
                                .font(.title3).fontWeight(.semibold)
                            Text("\(entry.slots.count) 個時段有空")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)

                    // 時間表格
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(spacing: 0) {
                            // 表頭
                            HStack(spacing: 0) {
                                Text("")
                                    .frame(width: timeColWidth, height: 32)
                                ForEach(event.uniqueDates, id: \.self) { date in
                                    Text(shortDate(date))
                                        .font(.caption2).fontWeight(.semibold)
                                        .frame(width: dateColWidth, height: 32)
                                        .lineLimit(2).multilineTextAlignment(.center)
                                }
                            }
                            .background(Color(UIColor.tertiarySystemBackground))

                            Divider()

                            // 格子
                            ForEach(times, id: \.self) { time in
                                HStack(spacing: 0) {
                                    // 時間標籤
                                    ZStack {
                                        Color.clear.frame(width: timeColWidth, height: cellHeight)
                                        if time.hasSuffix(":00") {
                                            Text(time)
                                                .font(.system(size: 9))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    // 每天的格子
                                    ForEach(event.uniqueDates, id: \.self) { date in
                                        let label = "\(date) \(time)"
                                        let available = slotSet.contains(label)
                                        ZStack {
                                            Rectangle()
                                                .fill(available
                                                      ? Color(hue: 0.6, saturation: 0.7, brightness: 0.9)
                                                      : Color(UIColor.systemBackground))
                                            if available {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 8, weight: .bold))
                                                    .foregroundStyle(.white)
                                            }
                                            if time.hasSuffix(":00") {
                                                VStack {
                                                    Divider()
                                                    Spacer()
                                                }
                                            }
                                        }
                                        .frame(width: dateColWidth, height: cellHeight)
                                        .overlay(alignment: .leading) {
                                            Rectangle().fill(Color(UIColor.separator).opacity(0.3)).frame(width: 0.5)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(UIColor.separator).opacity(0.3)))
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle(entry.user.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
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
}
