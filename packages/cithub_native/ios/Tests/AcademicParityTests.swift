import Foundation
import Testing
@testable import CithubNativeCore

@Suite("Academic feature parity")
struct AcademicParityTests {
    @Test("Intermediate redirects retain the session cookie")
    func redirectCookie() async throws {
        let store = MemorySecretStore()
        let transport = QueueHTTPTransport([
            .html("", status: 302, headers: ["Location": "/jsxsd/kscj/terms", "Set-Cookie": "JSESSIONID=redirect; Path=/jsxsd"]),
            .html("<select name='kksj'><option value='2026-1'>学期</option></select>"),
        ])
        let client = AcademicProtocolClient(store: store, logger: NullRuntimeLogger(), baseURL: URL(string: "https://academic.test/jsxsd/")!, transport: transport)
        #expect(try await client.initialize()?.first?.value == "2026-1")
        #expect(await transport.recordedCalls.last?.headers["Cookie"] == "JSESSIONID=redirect")
    }

    @Test("Terms selected by id and student home pages are recognized")
    func pageVariants() async throws {
        let client = AcademicProtocolClient(store: MemorySecretStore(), logger: NullRuntimeLogger(), baseURL: URL(string: "https://academic.test/jsxsd/")!, transport: QueueHTTPTransport([
            .html("<select id='kksj'><option value='2026-1'>学期</option></select>"),
            .html("<div>学生个人中心</div><a href='/jsxsd/framework/xsMain.jsp'>学生主页</a>"),
            .html("<title>WebVPN</title><div id='app'></div><script src='/assets/index.js'></script>"),
        ]))
        #expect(try await client.initialize()?.first?.value == "2026-1")
        #expect(try await client.initialize()?.isEmpty == true)
        #expect(try await client.initialize() == nil)
    }

    @Test("Browser login rejoins the native academic session")
    func browserLoginImport() async throws {
        let store = MemorySecretStore(values: ["webvpn.session.cookies": "SESSION=vpn; JSESSIONID=old"])
        let transport = QueueHTTPTransport([.html("<select name='kksj'><option value='2026-1'>学期</option></select>")])
        let client = AcademicProtocolClient(store: store, logger: NullRuntimeLogger(), baseURL: URL(string: "https://academic.test/jsxsd/")!, transport: transport)
        await client.importBrowserSession("browser")
        #expect(try await client.initialize()?.first?.value == "2026-1")
        #expect(await transport.recordedCalls.first?.headers["Cookie"] == "SESSION=vpn; JSESSIONID=browser")
    }

    @Test("Weekly timetable retains courses on every day")
    func weeklyTimetable() async throws {
        let cells = (1...7).map { day in
            "<td><div class='kbcontent1'>课程\(day)<br><font title='周次(节次)'>1-16周[01-02节]</font><font title='老师'>老师</font><font title='教室'>A101</font></div></td>"
        }.joined()
        let transport = QueueHTTPTransport([
            .html("<select name='xnxq01id'><option value='2026-1' selected>学期</option></select><table id='kbtable'><tr><th>周</th></tr><tr><td>08:00-09:35</td>\(cells)</tr></table>"),
            .html("第 2 周/20 周"),
        ])
        let client = AcademicProtocolClient(store: MemorySecretStore(), logger: NullRuntimeLogger(), baseURL: URL(string: "https://academic.test/jsxsd/")!, transport: transport)
        let timetable = try await client.loadTimetable(term: nil)
        #expect(timetable.courses.count == 7)
        #expect(Set(timetable.courses.map(\.dayOfWeek)) == Set(1...7))
    }

    @Test("Evaluation preserves repeated question fields and rejects server errors")
    func evaluationFields() async throws {
        let transport = QueueHTTPTransport([
            .html("<form action='/jsxsd/xspj/xspj_save.do'><input type='hidden' name='pj06xh' value='q1'><input type='hidden' name='pj06xh' value='q2'><table><tr><td>问题1<input name='pj06xh' value='q1'></td><td><input type='radio' name='pj0601id_q1' value='a'>好</td></tr><tr><td>问题2<input name='pj06xh' value='q2'></td><td><input type='radio' name='pj0601id_q2' value='b'>好</td></tr></table><button onclick='saveData()'>保存</button></form>"),
            .html("<script>alert('保存失败：评价已关闭')</script>"),
        ])
        let client = AcademicProtocolClient(store: MemorySecretStore(), logger: NullRuntimeLogger(), baseURL: URL(string: "https://academic.test/jsxsd/")!, transport: transport)
        let form = try await client.loadEvaluationForm(path: "xspj/form")
        var rejected = false
        do { _ = try await client.saveEvaluation(form: form, answers: [.init(questionID: "q1", optionID: "a"), .init(questionID: "q2", optionID: "b")], suggestion: "", submit: false) }
        catch { rejected = true }
        let body = String(decoding: await transport.recordedCalls.last!.body, as: UTF8.self)
        #expect(body.contains("pj06xh=q1"))
        #expect(body.contains("pj06xh=q2"))
        #expect(rejected)
    }
}
