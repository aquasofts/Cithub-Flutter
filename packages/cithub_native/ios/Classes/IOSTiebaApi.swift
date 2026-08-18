import Foundation
import UIKit

final class IOSTiebaApi: TiebaHostApi {
    private let store: any SecretStore
    private let logger: IOSRuntimeLogStore
    private let events: IOSNativeEvents
    private let webClient: TiebaWebClient
    private let protoClient: TiebaProtoClient
    private var forumNames: [Int64: String] = [:]
    private var threadForums: [String: (Int64, String)] = [:]

    init(store: any SecretStore, logger: IOSRuntimeLogStore, events: IOSNativeEvents) {
        self.store = store
        self.logger = logger
        self.events = events
        self.webClient = TiebaWebClient(logger: logger)
        let device = UIDevice.current
        let identity = TiebaProtoIdentity(
            seed: device.identifierForVendor?.uuidString ?? (Bundle.main.bundleIdentifier ?? "cithub-ios"),
            model: device.model,
            osVersion: device.systemVersion,
            screenWidth: Int64(UIScreen.main.nativeBounds.width),
            screenHeight: Int64(UIScreen.main.nativeBounds.height),
            screenScale: Double(UIScreen.main.scale)
        )
        self.protoClient = TiebaProtoClient(logger: logger, identity: identity)
    }

    func currentAccount(completion: @escaping (Result<TiebaAccountDto?, Error>) -> Void) {
        runNative(completion: completion) { [self] in
            let cookie = await cookie()
            guard !cookie.isEmpty else { return nil }
            do { return tiebaAccountDto(try await refreshProfile(cookie: cookie)) }
            catch {
                await logger.append(source: "tieba", message: "Stored login rejected: \(error.localizedDescription)")
                await clearAccount()
                return nil
            }
        }
    }

    func completeWebLogin(cookieHeader: String, completion: @escaping (Result<TiebaAccountDto, Error>) -> Void) {
        runNative(completion: completion) { [self] in
            var raw = cookieHeader
            if raw.isEmpty {
                let cookies = await allWebCookies().filter { cookie in
                    cookie.domain.contains("baidu.com") || cookie.domain.contains("tiebac.baidu.com")
                }
                var seen = Set<String>()
                raw = cookies.filter { seen.insert($0.name).inserted }
                    .map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            }
            guard CookieHeaderStore.parse(raw).keys.contains(where: {
                $0.caseInsensitiveCompare("BDUSS") == .orderedSame
            }) else {
                throw CithubNativeError.loginRequired("百度账号登录尚未完成")
            }
            await store.put("tieba.cookie", raw)
            let account = try await refreshProfile(cookie: raw)
            await logger.append(source: "tieba", message: "Web login completed; encrypted Cookie stored")
            await events.emit(source: "tieba", stage: "signedIn", message: "贴吧登录成功")
            return tiebaAccountDto(account)
        }
    }

    func refreshAccount(completion: @escaping (Result<TiebaAccountDto, Error>) -> Void) {
        runNative(completion: completion) { [self] in
            tiebaAccountDto(try await refreshProfile(cookie: try await requireCookie()))
        }
    }

    func logout(completion: @escaping (Result<Bool, Error>) -> Void) {
        runNative(completion: completion) { [self] in
            let old = await cookie()
            await clearAccount()
            await deleteCookies(
                names: Set(CookieHeaderStore.parse(old).keys),
                domains: ["baidu.com", "tiebac.baidu.com"]
            )
            await events.emit(source: "tieba", stage: "signedOut", message: "已退出贴吧")
            return true
        }
    }

