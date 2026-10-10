package com.aquasofts.cithub_flutter

import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import java.time.LocalDate

@RunWith(RobolectricTestRunner::class)
class ProtocolMockServerTest {
    private lateinit var server: MockWebServer
    private lateinit var store: MemorySecretStore
    private lateinit var logs: RuntimeLogStore

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        store = MemorySecretStore()
        logs = RuntimeLogStore(RuntimeEnvironment.getApplication())
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun webVpnParsesConfigurationCaptchaUserAndPersistsSessionCookie() {
        server.enqueue(json("""{"code":0,"data":{"list":[{"authType":1,"externalId":"local","authOptions":{"staticVerification":1,"useGraphValidateCode":1,"dynamicVerification":[]}}]}}""")
            .setHeader("Set-Cookie", "SESSION=abc; Path=/; HttpOnly; Secure"))
        server.enqueue(json("""{"code":0,"data":{"id":"captcha-1","captcha":"data:image/png;base64,AA=="}}"""))
        server.enqueue(json("""{"code":0,"data":{"username":"20260001","nickname":"昵称","fullName":"测试同学","groups":["学生"],"authType":1,"bindWechat":true,"bindOtp":false,"needTriggerTFA":true}}"""))
        server.enqueue(json("""{"code":0,"data":{"list":[{"name":"业务系统","sites":[{"name":"教务系统师生端","url":"https://http-10-198-47-148-8080.webvpn.ccit.edu.cn/jsxsd"}]}]}}"""))
        val client = WebVpnProtocolClient(store, logs, server.url("/").toString())

        val configuration = client.loadConfiguration()
        val captcha = client.loadCaptcha()
        val user = client.userInfo()
        val academicBaseUrl = client.refreshAcademicBaseUrl()

        assertEquals("local", configuration.externalId)
        assertTrue(configuration.requiresPassword)
        assertTrue(configuration.requiresCaptcha)
        assertEquals("captcha-1", captcha.id)
        assertEquals("20260001", user.dto.username)
        assertEquals("https://http-10-198-47-148-8080.webvpn.ccit.edu.cn/jsxsd/", academicBaseUrl)
        assertEquals(academicBaseUrl, store.get(AcademicServerRouter.STORE_KEY))
        assertEquals("SESSION=abc", client.cookies())
        assertEquals("SESSION=abc", store.get("webvpn.session.cookies"))
        assertNull(server.takeRequest().getHeader("Cookie"))
        repeat(3) { assertEquals("SESSION=abc", server.takeRequest().getHeader("Cookie")) }
    }

    @Test
    fun academicParsesTermsGradesSelectionAndEvaluationBatches() {
        server.enqueue(html("""
            <select name="kksj"><option value="2025-2026-2" selected>2025-2026 学年第二学期</option></select>
        """).setHeader("Set-Cookie", "JSESSIONID=xyz; Path=/jsxsd; Secure"))
        server.enqueue(html("""
            <table id="dataList"><tr><th>表头</th></tr><tr>
              ${cells((1..20).map { index -> if (index == 4) "程序设计基础" else "字段$index" })}
            </tr></table>
        """))
        server.enqueue(html("""<table><tr>${cells(listOf("1", "移动应用开发", "CS305", "陈老师", "48", "3.0", "选修", "专业选修课"))}</tr></table>"""))
        server.enqueue(html("""<table><tr><td>1</td><td>2025-2026-2</td><td>理论课</td><td>期末评价</td><td>2026-06-01</td><td>2026-06-30</td><td><a href="/jsxsd/xspj/courses">进入</a></td></tr></table>"""))
        val client = AcademicProtocolClient(store, logs, server.url("/jsxsd/").toString())

        val terms = client.initialize()
        val grades = client.loadGrades("2025-2026-2", false)
        val selected = client.loadSelectionResults("2025-2026-2")
        val batches = client.loadEvaluationBatches()

        assertEquals("2025-2026-2", terms?.single()?.value)
        assertTrue(terms?.single()?.selected == true)
        assertEquals("程序设计基础", grades.single().courseName)
        assertEquals("移动应用开发", selected.single().courseName)
        assertEquals("期末评价", batches.single().name)
        assertEquals("JSESSIONID=xyz", store.get("webvpn.session.cookies"))
        assertNull(server.takeRequest().getHeader("Cookie"))
        repeat(3) { assertEquals("JSESSIONID=xyz", server.takeRequest().getHeader("Cookie")) }
    }

