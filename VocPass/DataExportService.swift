//
//  DataExportService.swift
//  VocPass
//
//  自動抓取每個學期的每一項校務資料，彙整成單一 JSON 檔案。
//

import Foundation

// MARK: - 匯出結果

/// 單一項目（例如「一年級成績」「第一次段考」）的匯出狀態
struct DataExportSection: Identifiable {
    let id = UUID()
    let title: String
    let success: Bool
    let detail: String      // 成功時為簡述，失敗時為錯誤訊息
}

/// 完整匯出結果
struct DataExportResult {
    let fileURL: URL
    let fileName: String
    let byteCount: Int
    let sections: [DataExportSection]
}

extension APIService {

    /// 抓取所有校務資料並產生單一 JSON 檔案。
    /// - Parameter onProgress: 於主執行緒回報進度（0...1）與目前步驟說明。
    /// - Returns: 匯出結果，包含暫存檔 URL 與各項目狀態。
    func exportAllSchoolData(
        onProgress: @escaping @MainActor (_ fraction: Double, _ message: String) -> Void
    ) async throws -> DataExportResult {
        guard let school = SchoolConfigManager.shared.selectedSchool else {
            throw APIError.noSchoolSelected
        }

        await MainActor.run { onProgress(0, "準備中…") }

        // 先取得考試清單，才能算出總步數
        var examMenu: [ExamMenuItem] = []
        var examMenuError: String?
        do {
            examMenu = try await fetchExamMenu()
        } catch APIError.featureNotSupported {
            examMenuError = nil     // 此校不支援考試成績，靜默略過
        } catch {
            examMenuError = error.localizedDescription
        }

        // 固定步驟：課表、缺曠、獎懲、三個學年成績；動態步驟：每次考試
        let totalSteps = max(3 + 3 + examMenu.count, 1)
        var completed = 0
        var sections: [DataExportSection] = []
        var root: [String: Any] = [:]

        func report(_ message: String) async {
            let fraction = min(Double(completed) / Double(totalSteps), 1)
            await MainActor.run { onProgress(fraction, message) }
        }

        // MARK: 課表
        await report("正在抓取課表…")
        let curriculum = await fetchSectionPayload(path: "curriculum", title: "課表")
        root["curriculum"] = curriculum.payload
        sections.append(curriculum.section)
        completed += 1

        // MARK: 缺曠
        await report("正在抓取缺曠…")
        let attendance = await fetchSectionPayload(path: "attendance", title: "缺曠")
        root["attendance"] = attendance.payload
        sections.append(attendance.section)
        completed += 1

        // MARK: 獎懲
        await report("正在抓取獎懲…")
        let merit = await fetchSectionPayload(path: "merit_demerit", title: "獎懲")
        root["merit_demerit"] = merit.payload
        sections.append(merit.section)
        completed += 1

        // MARK: 各學年成績
        var semesterScores: [String: Any] = [:]
        for year in 1...3 {
            await report("正在抓取 \(year) 年級成績…")
            let result = await fetchSectionPayload(
                path: "semester_scores",
                title: "\(year) 年級學年成績",
                extraQueryItems: [URLQueryItem(name: "semester", value: "\(year)")]
            )
            if let payload = result.payload { semesterScores["\(year)"] = payload }
            sections.append(result.section)
            completed += 1
        }
        root["semester_scores"] = semesterScores

        // MARK: 各次考試成績
        var exams: [[String: Any]] = []
        for exam in examMenu {
            await report("正在抓取考試：\(exam.name)…")
            let encoded = Data(exam.url.utf8).base64EncodedString()
            let result = await fetchSectionPayload(
                path: "exam_results",
                title: "考試：\(exam.name)",
                extraQueryItems: [URLQueryItem(name: "exam", value: encoded)]
            )
            var entry: [String: Any] = ["name": exam.name, "file": exam.url]
            if let payload = result.payload { entry["data"] = payload }
            exams.append(entry)
            sections.append(result.section)
            completed += 1
        }
        root["exams"] = exams
        if let examMenuError {
            sections.append(DataExportSection(title: "考試清單", success: false, detail: examMenuError))
        }

        // MARK: 中繼資料
        let now = Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        root["_meta"] = [
            "exported_at": iso.string(from: now),
            "app_version": appVersion,
            "school": school.name,
            "schema_version": 1,
        ]

        // MARK: 寫出檔案
        await MainActor.run { onProgress(1, "正在產生檔案…") }
        let jsonData = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let safeSchool = school.name.replacingOccurrences(of: "/", with: "_")
        let fileName = "VocPass_\(safeSchool)_\(dateFormatter.string(from: now)).json"

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
        try jsonData.write(to: fileURL, options: .atomic)

        await MainActor.run { onProgress(1, "匯出完成") }

        return DataExportResult(
            fileURL: fileURL,
            fileName: fileName,
            byteCount: jsonData.count,
            sections: sections
        )
    }

    // MARK: - Helpers

    /// 抓取單一端點的原始 JSON，取出 `data` 欄位（若有）作為 payload，
    /// 並回傳成功/失敗狀態。任何錯誤都不會中斷整體匯出。
    private func fetchSectionPayload(
        path: String,
        title: String,
        extraQueryItems: [URLQueryItem] = []
    ) async -> (payload: Any?, section: DataExportSection) {
        do {
            let data = try await proxyGetData(path: path, extraQueryItems: extraQueryItems)
            let payload = Self.extractPayload(from: data)
            let section = DataExportSection(title: title, success: true, detail: Self.describe(payload))
            return (payload, section)
        } catch APIError.featureNotSupported {
            return (nil, DataExportSection(title: title, success: false, detail: "此校不支援"))
        } catch {
            return (nil, DataExportSection(title: title, success: false, detail: error.localizedDescription))
        }
    }

    /// 解析原始回應：若外層是 `{code,message,data}` 包裝則取出 `data`，否則回傳整包。
    private static func extractPayload(from data: Data) -> Any? {
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        if let dict = obj as? [String: Any], let inner = dict["data"] {
            return inner
        }
        return obj
    }

    /// 產生給使用者看的簡短摘要（例如「12 筆」）。
    private static func describe(_ payload: Any?) -> String {
        switch payload {
        case let array as [Any]:
            return "\(array.count) 筆"
        case let dict as [String: Any]:
            return "\(dict.count) 個欄位"
        case is NSNull, .none:
            return "無資料"
        default:
            return "已取得"
        }
    }
}
