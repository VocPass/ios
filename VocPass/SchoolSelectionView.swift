//
//  SchoolSelectionView.swift
//  BSH
//
//  Created by Hans on 2026/1/11.
//

import SwiftUI

struct SchoolSelectionView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var configManager = SchoolConfigManager.shared
    @ObservedObject private var apiService = APIService.shared
    @Binding var hasSelectedSchool: Bool
    var onSchoolSelected: (() -> Void)? = nil
    @State private var showBeta = false
    @State private var searchText = ""

    private let applySchoolURL = URL(string: "https://vocpass.com/apply")
    private let privacyPolicyURL = URL(string: "https://vocpass.com/privacy-policy")
    private let disclaimerURL = URL(string: "https://vocpass.com/disclaimer")

    private var agreementText: AttributedString {
        let privacyLink = privacyPolicyURL?.absoluteString ?? "https://vocpass.com/privacy-policy"
        let disclaimerLink = disclaimerURL?.absoluteString ?? "https://vocpass.com/disclaimer"
        let markdown = "繼續使用表示你同意[隱私權政策](\(privacyLink))和[免責聲明](\(disclaimerLink))"
        return (try? AttributedString(markdown: markdown))
            ?? AttributedString("繼續使用表示你同意隱私權政策和免責聲明")
    }

    private var filteredSchools: [SchoolConfig] {
        let sourceSchools = showBeta ? configManager.allSchools : configManager.schools
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !keyword.isEmpty else { return sourceSchools }

        return sourceSchools.filter { school in
            let appName = school.app ?? ""
            return school.name.localizedCaseInsensitiveContains(keyword)
                || school.vision.localizedCaseInsensitiveContains(keyword)
                || appName.localizedCaseInsensitiveContains(keyword)
                || school.api.localizedCaseInsensitiveContains(keyword)
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(showBeta ? .orange : .blue)
                        .onTapGesture { showBeta.toggle() }

                    Text("選擇學校")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("請選擇您就讀的學校")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 28)
                
                if configManager.isLoading {
                    Spacer()
                    ProgressView("載入中...")
                    Spacer()
                } else if configManager.schools.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        Text(configManager.error ?? "無法載入學校列表")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        Button("重試") {
                            configManager.loadSchools()
                        }
                        .buttonStyle(.bordered)
                    }
                    Spacer()
                } else {
                    VStack(spacing: 0) {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)

                            TextField("搜尋學校", text: $searchText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)

                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                        .padding(.horizontal)

                        if filteredSchools.isEmpty && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Spacer()
                            VStack(spacing: 10) {
                                Image(systemName: "magnifyingglass")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                Text("找不到符合的學校")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        } else {
                            List {
                                Section {
                                    SchoolRowView(school: SchoolConfig.guest) {
                                        selectSchool(SchoolConfig.guest)
                                    }
                                } footer: {
                                    Text("訪客模式不需登入，可直接使用課表功能（手動輸入）。")
                                }

                                if !filteredSchools.isEmpty {
                                    Section {
                                        ForEach(filteredSchools) { school in
                                            SchoolRowView(school: school) {
                                                selectSchool(school)
                                            }
                                        }
                                    }
                                }
                            }
                            .listStyle(.insetGrouped)
                        }

                        Button {
                            guard let applySchoolURL else { return }
                            openURL(applySchoolURL)
                        } label: {
                            Label("申請新增學校", systemImage: "plus.circle")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal)
                        .padding(.top, 8)

                            Spacer(minLength: 16)

                            Text(agreementText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .tint(.accentColor)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 16)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("關閉", systemImage: "xmark") {
                        dismiss()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear {
            if configManager.schools.isEmpty {
                configManager.loadSchools()
            }
        }
    }
    
    private func selectSchool(_ school: SchoolConfig) {
        if configManager.hasSelectedSchool {
            apiService.logout()
        }
        configManager.selectSchool(school)
        hasSelectedSchool = true
        onSchoolSelected?()
        dismiss()
    }
}

// MARK: - 學校列表項目
struct SchoolRowView: View {
    let school: SchoolConfig
    let onSelect: () -> Void
    
    var body: some View {
        let tint: Color = school.isGuest ? .green : .blue
        let iconName = school.isGuest ? "person.fill.questionmark" : "graduationcap.fill"

        Button(action: onSelect) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.1))
                        .frame(width: 50, height: 50)

                    Image(systemName: iconName)
                        .font(.title2)
                        .foregroundColor(tint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(school.name)
                            .font(.headline)
                            .foregroundColor(.primary)

                        if school.beta {
                            Text("Beta")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }

                    Text(school.isGuest ? "免登入 · 僅支援課表" : school.api)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SchoolSelectionView(hasSelectedSchool: .constant(false))
}
