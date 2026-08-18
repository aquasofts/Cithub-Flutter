import Foundation

final class IOSWebVpnApi: WebVpnHostApi {
    private let store: any SecretStore
    private let state: IOSSessionState
    private let logger: IOSRuntimeLogStore
    private let client: WebVpnProtocolClient
    private let events: IOSNativeEvents
    private var configuration: WebVpnLoginConfiguration?
    private var captcha: WebVpnCaptcha?
    private var activeUser: WebVpnUser?

    init(
        store: any SecretStore,
        state: IOSSessionState,
        logger: IOSRuntimeLogStore,
        events: IOSNativeEvents
    ) {
        self.store = store
        self.state = state
        self.logger = logger
        self.events = events
        self.client = WebVpnProtocolClient(store: store, logger: logger)
    }

    func getCapabilities() throws -> NativeCapabilities {
        let info = Bundle.main.infoDictionary ?? [:]
        return NativeCapabilities(
            flavor: .manualCaptcha,
            captchaAutofillEnabled: false,
            versionName: info["CFBundleShortVersionString"] as? String ?? "0.0.0",
            versionCode: Int64(info["CFBundleVersion"] as? String ?? "0") ?? 0
        )
    }

    func initialize(completion: @escaping (Result<WebVpnSessionDto, Error>) -> Void) {
        runNative(completion: completion) { [self] in
            if await client.hasRestorableSession(), let restored = try? await client.userInfo() {
                activeUser = restored
                await state.setWebVPN(authenticated: true, username: restored.username)
                await syncWebVPNCookies()
                await logger.append(source: "webvpn", message: "Encrypted Cookie session restored")
                return await session(message: "已恢复 WebVPN 会话")
            }
            if await client.hasRestorableSession() { await client.clearSession() }
            let config = try await ensureConfiguration()
            if config.requiresCaptcha { captcha = try await client.loadCaptcha() }
            await state.setWebVPN(authenticated: false, username: nil)
            return await session(message: nil)
        }
    }

    func refreshCaptcha(completion: @escaping (Result<WebVpnSessionDto, Error>) -> Void) {
        runNative(completion: completion) { [self] in
            let config = try await ensureConfiguration()
            captcha = config.requiresCaptcha ? try await client.loadCaptcha() : nil
            return await session(message: "验证码已刷新")
        }
    }

    func login(request: LoginRequestDto, completion: @escaping (Result<WebVpnSessionDto, Error>) -> Void) {
        runNative(completion: completion) { [self] in
            let username = request.username.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !username.isEmpty else { throw CithubNativeError.invalidInput("请输入 WebVPN 账号") }
            let password: String
            if request.useSavedPassword {
                guard let saved = await store.get("webvpn.password.\(username)") else {
                    throw CithubNativeError.loginRequired("保存的密码不可用，请重新输入")
                }
                password = saved
            } else { password = request.password }
            let config = try await ensureConfiguration()
            if config.requiresPassword && password.isEmpty {
                throw CithubNativeError.invalidInput("请输入 WebVPN 密码")
            }
            if config.requiresCaptcha && (request.captchaId.isEmpty || request.captchaCode.isEmpty) {
                throw CithubNativeError.invalidInput("请输入图形验证码")
            }
            let user = try await client.login(
                username: username,
                password: password,
                captchaID: request.captchaId,
                captchaCode: request.captchaCode,
                configuration: config
            )
            activeUser = user
            await state.setWebVPN(authenticated: true, username: username)
            if request.rememberPassword { await saveCredential(username: username, password: password) }
            await syncWebVPNCookies()
            await events.emit(source: "webvpn", stage: "signedIn", message: "WebVPN 登录成功")
            return await session(message: "登录成功")
        }
    }

    func selectSavedAccount(username: String, completion: @escaping (Result<WebVpnSessionDto, Error>) -> Void) {
        runNative(completion: completion) { [self] in
            guard await store.get("webvpn.password.\(username)") != nil else {
                throw CithubNativeError.loginRequired("保存的账号不可用")
            }
            _ = try await ensureConfiguration()
            if captcha == nil, configuration?.requiresCaptcha == true { captcha = try await client.loadCaptcha() }
            return await session(message: "已选择保存的账号")
        }
    }

