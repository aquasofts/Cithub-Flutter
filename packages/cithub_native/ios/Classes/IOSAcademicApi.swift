import Foundation

final class IOSAcademicApi: AcademicHostApi {
    private let store: any SecretStore
    private let state: IOSSessionState
    private let logger: IOSRuntimeLogStore
    private let client: AcademicProtocolClient
    private var captcha: CaptchaDto?
    private var terms: [CoreAcademicTerm] = []

    init(store: any SecretStore, state: IOSSessionState, logger: IOSRuntimeLogStore) {
        self.store = store
        self.state = state
        self.logger = logger
        self.client = AcademicProtocolClient(store: store, logger: logger)
    }

    func initialize(webVpnUsername: String, completion: @escaping (Result<WebVpnSessionDto, Error>) -> Void) {
        runNative(completion: completion) { [self] in
            guard await state.webVPNAuthenticated else {
                throw CithubNativeError.loginRequired("请先登录 WebVPN")
            }
            if await client.routeForUsername(webVpnUsername) {
                await logger.append(source: "academic", message: "Selected academic server for account \(webVpnUsername)")
            }
            if let restored = try await client.initialize() {
                terms = restored
                let username = await store.get("academic.last_username") ?? webVpnUsername
                await state.setAcademic(authenticated: true, username: username)
                await syncWebViewCookies()
                return await session(message: "已恢复教务系统会话")
            }
            await state.setAcademic(authenticated: false, username: nil)
            try await refreshCaptchaValue()
            return await session(message: "请登录教务系统")
        }
    }

    func refreshCaptcha(completion: @escaping (Result<WebVpnSessionDto, Error>) -> Void) {
        runNative(completion: completion) { [self] in
            guard await state.webVPNAuthenticated else {
                throw CithubNativeError.loginRequired("请先登录 WebVPN")
            }
            try await refreshCaptchaValue()
            return await session(message: "教务验证码已刷新")
        }
    }

    func login(request: LoginRequestDto, completion: @escaping (Result<WebVpnSessionDto, Error>) -> Void) {
        runNative(completion: completion) { [self] in
            guard await state.webVPNAuthenticated else {
                throw CithubNativeError.loginRequired("请先登录 WebVPN")
            }
            let username = request.username.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !username.isEmpty else { throw CithubNativeError.invalidInput("请输入教务系统账号") }
            if await client.routeForUsername(username) {
                await state.setAcademic(authenticated: false, username: username)
                try await refreshCaptchaValue()
                await logger.append(source: "academic", message: "Switched academic server for account \(username)")
                return await session(message: "账号对应的教务服务器已切换，请核对新验证码后重新登录")
            }
            let password: String
            if request.useSavedPassword {
                guard let saved = await store.get("academic.password.\(username)") else {
                    throw CithubNativeError.loginRequired("保存的教务密码不可用，请重新输入")
                }
                password = saved
            } else { password = request.password }
            terms = try await client.login(
                username: username, password: password, captchaCode: request.captchaCode
            )
            await state.setAcademic(authenticated: true, username: username)
            await store.put("academic.last_username", username)
            if request.rememberPassword { await saveCredential(username: username, password: password) }
            await syncWebViewCookies()
            await logger.append(source: "academic", message: "Academic session established for \(username)")
            return await session(message: "教务登录成功")
        }
    }

    func loadTerms(completion: @escaping (Result<[AcademicTermDto], Error>) -> Void) {
        runNative(completion: completion) { [self] in
            try await requireSession()
            if terms.isEmpty {
                guard let restored = try await client.initialize() else {
                    throw CithubNativeError.loginRequired("教务登录已过期")
                }
                terms = restored
            }
            return terms.map(academicTermDto)
        }
    }

    func loadGrades(term: String, bestOnly: Bool, completion: @escaping (Result<[CourseGradeDto], Error>) -> Void) {
        runNative(completion: completion) { [self] in
            try await requireSession()
            return try await client.loadGrades(term: term, bestOnly: bestOnly).map(gradeDto)
        }
    }

    func loadTimetable(term: String?, completion: @escaping (Result<TimetableDto, Error>) -> Void) {
        runNative(completion: completion) { [self] in
            try await requireSession()
            return timetableDto(try await client.loadTimetable(term: term))
        }
    }

    func loadSelectionResults(term: String, completion: @escaping (Result<[SelectedCourseDto], Error>) -> Void) {
        runNative(completion: completion) { [self] in
            try await requireSession()
            return try await client.loadSelectionResults(term: term).map(selectedCourseDto)
        }
    }

