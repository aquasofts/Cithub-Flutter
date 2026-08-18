import Foundation
import CryptoKit

public struct TiebaProtoIdentity: Sendable, Equatable {
    public var cuid: String
    public var aid: String
    public var clientID: String
    public var activeTimestamp: Int64
    public var firstInstallTime: Int64
    public var lastUpdateTime: Int64
    public var model: String
    public var osVersion: String
    public var userAgent: String
    public var screenWidth: Int64
    public var screenHeight: Int64
    public var screenScale: Double

    public init(
        seed: String,
        model: String = "iPhone",
        osVersion: String = "18",
        screenWidth: Int64 = 390,
        screenHeight: Int64 = 844,
        screenScale: Double = 3,
        installTimestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        let digest = md5Hex("com.baidu\(seed)").uppercased()
        let suffix = base32(Data(SHA256.hash(data: Data(digest.utf8)).prefix(5)))
        self.cuid = "\(digest)|V\(suffix)"
        self.aid = "A00-\(base32(Data(Insecure.SHA1.hash(data: Data("com.helios\(seed)".utf8)))))-"
        self.clientID = "wappc_\(installTimestamp)_\(digest.prefix(6))"
        self.activeTimestamp = installTimestamp
        self.firstInstallTime = installTimestamp
        self.lastUpdateTime = installTimestamp
        self.model = model
        self.osVersion = osVersion
        self.userAgent = "\(TiebaProtoClient.webUserAgent) tieba/\(TiebaProtoClient.protocolVersion)"
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.screenScale = screenScale
    }

    public static let testing = TiebaProtoIdentity(
        seed: "cithub-tests", model: "iPhone-Test", osVersion: "18",
        screenWidth: 390, screenHeight: 844, screenScale: 3,
        installTimestamp: 1_700_000_000_000
    )
}

private struct TiebaCredentials: Sendable {
    var uid: Int64
    var bduss: String
    var stoken: String
}

private struct TiebaPBUser: Sendable {
    var id: Int64
    var name: String
    var nickname: String
    var portrait: String
    var isManager: Bool
    var isBawu: Bool
    var bawuType: String
    var level: Int64
    var levelName: String
    var ip: String
}

