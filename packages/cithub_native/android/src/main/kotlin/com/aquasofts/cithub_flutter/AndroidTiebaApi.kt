package com.aquasofts.cithub_flutter

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.webkit.CookieManager
import com.aquasofts.cithub_flutter.native.FloorReplyPageDto
import com.aquasofts.cithub_flutter.native.ForumPageDto
import com.aquasofts.cithub_flutter.native.ThreadPageDto
import com.aquasofts.cithub_flutter.native.TiebaAccountDto
import com.aquasofts.cithub_flutter.native.TiebaHostApi
import com.aquasofts.cithub_flutter.native.TiebaImageRequestDto
import com.aquasofts.cithub_flutter.native.TiebaUserProfileDto
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executor

internal class AndroidTiebaApi(
    private val context: Context,
    private val state: NativeSessionState,
    private val logs: RuntimeLogStore,
    private val executor: Executor,
    private val mainHandler: Handler,
    private val events: NativeEvents,
) : TiebaHostApi {
    private val client = TiebaWebClient(logs)
    private val protoClient = TiebaProtoClient(context, logs)
    private val forumNames = ConcurrentHashMap<Long, String>()
    private val threadForums = ConcurrentHashMap<String, Pair<Long, String>>()

    override fun currentAccount(callback: (Result<TiebaAccountDto?>) -> Unit) =
        runAsync(executor, mainHandler, callback) {
            val cookie = cookie()
            if (cookie.isBlank()) return@runAsync null
            runCatching { refreshProfile(cookie) }.getOrElse {
                logs.append("tieba", "Stored login rejected: ${it.message}")
                clearAccount()
                null
            }
        }

    override fun completeWebLogin(cookieHeader: String, callback: (Result<TiebaAccountDto>) -> Unit) =
        runAsync(executor, mainHandler, callback) {
            val raw = cookieHeader.ifBlank {
                listOfNotNull(
                    CookieManager.getInstance().getCookie("https://tieba.baidu.com/"),
                    CookieManager.getInstance().getCookie("https://tiebac.baidu.com/"),
                    CookieManager.getInstance().getCookie("https://passport.baidu.com/"),
                    CookieManager.getInstance().getCookie("https://wappass.baidu.com/"),
                ).flatMap { it.split(';') }.map(String::trim).filter(String::isNotBlank).distinct()
                    .joinToString("; ")
            }
            check(raw.contains("BDUSS=")) { "百度账号登录尚未完成" }
            state.secureStore.put("tieba.cookie", raw)
            state.tiebaAccountPresent = true
            val account = refreshProfile(raw)
            logs.append("tieba", "Web login completed; encrypted Cookie stored")
            events.emit("tieba", "signedIn", "贴吧登录成功")
            account
        }

    override fun refreshAccount(callback: (Result<TiebaAccountDto>) -> Unit) =
        runAsync(executor, mainHandler, callback) {
            requireCookie().let(::refreshProfile)
        }

    override fun logout(callback: (Result<Boolean>) -> Unit) =
        runAsync(executor, mainHandler, callback) {
            val oldCookie = cookie()
            clearAccount()
            expireWebViewCookies(oldCookie)
            events.emit("tieba", "signedOut", "已退出贴吧")
            true
        }

    override fun loadForum(
        forumName: String,
        page: Long,
        sort: String,
        goodOnly: Boolean,
        callback: (Result<ForumPageDto>) -> Unit,
    ) = runAsync(executor, mainHandler, callback) {
        val cookie = cookie()
        val result = protoFallback(
            "forum",
            { protoClient.forum(forumName, page, sort, goodOnly, cookie, accountUid()) },
            { client.forum(forumName, page, sort, goodOnly, cookie) },
        )
        result.forum.id.toLongOrNull()?.let { forumNames[it] = forumName }
        result
    }

    override fun search(
        forumName: String,
        keyword: String,
        page: Long,
        callback: (Result<ForumPageDto>) -> Unit,
    ) = runAsync(executor, mainHandler, callback) {
        require(keyword.isNotBlank()) { "请输入搜索关键词" }
        client.search(forumName, keyword, page, cookie())
    }

    override fun loadThread(
        threadId: String,
        forumId: Long,
        forumName: String,
        page: Long,
        sort: String,
        onlyOriginalPoster: Boolean,
        callback: (Result<ThreadPageDto>) -> Unit,
    ) = runAsync(executor, mainHandler, callback) {
        threadForums[threadId] = forumId to forumName
        val cookie = cookie()
        protoFallback(
            "thread",
            {
                protoClient.thread(
                    threadId,
                    forumId,
                    forumName,
                    page,
                    sort,
                    onlyOriginalPoster,
                    cookie,
                    accountUid(),
                )
            },
            { client.thread(threadId, forumId, forumName, page, sort, onlyOriginalPoster, cookie) },
        )
    }

    override fun loadFloorReplies(
        threadId: String,
        postId: String,
        page: Long,
        callback: (Result<FloorReplyPageDto>) -> Unit,
    ) = runAsync(executor, mainHandler, callback) {
        val forum = threadForums[threadId] ?: (0L to "")
        val cookie = cookie()
        protoFallback(
            "floor",
            {
                protoClient.floorReplies(
                    threadId,
                    postId,
                    page,
                    forum.first,
                    forum.second,
                    cookie,
                    accountUid(),
                )
            },
            { client.floorReplies(threadId, postId, page, cookie) },
        )
    }

    override fun loadUserProfile(uid: Long, callback: (Result<TiebaUserProfileDto>) -> Unit) =
        runAsync(executor, mainHandler, callback) {
            val cookie = cookie()
            protoFallback(
                "profile",
                { protoClient.userProfile(uid, cookie, accountUid()) },
                { client.userProfile(uid, cookie) },
            )
        }

    override fun loadForumRule(forumId: Long, callback: (Result<String>) -> Unit) =
        runAsync(executor, mainHandler, callback) {
            val name = forumNames[forumId] ?: error("请先打开该贴吧")
            val cookie = cookie()
            protoFallback(
                "forum-rule",
                { protoClient.forumRule(forumId, cookie, accountUid()) },
                { client.forumRule(name, cookie) },
            )
        }

    override fun sign(forumId: String, forumName: String, callback: (Result<String>) -> Unit) =
        runAsync(executor, mainHandler, callback) {
            val result = client.sign(forumName, requireTbs(), requireCookie())
            events.emit("tieba", "signSuccess", result)
            result
        }

    override fun followForum(forumId: String, forumName: String, callback: (Result<String>) -> Unit) =
        runAsync(executor, mainHandler, callback) {
            client.follow(forumId, forumName, requireTbs(), requireCookie())
        }

    override fun resolveOriginalImage(request: TiebaImageRequestDto, callback: (Result<String>) -> Unit) =
        runAsync(executor, mainHandler, callback) {
            val uri = Uri.parse(request.url)
            require(uri.scheme == "https") { "只允许 HTTPS 图片" }
            protoFallback(
                "original-image",
                { protoClient.resolveOriginalImage(request, cookie(), accountUid()) },
                { request.url },
            )
        }

    override fun launchOfficialReply(threadId: Long, postId: Long?, callback: (Result<Boolean>) -> Unit) =
        runAsync(executor, mainHandler, callback) {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(TiebaOfficialReplyUri.build(threadId, postId)))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            runCatching { context.startActivity(intent) }.isSuccess
        }

    private fun refreshProfile(cookie: String): TiebaAccountDto {
        val (account, tbs) = client.profile(cookie)
        state.tiebaAccountPresent = true
        state.secureStore.put("tieba.uid", account.uid.toString())
        if (tbs.isNotBlank()) state.secureStore.put("tieba.tbs", tbs)
        return account
    }

    private fun cookie(): String = state.secureStore.get("tieba.cookie").orEmpty()

    private fun requireCookie(): String = cookie().also {
        check(it.isNotBlank()) { "请先登录贴吧" }
    }

    private fun requireTbs(): String = state.secureStore.get("tieba.tbs").orEmpty().also {
        check(it.isNotBlank()) { "贴吧登录凭据已过期，请重新登录" }
    }

    private fun accountUid(): Long = state.secureStore.get("tieba.uid")?.toLongOrNull() ?: 0L

    private inline fun <T> protoFallback(
        operation: String,
        proto: () -> T,
        web: () -> T,
    ): T = runCatching(proto).getOrElse { failure ->
        logs.append(
            "tieba",
            "PB $operation unavailable; HTTPS fallback: ${failure.javaClass.simpleName}: ${failure.message}",
        )
        web()
    }

    private fun clearAccount() {
        state.secureStore.remove("tieba.cookie")
        state.secureStore.remove("tieba.token")
        state.secureStore.remove("tieba.tbs")
        state.secureStore.remove("tieba.uid")
        state.tiebaAccountPresent = false
    }

    private fun expireWebViewCookies(cookie: String) {
        val manager = CookieManager.getInstance()
        cookie.split(';').map(String::trim).filter { it.contains('=') }.forEach { pair ->
            val name = pair.substringBefore('=')
            manager.setCookie("https://tieba.baidu.com/", "$name=; Path=/; Max-Age=0; Secure")
            manager.setCookie("https://tiebac.baidu.com/", "$name=; Path=/; Max-Age=0; Secure")
            manager.setCookie("https://passport.baidu.com/", "$name=; Path=/; Max-Age=0; Secure")
            manager.setCookie("https://wappass.baidu.com/", "$name=; Path=/; Max-Age=0; Secure")
        }
        manager.flush()
    }
}
