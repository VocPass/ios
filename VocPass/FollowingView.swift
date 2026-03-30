//
//  FollowingView.swift
//  VocPass
//

import SwiftUI

// MARK: - 追蹤名單

struct FollowingListView: View {
    @EnvironmentObject var apiService: APIService
    @State private var followed: [String] = CacheService.shared.followedUsernames
    @State private var showAddAlert = false
    @State private var newUsername = ""
    @State private var userProfiles: [String: VocPassPublicUser] = [:]

    var body: some View {
        NavigationStack {
            List {
                if followed.isEmpty {
                    ContentUnavailableView(
                        "尚無追蹤對象",
                        systemImage: "person.2.slash",
                        description: Text("點擊右上角「+」新增")
                    )
                } else {
                    ForEach(followed, id: \.self) { username in
                        NavigationLink {
                            SharedCurriculumView(username: username, publicProfile: userProfiles[username])
                                .environmentObject(apiService)
                        } label: {
                            HStack(spacing: 10) {
                                let profile = userProfiles[username]
                                if let avatarURL = profile?.avatarURL {
                                    CachedAsyncImage(url: avatarURL) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 36, height: 36)
                                                .clipShape(Circle())
                                        default:
                                            Image(systemName: "person.circle.fill")
                                                .font(.system(size: 36))
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                } else {
                                    Image(systemName: "person.circle.fill")
                                        .font(.system(size: 36))
                                        .foregroundStyle(.blue)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    if let name = profile?.name, !name.isEmpty {
                                        Text(name)
                                            .font(.body)
                                    }
                                    Text("@\(username)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .task(id: username) {
                            if userProfiles[username] == nil {
                                userProfiles[username] = try? await VocPassAuthService.shared.fetchUser(username: username)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        followed.remove(atOffsets: indexSet)
                        CacheService.shared.followedUsernames = followed
                        PhoneConnectivityManager.shared.pushFollowedUsernames(followed)
                    }
                }
            }
            .navigationTitle("已追蹤課表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        newUsername = ""
                        showAddAlert = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("新增追蹤", isPresented: $showAddAlert) {
                TextField("輸入用戶名稱", text: $newUsername)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("新增") {
                    let name = newUsername.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty, !followed.contains(name) else { return }
                    followed.append(name)
                    CacheService.shared.followedUsernames = followed
                    PhoneConnectivityManager.shared.pushFollowedUsernames(followed)
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("輸入對方的 VocPass 用戶名稱")
            }
        }
    }
}

// MARK: - 他人課表（唯讀）

struct SharedCurriculumView: View {
    let username: String
    var publicProfile: VocPassPublicUser? = nil

    @EnvironmentObject var apiService: APIService
    @State private var curriculum: [String: CourseInfo] = [:]
    @State private var periodTimes: [String: PeriodTime] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var fetchedProfile: VocPassPublicUser?

    private var displayProfile: VocPassPublicUser? { fetchedProfile ?? publicProfile }

    private let weekdays = ["一", "二", "三", "四", "五"]
    private let periodOrder = ["早讀", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十",
                                "1", "2", "3", "4", "5", "6", "7", "8", "9", "10"]
    private let defaultPeriods = ["一", "二", "三", "四", "五", "六", "七", "八"]

    private var periods: [String] {
        let all = curriculum.values.flatMap { $0.schedule.map { $0.period } }
        let unique = Array(Set(all)).filter { !$0.isEmpty }
        if unique.isEmpty { return defaultPeriods }
        return unique.sorted {
            let ia = periodOrder.firstIndex(of: $0) ?? Int.max
            let ib = periodOrder.firstIndex(of: $1) ?? Int.max
            if ia != Int.max || ib != Int.max { return ia < ib }
            return (Int($0) ?? 0) < (Int($1) ?? 0)
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("載入中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                    Text(error)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("重試") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    sharedGrid
                        .padding()
                }
                .refreshable { await load() }
            }
        }
        .navigationTitle("@\(username) 的課表")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if let avatarURL = displayProfile?.avatarURL {
                    CachedAsyncImage(url: avatarURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 30, height: 30)
                                .clipShape(Circle())
                        default:
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
        .task {
            await load()
            if fetchedProfile == nil && publicProfile == nil {
                fetchedProfile = try? await VocPassAuthService.shared.fetchUser(username: username)
            }
        }
    }

    // MARK: - Grid

    private var sharedGrid: some View {
        VStack(spacing: 1) {
            // Header row
            HStack(spacing: 1) {
                Text("節次")
                    .frame(width: 40, height: 40)
                    .background(Color(.systemGray5))
                    .font(.caption)

                ForEach(weekdays, id: \.self) { day in
                    Text("週\(day)")
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Color(.systemGray5))
                        .font(.caption)
                }
            }

            ForEach(periods, id: \.self) { period in
                HStack(spacing: 1) {
                    // Period label
                    VStack(spacing: 1) {
                        Text(period == "早讀" ? "讀" : period)
                            .font(.caption)
                        if let pt = periodTimes[period] {
                            Text(pt.startTime)
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                            Text(pt.endTime)
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 40, height: 68)
                    .background(Color(.systemGray6))

                    ForEach(weekdays, id: \.self) { day in
                        let subject = subjectAt(weekday: day, period: period)
                        let extra   = extraAt(weekday: day, period: period)
                        let meta    = [extra.room, extra.teacher].filter { !$0.isEmpty }.joined(separator: "・")

                        VStack(spacing: 2) {
                            Text(subject.isEmpty ? " " : subject)
                                .font(.system(size: 11))
                                .foregroundStyle(subject.isEmpty ? .clear : .primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                            if !meta.isEmpty {
                                Text(meta)
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.horizontal, 2)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, minHeight: 68)
                        .background(subject.isEmpty ? Color(.systemGray6) : Color(.systemBackground))
                    }
                }
            }
        }
        .background(Color(.systemGray4))
        .cornerRadius(8)
    }

    // MARK: - Helpers

    private func subjectAt(weekday: String, period: String) -> String {
        for (subject, info) in curriculum {
            for schedule in info.schedule where schedule.weekday == weekday && schedule.period == period {
                return subject
            }
        }
        return ""
    }

    private func extraAt(weekday: String, period: String) -> CourseExtra {
        for (_, info) in curriculum {
            for schedule in info.schedule where schedule.weekday == weekday && schedule.period == period {
                return CourseExtra(room: schedule.room ?? "", teacher: schedule.teacher ?? "")
            }
        }
        return CourseExtra(room: "", teacher: "")
    }

    private func load() async {
        await MainActor.run { isLoading = true; errorMessage = nil }
        do {
            let timetable = try await apiService.fetchSharedCurriculum(username: username)
            await MainActor.run {
                self.curriculum = timetable.curriculum
                self.periodTimes = timetable.periodTimes
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}
