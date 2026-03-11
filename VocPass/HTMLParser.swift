//
//  HTMLParser.swift
//  YKVS
//
//  Created by Hans on 2025/12/31.
//

import Foundation

class HTMLParser {

    // MARK: - 解析獎懲記錄
    static func parseMeritDemeritRecords(html: String) -> (merits: [MeritDemeritRecord], demerits: [MeritDemeritRecord]) {
        var merits: [MeritDemeritRecord] = []
        var demerits: [MeritDemeritRecord] = []

        print("🔍 [Parser] 解析獎懲記錄...")

        let rowPattern = #"<tr class="dataRow"[^>]*>(.*?)</tr>"#
        let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.dotMatchesLineSeparators])
        let rowMatches = rowRegex?.matches(in: html, range: NSRange(html.startIndex..., in: html)) ?? []

        print("🔍 [Parser] 找到 \(rowMatches.count) 個 dataRow")

        for match in rowMatches {
            if let range = Range(match.range(at: 1), in: html) {
                let rowContent = String(html[range])
                let cells = extractTableCells(from: rowContent)

                print("🔍 [Parser] cells: \(cells)")

                if cells.count >= 7 {
                    let record = MeritDemeritRecord(
                        dateOccurred: cells[1],
                        dateApproved: cells[2],
                        reason: cells[3],
                        action: cells[4],
                        dateRevoked: cells[5].isEmpty ? nil : cells[5],
                        year: cells[6]
                    )

                    if cells[0] == "獎勵" {
                        merits.append(record)
                    } else if cells[0] == "懲罰" {
                        demerits.append(record)
                    }
                }
            }
        }

        print("🔍 [Parser] 獎勵: \(merits.count), 懲罰: \(demerits.count)")
        return (merits, demerits)
    }

    // MARK: - 解析課表
    static func parseWeeklyCurriculum(html: String) -> [String: CourseInfo] {
        var result: [String: CourseInfo] = [:]
        let weekdayMapping = ["一", "二", "三", "四", "五", "六", "日"]

        print("🔍 [Parser] 解析課表...")

        let tablePattern = #"<table[^>]*TimeTable[^>]*>(.*?)</table>"#
        guard let tableRegex = try? NSRegularExpression(pattern: tablePattern, options: [.dotMatchesLineSeparators, .caseInsensitive]),
              let tableMatch = tableRegex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let tableRange = Range(tableMatch.range, in: html) else {
            print("❌ [Parser] 找不到 TimeTable 表格")
            return result
        }

        let tableContent = String(html[tableRange])
        print("🔍 [Parser] 找到 TimeTable，長度: \(tableContent.count)")

        let rowPattern = #"<tr[^>]*>(.*?)</tr>"#
        let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.dotMatchesLineSeparators])
        let rowMatches = rowRegex?.matches(in: tableContent, range: NSRange(tableContent.startIndex..., in: tableContent)) ?? []

        print("🔍 [Parser] 找到 \(rowMatches.count) 行")

        for (rowIndex, match) in rowMatches.enumerated() {
            if rowIndex == 0 { continue }

            if let range = Range(match.range(at: 1), in: tableContent) {
                let rowContent = String(tableContent[range])

                let hasRowspan = rowContent.contains("rowspan")
                let cells = extractTableCellsWithNewline(from: rowContent)

                var period = ""
                var courseCellsStartIndex = 0

                if hasRowspan {
                    if cells.count > 1 {
                        period = cells[1]
                        courseCellsStartIndex = 3
                    }
                } else {
                    if cells.count > 0 {
                        period = cells[0]
                        courseCellsStartIndex = 2
                    }
                }

                if let periodMatch = period.range(of: #"第(.+)節"#, options: .regularExpression) {
                    let periodStr = String(period[periodMatch])
                    period = periodStr.replacingOccurrences(of: "第", with: "").replacingOccurrences(of: "節", with: "")
                }

                if period.isEmpty { continue }

                let courseCells = cells.count > courseCellsStartIndex ? Array(cells.suffix(from: courseCellsStartIndex)) : []

                for (idx, cell) in courseCells.enumerated() {
                    let subject = cell.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
                    if subject.isEmpty { continue }

                    let weekday = weekdayMapping[idx % 7]

                    if result[subject] == nil {
                        result[subject] = CourseInfo(count: 0, schedule: [])
                    }

                    let info = result[subject]!
                    let newSchedule = info.schedule + [CourseSchedule(weekday: weekday, period: period)]
                    result[subject] = CourseInfo(count: info.count + 1, schedule: newSchedule)
                }
            }
        }

        print("🔍 [Parser] 解析到 \(result.count) 門課")
        return result
    }

    // MARK: - 解析完整課表
    static func parseTimetableData(html: String) -> TimetableData {
        var entries: [TimetableEntry] = []
        var periodTimes: [String: PeriodTime] = [:]
        let weekdayMapping = ["一", "二", "三", "四", "五", "六", "日"]

        print("🔍 [Parser] 解析完整課表（含時間）...")

        let tablePattern = #"<table[^>]*TimeTable[^>]*>(.*?)</table>"#
        guard let tableRegex = try? NSRegularExpression(pattern: tablePattern,
                                                         options: [.dotMatchesLineSeparators, .caseInsensitive]),
              let tableMatch = tableRegex.firstMatch(in: html,
                                                      range: NSRange(html.startIndex..., in: html)),
              let tableRange = Range(tableMatch.range, in: html) else {
            print("❌ [Parser] 找不到 TimeTable 表格")
            return TimetableData(entries: [], periodTimes: [:], curriculum: [:])
        }

        let tableContent = String(html[tableRange])

        let rowPattern = #"<tr[^>]*>(.*?)</tr>"#
        let rowRegex = try? NSRegularExpression(pattern: rowPattern,
                                                 options: [.dotMatchesLineSeparators])
        let rowMatches = rowRegex?.matches(in: tableContent,
                                            range: NSRange(tableContent.startIndex..., in: tableContent)) ?? []

        for (rowIndex, match) in rowMatches.enumerated() {
            if rowIndex == 0 { continue }
            guard let range = Range(match.range(at: 1), in: tableContent) else { continue }

            let rowContent = String(tableContent[range])
            let hasRowspan = rowContent.contains("rowspan")
            let cells = extractTableCellsWithNewline(from: rowContent)

            var periodLabel = ""
            var timeCell = ""
            var courseCellsStartIndex = 0

            if hasRowspan {
                guard cells.count > 2 else { continue }
                periodLabel = cells[1]
                timeCell    = cells[2]
                courseCellsStartIndex = 3
            } else {
                guard cells.count > 1 else { continue }
                periodLabel = cells[0]
                timeCell    = cells[1]
                courseCellsStartIndex = 2
            }

            var periodKey = periodLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            if let m = periodKey.range(of: #"第(.+)節"#, options: .regularExpression) {
                let raw = String(periodKey[m])
                periodKey = raw
                    .replacingOccurrences(of: "第", with: "")
                    .replacingOccurrences(of: "節", with: "")
            }
            if periodKey.isEmpty { continue }

            let timeLines = timeCell.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let timeParts = timeLines.filter {
                $0.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil
            }
            if timeParts.count >= 2 {
                periodTimes[periodKey] = PeriodTime(startTime: timeParts[0], endTime: timeParts[1])
            }

            let courseCells = cells.count > courseCellsStartIndex
                ? Array(cells[courseCellsStartIndex...])
                : []

            for (idx, cell) in courseCells.enumerated() {
                let subject = cell
                    .components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first { !$0.isEmpty } ?? ""
                guard !subject.isEmpty else { continue }

                let weekday = weekdayMapping[idx % 7]
                entries.append(TimetableEntry(weekday: weekday, period: periodKey, subject: subject))
            }
        }

        var curriculum: [String: CourseInfo] = [:]
        for entry in entries {
            let schedule = CourseSchedule(weekday: entry.weekday, period: entry.period)
            if let existing = curriculum[entry.subject] {
                curriculum[entry.subject] = CourseInfo(
                    count: existing.count + 1,
                    schedule: existing.schedule + [schedule]
                )
            } else {
                curriculum[entry.subject] = CourseInfo(count: 1, schedule: [schedule])
            }
        }

        print("🔍 [Parser] parseTimetableData: \(entries.count) 格課、\(periodTimes.count) 個節次時間")
        return TimetableData(entries: entries, periodTimes: periodTimes, curriculum: curriculum)
    }

    // MARK: - 解析缺曠記錄
    static func parseAbsenceRecords(html: String, filterTypes: [String] = ["曠", "事"]) -> [AbsenceRecord] {
        var records: [AbsenceRecord] = []

        print("🔍 [Parser] 解析缺曠記錄...")

        let tablePattern = #"<table[^>]*padding2[^>]*spacing0[^>]*>(.*?)</table>"#
        guard let tableRegex = try? NSRegularExpression(pattern: tablePattern, options: [.dotMatchesLineSeparators, .caseInsensitive]),
              let tableMatch = tableRegex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let tableRange = Range(tableMatch.range, in: html) else {
            print("❌ [Parser] 找不到缺曠表格 (padding2 spacing0)")
            return records
        }

        let tableContent = String(html[tableRange])
        print("🔍 [Parser] 找到缺曠表格，長度: \(tableContent.count)")

        var headers: [String] = []
        let headerPattern = #"<tr[^>]*td_03[^>]*>(.*?)</tr>"#
        if let headerRegex = try? NSRegularExpression(pattern: headerPattern, options: [.dotMatchesLineSeparators]),
           let headerMatch = headerRegex.firstMatch(in: tableContent, range: NSRange(tableContent.startIndex..., in: tableContent)),
           let headerRange = Range(headerMatch.range(at: 1), in: tableContent) {
            let headerContent = String(tableContent[headerRange])
            headers = extractTableCells(from: headerContent)
            print("🔍 [Parser] headers: \(headers)")
        }

        let rowPattern = #"<tr[^>]*>(.*?)</tr>"#
        let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.dotMatchesLineSeparators])
        let rowMatches = rowRegex?.matches(in: tableContent, range: NSRange(tableContent.startIndex..., in: tableContent)) ?? []

        print("🔍 [Parser] 找到 \(rowMatches.count) 行")

        for match in rowMatches.dropFirst() { 
            if let range = Range(match.range(at: 1), in: tableContent) {
                let rowContent = String(tableContent[range])
                let cells = extractTableCells(from: rowContent)

                if cells.count < 3 { continue }

                let academicTerm = cells[0]
                let date = cells[1]
                let weekday = cells[2]

                for (i, cell) in cells.enumerated().dropFirst(3) {
                    if filterTypes.isEmpty || filterTypes.contains(cell) {
                        let period = i < headers.count ? headers[i] : "\(i)"

                        if period.allSatisfy({ $0.isNumber }) && !cell.isEmpty {
                            records.append(AbsenceRecord(
                                academicYear: String(academicTerm.first ?? Character("")),
                                date: date,
                                weekday: weekday,
                                period: period,
                                status: cell
                            ))
                        }
                    }
                }
            }
        }

        print("🔍 [Parser] 解析到 \(records.count) 筆缺曠記錄")
        return records
    }

    // MARK: - 解析缺曠統計
    static func parseAttendanceStatistics(html: String) -> AttendanceStatistics {
        var statistics = AttendanceStatistics()

        print("🔍 [Parser] 解析缺曠統計...")

        var tableContent: String? = nil

        let tablePattern1 = #"<table[^>]*class="[^"]*collapse[^"]*"[^>]*style="[^"]*width:\s*100%[^"]*"[^>]*>(.*?)</table>"#
        if let tableRegex = try? NSRegularExpression(pattern: tablePattern1, options: [.dotMatchesLineSeparators, .caseInsensitive]),
           let tableMatch = tableRegex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let tableRange = Range(tableMatch.range, in: html) {
            tableContent = String(html[tableRange])
            print("🔍 [Parser] 找到統計表格 (模式1)，長度: \(tableContent!.count)")
        }

        if tableContent == nil {
            let tablePattern2 = #"<table[^>]*style="[^"]*width:\s*100%[^"]*"[^>]*class="[^"]*collapse[^"]*"[^>]*>(.*?)</table>"#
            if let tableRegex = try? NSRegularExpression(pattern: tablePattern2, options: [.dotMatchesLineSeparators, .caseInsensitive]),
               let tableMatch = tableRegex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let tableRange = Range(tableMatch.range, in: html) {
                tableContent = String(html[tableRange])
                print("🔍 [Parser] 找到統計表格 (模式2)，長度: \(tableContent!.count)")
            }
        }

        if tableContent == nil {
            let tablePattern3 = #"<table[^>]*class="[^"]*collapse[^"]*"[^>]*>(.*?)</table>"#
            if let tableRegex = try? NSRegularExpression(pattern: tablePattern3, options: [.dotMatchesLineSeparators, .caseInsensitive]),
               let tableMatch = tableRegex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let tableRange = Range(tableMatch.range, in: html) {
                tableContent = String(html[tableRange])
                print("🔍 [Parser] 找到統計表格 (模式3 - collapse)，長度: \(tableContent!.count)")
            }
        }

        guard let content = tableContent else {
            print("❌ [Parser] 找不到缺曠統計表格")

            if let dateMatch = html.range(of: #"以上資料為本學年至.*?之累計"#, options: .regularExpression) {
                statistics.statisticsDate = stripHTML(String(html[dateMatch]))
            }
            return statistics
        }

        let rowPattern = #"<tr[^>]*>(.*?)</tr>"#
        let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.dotMatchesLineSeparators])
        let rowMatches = rowRegex?.matches(in: content, range: NSRange(content.startIndex..., in: content)) ?? []

        print("🔍 [Parser] 統計表格找到 \(rowMatches.count) 行")

        var headers: [String] = []
        var currentSemester = ""
        var semesterData: [String: [String: String]] = [:]

        for (rowIndex, match) in rowMatches.enumerated() {
            if let range = Range(match.range(at: 1), in: content) {
                let rowContent = String(content[range])
                let cells = extractTableCells(from: rowContent)

                print("🔍 [Parser] Row \(rowIndex): cells.count=\(cells.count), cells=\(cells.prefix(5))...")

                if cells.count == 1 && cells[0].contains("學期") && cells[0].contains("合計") {
                    currentSemester = cells[0].replacingOccurrences(of: "合計", with: "").trimmingCharacters(in: .whitespaces)
                    semesterData[currentSemester] = [:]
                    headers = []
                    print("🔍 [Parser] 發現學期: '\(currentSemester)'")
                } else if cells.count > 1 && !currentSemester.isEmpty {
                    let nonEmptyCells = cells.filter { !$0.isEmpty }
                    if nonEmptyCells.isEmpty {
                        continue
                    }

                    if headers.isEmpty {
                        headers = cells
                        print("🔍 [Parser] headers for '\(currentSemester)': \(headers)")
                    } else {
                        print("🔍 [Parser] 資料行 for '\(currentSemester)': \(cells)")
                        for (i, header) in headers.enumerated() {
                            if i < cells.count {
                                let value = cells[i].isEmpty || cells[i] == "&nbsp;" ? "0" : cells[i]
                                semesterData[currentSemester]?[header] = value
                            }
                        }
                        headers = []
                    }
                }
            }
        }

        let firstSem = semesterData["上學期"] ?? [:]
        let secondSem = semesterData["下學期"] ?? [:]

        statistics.firstSemester = firstSem
        statistics.secondSemester = secondSem

        print("🔍 [Parser] 上學期資料: \(firstSem)")
        print("🔍 [Parser] 下學期資料: \(secondSem)")

        func getValue(_ dict: [String: String], _ keys: [String]) -> Int {
            for key in keys {
                if let value = dict[key], let intValue = Int(value) {
                    return intValue
                }
            }
            return 0
        }

        let truancy = getValue(firstSem, ["曠課"]) + getValue(secondSem, ["曠課"])

        let personalLeave = getValue(firstSem, ["事假"]) + getValue(secondSem, ["事假"]) +
                           getValue(firstSem, ["事假1"]) + getValue(secondSem, ["事假1"])

        let sickLeave = getValue(firstSem, ["病假"]) + getValue(secondSem, ["病假"]) +
                       getValue(firstSem, ["病假1"]) + getValue(secondSem, ["病假1"]) +
                       getValue(firstSem, ["病假2"]) + getValue(secondSem, ["病假2"])

        let officialLeave = getValue(firstSem, ["公假"]) + getValue(secondSem, ["公假"])

        statistics.total = AttendanceTotals(
            truancy: truancy,
            personalLeave: personalLeave,
            sickLeave: sickLeave,
            officialLeave: officialLeave
        )

        print("🔍 [Parser] 統計: 曠課=\(truancy), 事假=\(personalLeave), 病假=\(sickLeave), 公假=\(officialLeave)")

        if let dateMatch = html.range(of: #"以上資料為本學年至.*?之累計"#, options: .regularExpression) {
            statistics.statisticsDate = stripHTML(String(html[dateMatch]))
            print("🔍 [Parser] 統計日期: \(statistics.statisticsDate)")
        }

        return statistics
    }

    // MARK: - 解析學年成績
    static func parseGradeData(html: String) -> GradeData {
        var gradeData = GradeData()

        print("🔍 [Parser] 解析學年成績...")

        if let infoMatch = html.range(of: #"<div style="vertical-align: bottom;"[^>]*>(.*?)</div>"#, options: .regularExpression) {
            gradeData.studentInfo = stripHTML(String(html[infoMatch]))
            print("🔍 [Parser] 學生資訊: \(gradeData.studentInfo)")
        }

        let tablePattern = #"<table[^>]*border-collapse[^>]*>(.*?)</table>"#
        if let tableRegex = try? NSRegularExpression(pattern: tablePattern, options: [.dotMatchesLineSeparators, .caseInsensitive]),
           let tableMatch = tableRegex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let tableRange = Range(tableMatch.range, in: html) {
            let tableContent = String(html[tableRange])
            print("🔍 [Parser] 找到成績表格，長度: \(tableContent.count)")

            let rowPattern = #"<tr[^>]*>(.*?)</tr>"#
            let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.dotMatchesLineSeparators])
            let rowMatches = rowRegex?.matches(in: tableContent, range: NSRange(tableContent.startIndex..., in: tableContent)) ?? []

            print("🔍 [Parser] 找到 \(rowMatches.count) 行")

            for match in rowMatches.dropFirst(2) {
                if let range = Range(match.range(at: 1), in: tableContent) {
                    let rowContent = String(tableContent[range])
                    let cells = extractTableCells(from: rowContent)

                    if cells.count >= 8 {
                        let subject = SubjectGrade(
                            subject: cells[0],
                            firstSemester: SemesterGrade(attribute: cells[1], credit: cells[2], score: cells[3]),
                            secondSemester: SemesterGrade(attribute: cells[4], credit: cells[5], score: cells[6]),
                            yearGrade: cells[7]
                        )
                        gradeData.subjects.append(subject)
                    }
                }
            }
        } else {
            print("❌ [Parser] 找不到成績表格 (border-collapse)")
        }

        print("🔍 [Parser] 解析到 \(gradeData.subjects.count) 門課成績")
        return gradeData
    }

    // MARK: - 解析考試選單
    static func parseExamMenu(html: String, baseURL: String) -> [ExamMenuItem] {
        var menuItems: [ExamMenuItem] = []

        print("🔍 [Parser] 解析考試選單...")

        let optionPattern = #"<option[^>]*value="([^"]*)"[^>]*>([^<]*)</option>"#
        let optionRegex = try? NSRegularExpression(pattern: optionPattern, options: [])
        let optionMatches = optionRegex?.matches(in: html, range: NSRange(html.startIndex..., in: html)) ?? []

        print("🔍 [Parser] 找到 \(optionMatches.count) 個選項")

        for match in optionMatches {
            if let valueRange = Range(match.range(at: 1), in: html),
               let textRange = Range(match.range(at: 2), in: html) {
                let value = String(html[valueRange])
                let text = String(html[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)

                if !value.isEmpty && !text.isEmpty {
                    menuItems.append(ExamMenuItem(
                        name: text,
                        url: value,
                        fullURL: "\(baseURL)selection_student/\(value)"
                    ))
                }
            }
        }

        print("🔍 [Parser] 解析到 \(menuItems.count) 個考試選單")
        return menuItems
    }

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

    static func extractSemesterInfo(html: String) -> SemesterInfo? {
        let patterns = [
            #"<td[^>]*class="center"[^>]*style="[^"]*height:\s*400px[^"]*"[^>]*>(.*?)</td>"#,
            #"<td[^>]*class="center"[^>]*style="[^"]*height:400px[^"]*"[^>]*>(.*?)</td>"#,
            #"<td[^>]*style="[^"]*height:\s*400px[^"]*"[^>]*class="center"[^>]*>(.*?)</td>"#,
            #"<td[^>]*>\s*\d+<br[^>]*>.*?學<br[^>]*>.*?年<br[^>]*>.*?度<br[^>]*>.*?第<br[^>]*>.*?\d+<br[^>]*>.*?學<br[^>]*>.*?期.*?</td>"#
        ]
        
        var semesterContent: String?
        var foundPattern = 0
        
        for (index, pattern) in patterns.enumerated() {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                semesterContent = String(html[range])
                foundPattern = index + 1
                print("🔍 [Parser] 找到學期信息 (模式\(foundPattern))")
                break
            }
        }
        
        if semesterContent == nil {
            if let dateMatch = html.range(of: #"以上資料為本學年至\s*(\d+)\s*年\s*(\d+)\s*月"#, options: .regularExpression) {
                let dateStr = String(html[dateMatch])
                print("🔍 [Parser] 嘗試從統計日期推斷學期: \(dateStr)")
                
                let yearPattern = #"(\d+)\s*年"#
                let monthPattern = #"(\d+)\s*月"#
                
                var year = ""
                var month = ""
                
                if let yearRegex = try? NSRegularExpression(pattern: yearPattern),
                   let yearMatch = yearRegex.firstMatch(in: dateStr, range: NSRange(dateStr.startIndex..., in: dateStr)),
                   let yearRange = Range(yearMatch.range(at: 1), in: dateStr) {
                    year = String(dateStr[yearRange])
                }
                
                if let monthRegex = try? NSRegularExpression(pattern: monthPattern),
                   let monthMatch = monthRegex.firstMatch(in: dateStr, range: NSRange(dateStr.startIndex..., in: dateStr)),
                   let monthRange = Range(monthMatch.range(at: 1), in: dateStr) {
                    month = String(dateStr[monthRange])
                }
                
                if let monthNum = Int(month), let yearNum = Int(year) {
                    let schoolYear = monthNum >= 8 ? String(yearNum - 1911) : String(yearNum - 1912) // 轉民國年
                    let semester = monthNum >= 8 ? "1" : "2"
                    
                    print("🔍 [Parser] 從日期推斷 - 學年: \(schoolYear), 學期: \(semester)")
                    return SemesterInfo(schoolYear: schoolYear, semester: semester)
                }
            }
            
            let calendar = Calendar.current
            let now = Date()
            let currentMonth = calendar.component(.month, from: now)
            let currentYear = calendar.component(.year, from: now)
            
            let schoolYear = currentMonth >= 8 ? String(currentYear - 1911) : String(currentYear - 1912) // 轉民國年
            let semester = currentMonth >= 8 ? "1" : "2"
            
            print("🔍 [Parser] 使用當前日期推斷 - 學年: \(schoolYear), 學期: \(semester) (月份: \(currentMonth))")
            return SemesterInfo(schoolYear: schoolYear, semester: semester)
        }

        guard let content = semesterContent else {
            print("❌ [Parser] 找不到學期信息 td 元素")
            return nil
        }

        let cleanText = stripHTML(content)
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("🔍 [Parser] 清理後的學期文本: '\(cleanText)'")
        
        let yearPattern = #"(\d+)學年度"#
        let semesterPattern = #"第(\d+)學期"#
        
        var schoolYear = ""
        var semester = ""
        
        if let yearRegex = try? NSRegularExpression(pattern: yearPattern),
           let yearMatch = yearRegex.firstMatch(in: cleanText, range: NSRange(cleanText.startIndex..., in: cleanText)),
           let yearRange = Range(yearMatch.range(at: 1), in: cleanText) {
            schoolYear = String(cleanText[yearRange])
        }
        
        if let semesterRegex = try? NSRegularExpression(pattern: semesterPattern),
           let semesterMatch = semesterRegex.firstMatch(in: cleanText, range: NSRange(cleanText.startIndex..., in: cleanText)),
           let semesterRange = Range(semesterMatch.range(at: 1), in: cleanText) {
            semester = String(cleanText[semesterRange])
        }
        
        if !schoolYear.isEmpty && !semester.isEmpty {
            let result = SemesterInfo(schoolYear: schoolYear, semester: semester)
            print("🔍 [Parser] 解析學期信息: 學年=\(schoolYear), 學期=\(semester)")
            return result
        } else {
            print("❌ [Parser] 無法解析學期信息，學年='\(schoolYear)', 學期='\(semester)'")
            return nil
        }
    }

    // MARK: - 輔助函數

    private static func extractTableCellsWithNewline(from rowHTML: String) -> [String] {
        var cells: [String] = []
        let cellPattern = #"<td[^>]*>(.*?)</td>"#
        let cellRegex = try? NSRegularExpression(pattern: cellPattern, options: [.dotMatchesLineSeparators])
        let cellMatches = cellRegex?.matches(in: rowHTML, range: NSRange(rowHTML.startIndex..., in: rowHTML)) ?? []

        for match in cellMatches {
            if let range = Range(match.range(at: 1), in: rowHTML) {
                var cellContent = String(rowHTML[range])
                cellContent = cellContent.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
                cellContent = cellContent.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                cellContent = decodeHTMLEntities(cellContent)
                cellContent = cellContent.replacingOccurrences(of: "&nbsp;", with: " ")
                cellContent = cellContent.replacingOccurrences(of: "&emsp;", with: " ")
                cellContent = cellContent.replacingOccurrences(of: "&ensp;", with: " ")
                cellContent = cellContent.replacingOccurrences(of: "&thinsp;", with: " ")
                cellContent = cellContent.replacingOccurrences(of: "&amp;", with: "&")
                cellContent = cellContent.replacingOccurrences(of: "&lt;", with: "<")
                cellContent = cellContent.replacingOccurrences(of: "&gt;", with: ">")
                cellContent = cellContent.replacingOccurrences(of: "&quot;", with: "\"")
                cellContent = cellContent.replacingOccurrences(of: "&apos;", with: "'")
                cells.append(cellContent.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        return cells
    }

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

        if result.contains("&#") {
            print("🔤 [Entity] 發現 HTML 實體，原始: \(result.prefix(100))...")
        }

        let decimalPattern = #"&#(\d+);?"#
        if let regex = try? NSRegularExpression(pattern: decimalPattern, options: []) {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                if let range = Range(match.range, in: result),
                   let codeRange = Range(match.range(at: 1), in: result),
                   let code = Int(result[codeRange]),
                   let scalar = Unicode.Scalar(code) {
                    let original = String(result[range])
                    let decoded = String(Character(scalar))
                    print("🔤 [Entity] 解碼: \(original) -> \(decoded)")
                    result.replaceSubrange(range, with: decoded)
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
                    let original = String(result[range])
                    let decoded = String(Character(scalar))
                    print("🔤 [Entity] 解碼 (hex): \(original) -> \(decoded)")
                    result.replaceSubrange(range, with: decoded)
                }
            }
        }

        return result
    }
}
