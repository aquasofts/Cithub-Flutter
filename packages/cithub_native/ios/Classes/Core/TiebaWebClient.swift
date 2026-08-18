import Foundation

public actor TiebaWebClient {
    private let logger: any RuntimeLogger
    private let transport: any HTTPTransport

    public init(logger: any RuntimeLogger, transport: any HTTPTransport = URLSessionTransport()) {
        self.logger = logger
        self.transport = transport
    }

    public func profile(cookie: String) async throws -> (CoreTiebaAccount, String) {
        let response = try await getJSON("https://tieba.baidu.com/mo/q/newmoindex?need_user=1", cookie: cookie)
        guard response.int64("no", default: -1) == 0 else {
            throw CithubNativeError.loginRequired(response.string("error", default: "贴吧登录状态无效"))
        }
        guard let data = response.object("data"), data.bool("is_login") else {
            throw CithubNativeError.loginRequired("贴吧登录状态无效")
        }
        return (
            CoreTiebaAccount(
                uid: data.int64("uid"), username: data.string("name"),
                nickname: data.string("name_show", default: data.string("name")),
                avatarURL: normalizeWebURL(data.string("portrait_url")), intro: data.string("intro"),
                fans: data.string("fans_num", default: "0"), posts: data.string("post_num", default: "0"),
                concerned: data.string("concern_num", default: "0")
            ),
            data.string("itb_tbs", default: data.string("tbs"))
        )
    }

    public func forum(
        name: String, page: Int64, sort: String, goodOnly: Bool, cookie: String
    ) async throws -> CoreForumPage {
        let pn = (max(1, page) - 1) * 50
        var url = "https://tieba.baidu.com/f?kw=\(FormEncoding.percent(name))&ie=utf-8&pn=\(pn)"
        if goodOnly { url += "&tab=good" }
        if sort == "post" { url += "&st=new" }
        let html = try await get(url, cookie: cookie)
        let inputs = HTMLParser.voidElements("input", in: html)
        let forumID = inputs.first(where: { $0.attribute("id") == "forum_id" })?.attribute("value")
            ?? firstAttribute("data-fid", in: html) ?? "0"
        let member = firstText(className: "card_menNum", in: html)
        let posts = firstText(className: "card_infoNum", in: html)
        let candidates = HTMLParser.elements("li", in: html) + HTMLParser.elements("div", in: html)
        let threadNodes = candidates.filter { hasClass($0, "j_thread_list") }
        var threads: [CoreForumThread] = []
        for node in threadNodes {
            let links = HTMLParser.elements("a", in: node.innerHTML)
            guard let titleLink = links.first(where: {
                hasClass($0, "j_th_tit") || $0.attribute("href").contains("/p/")
            }) else { continue }
            let href = titleLink.attribute("href")
            let id = HTMLParser.firstCapture(#"/p/(\d+)"#, in: href) ?? ""
            guard !id.isEmpty else { continue }
            let object = dataObject(node)
            let author = object.string("author_name")
            let excerpt = firstText(className: "threadlist_abs", in: node.innerHTML).nilIfEmpty
                ?? firstText(className: "threadlist_text", in: node.innerHTML)
            let images = HTMLParser.voidElements("img", in: node.innerHTML)
                .filter { hasClass($0, "threadlist_pic") }
                .map { normalizeWebURL($0.attribute("src")) }.filter { !$0.isEmpty }
            threads.append(CoreForumThread(
                id: id, title: titleLink.text.nilIfEmpty ?? "无标题", excerpt: excerpt,
                excerptContent: excerpt.isEmpty ? [] : [.text(excerpt)], authorName: author,
                authorNickname: author, authorID: object.int64("author_id"), authorPortrait: "",
                replyCount: object.string("reply_num"), viewCount: "", lastReplyTime: "",
                isTop: hasClass(node, "thread_top_list_folder"), isGood: node.innerHTML.contains("icon-good"),
                imageURLs: images, forumID: Int64(forumID) ?? 0, forumName: name,
                authorModeratorRole: moderatorRole(object)
            ))
        }
        guard !threads.isEmpty else {
            throw CithubNativeError.invalidResponse("贴吧页面未返回帖子，可能需要登录或页面结构已更新")
        }
        let hasMore = HTMLParser.elements("a", in: html).contains {
            hasClass($0, "next") || ($0.attribute("href").contains("pn=") && $0.text.contains("下一页"))
        }
        return CoreForumPage(
            forum: CoreForumSummary(
                id: forumID, name: name, avatarURL: "", memberCount: member, threadCount: posts,
                forumRuleTitle: "", isFollowed: html.contains("cancel_focus") || html.contains("islike_focus"),
                signed: false, signedDays: 0
            ),
            threads: threads, page: page, hasMore: hasMore
        )
    }

    public func search(name: String, keyword: String, page: Int64, cookie: String) async throws -> CoreForumPage {
        let referer = FormEncoding.percent("https://tieba.baidu.com/f?kw=\(name)")
        let url = "https://tieba.baidu.com/mo/q/search/thread?word=\(FormEncoding.percent(keyword))&pn=\(page)&st=1&tt=1&rn=30&fname=\(FormEncoding.percent(name))&ct=2&cv=12.80.1.0&referer=\(referer)"
        let envelope = try await getJSON(url, cookie: cookie)
        guard envelope.int64("no", default: -1) == 0 else {
            throw CithubNativeError.requestFailed(envelope.string("error", default: "贴吧搜索失败"))
        }
        guard let data = envelope.object("data") else {
            throw CithubNativeError.invalidResponse("贴吧搜索未返回数据")
        }
        let threads = (data.array("post_list") ?? []).compactMap { raw -> CoreForumThread? in
            guard let post = raw as? [String: Any] else { return nil }
            let user = post.object("user") ?? [:]
            let info = post.object("forum_info") ?? [:]
            let excerpt = HTMLParser.text(post.string("content"))
            return CoreForumThread(
                id: post.string("tid"), title: post.string("title", default: "无标题"), excerpt: excerpt,
                excerptContent: excerpt.isEmpty ? [] : [.text(excerpt)], authorName: user.string("user_name"),
                authorNickname: user.string("show_nickname", default: user.string("user_name")),
                authorID: user.int64("user_id"), authorPortrait: webPortrait(user.string("portrait")),
                replyCount: post.string("post_num"), viewCount: "", lastReplyTime: formatWebEpoch(post.int64("time")),
                isTop: false, isGood: false, imageURLs: [], forumID: post.int64("forum_id"),
                forumName: post.string("forum_name", default: info.string("forum_name", default: name)),
                authorModeratorRole: .none
            )
        }
        return CoreForumPage(
            forum: CoreForumSummary(
                id: "0", name: name, avatarURL: "", memberCount: "", threadCount: "",
                forumRuleTitle: "", isFollowed: false, signed: false, signedDays: 0
            ),
            threads: threads, page: page, hasMore: data.int64("has_more") == 1
        )
    }

    public func thread(
        threadID: String,
        forumID: Int64,
        forumName: String,
        page: Int64,
        sort: String,
        onlyOriginalPoster: Bool,
        cookie: String
    ) async throws -> CoreThreadPage {
        var url = "https://tieba.baidu.com/p/\(threadID)?pn=\(page)"
        if onlyOriginalPoster { url += "&see_lz=1" }
        if sort == "desc" { url += "&sort=1" }
        let html = try await get(url, cookie: cookie)
        let titleNode = HTMLParser.elements("h1", in: html).first(where: { hasClass($0, "core_title_txt") })
        let title = titleNode?.attribute("title").nilIfEmpty ?? titleNode?.text.nilIfEmpty ?? "帖子"
        let floors = HTMLParser.elements("div", in: html).filter { hasClass($0, "l_post") }
            .compactMap(parseFloor)
        guard !floors.isEmpty else {
            throw CithubNativeError.invalidResponse("帖子页面未返回楼层，可能已删除或页面结构已更新")
        }
        let pageNumbers = HTMLParser.elements("a", in: html).compactMap {
            HTMLParser.firstCapture(#"[?&]pn=(\d+)"#, in: $0.attribute("href")).flatMap(Int64.init)
        }
        return CoreThreadPage(
            title: title, body: floors.first, floors: Array(floors.dropFirst()), page: page,
            totalPages: max(page, pageNumbers.max() ?? page), replyCount: max(0, Int64(floors.count - 1))
        )
    }

    public func floorReplies(
        threadID: String, postID: String, page: Int64, cookie: String
    ) async throws -> CoreFloorReplyPage {
        let html = try await get(
            "https://tieba.baidu.com/p/comment?tid=\(threadID)&pid=\(postID)&pn=\(page)", cookie: cookie
        )
        let nodes = HTMLParser.elements("li", in: html).filter { hasClass($0, "lzl_single_post") }
        let replies = nodes.compactMap { node -> CoreFloorReply? in
            let object = dataObject(node)
            let id = object.string("spid", default: object.string("post_id"))
            guard !id.isEmpty else { return nil }
            let author = object.string("user_name")
            let content = firstText(className: "lzl_content_main", in: node.innerHTML)
            return CoreFloorReply(
                id: id, authorID: object.int64("user_id"), authorName: author, authorNickname: author,
                authorPortrait: webPortrait(object.string("portrait")), content: [.text(content)],
                time: firstText(className: "lzl_time", in: node.innerHTML),
                authorLevel: object.int64("level_id"), authorTitle: object.string("level_name"),
                authorIP: object.string("ip_address", default: object.string("ip")),
                authorModeratorRole: moderatorRole(object)
            )
        }
        let pages = HTMLParser.elements("a", in: html).compactMap {
            HTMLParser.firstCapture(#"[?&]pn=(\d+)"#, in: $0.attribute("href")).flatMap(Int64.init)
        }
        return CoreFloorReplyPage(
            replies: replies, page: page, totalPages: max(page, pages.max() ?? page),
            totalReplies: Int64(replies.count)
        )
    }

    public func userProfile(uid: Int64, cookie: String) async throws -> CoreTiebaUserProfile {
        let html = try await get("https://tieba.baidu.com/home/main?id=\(uid)&fr=pb", cookie: cookie)
        let name = firstText(className: "userinfo_username", in: html).nilIfEmpty ?? "贴吧用户 \(uid)"
        let intro = firstText(className: "userinfo_userdata", in: html)
        return CoreTiebaUserProfile(
            uid: uid, username: name, nickname: name, avatarURL: "", intro: intro,
            fans: 0, concerned: 0, posts: 0, threads: [], replies: []
        )
    }

    public func sign(name: String, tbs: String, cookie: String) async throws -> String {
        guard !tbs.isEmpty else { throw CithubNativeError.loginRequired("贴吧签到凭据无效，请重新登录") }
        let result = try await postJSON(
            "https://tieba.baidu.com/sign/add",
            form: ["ie": "utf-8", "kw": name, "tbs": tbs], cookie: cookie,
            referer: "https://tieba.baidu.com/f?kw=\(FormEncoding.percent(name))&ie=utf-8"
        )
        let code = result.int64("no", default: -1)
        let message = result.string("error")
        let days = result.object("data")?.object("uinfo")?.int64("cont_sign_num")
        if code == 0 { return days.map { "已签\($0)天" } ?? "签到成功" }
        if code == 1101 || message.contains("已签") { return days.map { "已签\($0)天" } ?? "今日已经签到" }
        throw CithubNativeError.requestFailed(message.nilIfEmpty ?? "贴吧签到失败（错误码 \(code)）")
    }

    public func follow(forumID: String, name: String, tbs: String, cookie: String) async throws -> String {
        guard !tbs.isEmpty else { throw CithubNativeError.loginRequired("贴吧关注凭据无效，请重新登录") }
        let result = try await postJSON(
            "https://tieba.baidu.com/mo/q/favolike",
            form: ["cmd": "add", "fid": forumID, "kw": name, "tbs": tbs], cookie: cookie,
            referer: "https://tieba.baidu.com/f?kw=\(FormEncoding.percent(name))&ie=utf-8"
        )
        let code = result.int64("no", default: result.int64("error_code", default: -1))
        guard code == 0 || code == 1101 else {
            throw CithubNativeError.requestFailed(
                result.string("error", default: result.string("error_msg", default: "贴吧关注失败（错误码 \(code)）"))
            )
        }
        return "已关注 \(name)"
    }

    public func forumRule(name: String, cookie: String) async throws -> String {
        let html = try await get(
            "https://tieba.baidu.com/bawu2/platform/listBawuTeamInfo?word=\(FormEncoding.percent(name))&ie=utf-8",
            cookie: cookie
        )
        let candidates = ["rules", "forum_rule", "bawu_single_type"]
        let text = candidates.map { firstText(className: $0, in: html) }.filter { !$0.isEmpty }.joined(separator: "\n")
        return text.nilIfEmpty ?? "该吧未提供可读取的公开吧规。"
    }

    private func getJSON(_ url: String, cookie: String) async throws -> [String: Any] {
        try jsonObject(Data((try await get(url, cookie: cookie)).utf8))
    }

    private func get(_ value: String, cookie: String) async throws -> String {
        guard let url = URL(string: value) else { throw CithubNativeError.invalidInput("贴吧请求地址无效") }
        let response = try await perform(HTTPCall(method: "GET", url: url, headers: headers(cookie: cookie)))
        return response.text
    }

    private func postJSON(
        _ value: String, form: [String: String], cookie: String, referer: String
    ) async throws -> [String: Any] {
        guard let url = URL(string: value) else { throw CithubNativeError.invalidInput("贴吧请求地址无效") }
        var requestHeaders = headers(cookie: cookie)
        requestHeaders["Content-Type"] = "application/x-www-form-urlencoded"
        requestHeaders["Referer"] = referer
        let response = try await perform(HTTPCall(
            method: "POST", url: url, headers: requestHeaders, body: FormEncoding.encode(form)
        ))
        return try jsonObject(response.data)
    }

    private func perform(_ call: HTTPCall) async throws -> HTTPResponse {
        let response = try await transport.perform(call)
        await logger.append(source: "tieba", message: "\(call.method) \(call.url.path) -> HTTP \(response.status)")
        guard (200...299).contains(response.status) else {
            throw CithubNativeError.requestFailed("贴吧请求失败（HTTP \(response.status)）")
        }
        return response
    }

    private func headers(cookie: String) -> [String: String] {
        var headers = [
            "Accept": "application/json,text/html,*/*",
            "Accept-Language": "zh-CN,zh;q=0.9",
            "User-Agent": TiebaProtoClient.webUserAgent,
        ]
        if !cookie.isEmpty { headers["Cookie"] = cookie }
        return headers
    }

    private func parseFloor(_ node: HTMLNode) -> CoreThreadFloor? {
        let object = dataObject(node)
        let author = object.object("author") ?? [:]
        let content = object.object("content") ?? [:]
        let postID = content.string("post_id").nilIfEmpty ?? node.attribute("data-pid")
        guard !postID.isEmpty else { return nil }
        let contentNode = HTMLParser.elements("div", in: node.innerHTML).first(where: {
            hasClass($0, "d_post_content")
        })
        let text = contentNode?.text ?? ""
        return CoreThreadFloor(
            postID: postID, floor: content.int64("post_no"), authorID: author.int64("user_id"),
            authorName: author.string("user_name"),
            authorNickname: author.string("user_nickname", default: author.string("user_name")),
            authorPortrait: webPortrait(author.string("portrait")), authorLevel: author.int64("level_id"),
            authorTitle: author.string("level_name"),
            authorIP: author.string("ip_address", default: author.string("ip")),
            authorModeratorRole: moderatorRole(author), time: content.string("date"),
            content: [.text(text)], replies: [], replyCount: content.int64("comment_num"),
            isOriginalPoster: content.int64("post_no") == 1
        )
    }

    private func dataObject(_ node: HTMLNode) -> [String: Any] {
        let raw = node.attribute("data-field")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
        return (try? jsonObject(Data(raw.utf8))) ?? [:]
    }

    private func hasClass(_ node: HTMLNode, _ name: String) -> Bool {
        node.attribute("class").split(whereSeparator: \.isWhitespace).contains(Substring(name))
    }

    private func firstText(className: String, in html: String) -> String {
        let tags = ["span", "div", "a", "li", "p"]
        for tag in tags {
            if let node = HTMLParser.elements(tag, in: html).first(where: { hasClass($0, className) }) {
                return node.text
            }
        }
        return ""
    }

    private func firstAttribute(_ name: String, in html: String) -> String? {
        let pattern = #"<[^>]+\s\#(NSRegularExpression.escapedPattern(for: name))\s*=\s*(?:"([^"]+)"|'([^']+)'|([^\s>]+))"#
        let match = HTMLParser.captures(pattern: pattern, in: html, options: [.caseInsensitive]).first
        return match?.dropFirst().first(where: { !$0.isEmpty })
    }

    private func moderatorRole(_ object: [String: Any]) -> CoreTiebaModeratorRole {
        if object.int64("is_manager") == 1 ||
            (object.int64("is_bawu") == 1 && object.string("bawu_type").lowercased() == "manager") {
            return .owner
        }
        return object.int64("is_bawu") == 1 ? .assistant : .none
    }
}

private func normalizeWebURL(_ raw: String) -> String {
    if raw.hasPrefix("//") { return "https:\(raw)" }
    if raw.hasPrefix("http://") { return "https://" + String(raw.dropFirst(7)) }
    return raw.hasPrefix("https://") ? raw : ""
}

private func webPortrait(_ raw: String) -> String {
    raw.isEmpty ? "" : "https://himg.bdimg.com/sys/portrait/item/\(raw).jpg"
}

private func formatWebEpoch(_ seconds: Int64) -> String {
    seconds > 0 ? ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(seconds))) : ""
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