public actor TiebaProtoClient {
    public static let defaultBaseURL = URL(string: "https://tiebac.baidu.com/")!
    public static let protocolVersion = "22.8.5.0"
    public static let webUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
    private static let boundary = "--------7da3d81520810*"

    private let logger: any RuntimeLogger
    private let baseURL: URL
    private let identity: TiebaProtoIdentity
    private let transport: any HTTPTransport

    public init(
        logger: any RuntimeLogger,
        baseURL: URL = TiebaProtoClient.defaultBaseURL,
        identity: TiebaProtoIdentity,
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.logger = logger
        self.baseURL = baseURL.absoluteString.hasSuffix("/") ? baseURL : URL(string: baseURL.absoluteString + "/")!
        self.identity = identity
        self.transport = transport
    }

    public func forum(
        name: String,
        page: Int64,
        sort: String,
        goodOnly: Bool,
        cookie: String,
        uid: Int64
    ) async throws -> CoreForumPage {
        let requestedPage = max(1, page)
        let credentials = credentials(cookie: cookie, uid: uid)
        let message = forumRequest(
            name: name,
            page: requestedPage,
            sortType: sort == "post" ? 1 : 0,
            goodOnly: goodOnly,
            credentials: credentials
        )
        let response = try await perform(
            name: "FRS",
            path: "c/f/frs/page?cmd=301001",
            message: message,
            credentials: credentials,
            includeSToken: true,
            extraHeaders: ["forum_name": FormEncoding.percent(name)]
        )
        try requireSuccess(response, kind: "FRS")
        return try mapForum(response, requestedPage: requestedPage, requestedForumName: name)
    }

    public func thread(
        threadID: String,
        forumID: Int64,
        forumName: String,
        page: Int64,
        sort: String,
        onlyOriginalPoster: Bool,
        cookie: String,
        uid: Int64
    ) async throws -> CoreThreadPage {
        guard let tid = Int64(threadID), tid > 0 else {
            throw CithubNativeError.invalidInput("无效的帖子 ID")
        }
        let requestedPage = max(1, page)
        let credentials = credentials(cookie: cookie, uid: uid)
        let sortType: Int64 = sort == "desc" ? 1 : (sort == "hot" ? 2 : 0)
        let response = try await perform(
            name: "PB",
            path: "c/f/pb/page?cmd=302001&format=protobuf",
            message: threadRequest(
                threadID: tid, page: requestedPage, sortType: sortType,
                onlyOriginalPoster: onlyOriginalPoster, forumID: forumID,
                credentials: credentials
            ),
            credentials: credentials,
            includeSToken: true
        )
        try requireSuccess(response, kind: "PB")
        return try mapThread(
            response, threadID: tid, requestedPage: requestedPage,
            expectedForumID: forumID, expectedForumName: forumName
        )
    }

    public func floorReplies(
        threadID: String,
        postID: String,
        page: Int64,
        forumID: Int64,
        forumName: String,
        cookie: String,
        uid: Int64
    ) async throws -> CoreFloorReplyPage {
        guard let tid = Int64(threadID), tid > 0 else {
            throw CithubNativeError.invalidInput("无效的帖子 ID")
        }
        guard let pid = Int64(postID), pid > 0 else {
            throw CithubNativeError.invalidInput("无效的楼层 ID")
        }
        let credentials = credentials(cookie: cookie, uid: uid)
        let response = try await perform(
            name: "PB_FLOOR",
            path: "c/f/pb/floor?cmd=302002&format=protobuf",
            message: floorRequest(
                threadID: tid, postID: pid, page: max(1, page),
                forumID: forumID, credentials: credentials
            ),
            credentials: credentials,
            includeSToken: false
        )
        try requireSuccess(response, kind: "PB_FLOOR")
        guard let data = response.message(2), let responsePage = data.message(1) else {
            throw CithubNativeError.invalidResponse("贴吧楼中楼响应缺少数据")
        }
        try requireForum(
            data.message(6), expectedID: forumID, expectedName: forumName
        )
        var seen = Set<String>()
        let replies = data.messages(4).compactMap { reply -> CoreFloorReply? in
            let mapped = mapReply(reply)
            let key = mapped.id.isEmpty ? "\(mapped.authorName):\(mapped.time):\(plainText(mapped.content))" : mapped.id
            return seen.insert(key).inserted ? mapped : nil
        }
        let currentPage = max(1, responsePage.int64(3) == 0 ? page : responsePage.int64(3))
        return CoreFloorReplyPage(
            replies: replies,
            page: currentPage,
            totalPages: max(currentPage, responsePage.int64(5)),
            totalReplies: max(Int64(replies.count), responsePage.int64(4))
        )
    }

    public func userProfile(uid: Int64, cookie: String, accountUID: Int64) async throws -> CoreTiebaUserProfile {
        guard uid > 0 else { throw CithubNativeError.invalidInput("无效的贴吧用户 ID") }
        let credentials = credentials(cookie: cookie, uid: accountUID)
        let response = try await perform(
            name: "PROFILE",
            path: "c/u/user/profile?cmd=303012&format=protobuf",
            message: profileRequest(uid: uid, credentials: credentials),
            credentials: credentials,
            includeSToken: true
        )
        try requireSuccess(response, kind: "PROFILE")
        guard let user = response.message(2)?.message(1) else {
            throw CithubNativeError.invalidResponse("贴吧用户响应缺少用户信息")
        }
        let threads = try await loadUserPosts(
            uid: uid, isThread: true, credentials: credentials
        )
        let replies = try await loadUserPosts(
            uid: uid, isThread: false, credentials: credentials
        )
        return CoreTiebaUserProfile(
            uid: user.int64(2),
            username: user.string(3),
            nickname: user.string(4).nilIfEmpty ?? user.string(3),
            avatarURL: portraitURL(user.string(27).nilIfEmpty ?? user.string(5)),
            intro: user.string(138).nilIfEmpty ?? user.string(34),
            fans: user.int64(30),
            concerned: user.int64(31),
            posts: user.int64(37),
            threads: threads,
            replies: replies
        )
    }

    public func forumRule(forumID: Int64, cookie: String, uid: Int64) async throws -> String {
        guard forumID > 0 else { throw CithubNativeError.invalidInput("无效的贴吧 ID") }
        let credentials = credentials(cookie: cookie, uid: uid)
        let response = try await perform(
            name: "FORUM_RULE",
            path: "c/f/forum/forumRuleDetail?cmd=309690&format=protobuf",
            message: forumRuleRequest(forumID: forumID, credentials: credentials),
            credentials: credentials,
            includeSToken: true
        )
        try requireSuccess(response, kind: "FORUM_RULE")
        guard let data = response.message(2) else {
            throw CithubNativeError.invalidResponse("贴吧吧规响应缺少数据")
        }
        var lines: [String] = []
        if !data.string(3).isEmpty { lines.append(data.string(3)) }
        if !data.string(4).isEmpty { lines.append(data.string(4)) }
        for rule in data.messages(5) {
            if !rule.string(1).isEmpty { lines.append(rule.string(1)) }
            let text = plainText(rule.messages(2).compactMap(mapContent))
            if !text.isEmpty { lines.append(text) }
        }
        return lines.joined(separator: "\n").nilIfEmpty ?? "该吧未提供公开吧规。"
    }

    public func resolveOriginalImage(
        _ request: CoreTiebaImageRequest,
        cookie: String,
        uid: Int64
    ) async throws -> String {
        guard let source = URL(string: request.url), source.scheme == "https", source.host != nil else {
            throw CithubNativeError.invalidInput("只允许 HTTPS 贴吧图片")
        }
        let picID = source.deletingPathExtension().lastPathComponent
        guard !picID.isEmpty else { throw CithubNativeError.invalidInput("无法识别贴吧图片 ID") }
        var fields = [
            "forum_id": String(request.forumID),
            "kw": request.forumName,
            "tid": String(request.threadID),
            "pic_id": picID,
            "pic_index": String(request.imageIndex),
            "obj_type": "pb",
            "page_name": "PB",
            "next": "10",
            "scr_h": String(identity.screenHeight),
            "scr_w": String(identity.screenWidth),
            "q_type": "2",
            "prev": "0",
            "not_see_lz": request.seeOriginalPosterOnly ? "0" : "1",
            "_client_id": identity.clientID,
            "_client_type": "2",
            "_client_version": "7.2.0.0",
            "_os_version": identity.osVersion,
            "_model": identity.model,
            "_net_type": "1",
            "_phone_imei": "",
            "_timestamp": String(Int64(Date().timeIntervalSince1970 * 1000)),
            "cuid": identity.cuid,
            "cuid_galaxy2": identity.cuid,
            "from": "1021636m",
            "subapp_type": "mini",
            "stErrorNums": "0",
        ]
        if let credentials = credentials(cookie: cookie, uid: uid) {
            fields["BDUSS"] = credentials.bduss
            fields["user_id"] = String(credentials.uid)
        }
        fields["sign"] = miniTiebaSign(fields)
        let endpointBase = baseURL == Self.defaultBaseURL
            ? URL(string: "https://c.tieba.baidu.com/")!
            : baseURL
        let url = URL(string: "c/f/pb/picpage", relativeTo: endpointBase)!.absoluteURL
        let response = try await transport.perform(HTTPCall(
            method: "POST",
            url: url,
            headers: [
                "Content-Type": "application/x-www-form-urlencoded",
                "User-Agent": identity.userAgent,
            ],
            body: FormEncoding.encode(fields, sorted: true)
        ))
        await logger.append(source: "tieba-pb", message: "PIC_PAGE -> HTTP \(response.status)")
        guard (200...299).contains(response.status) else {
            throw CithubNativeError.requestFailed("贴吧原图接口失败（HTTP \(response.status)）")
        }
        let envelope = try jsonObject(response.data)
        guard envelope.string("error_code", default: "-1") == "0" else {
            throw CithubNativeError.requestFailed(
                "贴吧原图接口失败（错误码 \(envelope.string("error_code"))）"
            )
        }
        let pictures = envelope.array("pic_list")?.compactMap { $0 as? [String: Any] } ?? []
        let picture = pictures.first { item in
            item.object("img")?.object("original")?.string("id") == picID
        } ?? pictures.first { item in
            item.int64("overall_index") == request.imageIndex
        }
        guard let original = picture?.object("img")?.object("original") else {
            throw CithubNativeError.invalidResponse("贴吧原图响应未包含目标图片")
        }
        let byteSize = original.int64("size")
        let width = original.int64("width")
        let height = original.int64("height")
        let selected: String
        if original.string("format") == "2" {
            selected = original.string("waterurl")
        } else if byteSize >= 2 * 1024 * 1024, width > 0, height > width * 3 {
            selected = original.string("big_cdn_src")
        } else { selected = original.string("waterurl") }
        let resolved = normalizeURL(selected.nilIfEmpty
            ?? original.string("original_src").nilIfEmpty
            ?? original.string("url").nilIfEmpty
            ?? original.string("big_cdn_src"))
        guard resolved.hasPrefix("https://"),
              !resolved.contains("/forum/pic/item/") || resolved.contains("tbpicau=") else {
            throw CithubNativeError.invalidResponse("贴吧原图地址无效")
        }
        return resolved
    }

    private func forumRequest(
        name: String,
        page: Int64,
        sortType: Int64,
        goodOnly: Bool,
        credentials: TiebaCredentials?
    ) -> Data {
        var request = PBWriter()
        request.message(1) { data in
            data.string(1, FormEncoding.percent(name))
            data.varint(2, 90)
            data.varint(3, 30)
            data.varint(4, goodOnly ? 1 : 0, includeZero: true)
            data.varint(8, 1)
            data.int64(11, identity.screenWidth)
            data.int64(12, identity.screenHeight)
            data.double(13, identity.screenScale)
            data.varint(14, 2)
            data.int64(15, page)
            data.string(16, "recom_flist")
            data.message(39) { common in commonRequest(&common, credentials: credentials) }
            data.int64(47, goodOnly ? -1 : sortType, includeZero: true)
            data.varint(49, page == 1 ? 1 : 2)
        }
        return request.data
    }

    private func threadRequest(
        threadID: Int64,
        page: Int64,
        sortType: Int64,
        onlyOriginalPoster: Bool,
        forumID: Int64,
        credentials: TiebaCredentials?
    ) -> Data {
        var request = PBWriter()
        request.message(1) { data in
            data.int64(4, threadID)
            data.varint(5, onlyOriginalPoster ? 1 : 0, includeZero: true)
            data.int64(6, sortType, includeZero: true)
            data.varint(8, 1)
            data.varint(9, 4)
            data.varint(13, 15)
            data.int64(14, identity.screenWidth)
            data.int64(15, identity.screenHeight)
            data.double(16, identity.screenScale)
            data.varint(17, 2)
            data.int64(18, page)
            data.string(19, "", includeEmpty: true)
            data.message(25) { common in commonRequest(&common, credentials: credentials) }
            data.string(50, "", includeEmpty: true)
            data.string(51, "", includeEmpty: true)
            data.string(52, "10")
            data.int64(56, forumID)
            data.message(58) { ad in
                ad.varint(1, 0, includeZero: true)
                ad.varint(2, 1)
                ad.varint(3, 1)
            }
            data.varint(74, 1)
            data.varint(75, 2)
        }
        return request.data
    }

    private func floorRequest(
        threadID: Int64,
        postID: Int64,
        page: Int64,
        forumID: Int64,
        credentials: TiebaCredentials?
    ) -> Data {
        var request = PBWriter()
        request.message(1) { data in
            data.int64(1, threadID)
            data.int64(2, postID)
            data.int64(4, page)
            data.int64(5, identity.screenWidth)
            data.int64(6, identity.screenHeight)
            data.double(7, identity.screenScale)
            data.string(8, "", includeEmpty: true)
            data.message(9) { common in commonRequest(&common, credentials: credentials) }
            data.varint(10, 0, includeZero: true)
            data.int64(11, forumID)
            data.varint(15, 0, includeZero: true)
        }
        return request.data
    }

    private func profileRequest(uid: Int64, credentials: TiebaCredentials?) -> Data {
        let selfProfile = credentials?.uid == uid
        var request = PBWriter()
        request.message(1) { data in
            if let credentials { data.int64(1, credentials.uid) }
            data.varint(2, 1)
            if !selfProfile { data.int64(3, uid) }
            data.varint(4, selfProfile ? 0 : 1, includeZero: true)
            data.varint(6, 1)
            data.varint(7, 20)
            data.varint(8, 1)
            data.message(9) { common in commonRequest(&common, credentials: credentials) }
            data.int64(10, identity.screenWidth)
            data.int64(11, identity.screenHeight)
            data.varint(12, 0, includeZero: true)
            data.double(13, identity.screenScale)
            data.varint(14, 1)
            data.varint(15, 1)
            data.string(16, "", includeEmpty: true)
        }
        return request.data
    }

    private func userPostsRequest(
        uid: Int64,
        isThread: Bool,
        credentials: TiebaCredentials?
    ) -> Data {
        var request = PBWriter()
        request.message(1) { data in
            data.int64(1, uid)
            data.varint(2, 20)
            data.varint(4, isThread ? 1 : 0, includeZero: true)
            data.varint(5, 1)
            if !isThread { data.varint(9, 0, includeZero: true) }
            data.varint(26, 1)
            data.message(27) { common in commonRequest(&common, credentials: credentials) }
            data.int64(29, identity.screenWidth)
            data.int64(30, identity.screenHeight)
            data.double(31, identity.screenScale)
            data.varint(32, 1)
            data.varint(33, isThread ? 1 : 0, includeZero: true)
        }
        return request.data
    }

    private func forumRuleRequest(forumID: Int64, credentials: TiebaCredentials?) -> Data {
        var request = PBWriter()
        request.message(1) { data in
            data.int64(1, forumID)
            data.message(2) { common in commonRequest(&common, credentials: credentials) }
        }
        return request.data
    }

    private func loadUserPosts(
        uid: Int64,
        isThread: Bool,
        credentials: TiebaCredentials?
    ) async throws -> [CoreTiebaUserPost] {
        let response = try await perform(
            name: isThread ? "USER_THREAD" : "USER_REPLY",
            path: "c/u/feed/userpost?cmd=303002&format=protobuf",
            message: userPostsRequest(uid: uid, isThread: isThread, credentials: credentials),
            credentials: credentials,
            includeSToken: true
        )
        try requireSuccess(response, kind: "USER_POST")
        let posts = response.message(2)?.messages(1) ?? []
        if isThread { return posts.map(mapUserThread) }
        return posts.flatMap(mapUserReplies)
    }

    private func mapUserThread(_ post: PBMessage) -> CoreTiebaUserPost {
        let rich = post.messages(46).compactMap(mapContent)
        let media = post.messages(16).compactMap { item in
            [item.string(15), item.string(3), item.string(8)].first(where: { !$0.isEmpty }).map(normalizeURL)
        }
        let images = media.isEmpty ? rich.filter { $0.kind == "image" }.map(\.originalURL) : media
        return CoreTiebaUserPost(
            threadID: post.int64(2), postID: post.int64(3),
            title: post.string(7).nilIfEmpty ?? "无标题",
            excerpt: plainText(rich).nilIfEmpty ?? HTMLParser.text(post.string(14)),
            time: formatEpoch(post.int64(5)), forumID: post.int64(1), forumName: post.string(6),
            replyCount: post.int64(17), isReply: false,
            imageURLs: Array(Set(images.filter { !$0.isEmpty })).sorted()
        )
    }

    private func mapUserReplies(_ post: PBMessage) -> [CoreTiebaUserPost] {
        let content = post.messages(8)
        if content.isEmpty {
            return [CoreTiebaUserPost(
                threadID: post.int64(2), postID: post.int64(3),
                title: post.string(7).nilIfEmpty ?? "原帖", excerpt: HTMLParser.text(post.string(14)),
                time: formatEpoch(post.int64(5)), forumID: post.int64(1), forumName: post.string(6),
                replyCount: post.int64(17), isReply: true, imageURLs: []
            )]
        }
        return content.map { item in
            CoreTiebaUserPost(
                threadID: post.int64(2), postID: item.int64(4),
                title: post.string(7).nilIfEmpty ?? "原帖",
                excerpt: item.messages(1).map { $0.string(2) }.joined(),
                time: formatEpoch(item.int64(2)), forumID: post.int64(1), forumName: post.string(6),
                replyCount: post.int64(17), isReply: true, imageURLs: []
            )
        }
    }

    private func commonRequest(_ writer: inout PBWriter, credentials: TiebaCredentials?) {
        writer.varint(1, 2)
        writer.string(2, Self.protocolVersion)
        writer.string(3, identity.clientID)
        writer.string(5, "000000000000000")
        writer.string(6, "1020031h")
        writer.string(7, identity.cuid)
        writer.int64(8, Int64(Date().timeIntervalSince1970 * 1000))
        writer.string(9, identity.model)
        if let credentials {
            writer.string(10, credentials.bduss)
            writer.string(30, credentials.stoken)
        }
        writer.varint(12, 1)
        writer.string(24, "1.0.3")
        writer.string(25, identity.osVersion)
        writer.string(26, "Apple")
        writer.string(28, "3.0.0")
        writer.string(32, identity.cuid)
        writer.string(35, identity.aid)
        writer.int64(37, identity.screenWidth)
        writer.int64(38, identity.screenHeight)
        writer.double(39, identity.screenScale)
        writer.varint(40, 0, includeZero: true)
        writer.varint(41, 0, includeZero: true)
        writer.string(42, "2.34.0")
        writer.string(43, "3340042")
        writer.string(44, "1038000")
        writer.int64(49, identity.activeTimestamp)
        writer.int64(50, identity.firstInstallTime)
        writer.int64(51, identity.lastUpdateTime)
        writer.string(53, eventDay())
        writer.string(54, Data(identity.clientID.utf8).base64EncodedString())
        writer.varint(55, 1)
        writer.string(56, "", includeEmpty: true)
        writer.varint(57, 1)
        writer.string(61, "", includeEmpty: true)
        writer.string(62, identity.userAgent)
        writer.varint(63, 1)
    }

    private func perform(
        name: String,
        path: String,
        message: Data,
        credentials: TiebaCredentials?,
        includeSToken: Bool,
        extraHeaders: [String: String] = [:]
    ) async throws -> PBMessage {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw CithubNativeError.invalidInput("贴吧协议地址无效")
        }
        var headers = [
            "Charset": "UTF-8",
            "client_type": "2",
            "cookie": "ka:open; CUID:\(identity.cuid); TBBRAND:\(identity.model)",
            "cuid": identity.cuid,
            "cuid_galaxy2": identity.cuid,
            "cuid_gid": "",
            "c3_aid": identity.aid,
            "User-Agent": identity.userAgent,
            "x_bd_data_type": "protobuf",
            "Content-Type": "multipart/form-data; boundary=\(Self.boundary)",
        ]
        extraHeaders.forEach { headers[$0.key] = $0.value }
        if let credentials { headers["client_user_token"] = String(credentials.uid) }
        let body = multipart(message: message, stoken: includeSToken ? credentials?.stoken : nil)
        let started = Date().timeIntervalSinceReferenceDate
        let response = try await transport.perform(HTTPCall(method: "POST", url: url, headers: headers, body: body))
        let elapsed = Int64((Date().timeIntervalSinceReferenceDate - started) * 1000)
        await logger.append(source: "tieba-pb", message: "\(name) -> HTTP \(response.status) \(elapsed)ms")
        guard (200...299).contains(response.status) else {
            throw CithubNativeError.requestFailed("\(name) 请求失败（HTTP \(response.status)）")
        }
        return try PBMessage(data: response.data)
    }

    private func multipart(message: Data, stoken: String?) -> Data {
        var result = Data()
        func append(_ value: String) { result.append(Data(value.utf8)) }
        if let stoken, !stoken.isEmpty {
            append("--\(Self.boundary)\r\n")
            append("Content-Disposition: form-data; name=\"stoken\"\r\n\r\n")
            append(stoken + "\r\n")
        }
        append("--\(Self.boundary)\r\n")
        append("Content-Disposition: form-data; name=\"data\"; filename=\"file\"\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
        result.append(message)
        append("\r\n--\(Self.boundary)--\r\n")
        return result
    }

    private func requireSuccess(_ response: PBMessage, kind: String) throws {
        let code = response.message(1)?.int64(1) ?? 0
        guard code == 0 else { throw CithubNativeError.requestFailed("\(kind) 接口失败（错误码 \(code)）") }
    }

    private func mapForum(
        _ response: PBMessage,
        requestedPage: Int64,
        requestedForumName: String
    ) throws -> CoreForumPage {
        guard let data = response.message(2), let forum = data.message(2), let page = data.message(4) else {
            throw CithubNativeError.invalidResponse("贴吧列表响应缺少数据")
        }
        let forumName = forum.string(2)
        guard canonicalForumName(forumName) == canonicalForumName(requestedForumName) else {
            throw CithubNativeError.invalidResponse("贴吧响应与请求名称不匹配")
        }
        let users = Dictionary(uniqueKeysWithValues: data.messages(17).map { user in
            let parsed = mapUser(user)
            return (parsed.id, parsed)
        })
        let forumID = forum.int64(1)
        var seen = Set<String>()
        let threads = data.messages(7).compactMap { thread -> CoreForumThread? in
            guard let mapped = mapForumThread(
                thread, users: users, fallbackForumID: forumID, fallbackForumName: forumName
            ), seen.insert(mapped.id).inserted else { return nil }
            return mapped
        }
        guard !threads.isEmpty else {
            throw CithubNativeError.invalidResponse("贴吧移动协议未返回可显示帖子")
        }
        let signUser = forum.message(15)?.message(1)
        let ruleTitle = data.message(105)?.string(2) ?? ""
        let currentPage = max(1, page.int64(3) == 0 ? requestedPage : page.int64(3))
        let hasMore = page.int64(6) == 1 || page.int64(5) > currentPage
        return CoreForumPage(
            forum: CoreForumSummary(
                id: String(forumID), name: forumName, avatarURL: normalizeURL(forum.string(24)),
                memberCount: String(forum.int64(9)), threadCount: String(forum.int64(10)),
                forumRuleTitle: ruleTitle, isFollowed: forum.int64(6) == 1,
                signed: signUser?.int64(2) == 1, signedDays: signUser?.int64(5) ?? 0
            ),
            threads: threads,
            page: currentPage,
            hasMore: hasMore
        )
    }

    private func mapForumThread(
        _ source: PBMessage,
        users: [Int64: TiebaPBUser],
        fallbackForumID: Int64,
        fallbackForumName: String
    ) -> CoreForumThread? {
        let id = source.int64(2) != 0 ? source.int64(2) : source.int64(1)
        guard id > 0 else { return nil }
        let authorID = source.int64(56)
        let author = users[authorID] ?? source.message(18).map(mapUser)
        let content = source.messages(112).compactMap(mapContent)
        let mediaImages = source.messages(22).compactMap { media in
            [media.string(15), media.string(3), media.string(8)].first(where: { !$0.isEmpty }).map(normalizeURL)
        }
        let contentImages = content.filter { $0.kind == "image" }.map(\.originalURL)
        let nestedForum = source.message(155)
        return CoreForumThread(
            id: String(id),
            title: source.string(3).isEmpty ? "无标题" : source.string(3),
            excerpt: plainText(content).isEmpty
                ? source.messages(21).map { $0.string(2) }.joined()
                : plainText(content),
            excerptContent: content,
            authorName: author?.name ?? "",
            authorNickname: (author?.nickname.isEmpty == false ? author?.nickname : author?.name) ?? "",
            authorID: author?.id ?? authorID,
            authorPortrait: portraitURL(author?.portrait ?? ""),
            replyCount: String(max(0, source.int64(4) - 1)),
            viewCount: String(source.int64(5)),
            lastReplyTime: source.string(6),
            isTop: source.int64(9) == 1,
            isGood: source.int64(10) == 1,
            imageURLs: Array(Set((mediaImages + contentImages).filter { !$0.isEmpty })).sorted(),
            forumID: nestedForum?.int64(1) ?? (source.int64(27) != 0 ? source.int64(27) : fallbackForumID),
            forumName: nestedForum?.string(2).nilIfEmpty ?? source.string(28).nilIfEmpty ?? fallbackForumName,
            authorModeratorRole: moderatorRole(author)
        )
    }

    private func mapThread(
        _ response: PBMessage,
        threadID: Int64,
        requestedPage: Int64,
        expectedForumID: Int64,
        expectedForumName: String
    ) throws -> CoreThreadPage {
        guard let data = response.message(2), let page = data.message(3), let thread = data.message(8) else {
            throw CithubNativeError.invalidResponse("贴吧帖子响应缺少数据")
        }
        try requireForum(data.message(2), expectedID: expectedForumID, expectedName: expectedForumName)
        let users = Dictionary(uniqueKeysWithValues: data.messages(13).map { message in
            let user = mapUser(message)
            return (user.id, user)
        })
        var posts = data.messages(6)
        if let first = data.message(38) { posts.insert(first, at: 0) }
        if let hot = data.message(20) { posts.append(contentsOf: hot.messages(1)) }
        if let top = data.message(34) { posts.append(contentsOf: top.messages(1)) }
        let originalAuthorID = thread.message(18)?.int64(2) ?? data.message(38)?.int64(19) ?? 0
        var mappedByID: [String: CoreThreadFloor] = [:]
        var order: [String] = []
        for post in posts {
            let mapped = mapPost(post, users: users, originalAuthorID: originalAuthorID)
            guard !mapped.postID.isEmpty else { continue }
            if mappedByID[mapped.postID] == nil { order.append(mapped.postID) }
            mappedByID[mapped.postID] = mapped
        }
        let mapped = order.compactMap { mappedByID[$0] }
        let body = data.message(38).map { mapPost($0, users: users, originalAuthorID: originalAuthorID) }
            ?? mapped.first(where: { $0.floor == 1 })
        let floors = mapped.filter { $0.postID != body?.postID && $0.floor != 1 }
        let currentPage = max(1, page.int64(3) == 0 ? requestedPage : page.int64(3))
        return CoreThreadPage(
            title: thread.string(3).nilIfEmpty ?? "帖子",
            body: body,
            floors: floors,
            page: currentPage,
            totalPages: max(currentPage, page.int64(5)),
            replyCount: max(0, thread.int64(4) - 1)
        )
    }

    private func mapPost(
        _ post: PBMessage,
        users: [Int64: TiebaPBUser],
        originalAuthorID: Int64
    ) -> CoreThreadFloor {
        let authorID = post.int64(19)
        let author = post.message(23).map(mapUser) ?? users[authorID]
        let replies = post.message(15)?.messages(2).map(mapReply) ?? []
        return CoreThreadFloor(
            postID: post.int64(1) > 0 ? String(post.int64(1)) : "",
            floor: post.int64(3),
            authorID: author?.id ?? authorID,
            authorName: author?.name ?? "",
            authorNickname: author?.nickname.nilIfEmpty ?? author?.name ?? "",
            authorPortrait: portraitURL(author?.portrait ?? ""),
            authorLevel: author?.level ?? 0,
            authorTitle: author?.levelName ?? "",
            authorIP: author?.ip ?? "",
            authorModeratorRole: moderatorRole(author),
            time: formatEpoch(post.int64(4)),
            content: post.messages(5).compactMap(mapContent),
            replies: replies,
            replyCount: post.int64(13),
            isOriginalPoster: (author?.id ?? authorID) > 0 && (author?.id ?? authorID) == originalAuthorID
        )
    }

    private func mapReply(_ reply: PBMessage) -> CoreFloorReply {
        let authorID = reply.int64(4)
        let author = reply.message(7).map(mapUser)
        return CoreFloorReply(
            id: reply.int64(1) > 0 ? String(reply.int64(1)) : "",
            authorID: author?.id ?? authorID,
            authorName: author?.name ?? "",
            authorNickname: author?.nickname.nilIfEmpty ?? author?.name ?? "",
            authorPortrait: portraitURL(author?.portrait ?? ""),
            content: reply.messages(2).compactMap(mapContent),
            time: formatEpoch(reply.int64(3)),
            authorLevel: author?.level ?? 0,
            authorTitle: author?.levelName ?? "",
            authorIP: author?.ip ?? "",
            authorModeratorRole: moderatorRole(author)
        )
    }

    private func requireForum(_ forum: PBMessage?, expectedID: Int64, expectedName: String) throws {
        guard let forum else {
            if expectedID <= 0 && expectedName.isEmpty { return }
            throw CithubNativeError.invalidResponse("贴吧响应缺少吧信息")
        }
        let idMatches = expectedID <= 0 || forum.int64(1) == expectedID
        let nameMatches = expectedName.isEmpty || canonicalForumName(forum.string(2)) == canonicalForumName(expectedName)
        guard idMatches && nameMatches else {
            throw CithubNativeError.invalidResponse("帖子不属于当前贴吧")
        }
    }

    private func formatEpoch(_ seconds: Int64) -> String {
        guard seconds > 0 else { return "" }
        return DateFormatter.localizedString(
            from: Date(timeIntervalSince1970: TimeInterval(seconds)),
            dateStyle: .short,
            timeStyle: .short
        )
    }

    private func mapUser(_ message: PBMessage) -> TiebaPBUser {
        TiebaPBUser(
            id: message.int64(2), name: message.string(3), nickname: message.string(4),
            portrait: message.string(5), isManager: message.int64(11) == 1,
            isBawu: message.int64(25) == 1, bawuType: message.string(26),
            level: message.int64(23), levelName: message.string(125),
            ip: message.string(127).nilIfEmpty ?? message.string(28)
        )
    }

    private func moderatorRole(_ user: TiebaPBUser?) -> CoreTiebaModeratorRole {
        guard let user else { return .none }
        if user.isManager || (user.isBawu && user.bawuType.lowercased() == "manager") { return .owner }
        if user.isBawu { return .assistant }
        return .none
    }

    private func mapContent(_ message: PBMessage) -> CoreTiebaContent? {
        let type = message.int64(1)
        let text = message.string(2)
        switch type {
        case 0, 4, 9, 27, 35, 40:
            return text.isEmpty ? nil : .text(text)
        case 1:
            return CoreTiebaContent(
                kind: "link", text: text.nilIfEmpty ?? message.string(3), emoticonID: "",
                url: normalizeURL(message.string(3)), originalURL: "", width: 0, height: 0
            )
        case 2:
            return CoreTiebaContent(
                kind: "emoticon", text: message.string(11).nilIfEmpty ?? text.nilIfEmpty ?? "表情",
                emoticonID: text, url: "", originalURL: "", width: 0, height: 0
            )
        case 3, 20:
            let preview = [9, 36, 8, 6, 4, 25].map(message.string).first(where: { !$0.isEmpty }) ?? ""
            let original = [25, 9, 6, 36, 8, 4].map(message.string).first(where: { !$0.isEmpty }) ?? preview
            guard !preview.isEmpty else { return nil }
            let dimensions = imageDimensions(message)
            return CoreTiebaContent(
                kind: "image", text: "", emoticonID: "", url: normalizeURL(preview),
                originalURL: normalizeURL(original), width: dimensions.0, height: dimensions.1
            )
        case 5:
            let link = [message.string(3), message.string(4)].first(where: {
                $0.hasPrefix("http") && ($0.contains(".mp4") || $0.contains(".m3u8"))
            })
            guard let link else { return .text("[视频]\(text)") }
            let dimensions = imageDimensions(message)
            return CoreTiebaContent(
                kind: "video", text: "", emoticonID: "", url: normalizeURL(link),
                originalURL: normalizeURL(message.string(4)), width: dimensions.0, height: dimensions.1
            )
        case 10: return .text("[语音]")
        default: return text.isEmpty ? nil : .text(text)
        }
    }

    private func imageDimensions(_ message: PBMessage) -> (Int64, Int64) {
        let parts = message.string(5).split(separator: ",").compactMap { Int64($0) }
        if parts.count >= 2 { return (max(0, parts[0]), max(0, parts[1])) }
        return (max(0, message.int64(18)), max(0, message.int64(19)))
    }

    private func credentials(cookie: String, uid: Int64) -> TiebaCredentials? {
        let parsed = CookieHeaderStore.parse(cookie)
        guard let bduss = parsed.first(where: { $0.key.caseInsensitiveCompare("BDUSS") == .orderedSame })?.value,
              let stoken = parsed.first(where: { $0.key.caseInsensitiveCompare("STOKEN") == .orderedSame })?.value,
              !bduss.isEmpty, !stoken.isEmpty else { return nil }
        return TiebaCredentials(uid: max(0, uid), bduss: bduss, stoken: stoken)
    }

    private func eventDay() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMdd"
        return formatter.string(from: Date())
    }
}

