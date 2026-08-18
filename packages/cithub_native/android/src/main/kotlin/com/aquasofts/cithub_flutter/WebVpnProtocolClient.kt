package com.aquasofts.cithub_flutter

import com.aquasofts.cithub_flutter.native.RequiredAccountAction
import com.aquasofts.cithub_flutter.native.UserInfoDto
import java.net.HttpURLConnection
import java.net.URL
import java.security.KeyFactory
import java.security.SecureRandom
import java.security.spec.X509EncodedKeySpec
import java.util.Base64
import javax.crypto.Cipher
import org.json.JSONObject

internal data class WebVpnLoginConfiguration(
    val externalId: String,
    val requiresPassword: Boolean,
    val requiresCaptcha: Boolean,
    val dynamicVerificationTypes: List<Int>,
)

internal data class WebVpnCaptcha(val id: String, val image: String)

internal data class WebVpnUser(
    val dto: UserInfoDto,
    val requiredAction: RequiredAccountAction,
)

internal class WebVpnProtocolClient(
    private val store: SecretStore,
    private val logs: RuntimeLogStore,
    baseUrl: String = BASE_URL,
) {
    private val baseUrl = baseUrl.ensureTrailingSlash()
    @Volatile private var cookieHeader: String = store.get(COOKIE_KEY).orEmpty()

    fun loadConfiguration(): WebVpnLoginConfiguration {
        val data = request("GET", "api/access/authentication/list").data()
        val methods = data.optJSONArray("list") ?: error("WebVPN 未返回认证方式")
        for (index in 0 until methods.length()) {
            val method = methods.getJSONObject(index)
            if (method.optInt("authType") != 1) continue
            val options = method.optJSONObject("authOptions")
            val dynamic = options?.optJSONArray("dynamicVerification")
            return WebVpnLoginConfiguration(
                method.getString("externalId"),
                options?.optInt("staticVerification") == 1,
                options?.optInt("useGraphValidateCode") == 1,
                if (dynamic == null) emptyList() else (0 until dynamic.length()).map(dynamic::optInt),
            )
        }
        error("学校 WebVPN 当前未开放本地账号登录")
    }

    fun loadCaptcha(): WebVpnCaptcha {
        val data = request("GET", "api/access/graph-captcha/validate-code?width=150&height=50").data()
        return WebVpnCaptcha(data.getString("id"), data.getString("captcha"))
    }

    fun login(
        username: String,
        password: String,
        captchaId: String,
        captchaCode: String,
        configuration: WebVpnLoginConfiguration,
    ): WebVpnUser {
        require(configuration.dynamicVerificationTypes.isEmpty()) {
            "学校当前要求动态验证码，请先使用官方 WebVPN 网页完成登录"
        }
        val payload = JSONObject()
            .put("deviceId", deviceId())
            .put("userName", username)
        if (configuration.requiresPassword) payload.put("password", encryptPassword(password))
        if (configuration.requiresCaptcha) {
            payload.put("captchaId", captchaId)
            payload.put("code", captchaCode)
        }
        val body = JSONObject()
            .put("externalId", configuration.externalId)
            .put("data", payload.toString())
        request("POST", "api/access/auth/finish", body)
        return userInfo()
    }

    fun userInfo(): WebVpnUser = parseUser(request("GET", "api/access/user/info").data())

    fun logout() {
        runCatching { request("POST", "api/access/user/logout", JSONObject()) }
        clearSession()
    }

    fun hasRestorableSession(): Boolean = cookieHeader.isNotBlank()

    fun cookies(): String = cookieHeader

    fun clearSession() {
        cookieHeader = ""
        store.remove(COOKIE_KEY)
    }

    private fun request(method: String, path: String, json: JSONObject? = null): JSONObject {
        val connection = URL(baseUrl + path).openConnection() as HttpURLConnection
        connection.requestMethod = method
        connection.connectTimeout = 20_000
        connection.readTimeout = 20_000
        connection.instanceFollowRedirects = false
        connection.setRequestProperty("Accept", "application/json, text/plain, */*")
        connection.setRequestProperty("Accept-Language", "zh-CN,zh;q=0.9")
        connection.setRequestProperty("User-Agent", BROWSER_USER_AGENT)
        connection.setRequestProperty("Origin", baseUrl.removeSuffix("/"))
        connection.setRequestProperty("Referer", baseUrl)
        connection.setRequestProperty("DNT", "1")
        if (cookieHeader.isNotBlank()) connection.setRequestProperty("Cookie", cookieHeader)
        if (json != null) {
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            connection.outputStream.use { it.write(json.toString().toByteArray()) }
        }
        val status = connection.responseCode
        mergeCookies(connection.headerFields.entries
            .firstOrNull { it.key?.equals("set-cookie", ignoreCase = true) == true }
            ?.value.orEmpty())
        val stream = if (status in 200..299) connection.inputStream else connection.errorStream
        val text = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
        logs.append("webvpn", "$method /$path -> HTTP $status")
        if (status !in 200..299) {
            val message = runCatching { JSONObject(text).optString("message") }.getOrNull()
            error(message?.takeIf(String::isNotBlank) ?: "WebVPN 请求失败（HTTP $status）")
        }
        val envelope = JSONObject(text)
        val code = envelope.optInt("code", -1)
        if (code != 0) error(envelope.optString("message", "WebVPN 接口返回错误：$code"))
        return envelope
    }

    @Synchronized
    private fun mergeCookies(setCookies: List<String>) {
        if (setCookies.isEmpty()) return
        val cookies = linkedMapOf<String, String>()
        cookieHeader.split(';').map(String::trim).filter { it.contains('=') }.forEach { pair ->
            cookies[pair.substringBefore('=')] = pair.substringAfter('=')
        }
        setCookies.forEach { raw ->
            val pair = raw.substringBefore(';').trim()
            if (pair.contains('=')) {
                val name = pair.substringBefore('=')
                val value = pair.substringAfter('=')
                if (value.isBlank() || raw.contains("Max-Age=0", ignoreCase = true)) cookies.remove(name)
                else cookies[name] = value
            }
        }
        cookieHeader = cookies.entries.joinToString("; ") { "${it.key}=${it.value}" }
        if (cookieHeader.isBlank()) store.remove(COOKIE_KEY) else store.put(COOKIE_KEY, cookieHeader)
    }

    private fun JSONObject.data(): JSONObject = optJSONObject("data")
        ?: error("WebVPN 接口未返回数据")

    private fun parseUser(data: JSONObject): WebVpnUser {
        val groupsJson = data.optJSONArray("groups")
        val groups = if (groupsJson == null) emptyList() else (0 until groupsJson.length()).map(groupsJson::optString)
        val action = when {
            data.optBoolean("needToBindLocalAccount") -> RequiredAccountAction.BIND_ACCOUNT
            data.optBoolean("needTriggerTFA") -> RequiredAccountAction.TFA
            data.optBoolean("needChangePwd") -> RequiredAccountAction.PASSWORD_RESET
            else -> RequiredAccountAction.NONE
        }
        return WebVpnUser(
            UserInfoDto(
                data.optString("username"),
                data.optString("nickname"),
                data.optString("fullName"),
                groups,
                data.optLong("authType"),
                data.optBoolean("bindWechat"),
                data.optBoolean("bindOtp"),
            ),
            action,
        )
    }

    private fun deviceId(): String {
        store.get(DEVICE_ID_KEY)?.takeIf { it.matches(Regex("^[0-9a-f]{32}$")) }?.let { return it }
        val bytes = ByteArray(16).also(SecureRandom()::nextBytes)
        return bytes.joinToString("") { "%02x".format(it) }.also { store.put(DEVICE_ID_KEY, it) }
    }

    private fun encryptPassword(password: String): String {
        val publicKeyBytes = PUBLIC_KEY_PEM
            .replace("-----BEGIN PUBLIC KEY-----", "")
            .replace("-----END PUBLIC KEY-----", "")
            .replace("\\s".toRegex(), "")
            .let(Base64.getDecoder()::decode)
        val publicKey = KeyFactory.getInstance("RSA").generatePublic(X509EncodedKeySpec(publicKeyBytes))
        return Cipher.getInstance("RSA/ECB/PKCS1Padding").run {
            init(Cipher.ENCRYPT_MODE, publicKey)
            Base64.getEncoder().encodeToString(doFinal(password.toByteArray()))
        }
    }

    private companion object {
        const val BASE_URL = "https://webvpn.ccit.edu.cn/"
        const val COOKIE_KEY = "webvpn.session.cookies"
        const val DEVICE_ID_KEY = "webvpn.device_id"
        const val BROWSER_USER_AGENT = "Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Mobile Safari/537.36"
        const val PUBLIC_KEY_PEM = """
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvrqdXbn6tf2kabHLRoE9
IASO5fZixKK5IsFcBMJ0h1tf0WUb3HMygcC3+NecScetMSoPmSOrDLSA6sBWwGEF
LTefRM5vP/eFdkXXB0YpFjfganpBKv4ZOvzCWZGhHOUlACRHViazsZbaPHvLYhsH
Z3XTSbS8iIVDYgrQCHgzs2ULWEUau3489HTAcg7A2V2ZfDDzqaHj5BU5vopbfmjs
cXObP0Ddy4IW4Mc/fcJoJs1e7M4hZg6iTIb8OTnlssOikckenO9mV+GdxdOSG9K2
lUTCS+qxFXQ/vgd7JWi0eTOYG2duEoA2u2T3b/G5I/h8En+tOG6Ax0rztp/YtF0Q
zQIDAQAB
-----END PUBLIC KEY-----
"""
    }
}

private fun String.ensureTrailingSlash(): String = if (endsWith('/')) this else "$this/"
