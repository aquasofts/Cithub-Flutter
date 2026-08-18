package com.aquasofts.cithub_flutter

import android.os.Handler
import com.aquasofts.cithub_flutter.nativeplugin.BuildConfig
import android.webkit.CookieManager
import com.aquasofts.cithub_flutter.native.AcademicHostApi
import com.aquasofts.cithub_flutter.native.AcademicTermDto
import com.aquasofts.cithub_flutter.native.AuthStatus
import com.aquasofts.cithub_flutter.native.CaptchaDto
import com.aquasofts.cithub_flutter.native.CourseGradeDto
import com.aquasofts.cithub_flutter.native.EvaluationAnswerDto
import com.aquasofts.cithub_flutter.native.EvaluationBatchDto
import com.aquasofts.cithub_flutter.native.EvaluationCourseDto
import com.aquasofts.cithub_flutter.native.EvaluationFormDto
import com.aquasofts.cithub_flutter.native.LoginRequestDto
import com.aquasofts.cithub_flutter.native.RequiredAccountAction
import com.aquasofts.cithub_flutter.native.SavedAccountDto
import com.aquasofts.cithub_flutter.native.SelectedCourseDto
import com.aquasofts.cithub_flutter.native.TimetableDto
import com.aquasofts.cithub_flutter.native.UserInfoDto
import com.aquasofts.cithub_flutter.native.WebVpnSessionDto
import java.util.concurrent.Executor

