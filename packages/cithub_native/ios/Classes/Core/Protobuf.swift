import Foundation

public enum PBValue: Sendable, Equatable {
    case varint(UInt64)
    case fixed64(UInt64)
    case bytes(Data)
    case fixed32(UInt32)
}

public struct PBMessage: Sendable, Equatable {
    public private(set) var fields: [Int: [PBValue]] = [:]

    public init(data: Data) throws {
        var index = data.startIndex
        while index < data.endIndex {
            let key = try Self.readVarint(data, index: &index)
            let field = Int(key >> 3)
            let wire = Int(key & 7)
            guard field > 0 else { throw CithubNativeError.invalidResponse("protobuf 字段编号无效") }
            let value: PBValue
            switch wire {
            case 0:
                value = .varint(try Self.readVarint(data, index: &index))
            case 1:
                guard data.distance(from: index, to: data.endIndex) >= 8 else {
                    throw CithubNativeError.invalidResponse("protobuf fixed64 被截断")
                }
                var raw: UInt64 = 0
                for offset in 0..<8 { raw |= UInt64(data[data.index(index, offsetBy: offset)]) << UInt64(offset * 8) }
                index = data.index(index, offsetBy: 8)
                value = .fixed64(raw)
            case 2:
                let count = try Self.readVarint(data, index: &index)
                guard count <= UInt64(Int.max),
                      data.distance(from: index, to: data.endIndex) >= Int(count) else {
                    throw CithubNativeError.invalidResponse("protobuf bytes 被截断")
                }
                let end = data.index(index, offsetBy: Int(count))
                value = .bytes(Data(data[index..<end]))
                index = end
            case 5:
                guard data.distance(from: index, to: data.endIndex) >= 4 else {
                    throw CithubNativeError.invalidResponse("protobuf fixed32 被截断")
                }
                var raw: UInt32 = 0
                for offset in 0..<4 { raw |= UInt32(data[data.index(index, offsetBy: offset)]) << UInt32(offset * 8) }
                index = data.index(index, offsetBy: 4)
                value = .fixed32(raw)
            default:
                throw CithubNativeError.invalidResponse("不支持的 protobuf wire type：\(wire)")
            }
            fields[field, default: []].append(value)
        }
    }

    public func varint(_ field: Int) -> UInt64 {
        fields[field]?.compactMap { if case .varint(let value) = $0 { value } else { nil } }.first ?? 0
    }

    public func int64(_ field: Int) -> Int64 { Int64(bitPattern: varint(field)) }

    public func string(_ field: Int) -> String {
        fields[field]?.compactMap { value -> String? in
            guard case .bytes(let data) = value else { return nil }
            return String(data: data, encoding: .utf8)
        }.first ?? ""
    }

    public func bytes(_ field: Int) -> Data? {
        fields[field]?.compactMap { if case .bytes(let data) = $0 { data } else { nil } }.first
    }

    public func message(_ field: Int) -> PBMessage? {
        guard let data = bytes(field) else { return nil }
        return try? PBMessage(data: data)
    }

    public func messages(_ field: Int) -> [PBMessage] {
        fields[field]?.compactMap { value in
            guard case .bytes(let data) = value else { return nil }
            return try? PBMessage(data: data)
        } ?? []
    }

    public func packedVarints(_ field: Int) -> [UInt64] {
        var result: [UInt64] = fields[field]?.compactMap { value -> UInt64? in
            if case .varint(let raw) = value { return raw }
            return nil
        } ?? []
        for value in fields[field] ?? [] {
            guard case .bytes(let data) = value else { continue }
            var index = data.startIndex
            while index < data.endIndex, let next = try? Self.readVarint(data, index: &index) { result.append(next) }
        }
        return result
    }

    private static func readVarint(_ data: Data, index: inout Data.Index) throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < data.endIndex, shift < 64 {
            let byte = data[index]
            index = data.index(after: index)
            result |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
        throw CithubNativeError.invalidResponse("protobuf varint 被截断")
    }
}

