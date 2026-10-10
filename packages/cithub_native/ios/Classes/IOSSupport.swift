import Foundation
import Security
import UIKit
import WebKit

final class KeychainSecretStore: SecretStore, @unchecked Sendable {
    private let service: String

    init(service: String = (Bundle.main.bundleIdentifier ?? "com.aquasofts.cithubFlutter") + ".cithub-native") {
        self.service = service
    }

    func put(_ key: String, _ value: String) async {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = query
            attributes.forEach { insertion[$0.key] = $0.value }
            SecItemAdd(insertion as CFDictionary, nil)
        }
    }

    func get(_ key: String) async -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func remove(_ key: String) async {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

typealias IOSRuntimeLogStore = PersistentRuntimeLog

actor IOSSessionState {
    private(set) var webVPNUsername: String?
    private(set) var academicUsername: String?
    private(set) var webVPNAuthenticated = false
    private(set) var academicAuthenticated = false

    func setWebVPN(authenticated: Bool, username: String?) {
        webVPNAuthenticated = authenticated
        webVPNUsername = username
        if !authenticated {
            academicAuthenticated = false
            academicUsername = nil
        }
    }

    func setAcademic(authenticated: Bool, username: String?) {
        academicAuthenticated = authenticated
        academicUsername = username
    }
}

final class IOSNativeEvents: EventsStreamHandler {
    private var eventSink: PigeonEventSink<NativeEventDto>?

    override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<NativeEventDto>) {
        eventSink = sink
    }

    override func onCancel(withArguments arguments: Any?) {
        eventSink = nil
    }

    @MainActor
    func emit(source: String, stage: String, message: String? = nil, progress: Double? = nil) {
        Task { await PersistentRuntimeLog.shared.append(source: source, message: "EVENT \(stage) progress=\(String(describing: progress)) \(message ?? "")") }
        eventSink?.success(NativeEventDto(
            source: source,
            stage: stage,
            message: message,
            progress: progress,
            timestampMillis: Int64(Date().timeIntervalSince1970 * 1000)
        ))
    }
}

func runNative<T>(
    completion: @escaping (Result<T, Error>) -> Void,
    operation: @escaping () async throws -> T
) {
    Task {
        do {
            let value = try await operation()
            await MainActor.run { completion(.success(value)) }
        } catch let error as CithubNativeError {
            await PersistentRuntimeLog.shared.append(source: "native-error", message: String(reflecting: error))
            let pigeonError = PigeonError(
                code: error.code,
                message: error.localizedDescription,
                details: nil
            )
            await MainActor.run { completion(.failure(pigeonError)) }
        } catch {
            await PersistentRuntimeLog.shared.append(source: "native-error", message: String(reflecting: error))
            await MainActor.run { completion(.failure(error)) }
        }
    }
}

@MainActor
func allWebCookies() async -> [HTTPCookie] {
    await withCheckedContinuation { continuation in
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
    }
}

@MainActor
func syncCookies(_ header: String, domains: [String], path: String = "/") async {
    let pairs = CookieHeaderStore.parse(header)
    for domain in domains {
        for (name, value) in pairs {
            let properties: [HTTPCookiePropertyKey: Any] = [
                .domain: domain,
                .path: path,
                .name: name,
                .value: value,
                .secure: "TRUE",
            ]
            guard let cookie = HTTPCookie(properties: properties) else { continue }
            await withCheckedContinuation { continuation in
                WKWebsiteDataStore.default().httpCookieStore.setCookie(cookie) {
                    continuation.resume()
                }
            }
        }
    }
}

@MainActor
func deleteCookies(names: Set<String>, domains: [String]) async {
    let cookies = await allWebCookies()
    for cookie in cookies where names.contains(cookie.name) && domains.contains(where: { cookie.domain.contains($0) }) {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.delete(cookie) { continuation.resume() }
        }
    }
}