    func loadEvaluationBatches(completion: @escaping (Result<[EvaluationBatchDto], Error>) -> Void) {
        runNative(completion: completion) { [self] in
            try await requireSession()
            return try await client.loadEvaluationBatches().map(evaluationBatchDto)
        }
    }

    func loadEvaluationCourses(path: String, completion: @escaping (Result<[EvaluationCourseDto], Error>) -> Void) {
        runNative(completion: completion) { [self] in
            try await requireSession()
            return try await client.loadEvaluationCourses(path: path).map(evaluationCourseDto)
        }
    }

    func loadEvaluationForm(path: String, completion: @escaping (Result<EvaluationFormDto, Error>) -> Void) {
        runNative(completion: completion) { [self] in
            try await requireSession()
            return evaluationFormDto(try await client.loadEvaluationForm(path: path))
        }
    }

    func saveEvaluation(
        form: EvaluationFormDto,
        answers: [EvaluationAnswerDto],
        suggestion: String,
        submit: Bool,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        runNative(completion: completion) { [self] in
            try await requireSession()
            return try await client.saveEvaluation(
                form: coreEvaluationForm(form),
                answers: answers.map { CoreEvaluationAnswer(questionID: $0.questionId, optionID: $0.optionId) },
                suggestion: suggestion,
                submit: submit
            )
        }
    }

    func prepareWebPage(path: String, completion: @escaping (Result<String, Error>) -> Void) {
        runNative(completion: completion) { [self] in
            try await requireSession()
            await syncWebViewCookies()
            return try await client.webPageURL(path)
        }
    }

    func logout(completion: @escaping (Result<Bool, Error>) -> Void) {
        runNative(completion: completion) { [self] in
            await client.logout()
            await state.setAcademic(authenticated: false, username: nil)
            terms = []
            captcha = nil
            await logger.append(source: "academic", message: "Academic session cleared")
            return true
        }
    }

    private func refreshCaptchaValue() async throws {
        captcha = CaptchaDto(
            id: "academic-\(Int64(Date().timeIntervalSince1970 * 1000))",
            base64Image: try await client.loadCaptcha(),
            recognizedCode: ""
        )
    }

    private func requireSession() async throws {
        guard await state.webVPNAuthenticated else {
            throw CithubNativeError.loginRequired("WebVPN 会话无效，请重新登录")
        }
        guard await state.academicAuthenticated else {
            throw CithubNativeError.loginRequired("教务系统登录已过期，请重新登录")
        }
    }

    private func session(message: String?) async -> WebVpnSessionDto {
        let authenticated = await state.academicAuthenticated
        let username = await state.academicUsername ?? ""
        let user = authenticated ? UserInfoDto(
            username: username, nickname: username, fullName: username,
            groups: ["学生"], authType: 1, bindWechat: false, bindOtp: false
        ) : nil
        return WebVpnSessionDto(
            status: authenticated ? .signedIn : .signedOut,
            requiredAction: .none,
            user: user,
            savedAccounts: await savedAccounts(),
            captcha: captcha,
            requiresCaptcha: !authenticated,
            message: message
        )
    }

    private func saveCredential(username: String, password: String) async {
        await store.put("academic.password.\(username)", password)
        await store.put("academic.saved_at.\(username)", String(Int64(Date().timeIntervalSince1970 * 1000)))
        let names = [username] + (await savedUsernames()).filter { $0 != username }
        await store.put("academic.saved_usernames", names.prefix(10).joined(separator: "\n"))
    }

    private func savedUsernames() async -> [String] {
        let raw = await store.get("academic.saved_usernames") ?? ""
        var seen = Set<String>()
        return raw.split(separator: "\n").map(String.init)
            .filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(10).map { $0 }
    }

    private func savedAccounts() async -> [SavedAccountDto] {
        var result: [SavedAccountDto] = []
        for username in await savedUsernames() {
            let timestamp = Int64(await store.get("academic.saved_at.\(username)") ?? "0") ?? 0
            result.append(SavedAccountDto(username: username, lastUsedAtMillis: timestamp))
        }
        return result
    }

    private func syncWebViewCookies() async {
        let origin = await client.webOrigin()
        guard let host = URL(string: origin)?.host else { return }
        await syncCookies(
            await client.cookieHeader(),
            domains: ["webvpn.ccit.edu.cn", host]
        )
    }
}
