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

actor IOSRuntimeLogStore: RuntimeLogger {
    private var entries: [String] = []
    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        fileURL = base.appendingPathComponent("cithub-runtime.log")
    }

    func append(source: String, message: String) async {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        entries.append("[\(timestamp)] [\(source)] \(message)")
        if entries.count > 2000 { entries.removeFirst(entries.count - 2000) }
    }

    func export() throws -> String {
        let data = Data((entries.joined(separator: "\n") + "\n").utf8)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
        return fileURL.path
    }

    func clear() {
        entries.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
    }
}

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
        } catch {
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
func syncCookies(_ header: String, domains: [String]) async {
    let pairs = CookieHeaderStore.parse(header)
    for domain in domains {
        for (name, value) in pairs {
            let properties: [HTTPCookiePropertyKey: Any] = [
                .domain: domain,
                .path: "/",
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