internal class AndroidAcademicApi(
    private val state: NativeSessionState,
    private val logs: RuntimeLogStore,
    private val executor: Executor,
    private val mainHandler: Handler,
) : AcademicHostApi {
    private val client = AcademicProtocolClient(state.secureStore, logs)
    private val captchaRecognizer = CaptchaRecognizer()
    @Volatile private var captcha: CaptchaDto? = null
    @Volatile private var terms: List<AcademicTermDto> = emptyList()

    override fun initialize(webVpnUsername: String, callback: (Result<WebVpnSessionDto>) -> Unit) =
        runAsync(executor, mainHandler, callback) {
            check(state.webVpnSignedIn) { "请先登录 WebVPN" }
            val restored = client.initialize()
            if (restored != null) {
                terms = restored
                state.academicSignedIn = true
                state.academicUsername = state.secureStore.get("academic.last_username") ?: webVpnUsername
                syncWebViewCookies()
                session("已恢复教务系统会话")
            } else {
                state.academicSignedIn = false
                refreshCaptchaBlocking()
                session("请登录教务系统")
            }
        }

    override fun refreshCaptcha(callback: (Result<WebVpnSessionDto>) -> Unit) =
        runAsync(executor, mainHandler, callback) {
            check(state.webVpnSignedIn) { "请先登录 WebVPN" }
            refreshCaptchaBlocking()
            session("教务验证码已刷新")
        }

    override fun login(request: LoginRequestDto, callback: (Result<WebVpnSessionDto>) -> Unit) =
        runAsync(executor, mainHandler, callback) {
            check(state.webVpnSignedIn) { "请先登录 WebVPN" }
            val username = request.username.trim()
            val password = if (request.useSavedPassword) {
                state.secureStore.get("academic.password.$username")
                    ?: error("保存的教务密码不可用，请重新输入")
            } else request.password
            terms = client.login(username, password, request.captchaCode)
            state.academicSignedIn = true
            state.academicUsername = username
            state.secureStore.put("academic.last_username", username)
            if (request.rememberPassword) saveCredential(username, password)
            syncWebViewCookies()
            logs.append("academic", "Academic session established for $username")
            session("教务登录成功")
        }

    override fun loadTerms(callback: (Result<List<AcademicTermDto>>) -> Unit) =
        runAsync(executor, mainHandler, callback) {
            requireSession()
            if (terms.isEmpty()) terms = client.initialize() ?: throw AcademicLoginRequired("教务登录已过期")
            terms
        }

    override fun loadGrades(term: String, bestOnly: Boolean, callback: (Result<List<CourseGradeDto>>) -> Unit) =
        runAsync(executor, mainHandler, callback) { requireSession(); client.loadGrades(term, bestOnly) }

    override fun loadTimetable(term: String?, callback: (Result<TimetableDto>) -> Unit) =
        runAsync(executor, mainHandler, callback) { requireSession(); client.loadTimetable(term) }

    override fun loadSelectionResults(term: String, callback: (Result<List<SelectedCourseDto>>) -> Unit) =
        runAsync(executor, mainHandler, callback) { requireSession(); client.loadSelectionResults(term) }

    override fun loadEvaluationBatches(callback: (Result<List<EvaluationBatchDto>>) -> Unit) =
        runAsync(executor, mainHandler, callback) { requireSession(); client.loadEvaluationBatches() }

    override fun loadEvaluationCourses(path: String, callback: (Result<List<EvaluationCourseDto>>) -> Unit) =
        runAsync(executor, mainHandler, callback) { requireSession(); client.loadEvaluationCourses(path) }

    override fun loadEvaluationForm(path: String, callback: (Result<EvaluationFormDto>) -> Unit) =
        runAsync(executor, mainHandler, callback) { requireSession(); client.loadEvaluationForm(path) }

    override fun saveEvaluation(
        form: EvaluationFormDto,
        answers: List<EvaluationAnswerDto>,
        suggestion: String,
        submit: Boolean,
        callback: (Result<Boolean>) -> Unit,
    ) = runAsync(executor, mainHandler, callback) {
        requireSession()
        client.saveEvaluation(form, answers, suggestion, submit)
    }

    override fun prepareWebPage(path: String, callback: (Result<String>) -> Unit) =
        runAsync(executor, mainHandler, callback) {
            requireSession()
            syncWebViewCookies()
            client.webPageUrl(path)
        }

    override fun logout(callback: (Result<Boolean>) -> Unit) =
        runAsync(executor, mainHandler, callback) {
            client.logout()
            state.academicSignedIn = false
            state.academicUsername = null
            terms = emptyList()
            captcha = null
            logs.append("academic", "Academic session cleared")
            true
        }

    private fun refreshCaptchaBlocking() {
        val image = client.loadCaptcha()
        val recognized = if (BuildConfig.CAPTCHA_AUTOFILL_ENABLED) {
            runCatching { captchaRecognizer.recognize(image) }.getOrDefault("")
        } else ""
        captcha = CaptchaDto("academic-${System.currentTimeMillis()}", image, recognized)
    }

    private fun saveCredential(username: String, password: String) {
        state.secureStore.put("academic.password.$username", password)
        state.secureStore.put("academic.saved_at.$username", System.currentTimeMillis().toString())
        val usernames = listOf(username) + savedUsernames().filterNot { it == username }
        state.secureStore.put("academic.saved_usernames", usernames.distinct().take(10).joinToString("\n"))
    }

    private fun savedUsernames(): List<String> = state.secureStore.get("academic.saved_usernames")
        .orEmpty().lineSequence().map(String::trim).filter(String::isNotBlank).distinct().take(10).toList()

    private fun savedAccounts(): List<SavedAccountDto> = savedUsernames().map {
        SavedAccountDto(it, state.secureStore.get("academic.saved_at.$it")?.toLongOrNull() ?: 0)
    }

    private fun requireSession() {
        check(state.webVpnSignedIn) { "WebVPN 会话无效，请重新登录" }
        check(state.academicSignedIn) { "教务系统登录已过期，请重新登录" }
    }

    private fun session(message: String? = null) = WebVpnSessionDto(
        if (state.academicSignedIn) AuthStatus.SIGNED_IN else AuthStatus.SIGNED_OUT,
        RequiredAccountAction.NONE,
        if (state.academicSignedIn) UserInfoDto(
            state.academicUsername.orEmpty(),
            state.academicUsername.orEmpty(),
            state.academicUsername.orEmpty(),
            listOf("学生"),
            1,
            false,
            false,
        ) else null,
        savedAccounts(),
        captcha,
        !state.academicSignedIn,
        message,
    )

    private fun syncWebViewCookies() {
        val manager = CookieManager.getInstance()
        client.cookieHeader().split(';').map(String::trim).filter(String::isNotBlank).forEach { cookie ->
            manager.setCookie("https://webvpn.ccit.edu.cn/", "$cookie; Path=/; Secure")
            manager.setCookie("https://http-10-198-47-148-8080.webvpn.ccit.edu.cn/", "$cookie; Path=/; Secure")
        }
        manager.flush()
    }
}