public func miniTiebaSign(_ fields: [String: String]) -> String {
    let raw = fields.filter { $0.key != "sign" }.sorted { $0.key < $1.key }
        .map { "\($0.key)=\($0.value)" }.joined() + "tiebaclient!!!"
    return md5Hex(raw)
}

private func md5Hex(_ value: String) -> String {
    Insecure.MD5.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
}

private func base32(_ data: Data) -> String {
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
    var buffer = 0
    var bits = 0
    var result = ""
    for byte in data {
        buffer = (buffer << 8) | Int(byte)
        bits += 8
        while bits >= 5 {
            bits -= 5
            result.append(alphabet[(buffer >> bits) & 31])
        }
    }
    if bits > 0 { result.append(alphabet[(buffer << (5 - bits)) & 31]) }
    return result
}

private func canonicalForumName(_ value: String) -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.hasSuffix("吧") ? String(normalized.dropLast()) : normalized
}

private func normalizeURL(_ raw: String) -> String {
    if raw.hasPrefix("//") { return "https:\(raw)" }
    if raw.hasPrefix("http://") { return "https://" + String(raw.dropFirst("http://".count)) }
    return raw.hasPrefix("https://") ? raw : ""
}

private func portraitURL(_ portrait: String) -> String {
    guard !portrait.isEmpty else { return "" }
    if portrait.hasPrefix("http") || portrait.hasPrefix("//") { return normalizeURL(portrait) }
    return "https://himg.bdimg.com/sys/portrait/item/\(portrait.components(separatedBy: "?").first ?? portrait).jpg"
}

private func plainText(_ content: [CoreTiebaContent]) -> String {
    content.map { item in
        switch item.kind {
        case "text", "link": return item.text
        case "emoticon": return "#(\(item.text))"
        case "video": return "[视频]"
        default: return ""
        }
    }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
