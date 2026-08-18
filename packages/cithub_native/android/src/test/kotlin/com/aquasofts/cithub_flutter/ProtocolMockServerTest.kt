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
        val client = WebVpnProtocolClient(store, logs, server.url("/").toString())

        val configuration = client.loadConfiguration()
        val captcha = client.loadCaptcha()
        val user = client.userInfo()

        assertEquals("local", configuration.externalId)
        assertTrue(configuration.requiresPassword)
        assertTrue(configuration.requiresCaptcha)
        assertEquals("captcha-1", captcha.id)
        assertEquals("20260001", user.dto.username)
        assertEquals("SESSION=abc", client.cookies())
        assertEquals("SESSION=abc", store.get("webvpn.session.cookies"))
        assertNull(server.takeRequest().getHeader("Cookie"))
        assertEquals("SESSION=abc", server.takeRequest().getHeader("Cookie"))
        assertEquals("SESSION=abc", server.takeRequest().getHeader("Cookie"))
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
        val client = AcademicProtocolClient(store, logs, server.url("/jsxsd/").toString())

        assertNull(client.initialize())
        assertFalse(runCatching { client.webPageUrl("https://evil.example/") }.isSuccess)
        assertFalse(runCatching { client.webPageUrl("../admin") }.isSuccess)
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
