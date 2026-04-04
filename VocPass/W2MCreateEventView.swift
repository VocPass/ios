//
//  W2MCreateEventView.swift
//  VocPass
//
//  建立「出來玩」活動：輸入標題、選擇多個日期
//

import SwiftUI

struct W2MCreateEventView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var selectedDates: Set<DateComponents> = []
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var createdEventID: String?
    @State private var navigateToAvailability = false

    private var sortedDates: [String] {
        selectedDates
            .compactMap { Calendar.current.date(from: $0) }
            .sorted()
            .map { W2MCreateEventView.dateFormatter.string(from: $0) }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var body: some View {
        NavigationStack {
            List {
                Section("活動名稱") {
                    TextField("例：吃飯約、畢業旅行", text: $title)
                }

                Section {
                    MultiDatePicker("選擇日期", selection: $selectedDates)
                } header: {
                    Text("選擇日期（可多選）")
                } footer: {
                    if !selectedDates.isEmpty {
                        Text("已選 \(selectedDates.count) 天：\(sortedDates.prefix(3).joined(separator: "、"))\(selectedDates.count > 3 ? "…" : "")")
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("建立活動")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await createEvent() }
                    } label: {
                        if isCreating {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("建立")
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || selectedDates.isEmpty || isCreating)
                }
            }
            .navigationDestination(isPresented: $navigateToAvailability) {
                if let id = createdEventID {
                    W2MResultView(eventID: id)
                }
            }
        }
    }

    private func createEvent() async {
        isCreating = true
        errorMessage = nil
        do {
            let id = try await W2MService.shared.createEvent(
                title: title.trimmingCharacters(in: .whitespaces),
                dates: sortedDates
            )
            createdEventID = id
            navigateToAvailability = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isCreating = false
    }
}