    @Test
    fun academicRecognizesExpiredSessionAndRejectsExternalWebPage() {
        server.enqueue(html("""<form action="LoginToXk"><input name="userAccount"><input name="RANDOMCODE"></form>"""))
        server.enqueue(html("""<div class="browser-compatibility">WebVPN</div><script src="/assets/index.js"></script>"""))
        val client = AcademicProtocolClient(store, logs, server.url("/jsxsd/").toString())

        assertNull(client.initialize())
        assertNull(client.initialize())
        assertFalse(runCatching { client.webPageUrl("https://evil.example/") }.isSuccess)
        assertFalse(runCatching { client.webPageUrl("../admin") }.isSuccess)
    }

    @Test
    fun academicUsesOnlyTheServerAdvertisedByWebVpn() {
        val expected = "https://http-10-198-47-148-8080.webvpn.ccit.edu.cn/jsxsd/"
        assertEquals(expected, AcademicServerRouter.baseUrl(store))
        assertEquals(expected, AcademicServerRouter.remember(store, expected.removeSuffix("/")))
        assertEquals(expected, AcademicServerRouter.baseUrl(store))
        assertNull(AcademicServerRouter.remember(store, "https://evil.example/jsxsd"))
        assertEquals(expected, AcademicServerRouter.baseUrl(store))
    }

    @Test
    fun academicUsesHomeDateWeekAndVisibleKbcontent1ForTodaysTimetable() {
        val weekday = "一二三四五六日"[LocalDate.now().dayOfWeek.value - 1]
        server.enqueue(html("""
            <select name="xnxq01id"><option value="2026-2027-1" selected>2026-2027 学年第一学期</option></select>
            <select name="kbjcmsid"><option value="scheme-1" selected>学生课表</option></select>
            <table id="kbtable"><tr><th>周/节次</th></tr><tr><td>第一大节 (01,02小节) 08:00-09:35</td>
              <td><div class="kbcontent1">全量课表课程<br/><font title="周次(节次)">1-16周[01-02节]</font><br/><font title="老师">张老师</font><br/><font title="教室">A101</font></div></td>
            </tr></table>
        """))
        server.enqueue(html("""
            <div>第 2 周/20 周</div>
            <table class="kb_table"><thead><tr><th>周/节次</th><th>星期$weekday</th></tr></thead><tbody><tr>
              <td>第一大节 (01,02小节) 08:00-09:35</td>
              <td><div class="kbcontent1">首页课程<br/><font title="周次(节次)">1-16周[01-02节]</font><br/><font title="老师">李老师</font><br/><font title="教室">B202</font></div></td>
            </tr></tbody></table>
        """))
        val client = AcademicProtocolClient(store, logs, server.url("/jsxsd/").toString())

        val timetable = client.loadTimetable(null)

        assertEquals(LocalDate.now().toString(), timetable.referenceDateIso)
        assertEquals(2L, timetable.referenceWeek)
        assertEquals(20L, timetable.totalWeeks)
        assertEquals("首页课程", timetable.courses.single().name)
        assertEquals("1-2", "${timetable.courses.single().startSection}-${timetable.courses.single().endSection}")
        server.takeRequest()
        val homeRequest = server.takeRequest()
        assertTrue(homeRequest.path!!.contains("framework/main_index_loadkb.jsp"))
        assertTrue(homeRequest.body.readUtf8().contains("sjmsValue=scheme-1"))
    }

    @Test
    fun academicRecognizesTermSelectByIdAndKeepsRedirectCookies() {
        server.enqueue(html("").setResponseCode(302).setHeader("Location", "/jsxsd/kscj/terms").setHeader("Set-Cookie", "JSESSIONID=hop; Path=/jsxsd"))
        server.enqueue(html("<select id='kksj'><option value='2026-1'>学期</option></select>"))
        val client = AcademicProtocolClient(store, logs, server.url("/jsxsd/").toString())
        assertEquals("2026-1", client.initialize()!!.single().value)
        server.takeRequest()
        assertEquals("JSESSIONID=hop", server.takeRequest().getHeader("Cookie"))
    }

