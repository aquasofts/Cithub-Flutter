import Foundation
import Testing
@testable import CithubNativeCore

@Suite("iOS native protocol regressions")
struct CithubNativeCoreTests {
    @Test("WebVPN merges cookies and sends them on subsequent requests")
    func webVpnSessionCookieRoundTrip() async throws {
        let store = MemorySecretStore()
        let transport = QueueHTTPTransport([
            .json(
                #"{"code":0,"data":{"list":[{"authType":1,"externalId":"local","authOptions":{"staticVerification":1,"useGraphValidateCode":1,"dynamicVerification":[]}}]}}"#,
                headers: ["Set-Cookie": "SESSION=abc; Path=/; HttpOnly; Secure"]
            ),
            .json(#"{"code":0,"data":{"id":"captcha-1","captcha":"data:image/png;base64,AA=="}}"#),
            .json(#"{"code":0,"data":{"username":"20260001","nickname":"昵称","fullName":"测试同学","groups":["学生"],"authType":1,"bindWechat":true,"bindOtp":false,"needTriggerTFA":true}}"#),
        ])
        let client = WebVpnProtocolClient(
            store: store,
            logger: NullRuntimeLogger(),
            baseURL: URL(string: "https://webvpn.test/")!,
            transport: transport
        )

        let configuration = try await client.loadConfiguration()
        let captcha = try await client.loadCaptcha()
        let user = try await client.userInfo()

        #expect(configuration.externalID == "local")
        #expect(configuration.requiresPassword)
        #expect(configuration.requiresCaptcha)
        #expect(captcha.id == "captcha-1")
        #expect(user.username == "20260001")
        #expect(user.requiredAction == .tfa)
        #expect(await store.get("webvpn.session.cookies") == "SESSION=abc")
        let calls = await transport.recordedCalls
        #expect(calls[0].headers["Cookie"] == nil)
        #expect(calls[1].headers["Cookie"] == "SESSION=abc")
        #expect(calls[2].headers["Cookie"] == "SESSION=abc")
    }

    @Test("Academic protocol parses core pages and preserves the WebVPN cookie")
    func academicMockServerFlow() async throws {
        let store = MemorySecretStore(values: ["webvpn.session.cookies": "SESSION=abc"])
        let transport = QueueHTTPTransport([
            .html(#"<select name="kksj"><option value="2025-2026-2" selected>2025-2026 学年第二学期</option></select>"#,
                  headers: ["Set-Cookie": "JSESSIONID=xyz; Path=/jsxsd; Secure"]),
            .html("<table id=\"dataList\"><tr><th>表头</th></tr><tr>" +
                  (1...20).map { index in
                      let value = index == 4 ? "程序设计基础" : "字段\(index)"
                      return "<td>\(value)</td>"
                  }.joined() + "</tr></table>"),
            .html("<table><tr>" + ["1", "移动应用开发", "CS305", "陈老师", "48", "3.0", "选修", "专业选修课"].map { "<td>\($0)</td>" }.joined() + "</tr></table>"),
            .html(#"<table><tr><td>1</td><td>2025-2026-2</td><td>理论课</td><td>期末评价</td><td>2026-06-01</td><td>2026-06-30</td><td><a href="/jsxsd/xspj/courses">进入</a></td></tr></table>"#),
        ])
        let client = AcademicProtocolClient(
            store: store,
            logger: NullRuntimeLogger(),
            baseURL: URL(string: "https://academic.test/jsxsd/")!,
            transport: transport
        )

        let terms = try await client.initialize()
        let grades = try await client.loadGrades(term: "2025-2026-2", bestOnly: false)
        let selected = try await client.loadSelectionResults(term: "2025-2026-2")
        let batches = try await client.loadEvaluationBatches()

        #expect(terms?.only?.value == "2025-2026-2")
        #expect(terms?.only?.selected == true)
        #expect(grades.only?.courseName == "程序设计基础")
        #expect(selected.only?.courseName == "移动应用开发")
        #expect(batches.only?.name == "期末评价")
        #expect(await store.get("webvpn.session.cookies") == "SESSION=abc; JSESSIONID=xyz")
        let calls = await transport.recordedCalls
        #expect(calls[0].headers["Cookie"] == "SESSION=abc")
        #expect(calls.dropFirst().allSatisfy { $0.headers["Cookie"] == "SESSION=abc; JSESSIONID=xyz" })
    }

    @Test("Academic routing matches the four school backends")
    func academicRouting() {
        #expect(AcademicServerRouter.baseURL(for: "teacher").absoluteString.contains("47-147-8080"))
        #expect(AcademicServerRouter.baseURL(for: "2505422544").absoluteString.contains("47-147-8080"))
        #expect(AcademicServerRouter.baseURL(for: "2505422545").absoluteString.contains("47-147-8081"))
        #expect(AcademicServerRouter.baseURL(for: "2505422546").absoluteString.contains("47-148-8080"))
        #expect(AcademicServerRouter.baseURL(for: "2505422547").absoluteString.contains("47-148-8081"))
    }

    @Test("Tieba native forum request is protobuf and maps a pinned response")
    func tiebaNativeForumRoundTrip() async throws {
        let fixture = TiebaFixture.forumResponse(
            forumID: 64554,
            forumName: "长春工程学院",
            threadID: 9988,
            title: "协议回归帖子",
            authorID: 7,
            authorName: "author",
            authorNickname: "作者"
        )
        let transport = QueueHTTPTransport([.protobuf(fixture)])
        let client = TiebaProtoClient(
            logger: NullRuntimeLogger(),
            baseURL: URL(string: "https://tieba.test/")!,
            identity: .testing,
            transport: transport
        )

        let page = try await client.forum(
            name: "长春工程学院",
            page: 1,
            sort: "reply",
            goodOnly: false,
            cookie: "",
            uid: 0
        )

        #expect(page.forum.id == "64554")
        #expect(page.threads.only?.title == "协议回归帖子")
        #expect(page.threads.only?.authorNickname == "作者")
        #expect(page.hasMore)
        let call = try #require(await transport.recordedCalls.only)
        #expect(call.url.path == "/c/f/frs/page")
        #expect(call.url.query == "cmd=301001")
        #expect(call.headers["x_bd_data_type"] == "protobuf")
        #expect(call.headers["forum_name"]?.removingPercentEncoding == "长春工程学院")
        #expect(call.body.range(of: Data("name=\"data\"".utf8)) != nil)
    }

    @Test("Tieba native thread response maps body, floors and reply authors")
    func tiebaNativeThreadRoundTrip() async throws {
        let transport = QueueHTTPTransport([
            .protobuf(TiebaFixture.threadResponse(
                forumID: 64554,
                forumName: "长春工程学院",
                threadID: 9988,
                title: "帖子协议回归",
                originalAuthorID: 11,
                replyAuthorID: 12
            )),
        ])
        let client = TiebaProtoClient(
            logger: NullRuntimeLogger(),
            baseURL: URL(string: "https://tieba.test/")!,
            identity: .testing,
            transport: transport
        )

        let page = try await client.thread(
            threadID: "9988",
            forumID: 64554,
            forumName: "长春工程学院",
            page: 1,
            sort: "asc",
            onlyOriginalPoster: false,
            cookie: "",
            uid: 0
        )

        #expect(page.title == "帖子协议回归")
        #expect(page.body?.postID == "100")
        #expect(page.body?.isOriginalPoster == true)
        #expect(page.floors.only?.postID == "200")
        #expect(page.floors.only?.authorNickname == "回复用户")
        #expect(page.totalPages == 2)
        let call = try #require(await transport.recordedCalls.only)
        #expect(call.url.path == "/c/f/pb/page")
        #expect(call.url.query == "cmd=302001&format=protobuf")
    }

    @Test("Tieba native floor response maps pagination and user list")
    func tiebaNativeFloorRoundTrip() async throws {
        let transport = QueueHTTPTransport([
            .protobuf(TiebaFixture.floorResponse(
                forumID: 64554,
                forumName: "长春工程学院",
                authorID: 12
            )),
        ])
        let client = TiebaProtoClient(
            logger: NullRuntimeLogger(),
            baseURL: URL(string: "https://tieba.test/")!,
            identity: .testing,
            transport: transport
        )

        let page = try await client.floorReplies(
            threadID: "9988",
            postID: "100",
            page: 1,
            forumID: 64554,
            forumName: "长春工程学院",
            cookie: "",
            uid: 0
        )

        #expect(page.replies.only?.id == "101")
        #expect(page.replies.only?.authorNickname == "楼中楼用户")
        #expect(page.totalPages == 3)
        #expect(page.totalReplies == 21)
        let call = try #require(await transport.recordedCalls.only)
        #expect(call.url.path == "/c/f/pb/floor")
        #expect(call.url.query == "cmd=302002&format=protobuf")
    }

    @Test("Tieba native profile combines protobuf user threads and replies")
    func tiebaNativeProfileRoundTrip() async throws {
        let transport = QueueHTTPTransport([
            .protobuf(TiebaFixture.profileResponse(uid: 7, name: "author", nickname: "作者")),
            .protobuf(TiebaFixture.userPostsResponse(uid: 7, isThread: true)),
            .protobuf(TiebaFixture.userPostsResponse(uid: 7, isThread: false)),
        ])
        let client = TiebaProtoClient(
            logger: NullRuntimeLogger(),
            baseURL: URL(string: "https://tieba.test/")!,
            identity: .testing,
            transport: transport
        )

        let profile = try await client.userProfile(uid: 7, cookie: "", accountUID: 0)

        #expect(profile.nickname == "作者")
        #expect(profile.fans == 12)
        #expect(profile.threads.only?.title == "用户主题")
        #expect(profile.replies.only?.excerpt == "用户回复")
        let calls = await transport.recordedCalls
        #expect(calls.map { $0.url.path } == [
            "/c/u/user/profile", "/c/u/feed/userpost", "/c/u/feed/userpost",
        ])
    }

    @Test("Tieba native forum-rule protobuf preserves structured text")
    func tiebaNativeForumRuleRoundTrip() async throws {
        let transport = QueueHTTPTransport([
            .protobuf(TiebaFixture.forumRuleResponse()),
        ])
        let client = TiebaProtoClient(
            logger: NullRuntimeLogger(),
            baseURL: URL(string: "https://tieba.test/")!,
            identity: .testing,
            transport: transport
        )

        let text = try await client.forumRule(forumID: 64554, cookie: "", uid: 0)

        #expect(text.contains("长春工程学院吧规"))
        #expect(text.contains("文明交流"))
        #expect(await transport.recordedCalls.only?.url.path == "/c/f/forum/forumRuleDetail")
    }

    @Test("Tieba mini image resolver signs and validates the original URL")
    func tiebaNativeOriginalImageRoundTrip() async throws {
        let response = #"{"error_code":"0","pic_list":[{"overall_index":"1","img":{"original":{"id":"abc","size":"2048","width":"800","height":"600","format":"2","waterurl":"https://tiebapic.baidu.com/forum/pic/item/abc.jpg?tbpicau=token"}}}]}"#
        let transport = QueueHTTPTransport([.json(response)])
        let client = TiebaProtoClient(
            logger: NullRuntimeLogger(),
            baseURL: URL(string: "https://tieba.test/")!,
            identity: .testing,
            transport: transport
        )

        let url = try await client.resolveOriginalImage(
            CoreTiebaImageRequest(
                url: "https://tiebapic.baidu.com/forum/pic/item/abc.jpg",
                threadID: 9988,
                postID: 100,
                forumID: 64554,
                forumName: "长春工程学院",
                imageIndex: 1,
                seeOriginalPosterOnly: false
            ),
            cookie: "",
            uid: 0
        )

        #expect(url.contains("tbpicau=token"))
        let call = try #require(await transport.recordedCalls.only)
        #expect(call.url.path == "/c/f/pb/picpage")
        #expect(String(decoding: call.body, as: UTF8.self).contains("sign="))
    }

    @Test("Tieba mini-image signature matches TiebaLite vector")
    func tiebaSignatureVector() {
        #expect(miniTiebaSign(["b": "2", "a": "1"]) == "42961b9881c2d7cb297e9498f9767789")
    }
}

private extension Array {
    var only: Element? { count == 1 ? self[0] : nil }
}
