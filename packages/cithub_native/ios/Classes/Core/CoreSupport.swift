import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum CithubNativeError: LocalizedError, Sendable {
    case invalidResponse(String)
    case requestFailed(String)
    case loginRequired(String)
    case invalidInput(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse(let message), .requestFailed(let message),
             .loginRequired(let message), .invalidInput(let message):
            return message
        }
    }

    public var code: String {
        switch self {
        case .invalidResponse: "invalidResponse"
        case .requestFailed: "requestFailed"
        case .loginRequired: "loginRequired"
        case .invalidInput: "invalidInput"
        }
    }
}

public protocol SecretStore: Sendable {
    func put(_ key: String, _ value: String) async
    func get(_ key: String) async -> String?
    func remove(_ key: String) async
}

public actor MemorySecretStore: SecretStore {
    private var values: [String: String]

    public init(values: [String: String] = [:]) {
        self.values = values
    }

    public func put(_ key: String, _ value: String) {
        values[key] = value
    }

    public func get(_ key: String) -> String? {
        values[key]
    }

    public func remove(_ key: String) {
        values.removeValue(forKey: key)
    }
}

public protocol RuntimeLogger: Sendable {
    func append(source: String, message: String) async
}

public struct NullRuntimeLogger: RuntimeLogger {
    public init() {}
    public func append(source: String, message: String) async {}
}

public struct HTTPCall: Sendable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data
    public var followRedirects: Bool

    public init(
        method: String = "GET",
        url: URL,
        headers: [String: String] = [:],
        body: Data = Data(),
        followRedirects: Bool = true
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.followRedirects = followRedirects
    }
}

public struct HTTPResponse: Sendable {
    public var status: Int
    public var headers: [String: String]
    public var data: Data
    public var finalURL: URL?

    public init(status: Int, headers: [String: String] = [:], data: Data, finalURL: URL? = nil) {
        self.status = status
        self.headers = headers
        self.data = data
        self.finalURL = finalURL
    }

    public static func json(_ body: String, status: Int = 200, headers: [String: String] = [:]) -> Self {
        var result = headers
        result["Content-Type"] = result["Content-Type"] ?? "application/json"
        return HTTPResponse(status: status, headers: result, data: Data(body.utf8))
    }

    public static func html(_ body: String, status: Int = 200, headers: [String: String] = [:]) -> Self {
        var result = headers
        result["Content-Type"] = result["Content-Type"] ?? "text/html; charset=utf-8"
        return HTTPResponse(status: status, headers: result, data: Data(body.utf8))
    }

    public static func protobuf(_ body: Data, status: Int = 200, headers: [String: String] = [:]) -> Self {
        var result = headers
        result["Content-Type"] = result["Content-Type"] ?? "application/x-protobuf"
        return HTTPResponse(status: status, headers: result, data: body)
    }

    public var text: String { String(decoding: data, as: UTF8.self) }

    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

public protocol HTTPTransport: Sendable {
    func perform(_ call: HTTPCall) async throws -> HTTPResponse
}

public actor QueueHTTPTransport: HTTPTransport {
    private var responses: [HTTPResponse]
    public private(set) var recordedCalls: [HTTPCall] = []

    public init(_ responses: [HTTPResponse]) {
        self.responses = responses
    }

    public func perform(_ call: HTTPCall) throws -> HTTPResponse {
        recordedCalls.append(call)
        guard !responses.isEmpty else {
            throw CithubNativeError.requestFailed("测试传输层没有更多响应")
        }
        return responses.removeFirst()
    }
}

private final class RedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

public final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let configuration: URLSessionConfiguration

    public init(configuration: URLSessionConfiguration = .ephemeral) {
        self.configuration = configuration
        self.configuration.timeoutIntervalForRequest = 20
        self.configuration.timeoutIntervalForResource = 30
        self.configuration.httpCookieStorage = nil
        self.configuration.urlCache = nil
    }