    func loadForum(
        forumName: String,
        page: Int64,
        sort: String,
        goodOnly: Bool,
        completion: @escaping (Result<ForumPageDto, Error>) -> Void
    ) {
        runNative(completion: completion) { [self] in
            guard !forumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CithubNativeError.invalidInput("请输入吧名")
            }
            let cookie = await cookie()
            let result: CoreForumPage
            do {
                result = try await protoClient.forum(
                    name: forumName, page: page, sort: sort, goodOnly: goodOnly,
                    cookie: cookie, uid: await accountUID()
                )
            } catch {
                await logger.append(
                    source: "tieba",
                    message: "PB forum unavailable; HTTPS fallback: \(error.localizedDescription)"
                )
                result = try await webClient.forum(
                    name: forumName, page: page, sort: sort, goodOnly: goodOnly, cookie: cookie
                )
            }
            if let id = Int64(result.forum.id) { forumNames[id] = forumName }
            return forumPageDto(result)
        }
    }

    func search(
        forumName: String,
        keyword: String,
        page: Int64,
        completion: @escaping (Result<ForumPageDto, Error>) -> Void
    ) {
        runNative(completion: completion) { [self] in
            guard !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CithubNativeError.invalidInput("请输入搜索关键词")
            }
            return forumPageDto(try await webClient.search(
                name: forumName, keyword: keyword, page: page, cookie: await cookie()
            ))
        }
    }

    func loadThread(
        threadId: String,
        forumId: Int64,
        forumName: String,
        page: Int64,
        sort: String,
        onlyOriginalPoster: Bool,
        completion: @escaping (Result<ThreadPageDto, Error>) -> Void
    ) {
        runNative(completion: completion) { [self] in
            guard Int64(threadId).map({ $0 > 0 }) == true else {
                throw CithubNativeError.invalidInput("无效的帖子 ID")
            }
            threadForums[threadId] = (forumId, forumName)
            let cookie = await cookie()
            let result: CoreThreadPage
            do {
                result = try await protoClient.thread(
                    threadID: threadId, forumID: forumId, forumName: forumName,
                    page: page, sort: sort, onlyOriginalPoster: onlyOriginalPoster,
                    cookie: cookie, uid: await accountUID()
                )
            } catch {
                await logger.append(
                    source: "tieba",
                    message: "PB thread unavailable; HTTPS fallback: \(error.localizedDescription)"
                )
                result = try await webClient.thread(
                    threadID: threadId, forumID: forumId, forumName: forumName,
                    page: page, sort: sort, onlyOriginalPoster: onlyOriginalPoster,
                    cookie: cookie
                )
            }
            return threadPageDto(result)
        }
    }

    func loadFloorReplies(
        threadId: String,
        postId: String,
        page: Int64,
        completion: @escaping (Result<FloorReplyPageDto, Error>) -> Void
    ) {
        runNative(completion: completion) { [self] in
            guard Int64(threadId).map({ $0 > 0 }) == true else {
                throw CithubNativeError.invalidInput("无效的帖子 ID")
            }
            guard Int64(postId).map({ $0 > 0 }) == true else {
                throw CithubNativeError.invalidInput("无效的楼层 ID")
            }
            let forum = threadForums[threadId] ?? (0, "")
            let cookie = await cookie()
            let result: CoreFloorReplyPage
            do {
                result = try await protoClient.floorReplies(
                    threadID: threadId, postID: postId, page: page,
                    forumID: forum.0, forumName: forum.1,
                    cookie: cookie, uid: await accountUID()
                )
            } catch {
                await logger.append(
                    source: "tieba",
                    message: "PB floor unavailable; HTTPS fallback: \(error.localizedDescription)"
                )
                result = try await webClient.floorReplies(
                    threadID: threadId, postID: postId, page: page, cookie: cookie
                )
            }
            return floorReplyPageDto(result)
        }
    }

    func loadUserProfile(uid: Int64, completion: @escaping (Result<TiebaUserProfileDto, Error>) -> Void) {
        runNative(completion: completion) { [self] in
            guard uid > 0 else { throw CithubNativeError.invalidInput("无效的贴吧用户 ID") }
            let cookie = await cookie()
            do {
                return tiebaUserProfileDto(try await protoClient.userProfile(
                    uid: uid, cookie: cookie, accountUID: await accountUID()
                ))
            } catch {
                await logger.append(
                    source: "tieba",
                    message: "PB profile unavailable; HTTPS fallback: \(error.localizedDescription)"
                )
                return tiebaUserProfileDto(try await webClient.userProfile(uid: uid, cookie: cookie))
            }
        }
    }

    func loadForumRule(forumId: Int64, completion: @escaping (Result<String, Error>) -> Void) {
        runNative(completion: completion) { [self] in
            guard forumId > 0 else { throw CithubNativeError.invalidInput("无效的贴吧 ID") }
            guard let name = forumNames[forumId] else {
                throw CithubNativeError.invalidInput("请先打开该贴吧")
            }
            let cookie = await cookie()
            do {
                return try await protoClient.forumRule(
                    forumID: forumId, cookie: cookie, uid: await accountUID()
                )
            } catch {
                await logger.append(
                    source: "tieba",
                    message: "PB forum-rule unavailable; HTTPS fallback: \(error.localizedDescription)"
                )
                return try await webClient.forumRule(name: name, cookie: cookie)
            }
        }
    }

    func sign(
        forumId: String,
        forumName: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        runNative(completion: completion) { [self] in
            let result = try await webClient.sign(
                name: forumName, tbs: try await requireTBS(), cookie: try await requireCookie()
            )
            await events.emit(source: "tieba", stage: "signSuccess", message: result)
            return result
        }
    }

    func followForum(
        forumId: String,
        forumName: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        runNative(completion: completion) { [self] in
            try await webClient.follow(
                forumID: forumId, name: forumName,
                tbs: try await requireTBS(), cookie: try await requireCookie()
            )
        }
    }

    func resolveOriginalImage(
        request: TiebaImageRequestDto,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        runNative(completion: completion) { [self] in
            guard let url = URL(string: request.url), url.scheme == "https" else {
                throw CithubNativeError.invalidInput("只允许 HTTPS 图片")
            }
            do {
                return try await protoClient.resolveOriginalImage(
                    CoreTiebaImageRequest(
                        url: request.url, threadID: request.threadId, postID: request.postId,
                        forumID: request.forumId, forumName: request.forumName,
                        imageIndex: request.imageIndex,
                        seeOriginalPosterOnly: request.seeOriginalPosterOnly
                    ),
                    cookie: await cookie(),
                    uid: await accountUID()
                )
            } catch {
                await logger.append(
                    source: "tieba",
                    message: "PB original-image unavailable; preview fallback: \(error.localizedDescription)"
                )
                return request.url
            }
        }
    }

    func launchOfficialReply(
        threadId: Int64,
        postId: Int64?,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        runNative(completion: completion) {
            var components = URLComponents(string: "com.baidu.tieba://unidispatch/pb")!
            var items = [
                URLQueryItem(name: "obj_locate", value: postId == nil ? "pb_reply" : "comment_lzl_cut_guide"),
                URLQueryItem(name: "obj_source", value: "wise"),
                URLQueryItem(name: "obj_name", value: "index"),
                URLQueryItem(name: "fr", value: "bpush"),
                URLQueryItem(name: "tid", value: String(threadId)),
            ]
            if let postId {
                items.append(URLQueryItem(name: "hightlight_anchor_pid", value: String(postId)))
                items.append(URLQueryItem(name: "is_anchor_to_comment", value: "1"))
            }
            components.queryItems = items
            guard let url = components.url else { return false }
            return await withCheckedContinuation { continuation in
                UIApplication.shared.open(url, options: [:]) { continuation.resume(returning: $0) }
            }
        }
    }

    private func refreshProfile(cookie: String) async throws -> CoreTiebaAccount {
        let (account, tbs) = try await webClient.profile(cookie: cookie)
        await store.put("tieba.uid", String(account.uid))
        if !tbs.isEmpty { await store.put("tieba.tbs", tbs) }
        return account
    }

    private func cookie() async -> String { await store.get("tieba.cookie") ?? "" }

    private func requireCookie() async throws -> String {
        let value = await cookie()
        guard !value.isEmpty else { throw CithubNativeError.loginRequired("请先登录贴吧") }
        return value
    }

    private func requireTBS() async throws -> String {
        let value = await store.get("tieba.tbs") ?? ""
        guard !value.isEmpty else { throw CithubNativeError.loginRequired("贴吧登录凭据已过期，请重新登录") }
        return value
    }

    private func accountUID() async -> Int64 {
        Int64(await store.get("tieba.uid") ?? "0") ?? 0
    }

    private func clearAccount() async {
        await store.remove("tieba.cookie")
        await store.remove("tieba.token")
        await store.remove("tieba.tbs")
        await store.remove("tieba.uid")
    }
}