    func forgetSavedAccount(username: String, completion: @escaping (Result<WebVpnSessionDto, Error>) -> Void) {
        runNative(completion: completion) { [self] in
            await store.remove("webvpn.password.\(username)")
            await store.remove("webvpn.saved_at.\(username)")
            let names = await savedUsernames().filter { $0 != username }
            await writeSavedUsernames(names)
            return await session(message: "已删除保存的账号")
        }
    }

    func revalidate(completion: @escaping (Result<WebVpnSessionDto, Error>) -> Void) {
        runNative(completion: completion) { [self] in
            guard await client.hasRestorableSession(), let restored = try? await client.userInfo() else {
                await clearActiveSession()
                return await session(message: "会话已失效")
            }
            activeUser = restored
            await state.setWebVPN(authenticated: true, username: restored.username)
            await syncWebVPNCookies()
            return await session(message: "会话有效")
        }
    }

    func logout(completion: @escaping (Result<WebVpnSessionDto, Error>) -> Void) {
        runNative(completion: completion) { [self] in
            let header = await client.cookieHeader()
            await client.logout()
            await clearActiveSession()
            await deleteCookies(
                names: Set(CookieHeaderStore.parse(header).keys),
                domains: ["webvpn.ccit.edu.cn"]
            )
            await events.emit(source: "webvpn", stage: "signedOut", message: "已退出 WebVPN")
            return await session(message: "已退出")
        }
    }

    private func ensureConfiguration() async throws -> WebVpnLoginConfiguration {
        if let configuration { return configuration }
        let loaded = try await client.loadConfiguration()
        configuration = loaded
        return loaded
    }

    private func session(message: String?) async -> WebVpnSessionDto {
        let authenticated = await state.webVPNAuthenticated
        let action = activeUser?.requiredAction ?? .none
        let status: AuthStatus = !authenticated ? .signedOut : (action == .none ? .signedIn : .actionRequired)
        return WebVpnSessionDto(
            status: status,
            requiredAction: requiredActionDto(action),
            user: activeUser.map(userDto),
            savedAccounts: await savedAccounts(),
            captcha: captcha.map {
                CaptchaDto(id: $0.id, base64Image: $0.image, recognizedCode: "")
            },
            requiresCaptcha: configuration?.requiresCaptcha ?? true,
            message: message
        )
    }

    private func saveCredential(username: String, password: String) async {
        await store.put("webvpn.password.\(username)", password)
        await store.put("webvpn.saved_at.\(username)", String(Int64(Date().timeIntervalSince1970 * 1000)))
        await writeSavedUsernames([username] + savedUsernames().filter { $0 != username })
    }

    private func savedUsernames() async -> [String] {
        let raw = await store.get("webvpn.saved_usernames") ?? ""
        var seen = Set<String>()
        return raw.split(separator: "\n").map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(10).map { $0 }
    }

    private func writeSavedUsernames(_ names: [String]) async {
        let value = names.prefix(10).joined(separator: "\n")
        if value.isEmpty { await store.remove("webvpn.saved_usernames") }
        else { await store.put("webvpn.saved_usernames", value) }
    }

    private func savedAccounts() async -> [SavedAccountDto] {
        var result: [SavedAccountDto] = []
        for username in await savedUsernames() {
            let timestamp = Int64(await store.get("webvpn.saved_at.\(username)") ?? "0") ?? 0
            result.append(SavedAccountDto(username: username, lastUsedAtMillis: timestamp))
        }
        return result
    }

    private func clearActiveSession() async {
        activeUser = nil
        await client.clearSession()
        await state.setWebVPN(authenticated: false, username: nil)
    }

    private func syncWebVPNCookies() async {
        await syncCookies(await client.cookieHeader(), domains: ["webvpn.ccit.edu.cn"])
    }
}
