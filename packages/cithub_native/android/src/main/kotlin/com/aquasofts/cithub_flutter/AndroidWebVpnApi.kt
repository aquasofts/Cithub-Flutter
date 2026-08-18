package com.aquasofts.cithub_flutter

import android.content.Context
import android.os.Build
import android.os.Handler
import android.webkit.CookieManager
import com.aquasofts.cithub_flutter.nativeplugin.BuildConfig
import com.aquasofts.cithub_flutter.native.AuthStatus
import com.aquasofts.cithub_flutter.native.CaptchaDto
import com.aquasofts.cithub_flutter.native.CaptchaFlavor
import com.aquasofts.cithub_flutter.native.LoginRequestDto
import com.aquasofts.cithub_flutter.native.NativeCapabilities
import com.aquasofts.cithub_flutter.native.RequiredAccountAction
import com.aquasofts.cithub_flutter.native.SavedAccountDto
import com.aquasofts.cithub_flutter.native.WebVpnHostApi
import com.aquasofts.cithub_flutter.native.WebVpnSessionDto
import java.util.concurrent.Executor

internal class AndroidWebVpnApi(
    private val context: Context,
    private val state: NativeSessionState,
    private val logs: RuntimeLogStore,
    private val executor: Executor,
    private val mainHandler: Handler,
    private val events: NativeEvents,
) : WebVpnHostApi {
    private val captchaRecognizer = CaptchaRecognizer()
    private val client = WebVpnProtocolClient(state.secureStore, logs)
    @Volatile private var configuration: WebVpnLoginConfiguration? = null
    @Volatile private var captcha: CaptchaDto? = null
    @Volatile private var activeUser: WebVpnUser? = null

    override fun getCapabilities(): NativeCapabilities {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        val code = if (Build.VERSION.SDK_INT >= 28) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION") info.versionCode.toLong()
        }
        return NativeCapabilities(
            if (BuildConfig.CAPTCHA_AUTOFILL_ENABLED) CaptchaFlavor.AUTO_CAPTCHA else CaptchaFlavor.MANUAL_CAPTCHA,
            BuildConfig.CAPTCHA_AUTOFILL_ENABLED,
            info.versionName ?: "0.0.0",
            code,
        )
    }

    override fun initialize(callback: (Result<WebVpnSessionDto>) -> Unit) =
        runAsync(executor, mainHandler, callback) { initializeBlocking() }

    override fun refreshCaptcha(callback: (Result<WebVpnSessionDto>) -> Unit) =
        runAsync(executor, mainHandler, callback) {
            ensureConfiguration()
            refreshCaptchaBlocking()
            session("验证码已刷新")
        }

    override fun login(request: LoginRequestDto, callback: (Result<WebVpnSessionDto>) -> Unit) =
        runAsync(executor, mainHandler, callback) {
            val username = request.username.trim()
            require(username.isNotBlank()) { "请输入 WebVPN 账号" }
            val password = if (request.useSavedPassword) {
                state.secureStore.get("webvpn.password.$username")
                    ?: error("保存的密码不可用，请重新输入")
            } else request.password
            val config = ensureConfiguration()
            if (config.requiresPassword) require(password.isNotBlank()) { "请输入 WebVPN 密码" }
            if (config.requiresCaptcha) {
                require(request.captchaId.isNotBlank() && request.captchaCode.isNotBlank()) { "请输入图形验证码" }
            }
            activeUser = client.login(
                username,
                password,
                request.captchaId,
                request.captchaCode,
                config,
            )
            state.webVpnSignedIn = true
            state.webVpnUsername = username
            syncWebViewCookies()
            if (request.rememberPassword) saveCredential(username, password)
            events.emit("webvpn", "signedIn", "WebVPN 登录成功")
            session("登录成功")
        }

    override fun selectSavedAccount(username: String, callback: (Result<WebVpnSessionDto>) -> Unit) =
        runAsync(executor, mainHandler, callback) {
            require(state.secureStore.get("webvpn.password.$username") != null) { "保存的账号不可用" }
            state.webVpnUsername = username
            ensureConfiguration()
            if (captcha == null) refreshCaptchaBlocking()
            session("已选择保存的账号")
        }

    override fun forgetSavedAccount(username: String, callback: (Result<WebVpnSessionDto>) -> Unit) =
        runAsync(executor, mainHandler, callback) {
            state.secureStore.remove("webvpn.password.$username")
            state.secureStore.remove("webvpn.saved_at.$username")
            writeSavedUsernames(savedUsernames().filterNot { it == username })
            session("已删除保存的账号")
        }

    override fun revalidate(callback: (Result<WebVpnSessionDto>) -> Unit) =
        runAsync(executor, mainHandler, callback) {
            if (!client.hasRestorableSession()) return@runAsync signedOutSession("会话已失效")
            activeUser = runCatching { client.userInfo() }.getOrElse {
                clearActiveSession()
                return@runAsync signedOutSession("会话已失效")
            }
            state.webVpnSignedIn = true
            state.webVpnUsername = activeUser?.dto?.username
            syncWebViewCookies()
            session("会话有效")
        }

    override fun logout(callback: (Result<WebVpnSessionDto>) -> Unit) =
        runAsync(executor, mainHandler, callback) {
            val cookies = client.cookies()
            client.logout()
            clearWebViewCookies(cookies)
            clearActiveSession()
            events.emit("webvpn", "signedOut", "已退出 WebVPN")
            signedOutSession("已退出")
        }

    @Synchronized
    private fun initializeBlocking(): WebVpnSessionDto {
        if (client.hasRestorableSession()) {
            val restored = runCatching { client.userInfo() }.getOrNull()
            if (restored != null) {
                activeUser = restored
                state.webVpnSignedIn = true
                state.webVpnUsername = restored.dto.username
                syncWebViewCookies()
                logs.append("webvpn", "Encrypted Cookie session restored")
                return session("已恢复 WebVPN 会话")
            }
            client.clearSession()
        }

        val config = ensureConfiguration()
        if (config.requiresCaptcha) refreshCaptchaBlocking()
        if (BuildConfig.CAPTCHA_AUTOFILL_ENABLED) {
            val username = savedUsernames().firstOrNull()
            val password = username?.let { state.secureStore.get("webvpn.password.$it") }
            val currentCaptcha = captcha
            if (username != null && password != null &&
                (!config.requiresCaptcha || !currentCaptcha?.recognizedCode.isNullOrBlank())
            ) {
                val user = runCatching {
                    client.login(
                        username,
                        password,
                        currentCaptcha?.id.orEmpty(),
                        currentCaptcha?.recognizedCode.orEmpty(),
                        config,
                    )
                }.getOrNull()
                if (user != null) {
                    activeUser = user
                    state.webVpnSignedIn = true
                    state.webVpnUsername = username
                    syncWebViewCookies()
                    events.emit("webvpn", "signedIn", "已自动续登 WebVPN")
                    return session("已自动续登")
                }
                client.clearSession()
                refreshCaptchaBlocking()
            }
        }
        return signedOutSession()
    }

    private fun ensureConfiguration(): WebVpnLoginConfiguration =
        configuration ?: client.loadConfiguration().also { configuration = it }

    private fun refreshCaptchaBlocking() {
        val config = ensureConfiguration()
        if (!config.requiresCaptcha) {
            captcha = null
            return
        }
        val loaded = client.loadCaptcha()
        val recognized = if (BuildConfig.CAPTCHA_AUTOFILL_ENABLED) {
            runCatching { captchaRecognizer.recognize(loaded.image) }.getOrDefault("")
        } else ""
        captcha = CaptchaDto(loaded.id, loaded.image, recognized)
    }

    private fun saveCredential(username: String, password: String) {
        state.secureStore.put("webvpn.password.$username", password)
        state.secureStore.put("webvpn.saved_at.$username", System.currentTimeMillis().toString())
        writeSavedUsernames(listOf(username) + savedUsernames().filterNot { it == username })
    }

    private fun savedUsernames(): List<String> = state.secureStore
        .get("webvpn.saved_usernames")
        .orEmpty()
        .lineSequence()
        .map(String::trim)
        .filter(String::isNotBlank)
        .distinct()
        .take(10)
        .toList()

    private fun writeSavedUsernames(usernames: List<String>) {
        val value = usernames.distinct().take(10).joinToString("\n")
        if (value.isBlank()) state.secureStore.remove("webvpn.saved_usernames")
        else state.secureStore.put("webvpn.saved_usernames", value)
    }

    private fun clearActiveSession() {
        activeUser = null
        state.webVpnSignedIn = false
        state.webVpnUsername = null
        client.clearSession()
    }

    private fun syncWebViewCookies() {
        val manager = CookieManager.getInstance()
        client.cookies().split(';').map(String::trim).filter(String::isNotBlank).forEach { cookie ->
            manager.setCookie("https://webvpn.ccit.edu.cn/", "$cookie; Path=/; Secure")
        }
        manager.flush()
    }

    private fun clearWebViewCookies(cookieHeader: String) {
        val manager = CookieManager.getInstance()
        cookieHeader.split(';').map(String::trim).filter { it.contains('=') }.forEach { cookie ->
            val name = cookie.substringBefore('=')
            manager.setCookie(
                "https://webvpn.ccit.edu.cn/",
                "$name=; Path=/; Max-Age=0; Secure",
            )
        }
        manager.flush()
    }

    private fun signedOutSession(message: String? = null): WebVpnSessionDto = WebVpnSessionDto(
        AuthStatus.SIGNED_OUT,
        RequiredAccountAction.NONE,
        null,
        savedAccounts(),
        captcha,
        configuration?.requiresCaptcha ?: true,
        message,
    )

    private fun session(message: String? = null): WebVpnSessionDto {
        val user = activeUser
        val action = user?.requiredAction ?: RequiredAccountAction.NONE
        val status = when {
            !state.webVpnSignedIn -> AuthStatus.SIGNED_OUT
            action != RequiredAccountAction.NONE -> AuthStatus.ACTION_REQUIRED
            else -> AuthStatus.SIGNED_IN
        }
        return WebVpnSessionDto(
            status,
            action,
            user?.dto,
            savedAccounts(),
            captcha,
            configuration?.requiresCaptcha ?: true,
            message,
        )
    }

    private fun savedAccounts(): List<SavedAccountDto> = savedUsernames().map { username ->
        SavedAccountDto(
            username,
            state.secureStore.get("webvpn.saved_at.$username")?.toLongOrNull() ?: 0,
        )
    }
}
