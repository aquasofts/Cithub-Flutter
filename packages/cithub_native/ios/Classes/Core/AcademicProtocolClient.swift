import Foundation

public enum AcademicServerRouter {
    private static let baseURLs = [
        URL(string: "https://http-10-198-47-147-8080.webvpn.ccit.edu.cn/jsxsd/")!,
        URL(string: "https://http-10-198-47-147-8081.webvpn.ccit.edu.cn/jsxsd/")!,
        URL(string: "https://http-10-198-47-148-8080.webvpn.ccit.edu.cn/jsxsd/")!,
        URL(string: "https://http-10-198-47-148-8081.webvpn.ccit.edu.cn/jsxsd/")!,
    ]

    public static func baseURL(for username: String) -> URL {
        let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let index: Int
        if !normalized.isEmpty, normalized.allSatisfy(\.isNumber) {
            index = normalized.reduce(0) { partial, character in
                (partial * 10 + (character.wholeNumberValue ?? 0)) % baseURLs.count
            }
        } else { index = 0 }
        return baseURLs[index]
    }
}

public actor AcademicProtocolClient {
    private static let browserUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    private let store: any SecretStore
    private let logger: any RuntimeLogger
    private let transport: any HTTPTransport
    private let cookies: CookieHeaderStore
    private let automaticServerRouting: Bool
    private var baseURL: URL
    private var timetableSchemeID: String?

    public init(
        store: any SecretStore,
        logger: any RuntimeLogger,
        baseURL: URL? = nil,
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.store = store
        self.logger = logger
        self.transport = transport
        self.cookies = CookieHeaderStore(store: store)
        self.automaticServerRouting = baseURL == nil
        let selected = baseURL ?? AcademicServerRouter.baseURL(for: "")
        self.baseURL = selected.absoluteString.hasSuffix("/") ? selected : URL(string: selected.absoluteString + "/")!
    }

    @discardableResult
    public func routeForUsername(_ username: String) -> Bool {
        guard automaticServerRouting else { return false }
        let next = AcademicServerRouter.baseURL(for: username)
        guard next != baseURL else { return false }
        baseURL = next
        timetableSchemeID = nil
        return true
    }

    public func webOrigin() -> String {
        baseURL.absoluteString.components(separatedBy: "/jsxsd/").first.map { $0 + "/" } ?? baseURL.absoluteString
    }

    public func initialize() async throws -> [CoreAcademicTerm]? {
        let html = try await get("kscj/cjcx_query", message: "连接教务系统失败")
        if isLoginPage(html) { return nil }
        let terms = HTMLParser.options(in: html, selectName: "kksj")
        guard !terms.isEmpty else {
            throw CithubNativeError.invalidResponse("无法识别教务系统的学期列表，页面结构可能已更新")
        }
        return terms
    }

    public func loadCaptcha() async throws -> String {
        let response = try await request("verifycode.servlet?ts=\(Int64(Date().timeIntervalSince1970 * 1000))")
        guard (200...299).contains(response.status), !response.data.isEmpty else {
            throw CithubNativeError.invalidResponse("教务系统未返回验证码图片")
        }
        return response.data.base64EncodedString()
    }

    public func login(username: String, password: String, captchaCode: String) async throws -> [CoreAcademicTerm] {
        guard !username.isEmpty else { throw CithubNativeError.invalidInput("请输入教务系统账号") }
        guard !password.isEmpty else { throw CithubNativeError.invalidInput("请输入教务系统密码") }
        guard !captchaCode.isEmpty else { throw CithubNativeError.invalidInput("请输入教务系统验证码") }
        let encoded = Data(username.utf8).base64EncodedString() + "%%%" + Data(password.utf8).base64EncodedString()
        let response = try await request(
            "xk/LoginToXk",
            method: "POST",
            form: [
                "userAccount": "", "userPassword": "",
                "RANDOMCODE": captchaCode.trimmingCharacters(in: .whitespacesAndNewlines),
                "encoded": encoded,
            ],
            followRedirects: false
        )
        let location = response.header("Location") ?? response.finalURL?.absoluteString ?? ""
        let successful = (300...399).contains(response.status) &&
            location.range(of: "/jsxsd/framework/xsMain.jsp", options: .caseInsensitive) != nil
        guard successful else {
            let alert = HTMLParser.firstCapture(
                #"alert\s*\(\s*['\"]([^'\"]+)['\"]"#,
                in: response.text,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            )
            let message = alert ?? HTMLParser.text(response.text)
            throw CithubNativeError.loginRequired(message.isEmpty ? "教务系统账号、密码或验证码错误" : message)
        }
        guard let terms = try await initialize() else {
            throw CithubNativeError.loginRequired("教务系统登录未建立")
        }
        return terms
    }

    public func loadGrades(term: String, bestOnly: Bool) async throws -> [CoreCourseGrade] {
        let html = try await get(
            "kscj/cjcx_list?kksj=\(FormEncoding.percent(term))&xsfs=\(bestOnly ? "max" : "all")",
            message: "加载成绩失败"
        )
        try requireSession(html)
        return HTMLParser.tableRows(in: html, id: "dataList").compactMap { row in
            row.count >= 20 ? CoreCourseGrade(values: Array(row.prefix(20))) : nil
        }
    }

    public func loadSelectionTerms() async throws -> [CoreAcademicTerm] {
        let html = try await get("xkgl/xsxkjgcx", message: "加载选课结果查询条件失败")
        try requireSession(html)
        return HTMLParser.options(in: html, selectName: "xnxqid")
    }

    public func loadSelectionResults(term: String) async throws -> [CoreSelectedCourse] {
        let html = try await post("xkgl/loadXsxkjgList", form: ["xnxqid": term], message: "加载选课结果失败")
        try requireSession(html)
        return HTMLParser.tableRows(in: html).compactMap { row in
            row.count >= 8 ? CoreSelectedCourse(values: Array(row.prefix(8))) : nil
        }
    }

    public func loadEvaluationBatches() async throws -> [CoreEvaluationBatch] {
        let html = try await get("xspj/xspj_find.do", message: "加载学生评价批次失败")
        try requireSession(html)
        return HTMLParser.rowNodes(in: html).compactMap { row in
            let cells = HTMLParser.rowCells(row).map(\.text)
            guard cells.count >= 7, let path = HTMLParser.href(in: row.innerHTML), !path.isEmpty else { return nil }
            return CoreEvaluationBatch(
                sequence: cells[0], semester: cells[1], category: cells[2], name: cells[3],
                startDate: cells[4], endDate: cells[5], courseListPath: path
            )
        }
    }

    public func loadEvaluationCourses(path: String) async throws -> [CoreEvaluationCourse] {
        let html = try await get(try safePath(path), message: "加载待评价课程失败")
        try requireSession(html)
        return HTMLParser.rowNodes(in: html, tableID: "dataList").compactMap { row in
            let cells = HTMLParser.rowCells(row).map(\.text)
            guard cells.count >= 9, let formPath = HTMLParser.href(in: row.innerHTML), !formPath.isEmpty else { return nil }
            return CoreEvaluationCourse(
                sequence: cells[0], courseCode: cells[1], courseName: cells[2], teacher: cells[3],
                category: cells[4], totalScore: cells[5], evaluated: cells[6] == "是",
                submitted: cells[7] == "是", teachingHours: cells[8], formPath: formPath
            )
        }
    }

    public func loadEvaluationForm(path: String) async throws -> CoreEvaluationForm {
        let html = try await get(try safePath(path), message: "加载课程评价表失败")
        try requireSession(html)
        guard let form = HTMLParser.elements("form", in: html).first(where: {
            $0.attribute("action").contains("xspj_save.do")
        }) else {
            throw CithubNativeError.invalidResponse("无法识别课程评价表，页面结构可能已更新")
        }
        let inputs = HTMLParser.voidElements("input", in: form.innerHTML)
        let hidden = inputs.compactMap { input -> CoreEvaluationHiddenField? in
            guard input.attribute("type").lowercased() == "hidden", !input.attribute("name").isEmpty else { return nil }
            return CoreEvaluationHiddenField(name: input.attribute("name"), value: input.attribute("value"))
        }
        let scores = Dictionary(uniqueKeysWithValues: hidden.filter { $0.name.hasPrefix("pj0601fz_") }.map { ($0.name, $0.value) })
        let questions = HTMLParser.rowNodes(in: form.innerHTML).compactMap { row -> CoreEvaluationQuestion? in
            guard let idInput = HTMLParser.voidElements("input", in: row.innerHTML).first(where: {
                $0.attribute("name") == "pj06xh"
            }) else { return nil }
            let id = idInput.attribute("value")
            let optionMatches = HTMLParser.captures(
                pattern: #"<input\b([^>]*)>\s*([^<]*)"#,
                in: row.innerHTML,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            )
            let options = optionMatches.compactMap { values -> CoreEvaluationOption? in
                let attributes = values[safe: 1] ?? ""
                guard HTMLParser.attribute("type", in: attributes).lowercased() == "radio",
                      HTMLParser.attribute("name", in: attributes) == "pj0601id_\(id)" else { return nil }
                let optionID = HTMLParser.attribute("value", in: attributes)
                return CoreEvaluationOption(
                    id: optionID,
                    label: HTMLParser.text(values[safe: 2] ?? ""),
                    score: scores["pj0601fz_\(id)_\(optionID)"] ?? "",
                    selected: HTMLParser.hasAttribute("checked", in: attributes)
                )
            }
            guard !options.isEmpty else { return nil }
            let title = HTMLParser.rowCells(row).first?.text ?? ""
            return CoreEvaluationQuestion(id: id, title: title, options: options)
        }
        let textarea = HTMLParser.elements("textarea", in: form.innerHTML).first(where: {
            !$0.attribute("name").isEmpty
        })
        let heading = HTMLParser.captures(
            pattern: #"课程名称\s*[：:]\s*(.*?)\s+评教大类\s*[：:]\s*(.*?)(?:<|$)"#,
            in: html,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ).first
        return CoreEvaluationForm(
            courseName: HTMLParser.text(heading?[safe: 1] ?? ""),
            category: HTMLParser.text(heading?[safe: 2] ?? ""),
            actionPath: form.attribute("action"),
            hiddenFields: hidden,
            questions: questions,
            suggestionField: textarea?.attribute("name"),
            suggestion: textarea?.text ?? "",
            readOnly: form.innerHTML.range(of: "onclick", options: .caseInsensitive) == nil ||
                form.innerHTML.range(of: "saveData", options: .caseInsensitive) == nil
        )
    }

    public func saveEvaluation(
        form: CoreEvaluationForm,
        answers: [CoreEvaluationAnswer],
        suggestion: String,
        submit: Bool
    ) async throws -> Bool {
        guard !form.readOnly else { throw CithubNativeError.invalidInput("该评价已提交，不能再修改") }
        let selected = Dictionary(uniqueKeysWithValues: answers.map { ($0.questionID, $0.optionID) })
        guard form.questions.allSatisfy({ !(selected[$0.id] ?? "").isEmpty }) else {
            throw CithubNativeError.invalidInput("请完成每一项评价指标")
        }
        var fields: [String: String] = [:]
        form.hiddenFields.filter { $0.name != "issubmit" && $0.name != "sfxyt" }
            .forEach { fields[$0.name] = $0.value }
        form.questions.forEach { fields["pj0601id_\($0.id)"] = selected[$0.id] }
        if let suggestionField = form.suggestionField { fields[suggestionField] = suggestion }
        fields["issubmit"] = submit ? "1" : "0"
        fields["sfxyt"] = "0"
        let html = try await post(
            try safePath(form.actionPath), form: fields,
            message: submit ? "提交学生评价失败" : "保存学生评价失败"
        )
        try requireSession(html)
        return true
    }

    public func loadTimetable(term: String?) async throws -> CoreTimetable {
        var html = try await get("xskb/xskb_list.do", message: "加载理论课表失败")
        try requireSession(html)
        var parsed = try parseTimetable(html)
        timetableSchemeID = parsed.schemeID.isEmpty ? timetableSchemeID : parsed.schemeID
        if let term, !term.isEmpty, term != parsed.dto.selectedTerm {
            html = try await post(
                "xskb/xskb_list.do",
                form: [
                    "jx0404id": "", "cj0701id": "", "zc": "", "demo": "",
                    "xnxq01id": term, "sfFD": "1", "kbjcmsid": timetableSchemeID ?? "",
                ],
                message: "加载理论课表失败"
            )
            parsed = try parseTimetable(html)
        }
        let today = Self.dateFormatter.string(from: Date())
        let weekday = Calendar(identifier: .gregorian).component(.weekday, from: Date())
        let dayOfWeek = weekday == 1 ? 7 : weekday - 1
        let homeTimetable: ((Int64, Int64)?, [CoreTimetableCourse])?
        do {
            let weekHTML = try await post(
            "framework/main_index_loadkb.jsp",
            form: ["rq": today, "sjmsValue": parsed.schemeID],
            message: "加载教学周失败"
            )
            try requireSession(weekHTML)
            homeTimetable = (parseTeachingWeek(weekHTML), parseHomeTimetable(weekHTML, day: Int64(dayOfWeek)))
        } catch {
            // The full timetable below is a reliable fallback when the home
            // panel is temporarily unavailable, but do not hide an expired
            // login as an empty timetable.
            if let nativeError = error as? CithubNativeError,
               case .loginRequired = nativeError { throw nativeError }
            homeTimetable = nil
        }
        let referenceWeek = homeTimetable?.0?.0
        let totalWeeks = homeTimetable?.0?.1
        let expectedTodayCourses = parsed.dto.courses.filter { course in
            course.dayOfWeek == Int64(dayOfWeek) &&
                (referenceWeek == nil || course.weekNumbers.isEmpty || course.weekNumbers.contains(referenceWeek!))
        }
        var result = parsed.dto
        result.courses = homeTimetable?.1.isEmpty == false ? homeTimetable!.1 : expectedTodayCourses
        result.referenceDateISO = today
        result.referenceWeek = referenceWeek
        result.totalWeeks = totalWeeks
        return result
    }

    public func webPageURL(_ path: String) throws -> String {
        let safe = try safePath(path)
        return URL(string: safe, relativeTo: baseURL)!.absoluteURL.absoluteString
    }

    public func cookieHeader() async -> String { await cookies.header() }

    public func logout() async {
        await cookies.remove(named: "JSESSIONID")
    }

    private struct ParsedTimetable { var dto: CoreTimetable; var schemeID: String }

    private func parseTimetable(_ html: String) throws -> ParsedTimetable {
        let rows = HTMLParser.rowNodes(in: html, tableID: "kbtable")
        guard rows.count >= 2 else {
            throw CithubNativeError.invalidResponse("无法识别理论课表，页面结构可能已更新")
        }
        var periods: [CoreTimetablePeriod] = []
        var courses: [CoreTimetableCourse] = []
        for (offset, row) in rows.dropFirst().enumerated() {
            let cells = HTMLParser.rowCells(row)
            guard cells.count >= 8 else { continue }
            let periodIndex = Int64(offset + 1)
            let periodText = cells[0].text
            let time = HTMLParser.captures(
                pattern: #"(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})"#, in: periodText
            ).first
            let timeValue = time?[safe: 0] ?? ""
            let label = periodText.replacingOccurrences(of: timeValue, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            periods.append(CoreTimetablePeriod(
                index: periodIndex,
                label: label.isEmpty ? "第\(periodIndex)大节" : label,
                startTime: time?[safe: 1] ?? "",
                endTime: time?[safe: 2] ?? ""
            ))
            for (dayOffset, cell) in cells.dropFirst().prefix(7).enumerated() {
                courses.append(contentsOf: parseTimetableCell(cell, day: Int64(dayOffset + 1), period: periodIndex))
            }
        }
        let terms = HTMLParser.options(in: html, selectName: "xnxq01id")
        let selected = terms.first(where: \.selected)?.value ?? terms.first?.value ?? ""
        let schemeSelect = HTMLParser.elements("select", in: html).first(where: {
            $0.attribute("name").caseInsensitiveCompare("kbjcmsid") == .orderedSame
        })
        let schemeOptions = schemeSelect.map { HTMLParser.elements("option", in: $0.innerHTML) } ?? []
        let scheme = schemeOptions.first(where: { $0.hasAttribute("selected") })?.attribute("value")
            ?? schemeOptions.first?.attribute("value")
            ?? HTMLParser.voidElements("input", in: html).first(where: {
                $0.attribute("name") == "kbjcmsid"
            })?.attribute("value") ?? ""
        return ParsedTimetable(
            dto: CoreTimetable(
                terms: terms, selectedTerm: selected, periods: periods, courses: courses,
                note: "", referenceDateISO: nil, referenceWeek: nil, totalWeeks: nil
            ),
            schemeID: scheme
        )
    }

    private func parseTimetableCell(_ cell: HTMLNode, day: Int64, period: Int64) -> [CoreTimetableCourse] {
        let contents = HTMLParser.elements("div", in: cell.innerHTML).filter {
            $0.attribute("class").split(separator: " ").contains(where: { $0.hasPrefix("kbcontent") }) && !$0.text.isEmpty
        }
        return contents.flatMap { content in
            content.innerHTML.replacingOccurrences(
                of: #"(?:<br\s*/?>\s*)?-{5,}(?:\s*<br\s*/?>)?"#,
                with: "\u{1f}", options: [.regularExpression, .caseInsensitive]
            ).split(separator: "\u{1f}").compactMap { parseCourseMarkup(String($0), day: day, period: period) }
        }.reduce(into: [String: CoreTimetableCourse]()) { result, course in
            let key = "\(course.name)|\(course.weeks)|\(course.location)|\(course.startSection)|\(course.endSection)"
            guard let existing = result[key] else {
                result[key] = course
                return
            }
            let existingDetailCount = (existing.teacher.isEmpty ? 0 : 1) + (existing.location.isEmpty ? 0 : 1)
            let newDetailCount = (course.teacher.isEmpty ? 0 : 1) + (course.location.isEmpty ? 0 : 1)
            if newDetailCount > existingDetailCount { result[key] = course }
        }.values.sorted { $0.id < $1.id }
    }

    private func parseHomeTimetable(_ html: String, day: Int64) -> [CoreTimetableCourse] {
        guard let table = HTMLParser.elements("table", in: html).first(where: {
            $0.attribute("class").split(separator: " ").contains("kb_table")
        }) else { return [] }
        let rows = HTMLParser.elements("tr", in: table.innerHTML)
        guard let header = rows.first else { return [] }
        let cells = HTMLParser.rowCells(header)
        let weekday = ["一", "二", "三", "四", "五", "六", "日"][safe: Int(day - 1)] ?? ""
        guard let column = cells.firstIndex(where: { $0.text.contains("星期\(weekday)") }), column > 0 else { return [] }
        return rows.dropFirst().enumerated().flatMap { offset, row in
            HTMLParser.rowCells(row)[safe: column].map { parseTimetableCell($0, day: day, period: Int64(offset + 1)) } ?? []
        }
    }

    private func parseCourseMarkup(_ markup: String, day: Int64, period: Int64) -> CoreTimetableCourse? {
        var details: [String: String] = [:]
        for font in HTMLParser.elements("font", in: markup) where !font.attribute("title").isEmpty {
            details[font.attribute("title")] = font.text
        }
        let nameHTML = markup.replacingOccurrences(
            of: #"<font\b[^>]*title\s*=.*?</font\s*>"#,
            with: "", options: [.regularExpression, .caseInsensitive]
        )
        let name = HTMLParser.text(nameHTML).replacingOccurrences(of: #"P$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let weeksAndSections = details["周次(节次)"] ?? ""
        let sections = HTMLParser.captures(pattern: #"(?:\[|（)(\d{1,2})\s*[-~,，]\s*(\d{1,2})(?:节|小节)?(?:\]|）)"#, in: weeksAndSections).first
        let start = Int64(sections?[safe: 1] ?? "") ?? period * 2 - 1
        let end = Int64(sections?[safe: 2] ?? "") ?? period * 2
        let weeks = weeksAndSections.replacingOccurrences(
            of: #"(?:\[|（)\d{1,2}\s*[-~,，]\s*\d{1,2}(?:节|小节)?(?:\]|）)"#, with: "", options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let location = details["教室"] ?? ""
        return CoreTimetableCourse(
            id: "\(day)-\(period)-\(name)-\(weeks)-\(location)",
            dayOfWeek: day, periodIndex: period, startSection: start, endSection: end,
            name: name, teacher: details["老师"] ?? "", weeks: weeks,
            weekNumbers: parseWeeks(weeks), location: location
        )
    }

    private func parseTeachingWeek(_ html: String) -> (Int64, Int64)? {
        let match = HTMLParser.captures(
            pattern: #"第\s*(\d+)\s*周.*?/(\d+)\s*周"#, in: html,
            options: [.dotMatchesLineSeparators]
        ).first
        guard let match, let week = Int64(match[safe: 1] ?? ""), let total = Int64(match[safe: 2] ?? "") else { return nil }
        return (week, total)
    }

    private func parseWeeks(_ source: String) -> [Int64] {
        let rangeText = source.components(separatedBy: "(周").first?.components(separatedBy: "（周").first ?? source
        let odd = source.contains("单")
        let even = source.contains("双")
        var result: [Int64] = []
        for match in HTMLParser.captures(pattern: #"(\d+)(?:\s*-\s*(\d+))?"#, in: rangeText) {
            guard let start = Int64(match[safe: 1] ?? "") else { continue }
            let end = Int64(match[safe: 2] ?? "") ?? start
            for value in start...end where (!odd || value % 2 == 1) && (!even || value % 2 == 0) {
                if !result.contains(value) { result.append(value) }
            }
        }
        return result
    }

    private func get(_ path: String, message: String) async throws -> String {
        let response = try await request(path)
        guard (200...299).contains(response.status) else {
            throw CithubNativeError.requestFailed("\(message)（HTTP \(response.status)）")
        }
        return response.text
    }

    private func post(_ path: String, form: [String: String], message: String) async throws -> String {
        let response = try await request(path, method: "POST", form: form)
        guard (200...299).contains(response.status) else {
            throw CithubNativeError.requestFailed("\(message)（HTTP \(response.status)）")
        }
        return response.text
    }

    private func request(
        _ path: String,
        method: String = "GET",
        form: [String: String]? = nil,
        followRedirects: Bool = true
    ) async throws -> HTTPResponse {
        let normalized: String
        if path.hasPrefix(baseURL.absoluteString) {
            normalized = String(path.dropFirst(baseURL.absoluteString.count))
        } else { normalized = try safePath(path) }
        guard let url = URL(string: normalized, relativeTo: baseURL)?.absoluteURL else {
            throw CithubNativeError.invalidInput("教务系统返回了无效页面地址")
        }
        var headers = [
            "User-Agent": Self.browserUserAgent,
            "Accept-Language": "zh-CN,zh;q=0.9",
        ]
        let cookie = await cookies.header()
        if !cookie.isEmpty { headers["Cookie"] = cookie }
        var body = Data()
        if let form {
            headers["Content-Type"] = "application/x-www-form-urlencoded"
            body = FormEncoding.encode(form)
        }
        let response = try await transport.perform(HTTPCall(
            method: method, url: url, headers: headers, body: body, followRedirects: followRedirects
        ))
        if let setCookie = response.header("Set-Cookie") { await cookies.merge([setCookie]) }
        await logger.append(source: "academic", message: "\(method) /jsxsd/\(normalized) -> HTTP \(response.status)")
        return response
    }

    private func requireSession(_ html: String) throws {
        if isLoginPage(html) {
            throw CithubNativeError.loginRequired("教务系统登录已过期，请重新登录")
        }
    }

    private func isLoginPage(_ html: String) -> Bool {
        html.range(of: "LoginToXk", options: .caseInsensitive) != nil ||
            (html.range(of: "userAccount", options: .caseInsensitive) != nil &&
             html.range(of: "RANDOMCODE", options: .caseInsensitive) != nil)
    }

    private func safePath(_ path: String) throws -> String {
        let value: String
        if let range = path.range(of: "/jsxsd/", options: .caseInsensitive) {
            value = String(path[range.upperBound...])
        } else { value = path }
        let normalized = value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !normalized.lowercased().hasPrefix("http"), !normalized.contains("..") else {
            throw CithubNativeError.invalidInput("教务系统返回了无效页面地址")
        }
        return normalized
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