public struct PBWriter: Sendable {
    public private(set) var data = Data()

    public init() {}

    public mutating func varint(_ field: Int, _ value: UInt64, includeZero: Bool = false) {
        guard value != 0 || includeZero else { return }
        appendVarint(UInt64(field << 3))
        appendVarint(value)
    }

    public mutating func int64(_ field: Int, _ value: Int64, includeZero: Bool = false) {
        varint(field, UInt64(bitPattern: value), includeZero: includeZero)
    }

    public mutating func bool(_ field: Int, _ value: Bool, includeFalse: Bool = false) {
        varint(field, value ? 1 : 0, includeZero: includeFalse)
    }

    public mutating func string(_ field: Int, _ value: String, includeEmpty: Bool = false) {
        guard !value.isEmpty || includeEmpty else { return }
        bytes(field, Data(value.utf8))
    }

    public mutating func bytes(_ field: Int, _ value: Data) {
        appendVarint(UInt64((field << 3) | 2))
        appendVarint(UInt64(value.count))
        data.append(value)
    }

    public mutating func message(_ field: Int, _ build: (inout PBWriter) -> Void) {
        var nested = PBWriter()
        build(&nested)
        bytes(field, nested.data)
    }

    public mutating func double(_ field: Int, _ value: Double, includeZero: Bool = false) {
        guard value != 0 || includeZero else { return }
        appendVarint(UInt64((field << 3) | 1))
        var bits = value.bitPattern.littleEndian
        withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
    }

    private mutating func appendVarint(_ value: UInt64) {
        var remaining = value
        while remaining >= 0x80 {
            data.append(UInt8(remaining & 0x7f) | 0x80)
            remaining >>= 7
        }
        data.append(UInt8(remaining))
    }
}

public enum TiebaFixture {
    public static func forumResponse(
        forumID: Int64,
        forumName: String,
        threadID: Int64,
        title: String,
        authorID: Int64,
        authorName: String,
        authorNickname: String
    ) -> Data {
        var outer = PBWriter()
        outer.message(2) { data in
            data.message(2) { forum in
                forum.int64(1, forumID)
                forum.string(2, forumName)
                forum.varint(9, 1234)
                forum.varint(10, 5678)
            }
            data.message(4) { page in
                page.varint(3, 1)
                page.varint(5, 3)
                page.varint(6, 1)
            }
            data.message(7) { thread in
                thread.int64(1, threadID)
                thread.int64(2, threadID)
                thread.string(3, title)
                thread.varint(4, 4)
                thread.varint(5, 42)
                thread.int64(27, forumID)
                thread.string(28, forumName)
                thread.int64(56, authorID)
            }
            data.message(17) { user in
                user.int64(2, authorID)
                user.string(3, authorName)
                user.string(4, authorNickname)
            }
        }
        return outer.data
    }

    public static func threadResponse(
        forumID: Int64,
        forumName: String,
        threadID: Int64,
        title: String,
        originalAuthorID: Int64,
        replyAuthorID: Int64
    ) -> Data {
        var outer = PBWriter()
        outer.message(2) { data in
            data.message(2) { forum in
                forum.int64(1, forumID)
                forum.string(2, forumName)
            }
            data.message(3) { page in
                page.varint(3, 1)
                page.varint(5, 2)
                page.varint(6, 1)
            }
            data.message(8) { thread in
                thread.int64(1, threadID)
                thread.int64(2, threadID)
                thread.string(3, title)
                thread.varint(4, 2)
                thread.message(18) { user in writeUser(
                    &user, id: originalAuthorID, name: "owner", nickname: "楼主"
                ) }
            }
            data.message(13) { user in writeUser(
                &user, id: originalAuthorID, name: "owner", nickname: "楼主"
            ) }
            data.message(13) { user in writeUser(
                &user, id: replyAuthorID, name: "reply", nickname: "回复用户"
            ) }
            data.message(38) { post in writePost(
                &post, id: 100, floor: 1, authorID: originalAuthorID, text: "正文"
            ) }
            data.message(6) { post in writePost(
                &post, id: 100, floor: 1, authorID: originalAuthorID, text: "正文"
            ) }
            data.message(6) { post in writePost(
                &post, id: 200, floor: 2, authorID: replyAuthorID, text: "回复正文"
            ) }
        }
        return outer.data
    }