    @Test
    fun academicStudentHomepageKeepsOtherFeaturesAvailableWhenGradeTermsChange() {
        server.enqueue(html("<div>学生个人中心</div><a href='/jsxsd/framework/xsMain.jsp'>学生主页</a>"))
        val client = AcademicProtocolClient(store, logs, server.url("/jsxsd/").toString())
        assertTrue(client.initialize()!!.isEmpty())
    }

    @Test
    fun academicLoginDoesNotTreatModernWebVpnPortalAsAnAcademicPage() {
        server.enqueue(html("<html><title>WebVPN</title><div id='app'></div><script type='module' src='/assets/index-123.js'></script></html>"))
        val client = AcademicProtocolClient(store, logs, server.url("/jsxsd/").toString())
        assertNull(client.initialize())
    }

    @Test
    fun academicEvaluationRetainsQuestionFieldsAndRejectsFailedSave() {
        server.enqueue(html("""<form action='/jsxsd/xspj/xspj_save.do'><input type='hidden' name='pj06xh' value='q1'><input type='hidden' name='pj06xh' value='q2'><table><tr><td>指标1<input name='pj06xh' value='q1'></td><td><input type='radio' name='pj0601id_q1' value='a'>好</td></tr><tr><td>指标2<input name='pj06xh' value='q2'></td><td><input type='radio' name='pj0601id_q2' value='b'>好</td></tr></table><button onclick='saveData()'>保存</button></form>"""))
        server.enqueue(html("<script>alert('保存失败：评价已关闭')</script>"))
        val client = AcademicProtocolClient(store, logs, server.url("/jsxsd/").toString())
        val form = client.loadEvaluationForm("xspj/form")
        assertEquals(2, form.questions.size)
        val result = runCatching { client.saveEvaluation(form, listOf(
            com.aquasofts.cithub_flutter.native.EvaluationAnswerDto("q1", "a"),
            com.aquasofts.cithub_flutter.native.EvaluationAnswerDto("q2", "b")), "", false) }
        assertTrue(result.isFailure)
        server.takeRequest()
        val body = server.takeRequest().body.readUtf8()
        assertTrue(body.contains("pj06xh=q1"))
        assertTrue(body.contains("pj06xh=q2"))
    }

    @Test
    fun academicWeeklyTimetableRetainsAllSevenDays() {
        val cells = (1..7).joinToString("") { day -> "<td><div class='kbcontent1'>课程$day<br><font title='周次(节次)'>1-16周[01-02节]</font><font title='教室'>A101</font></div></td>" }
        server.enqueue(html("<select name='xnxq01id'><option value='2026-1' selected>学期</option></select><table id='kbtable'><tr><th>周</th></tr><tr><td>08:00-09:35</td>$cells</tr></table>"))
        server.enqueue(html("第 2 周/20 周"))
        val client = AcademicProtocolClient(store, logs, server.url("/jsxsd/").toString())
        assertEquals((1L..7L).toSet(), client.loadTimetable(null).courses.map { it.dayOfWeek }.toSet())
    }

    @Test
    fun academicImportsBrowserLoginWithoutReplacingWebVpnCookie() {
        store.put("webvpn.session.cookies", "SESSION=vpn; JSESSIONID=old")
        server.enqueue(html("<select name='kksj'><option value='2026-1'>学期</option></select>"))
        val client = AcademicProtocolClient(store, logs, server.url("/jsxsd/").toString())
        client.importBrowserSession("SESSION=stale; JSESSIONID=browser")
        assertEquals("2026-1", client.initialize()!!.single().value)
        assertEquals("SESSION=vpn; JSESSIONID=browser", server.takeRequest().getHeader("Cookie"))
    }

    private fun json(body: String) = MockResponse().setHeader("Content-Type", "application/json").setBody(body)
    private fun html(body: String) = MockResponse().setHeader("Content-Type", "text/html; charset=utf-8").setBody(body)
    private fun cells(values: List<String>): String = values.joinToString("") { "<td>$it</td>" }
}

private class MemorySecretStore : SecretStore {
    private val values = mutableMapOf<String, String>()
    override fun put(key: String, value: String) { values[key] = value }
    override fun get(key: String): String? = values[key]
    override fun remove(key: String) { values.remove(key) }
}
