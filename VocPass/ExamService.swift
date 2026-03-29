//
//  ExamService.swift
//  VocPass
//

import Foundation

extension APIService {

    // MARK: - 考試成績選單
    func fetchExamMenu() async throws -> [ExamMenuItem] {
        let response: APIResponse<[ExamMenuItem]> = try await proxyGet(path: "exam_menu")
        return response.data
    }

    // MARK: - 考試成績詳情
    func fetchExamScore(fileName: String) async throws -> ExamScoreData {
        let encoded = Data(fileName.utf8).base64EncodedString()
        let response: APIResponse<ExamScoreData> = try await proxyGet(
            path: "exam_results",
            extraQueryItems: [URLQueryItem(name: "exam", value: encoded)]
        )
        return response.data
    }
}
