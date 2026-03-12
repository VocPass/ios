//
//  SchoolSelectionView.swift
//  BSH
//
//  Created by Hans on 2026/1/11.
//

import SwiftUI

struct SchoolSelectionView: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject var configManager = SchoolConfigManager.shared
    @Binding var hasSelectedSchool: Bool

    private let applySchoolURL = URL(string: "https://forms.gle/t145dao5K2DHkxa2A")
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue)
                    
                    Text("選擇學校")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("請選擇您就讀的學校")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 40)
                
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
                        List(configManager.schools) { school in
                            SchoolRowView(school: school) {
                                selectSchool(school)
                            }
                        }
                        .listStyle(.insetGrouped)

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
                        .padding(.bottom, 16)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarHidden(true)
        }
        .onAppear {
            if configManager.schools.isEmpty {
                configManager.loadSchools()
            }
        }
    }
    
    private func selectSchool(_ school: SchoolConfig) {
        configManager.selectSchool(school)
        hasSelectedSchool = true
    }
}

// MARK: - 學校列表項目
struct SchoolRowView: View {
    let school: SchoolConfig
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "graduationcap.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(school.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(school.api)
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
