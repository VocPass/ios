//
//  DataExportView.swift
//  VocPass
//
//  資料匯出頁面：一鍵抓取每個學期的所有校務資料，匯出成單一 JSON 檔案。
//

import SwiftUI

struct DataExportView: View {
    @EnvironmentObject var apiService: APIService

    @State private var isExporting = false
    @State private var progress: Double = 0
    @State private var statusMessage = ""
    @State private var result: DataExportResult?
    @State private var errorMessage: String?

    /// 線上解析頁面：使用者可將匯出的 JSON 上傳此處解讀。
    private let parseURL = URL(string: "\(AppConfig.defaultHost)/export")!

    var body: some View {
        List {
            Section {
                Text("將你的課表、缺曠、獎懲、各學年成績與所有考試成績，一次抓取並打包成單一 JSON 檔案，方便備份或自行分析。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Section {
                if isExporting {
                    VStack(alignment: .leading, spacing: 10) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                        HStack {
                            Text(statusMessage.isEmpty ? "處理中…" : statusMessage)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(progress * 100))%")
                                .font(.footnote.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Button {
                        Task { await runExport() }
                    } label: {
                        Label(result == nil ? "開始匯出" : "重新匯出", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!apiService.isLoggedIn)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            } footer: {
                if !apiService.isLoggedIn {
                    Text("請先登入學校帳號才能匯出資料。")
                        .foregroundColor(.orange)
                }
            }

            if let error = errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundColor(.red)
                }
            }

            if let result {
                Section("匯出結果") {
                    ForEach(result.sections) { section in
                        HStack {
                            Image(systemName: section.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(section.success ? .green : .orange)
                            Text(section.title)
                            Spacer()
                            Text(section.detail)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                Section {
                    ShareLink(item: result.fileURL) {
                        Label("分享 / 儲存 JSON 檔案", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    Text("檔案")
                } footer: {
                    Text("\(result.fileName)（\(formattedSize(result.byteCount))）")
                }
            }

            Section {
                Link(destination: parseURL) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("到線上工具解析這份資料")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } footer: {
                Text("將匯出的 JSON 上傳至 \(parseURL.absoluteString) 即可以圖表方式檢視你的成績與缺曠。")
            }
        }
        .navigationTitle("資料匯出")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func runExport() async {
        isExporting = true
        errorMessage = nil
        result = nil
        progress = 0
        statusMessage = "準備中…"

        do {
            let output = try await apiService.exportAllSchoolData { fraction, message in
                progress = fraction
                statusMessage = message
            }
            await MainActor.run {
                self.result = output
                self.isExporting = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isExporting = false
            }
        }
    }

    private func formattedSize(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

#Preview {
    NavigationStack {
        DataExportView()
            .environmentObject(APIService.shared)
    }
}
