//
//  HTMLParser.swift
//  YKVS
//
//  Created by Hans on 2025/12/31.
//

import Foundation

class HTMLParser {

    // MARK: - 解析考試成績
    static func parseExamScores(html: String) -> ExamScoreData {
        var examData = ExamScoreData()

        print("🔍 [Parser] 解析考試成績...")

        if let studentIdMatch = html.range(of: #"學號：(\d+)"#, options: .regularExpression) {
            let match = String(html[studentIdMatch])
            examData.studentInfo = StudentInfo(
                studentId: match.replacingOccurrences(of: "學號：", with: ""),
                name: "",
                className: ""
            )
        }

        if let examInfoMatch = html.range(of: #"<span class="bluetext"[^>]*>(.*?)</span>"#, options: .regularExpression) {
            examData.examInfo = stripHTML(String(html[examInfoMatch]))
        }

        let tablePattern = #"<table[^>]*id="Table1"[^>]*>(.*?)</table>"#
        if let tableRegex = try? NSRegularExpression(pattern: tablePattern, options: [.dotMatchesLineSeparators, .caseInsensitive]),
           let tableMatch = tableRegex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let tableRange = Range(tableMatch.range, in: html) {
            let tableContent = String(html[tableRange])
            let rowPattern = #"<tr[^>]*>(.*?)</tr>"#
            let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.dotMatchesLineSeparators])
            let rowMatches = rowRegex?.matches(in: tableContent, range: NSRange(tableContent.startIndex..., in: tableContent)) ?? []

            for match in rowMatches.dropFirst() {
                if let range = Range(match.range(at: 1), in: tableContent) {
                    let rowContent = String(tableContent[range])
                    let cells = extractTableCells(from: rowContent)

                    if cells.count >= 3 && !cells[0].isEmpty {
                        examData.subjects.append(ExamSubjectScore(
                            subject: cells[0],
                            personalScore: cells[1],
                            classAverage: cells[2]
                        ))
                    }
                }
            }
        }

        print("🔍 [Parser] 解析到 \(examData.subjects.count) 門考試成績")
        return examData
    }

    // MARK: - 輔助函數

    private static func extractTableCells(from rowHTML: String) -> [String] {
        var cells: [String] = []
        let cellPattern = #"<t[dh][^>]*>(.*?)</t[dh]>"#
        let cellRegex = try? NSRegularExpression(pattern: cellPattern, options: [.dotMatchesLineSeparators])
        let cellMatches = cellRegex?.matches(in: rowHTML, range: NSRange(rowHTML.startIndex..., in: rowHTML)) ?? []

        for match in cellMatches {
            if let range = Range(match.range(at: 1), in: rowHTML) {
                let cellContent = stripHTML(String(rowHTML[range]))
                cells.append(cellContent.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        return cells
    }

    private static func stripHTML(_ html: String) -> String {
        var result = html
        result = result.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&apos;", with: "'")
        result = decodeHTMLEntities(result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeHTMLEntities(_ string: String) -> String {
        var result = string

        let decimalPattern = #"&#(\d+);?"#
        if let regex = try? NSRegularExpression(pattern: decimalPattern, options: []) {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                if let range = Range(match.range, in: result),
                   let codeRange = Range(match.range(at: 1), in: result),
                   let code = Int(result[codeRange]),
                   let scalar = Unicode.Scalar(code) {
                    result.replaceSubrange(range, with: String(Character(scalar)))
                }
            }
        }
        let hexPattern = #"&#[xX]([0-9a-fA-F]+);?"#
        if let regex = try? NSRegularExpression(pattern: hexPattern, options: []) {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                if let range = Range(match.range, in: result),
                   let codeRange = Range(match.range(at: 1), in: result),
                   let code = Int(result[codeRange], radix: 16),
                   let scalar = Unicode.Scalar(code) {
                    result.replaceSubrange(range, with: String(Character(scalar)))
                }
            }
        }

        return result
    }
}