    public func perform(_ call: HTTPCall) async throws -> HTTPResponse {
        var request = URLRequest(url: call.url)
        request.httpMethod = call.method
        request.httpBody = call.body.isEmpty ? nil : call.body
        call.headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let delegate = call.followRedirects ? nil : RedirectDelegate()
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CithubNativeError.invalidResponse("服务器未返回 HTTP 响应")
        }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            headers[String(describing: key)] = String(describing: value)
        }
        return HTTPResponse(status: http.statusCode, headers: headers, data: data, finalURL: http.url)
    }
}

public enum FormEncoding {
    public static func encode(_ fields: [String: String], sorted: Bool = false) -> Data {
        let entries = sorted ? fields.sorted { $0.key < $1.key } : Array(fields)
        return Data(entries.map { "\(percent($0.key))=\(percent($0.value))" }.joined(separator: "&").utf8)
    }

    public static func percent(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}

public actor CookieHeaderStore {
    private let store: any SecretStore
    private let key: String

    public init(store: any SecretStore, key: String = "webvpn.session.cookies") {
        self.store = store
        self.key = key
    }

    public func header() async -> String {
        await store.get(key) ?? ""
    }

    public func merge(_ rawHeaders: [String]) async {
        guard !rawHeaders.isEmpty else { return }
        var cookies = Self.parseOrdered(await header())
        for rawHeader in rawHeaders {
            // URLSession may combine Set-Cookie values. Splitting at a comma is
            // safe here because only the first name=value pair of each cookie is used.
            for raw in rawHeader.split(separator: ",") {
                let pair = raw.split(separator: ";", maxSplits: 1).first.map(String.init) ?? ""
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if value.isEmpty || raw.range(of: "Max-Age=0", options: .caseInsensitive) != nil {
                    cookies.removeAll { $0.0.caseInsensitiveCompare(name) == .orderedSame }
                } else {
                    if let index = cookies.firstIndex(where: { $0.0.caseInsensitiveCompare(name) == .orderedSame }) {
                        cookies[index] = (name, value)
                    } else {
                        cookies.append((name, value))
                    }
                }
            }
        }
        let value = cookies.map { "\($0.0)=\($0.1)" }.joined(separator: "; ")
        if value.isEmpty { await store.remove(key) } else { await store.put(key, value) }
    }

    public func remove(named name: String) async {
        var cookies = Self.parseOrdered(await header())
        cookies.removeAll { $0.0.caseInsensitiveCompare(name) == .orderedSame }
        let value = cookies.map { "\($0.0)=\($0.1)" }.joined(separator: "; ")
        if value.isEmpty { await store.remove(key) } else { await store.put(key, value) }
    }

    public func clear() async { await store.remove(key) }

    public static func parse(_ header: String) -> [String: String] {
        Dictionary(uniqueKeysWithValues: parseOrdered(header))
    }

    private static func parseOrdered(_ header: String) -> [(String, String)] {
        var result: [(String, String)] = []
        for part in header.split(separator: ";") {
            let pieces = part.split(separator: "=", maxSplits: 1).map(String.init)
            if pieces.count == 2 {
                let name = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)
                result.append((name, value))
            }
        }
        return result
    }
}

public extension Dictionary where Key == String, Value == Any {
    func string(_ key: String, default fallback: String = "") -> String {
        if let value = self[key] as? String { return value }
        if let value = self[key] as? NSNumber { return value.stringValue }
        return fallback
    }

    func int64(_ key: String, default fallback: Int64 = 0) -> Int64 {
        if let value = self[key] as? NSNumber { return value.int64Value }
        return Int64(string(key)) ?? fallback
    }

    func bool(_ key: String) -> Bool {
        if let value = self[key] as? Bool { return value }
        if let value = self[key] as? NSNumber { return value.boolValue }
        return ["true", "1", "yes"].contains(string(key).lowercased())
    }

    func object(_ key: String) -> [String: Any]? { self[key] as? [String: Any] }
    func array(_ key: String) -> [Any]? { self[key] as? [Any] }
}

public func jsonObject(_ data: Data) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw CithubNativeError.invalidResponse("服务器返回了无效 JSON")
    }
    return object
}
