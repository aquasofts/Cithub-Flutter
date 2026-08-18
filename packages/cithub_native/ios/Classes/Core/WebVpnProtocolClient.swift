import Foundation
#if canImport(Security)
import Security
#endif

public actor WebVpnProtocolClient {
    public static let defaultBaseURL = URL(string: "https://webvpn.ccit.edu.cn/")!
    public static let browserUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    private let store: any SecretStore
    private let logger: any RuntimeLogger
    private let baseURL: URL
    private let transport: any HTTPTransport
    private let cookies: CookieHeaderStore

    public init(
        store: any SecretStore,
        logger: any RuntimeLogger,
        baseURL: URL = WebVpnProtocolClient.defaultBaseURL,
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.store = store
        self.logger = logger
        self.baseURL = baseURL.absoluteString.hasSuffix("/") ? baseURL : URL(string: baseURL.absoluteString + "/")!
        self.transport = transport
        self.cookies = CookieHeaderStore(store: store)
    }

    public func loadConfiguration() async throws -> WebVpnLoginConfiguration {
        let data = try await request(method: "GET", path: "api/access/authentication/list").object("data")
        guard let methods = data?.array("list") else {
            throw CithubNativeError.invalidResponse("WebVPN 未返回认证方式")
        }
        for raw in methods {
            guard let method = raw as? [String: Any], method.int64("authType") == 1 else { continue }
            let options = method.object("authOptions")
            let dynamic = options?.array("dynamicVerification")?.compactMap { ($0 as? NSNumber)?.int64Value } ?? []
            return WebVpnLoginConfiguration(
                externalID: method.string("externalId"),
                requiresPassword: options?.int64("staticVerification") == 1,
                requiresCaptcha: options?.int64("useGraphValidateCode") == 1,
                dynamicVerificationTypes: dynamic
            )
        }
        throw CithubNativeError.invalidResponse("学校 WebVPN 当前未开放本地账号登录")
    }

    public func loadCaptcha() async throws -> WebVpnCaptcha {
        guard let data = try await request(
            method: "GET",
            path: "api/access/graph-captcha/validate-code?width=150&height=50"
        ).object("data") else {
            throw CithubNativeError.invalidResponse("WebVPN 接口未返回验证码")
        }
        let id = data.string("id")
        let image = data.string("captcha")
        guard !id.isEmpty, !image.isEmpty else {
            throw CithubNativeError.invalidResponse("WebVPN 验证码响应不完整")
        }
        return WebVpnCaptcha(id: id, image: image)
    }

    public func login(
        username: String,
        password: String,
        captchaID: String,
        captchaCode: String,
        configuration: WebVpnLoginConfiguration
    ) async throws -> WebVpnUser {
        guard configuration.dynamicVerificationTypes.isEmpty else {
            throw CithubNativeError.loginRequired("学校当前要求动态验证码，请先使用官方 WebVPN 网页完成登录")
        }
        var payload: [String: Any] = [
            "deviceId": try await deviceID(),
            "userName": username,
        ]
        if configuration.requiresPassword {
            payload["password"] = try encryptPassword(password)
        }
        if configuration.requiresCaptcha {
            payload["captchaId"] = captchaID
            payload["code"] = captchaCode
        }
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let payloadString = String(decoding: payloadData, as: UTF8.self)
        _ = try await request(
            method: "POST",
            path: "api/access/auth/finish",
            json: ["externalId": configuration.externalID, "data": payloadString]
        )
        return try await userInfo()
    }

    public func userInfo() async throws -> WebVpnUser {
        guard let data = try await request(method: "GET", path: "api/access/user/info").object("data") else {
            throw CithubNativeError.invalidResponse("WebVPN 接口未返回用户信息")
        }
        let action: CoreRequiredAction
        if data.bool("needToBindLocalAccount") { action = .bindAccount }
        else if data.bool("needTriggerTFA") { action = .tfa }
        else if data.bool("needChangePwd") { action = .passwordReset }
        else { action = .none }
        let groups = data.array("groups")?.compactMap { $0 as? String } ?? []
        return WebVpnUser(
            username: data.string("username"),
            nickname: data.string("nickname"),
            fullName: data.string("fullName"),
            groups: groups,
            authType: data.int64("authType"),
            bindWechat: data.bool("bindWechat"),
            bindOtp: data.bool("bindOtp"),
            requiredAction: action
        )
    }

    public func logout() async {
        _ = try? await request(method: "POST", path: "api/access/user/logout", json: [:])
        await clearSession()
    }

    public func hasRestorableSession() async -> Bool { !(await cookies.header()).isEmpty }
    public func cookieHeader() async -> String { await cookies.header() }
    public func clearSession() async { await cookies.clear() }

    private func request(method: String, path: String, json: [String: Any]? = nil) async throws -> [String: Any] {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw CithubNativeError.invalidInput("无效 WebVPN 请求地址")
        }
        var headers = [
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "zh-CN,zh;q=0.9",
            "User-Agent": Self.browserUserAgent,
            "Origin": baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            "Referer": baseURL.absoluteString,
            "DNT": "1",
        ]
        let cookie = await cookies.header()
        if !cookie.isEmpty { headers["Cookie"] = cookie }
        var body = Data()
        if let json {
            headers["Content-Type"] = "application/json"
            body = try JSONSerialization.data(withJSONObject: json)
        }
        let response = try await transport.perform(HTTPCall(method: method, url: url, headers: headers, body: body))
        if let setCookie = response.header("Set-Cookie") { await cookies.merge([setCookie]) }
        await logger.append(source: "webvpn", message: "\(method) /\(path) -> HTTP \(response.status)")
        guard (200...299).contains(response.status) else {
            let message = (try? jsonObject(response.data).string("message")) ?? ""
            throw CithubNativeError.requestFailed(message.isEmpty ? "WebVPN 请求失败（HTTP \(response.status)）" : message)
        }
        let envelope = try jsonObject(response.data)
        let code = envelope.int64("code", default: -1)
        guard code == 0 else {
            let message = envelope.string("message", default: "WebVPN 接口返回错误：\(code)")
            throw CithubNativeError.requestFailed(message)
        }
        return envelope
    }

    private func deviceID() async throws -> String {
        if let existing = await store.get("webvpn.device_id"),
           existing.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil {
            return existing
        }
        let value = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        await store.put("webvpn.device_id", value)
        return value
    }

    private func encryptPassword(_ password: String) throws -> String {
        #if canImport(Security)
        let clean = Self.publicKeyPEM
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines).joined()
        guard let keyData = Data(base64Encoded: clean) else {
            throw CithubNativeError.invalidResponse("WebVPN 公钥格式无效")
        }
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: 2048,
        ]
        var keyError: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &keyError) else {
            throw CithubNativeError.invalidResponse("WebVPN 公钥无法载入")
        }
        guard SecKeyIsAlgorithmSupported(key, .encrypt, .rsaEncryptionPKCS1) else {
            throw CithubNativeError.invalidResponse("当前系统不支持 WebVPN RSA 加密")
        }
        var encryptError: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(
            key, .rsaEncryptionPKCS1, Data(password.utf8) as CFData, &encryptError
        ) else {
            throw CithubNativeError.requestFailed("WebVPN 密码加密失败")
        }
        return (encrypted as Data).base64EncodedString()
        #else
        throw CithubNativeError.requestFailed("当前平台不支持 WebVPN RSA 加密")
        #endif
    }

    private static let publicKeyPEM = """
    -----BEGIN PUBLIC KEY-----
    MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvrqdXbn6tf2kabHLRoE9
    IASO5fZixKK5IsFcBMJ0h1tf0WUb3HMygcC3+NecScetMSoPmSOrDLSA6sBWwGEF
    LTefRM5vP/eFdkXXB0YpFjfganpBKv4ZOvzCWZGhHOUlACRHViazsZbaPHvLYhsH
    Z3XTSbS8iIVDYgrQCHgzs2ULWEUau3489HTAcg7A2V2ZfDDzqaHj5BU5vopbfmjs
    cXObP0Ddy4IW4Mc/fcJoJs1e7M4hZg6iTIb8OTnlssOikckenO9mV+GdxdOSG9K2
    lUTCS+qxFXQ/vgd7JWi0eTOYG2duEoA2u2T3b/G5I/h8En+tOG6Ax0rztp/YtF0Q
    zQIDAQAB
    -----END PUBLIC KEY-----
    """
}