    public static func floorResponse(forumID: Int64, forumName: String, authorID: Int64) -> Data {
        var outer = PBWriter()
        outer.message(2) { data in
            data.message(1) { page in
                page.varint(3, 1)
                page.varint(4, 21)
                page.varint(5, 3)
                page.varint(6, 1)
            }
            data.message(4) { reply in
                reply.int64(1, 101)
                reply.message(2) { content in
                    content.varint(1, 0, includeZero: true)
                    content.string(2, "楼中楼回复")
                }
                reply.varint(3, 1_700_000_000)
                reply.int64(4, authorID)
                reply.message(7) { user in writeUser(
                    &user, id: authorID, name: "floor", nickname: "楼中楼用户"
                ) }
            }
            data.message(6) { forum in
                forum.int64(1, forumID)
                forum.string(2, forumName)
            }
        }
        return outer.data
    }

    public static func profileResponse(uid: Int64, name: String, nickname: String) -> Data {
        var outer = PBWriter()
        outer.message(2) { data in
            data.message(1) { user in
                writeUser(&user, id: uid, name: name, nickname: nickname)
                user.string(27, "portrait-high")
                user.varint(30, 12)
                user.varint(31, 8)
                user.string(34, "用户简介")
                user.varint(37, 34)
            }
        }
        return outer.data
    }

    public static func userPostsResponse(uid: Int64, isThread: Bool) -> Data {
        var outer = PBWriter()
        outer.message(2) { data in
            data.message(1) { post in
                post.int64(1, 64554)
                post.int64(2, 9988)
                post.int64(3, isThread ? 100 : 101)
                post.varint(4, isThread ? 1 : 0, includeZero: true)
                post.varint(5, 1_700_000_000)
                post.string(6, "长春工程学院")
                post.string(7, "用户主题")
                post.string(14, isThread ? "主题摘要" : "")
                post.varint(17, 4)
                post.int64(18, uid)
                if isThread {
                    post.message(46) { content in
                        content.varint(1, 0, includeZero: true)
                        content.string(2, "主题摘要")
                    }
                } else {
                    post.message(8) { reply in
                        reply.message(1) { abstract in
                            abstract.varint(1, 0, includeZero: true)
                            abstract.string(2, "用户回复")
                        }
                        reply.varint(2, 1_700_000_001)
                        reply.int64(4, 101)
                    }
                }
            }
        }
        return outer.data
    }

    public static func forumRuleResponse() -> Data {
        var outer = PBWriter()
        outer.message(2) { data in
            data.string(3, "长春工程学院吧规")
            data.string(4, "请共同维护社区秩序")
            data.message(5) { rule in
                rule.string(1, "第一条")
                rule.message(2) { content in
                    content.varint(1, 0, includeZero: true)
                    content.string(2, "文明交流")
                }
            }
        }
        return outer.data
    }

    private static func writeUser(
        _ writer: inout PBWriter,
        id: Int64,
        name: String,
        nickname: String
    ) {
        writer.int64(2, id)
        writer.string(3, name)
        writer.string(4, nickname)
        writer.string(5, "portrait-\(id)")
        writer.varint(23, 8)
        writer.string(125, "八级会员")
    }

    private static func writePost(
        _ writer: inout PBWriter,
        id: Int64,
        floor: Int64,
        authorID: Int64,
        text: String
    ) {
        writer.int64(1, id)
        writer.int64(3, floor)
        writer.varint(4, 1_700_000_000)
        writer.message(5) { content in
            content.varint(1, 0, includeZero: true)
            content.string(2, text)
        }
        writer.int64(19, authorID)
    }
}
