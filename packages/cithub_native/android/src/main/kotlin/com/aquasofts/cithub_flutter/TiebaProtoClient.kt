package com.aquasofts.cithub_flutter

import android.content.Context
import android.os.Build
import android.provider.Settings
import android.util.Base64
import com.aquasofts.cithub_flutter.native.FloorReplyDto
import com.aquasofts.cithub_flutter.native.FloorReplyPageDto
import com.aquasofts.cithub_flutter.native.ForumPageDto
import com.aquasofts.cithub_flutter.native.ForumSummaryDto
import com.aquasofts.cithub_flutter.native.ForumThreadDto
import com.aquasofts.cithub_flutter.native.ThreadFloorDto
import com.aquasofts.cithub_flutter.native.ThreadPageDto
import com.aquasofts.cithub_flutter.native.TiebaContentDto
import com.aquasofts.cithub_flutter.native.TiebaImageRequestDto
import com.aquasofts.cithub_flutter.native.TiebaModeratorRole
import com.aquasofts.cithub_flutter.native.TiebaUserPostDto
import com.aquasofts.cithub_flutter.native.TiebaUserProfileDto
import com.huanchengfly.tieba.post.api.models.protos.AppPosInfo
import com.huanchengfly.tieba.post.api.models.protos.CommonRequest
import com.huanchengfly.tieba.post.api.models.protos.HotPost
import com.huanchengfly.tieba.post.api.models.protos.PbContent
import com.huanchengfly.tieba.post.api.models.protos.Post
import com.huanchengfly.tieba.post.api.models.protos.PostInfoList
import com.huanchengfly.tieba.post.api.models.protos.SubPostList
import com.huanchengfly.tieba.post.api.models.protos.ThreadInfo
import com.huanchengfly.tieba.post.api.models.protos.User
import com.huanchengfly.tieba.post.api.models.protos.forumRuleDetail.ForumRuleDetailRequest
import com.huanchengfly.tieba.post.api.models.protos.forumRuleDetail.ForumRuleDetailRequestData
import com.huanchengfly.tieba.post.api.models.protos.forumRuleDetail.ForumRuleDetailResponse
import com.huanchengfly.tieba.post.api.models.protos.frsPage.AdParam as FrsAdParam
import com.huanchengfly.tieba.post.api.models.protos.frsPage.FrsPageRequest
import com.huanchengfly.tieba.post.api.models.protos.frsPage.FrsPageRequestData
import com.huanchengfly.tieba.post.api.models.protos.frsPage.FrsPageResponse
import com.huanchengfly.tieba.post.api.models.protos.pbFloor.PbFloorRequest
import com.huanchengfly.tieba.post.api.models.protos.pbFloor.PbFloorRequestData
import com.huanchengfly.tieba.post.api.models.protos.pbFloor.PbFloorResponse
import com.huanchengfly.tieba.post.api.models.protos.pbPage.AdParam as PbAdParam
import com.huanchengfly.tieba.post.api.models.protos.pbPage.PbPageRequest
import com.huanchengfly.tieba.post.api.models.protos.pbPage.PbPageRequestData
import com.huanchengfly.tieba.post.api.models.protos.pbPage.PbPageResponse
import com.huanchengfly.tieba.post.api.models.protos.profile.ProfileRequest
import com.huanchengfly.tieba.post.api.models.protos.profile.ProfileRequestData
import com.huanchengfly.tieba.post.api.models.protos.profile.ProfileResponse
import com.huanchengfly.tieba.post.api.models.protos.threadList.AdParam as ThreadListAdParam
import com.huanchengfly.tieba.post.api.models.protos.threadList.ThreadListRequest
import com.huanchengfly.tieba.post.api.models.protos.threadList.ThreadListRequestData
import com.huanchengfly.tieba.post.api.models.protos.threadList.ThreadListResponse
import com.huanchengfly.tieba.post.api.models.protos.userPost.UserPostRequest
import com.huanchengfly.tieba.post.api.models.protos.userPost.UserPostRequestData
import com.huanchengfly.tieba.post.api.models.protos.userPost.UserPostResponse
import com.huanchengfly.tieba.post.utils.helios.Base32
import com.huanchengfly.tieba.post.utils.helios.Hasher
import com.squareup.wire.Message
import java.net.URLEncoder
import java.net.URL
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.text.DateFormat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import java.util.concurrent.ThreadLocalRandom
import kotlin.math.roundToInt
import okhttp3.Interceptor
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import org.jsoup.Jsoup
import org.json.JSONObject
import retrofit2.Call
import retrofit2.Retrofit
import retrofit2.converter.wire.WireConverterFactory
import retrofit2.http.Body
import retrofit2.http.Header
import retrofit2.http.Headers
import retrofit2.http.POST

/**
 * Read-only Tieba mobile protocol adapter derived from TiebaLite commit
 * 910fd564c47f77ab6a807f1bc122279e7b9aa0b1.
 *
 * It deliberately excludes TiebaLite's in-app posting endpoint. Replies are
 * dispatched to the official client by [AndroidTiebaApi].
 */
internal class TiebaProtoClient(
    context: Context,
    private val logs: RuntimeLogStore,
    baseUrl: String = TIEBA_PROTO_BASE_URL,
) {
    private val appContext = context.applicationContext
    private val identity = TiebaProtoIdentity(appContext)
    private val requests = TiebaProtoRequestFactory(appContext, identity)
    private val api: TiebaProtoApi = Retrofit.Builder()
        .baseUrl(baseUrl)
        .client(
            OkHttpClient.Builder()
                .connectTimeout(java.time.Duration.ofSeconds(20))
                .readTimeout(java.time.Duration.ofSeconds(20))
                .addInterceptor(tiebaProtoHeaders(identity, logs))
                .build(),
        )
        .addConverterFactory(WireConverterFactory.create())
        .validateEagerly(true)
        .build()
        .create(TiebaProtoApi::class.java)

    fun forum(
        name: String,
        page: Long,
        sort: String,
        goodOnly: Boolean,
        cookie: String,
        uid: Long,
    ): ForumPageDto {
        val requestedPage = page.coerceAtLeast(1).toInt()
        val credentials = credentials(cookie, uid)
        val sortType = if (sort == "post") 1 else 0
        val response = execute(
            "FRS",
            api.forum(
                requests.forum(
                    page = requestedPage,
                    sortType = sortType,
                    goodOnly = goodOnly,
                    loadType = if (requestedPage == 1) 1 else 2,
                    credentials = credentials,
                    forumName = name,
                ),
                TiebaProtoRequestFactory.encodedForumName(name),
            ),
        )
        response.requireSuccess("FRS")
        val hydrated = hydrateForumThreads(response, requestedPage, sortType, credentials, name)
        return mapForum(hydrated, requestedPage, name)
    }

    fun thread(
        threadId: String,
        forumId: Long,
        forumName: String,
        page: Long,
        sort: String,
        onlyOriginalPoster: Boolean,
        cookie: String,
        uid: Long,
    ): ThreadPageDto {
        val tid = threadId.toLongOrNull()?.takeIf { it > 0 } ?: error("无效的帖子 ID")
        val requestedPage = page.coerceAtLeast(1).toInt()
        val credentials = credentials(cookie, uid)
        val sortType = when (sort) {
            "desc" -> 1
            "hot" -> 2
            else -> 0
        }
        val response = execute(
            "PB",
            api.thread(
                requests.thread(
                    threadId = tid,
                    page = requestedPage,
                    sortType = sortType,
                    onlyOriginalPoster = onlyOriginalPoster,
                    credentials = credentials,
                    forumId = forumId,
                ),
                credentials?.uid?.toString(),
            ),
        )
        response.requireSuccess("PB")
        return mapThread(response, tid, requestedPage, forumId, forumName)
    }

    fun floorReplies(
        threadId: String,
        postId: String,
        page: Long,
        forumId: Long,
        forumName: String,
        cookie: String,
        uid: Long,
    ): FloorReplyPageDto {
        val tid = threadId.toLongOrNull()?.takeIf { it > 0 } ?: error("无效的帖子 ID")
        val pid = postId.toLongOrNull()?.takeIf { it > 0 } ?: error("无效的楼层 ID")
        val credentials = credentials(cookie, uid)
        val response = execute(
            "PB_FLOOR",
            api.floor(
                requests.floor(
                    threadId = tid,
                    postId = pid,
                    page = page.coerceAtLeast(1).toInt(),
                    credentials = credentials,
                    forumId = forumId,
                ),
                credentials?.uid?.toString(),
            ),
        )
        response.requireSuccess("PB_FLOOR")
        val data = response.data_ ?: error("贴吧楼中楼响应缺少数据")
        requireExpectedForum(data.forum?.id, data.forum?.name, forumId, forumName)
        val replies = data.subpost_list.map { mapReply(it) }.distinctBy { reply ->
            reply.id.ifBlank { "${reply.authorName}:${reply.time}:${reply.content}" }
        }
        val responsePage = data.page
        val currentPage = responsePage?.current_page?.takeIf { it > 0 }
            ?: page.coerceAtLeast(1).toInt()
        val totalPages = responsePage?.total_page?.coerceAtLeast(currentPage) ?: currentPage
        val totalReplies = responsePage?.total_count?.coerceAtLeast(replies.size) ?: replies.size
        return FloorReplyPageDto(
            replies,
            currentPage.toLong(),
            totalPages.toLong(),
            totalReplies.toLong(),
        )
    }

    fun userProfile(uid: Long, cookie: String, accountUid: Long): TiebaUserProfileDto {
        require(uid > 0) { "无效的贴吧用户 ID" }
        val credentials = credentials(cookie, accountUid)
        val profile = execute(
            "PROFILE",
            api.profile(requests.profile(uid, credentials), credentials?.uid?.toString()),
        )
        profile.requireSuccess("PROFILE")
        val threads = loadUserPosts(uid, true, credentials)
        val replies = loadUserPosts(uid, false, credentials)
        return mapUserProfile(profile, threads, replies)
    }

    fun resolveOriginalImage(
        request: TiebaImageRequestDto,
        cookie: String,
        uid: Long,
    ): String {
        val source = java.net.URI(request.url)
        require(source.scheme == "https" && !source.host.isNullOrBlank()) { "只允许 HTTPS 贴吧图片" }
        val picId = source.path.substringAfterLast('/').substringBeforeLast('.').takeIf(String::isNotBlank)
            ?: error("无法识别贴吧图片 ID")
        val metrics = appContext.resources.displayMetrics
        val fields = linkedMapOf(
            "forum_id" to request.forumId.toString(),
            "kw" to request.forumName,
            "tid" to request.threadId.toString(),
            "pic_id" to picId,
            "pic_index" to request.imageIndex.toString(),
            "obj_type" to "pb",
            "page_name" to "PB",
            "next" to "10",
            "scr_h" to metrics.heightPixels.toString(),
            "scr_w" to metrics.widthPixels.toString(),
            "q_type" to "2",
            "prev" to "0",
            "not_see_lz" to if (request.seeOriginalPosterOnly) "0" else "1",
            "_client_id" to identity.clientId,
            "_client_type" to "2",
            "_client_version" to TIEBA_MINI_VERSION,
            "_os_version" to Build.VERSION.SDK_INT.toString(),
            "_model" to Build.MODEL,
            "_net_type" to "1",
            "_phone_imei" to "",
            "_timestamp" to System.currentTimeMillis().toString(),
            "cuid" to identity.cuid,
            "cuid_galaxy2" to identity.cuid,
            "from" to "1021636m",
            "subapp_type" to "mini",
        )
        credentials(cookie, uid)?.let { credentials ->
            fields["BDUSS"] = credentials.bduss
            fields["user_id"] = credentials.uid.toString()
        }
        val timing = ThreadLocalRandom.current().nextInt(100, 850)
        if (timing in 100..120) {
            fields["stErrorNums"] = "0"
        } else {
            fields["stErrorNums"] = "1"
            fields["stMethod"] = "1"
            fields["stMode"] = "1"
            fields["stTimesNum"] = "1"
            fields["stTime"] = timing.toString()
            fields["stSize"] = ((Math.random() * 8 + 0.4) * timing).roundToInt().toString()
        }
        fields["sign"] = miniTiebaSign(fields)
        val connection = URL(TIEBA_MINI_PIC_URL).openConnection() as java.net.HttpURLConnection
        connection.requestMethod = "POST"
        connection.connectTimeout = 20_000
        connection.readTimeout = 20_000
        connection.doOutput = true
        connection.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
        connection.setRequestProperty("User-Agent", identity.userAgent)
        connection.outputStream.use { output ->
            output.write(
                fields.toSortedMap().entries.joinToString("&") { entry ->
                    "${URLEncoder.encode(entry.key, "UTF-8")}" +
                        "=${URLEncoder.encode(entry.value, "UTF-8")}"
                }.toByteArray(),
            )
        }
        val status = connection.responseCode
        val stream = if (status in 200..299) connection.inputStream else connection.errorStream
        val body = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
        logs.append("tieba-pb", "PIC_PAGE -> HTTP $status")
        check(status in 200..299) { "贴吧原图接口失败（HTTP $status）" }
        val envelope = JSONObject(body)
        check(envelope.optString("error_code", "-1") == "0") {
            "贴吧原图接口失败（错误码 ${envelope.optString("error_code")}）"
        }
        val pictures = envelope.optJSONArray("pic_list") ?: error("贴吧原图响应缺少图片")
        val picture = (0 until pictures.length()).map(pictures::getJSONObject).firstOrNull { item ->
            item.optJSONObject("img")?.optJSONObject("original")?.optString("id") == picId
        } ?: (0 until pictures.length()).map(pictures::getJSONObject).firstOrNull { item ->
            item.optString("overall_index").toLongOrNull() == request.imageIndex
        } ?: error("贴吧原图响应未包含目标图片")
        val original = picture.getJSONObject("img").getJSONObject("original")
        val byteSize = original.optString("size").toLongOrNull() ?: 0
        val width = original.optString("width").toIntOrNull() ?: 0
        val height = original.optString("height").toIntOrNull() ?: 0
        val resolved = when {
            original.optString("format") == "2" -> original.optString("waterurl")
            byteSize >= 2L * 1024L * 1024L && width > 0 && height > width * 3 ->
                original.optString("big_cdn_src")
            else -> original.optString("waterurl")
        }.ifBlank {
            sequenceOf("original_src", "url", "big_cdn_src")
                .map(original::optString).firstOrNull(String::isNotBlank).orEmpty()
        }.let(::normalizeUrl)
        check(isAuthorizedTiebaImage(resolved)) { "贴吧原图地址无效" }
        return resolved
    }

    fun forumRule(forumId: Long, cookie: String, uid: Long): String {
        require(forumId > 0) { "无效的贴吧 ID" }
        val credentials = credentials(cookie, uid)
        val response = execute(
            "FORUM_RULE",
            api.forumRule(requests.forumRule(forumId, credentials)),
        )
        val code = response.error?.error_code ?: 0
        check(code == 0) { "贴吧吧规接口失败（错误码 $code）" }
        val data = response.data_ ?: error("贴吧吧规响应缺少数据")
        return buildString {
            if (data.title.isNotBlank()) appendLine(data.title)
            if (data.preface.isNotBlank()) appendLine(data.preface)
            data.rules.forEach { rule ->
                if (rule.title.isNotBlank()) appendLine(rule.title)
                val content = rule.content.toContentDtos().plainText()
                if (content.isNotBlank()) appendLine(content)
            }
        }.trim().ifBlank { "该吧未提供公开吧规。" }
    }

    private fun loadUserPosts(
        uid: Long,
        isThread: Boolean,
        credentials: TiebaProtoCredentials?,
    ): List<TiebaUserPostDto> {
        val response = execute(
            if (isThread) "USER_THREAD" else "USER_REPLY",
            api.userPosts(
                requests.userPosts(uid, 1, isThread, credentials),
                credentials?.uid?.toString(),
            ),
        )
        response.requireSuccess("USER_POST")
        val raw = response.data_?.post_list.orEmpty()
        return if (isThread) raw.map(::mapUserThread) else raw.flatMap(::mapUserReplies)
    }

    private fun hydrateForumThreads(
        response: FrsPageResponse,
        page: Int,
        sortType: Int,
        credentials: TiebaProtoCredentials?,
        forumName: String,
    ): FrsPageResponse {
        val data = response.data_ ?: return response
        val forum = data.forum ?: return response
        val ids = data.thread_id_list.filter { it > 0 }.distinct()
        if (ids.isEmpty()) return response
        val hydratedThreads = data.thread_list.toMutableList()
        val hydratedUsers = data.user_list.toMutableList()
        ids.chunked(30).forEach { batch ->
            val result = execute(
                "FRS_THREAD_LIST",
                api.forumThreads(
                    requests.forumThreads(
                        forumId = forum.id,
                        forumName = forumName,
                        page = page,
                        sortType = sortType,
                        threadIds = batch,
                        credentials = credentials,
                    ),
                ),
            )
            result.requireSuccess("FRS thread list")
            result.data_?.let { threadData ->
                hydratedThreads += threadData.thread_list
                hydratedUsers += threadData.user_list
            }
        }
        return response.copy(
            data_ = data.copy(
                thread_list = hydratedThreads.distinctBy { it.threadId.takeIf { id -> id > 0 } ?: it.id },
                user_list = hydratedUsers.distinctBy(User::id),
            ),
        )
    }

    private fun mapForum(
        response: FrsPageResponse,
        requestedPage: Int,
        requestedForumName: String,
    ): ForumPageDto {
        val data = response.data_ ?: error("贴吧列表响应缺少数据")
        val forum = data.forum ?: error("贴吧列表响应缺少吧信息")
        requireRequestedForum(forum.name, requestedForumName)
        val users = data.user_list.associateBy(User::id)
        val page = data.page ?: error("贴吧列表响应缺少分页信息")
        val threads = data.thread_list.mapNotNull { source ->
            if (source.ala_info != null) return@mapNotNull null
            mapForumThread(source, users, forum.id, forum.name)
        }.distinctBy(ForumThreadDto::id)
        check(threads.isNotEmpty()) { "贴吧移动协议未返回可显示帖子" }
        return ForumPageDto(
            ForumSummaryDto(
                forum.id.toString(),
                forum.name,
                normalizeUrl(forum.avatar),
                forum.member_num.toString(),
                forum.thread_num.toString(),
                data.forum_rule?.title.orEmpty(),
                forum.is_like == 1,
                forum.sign_in_info?.user_info?.is_sign_in == 1,
                (forum.sign_in_info?.user_info?.cont_sign_num ?: 0).toLong(),
            ),
            threads,
            (page.current_page.takeIf { it > 0 } ?: requestedPage).toLong(),
            page.has_more == 1 || page.total_page > requestedPage,
        )
    }

    private fun mapForumThread(
        source: ThreadInfo,
        users: Map<Long, User>,
        fallbackForumId: Long,
        fallbackForumName: String,
    ): ForumThreadDto? {
        val id = source.threadId.takeIf { it > 0 } ?: source.id.takeIf { it > 0 } ?: return null
        val author = users[source.authorId] ?: source.author
        val content = source.richAbstract.toContentDtos()
        val images = buildList {
            source.media.forEach { media ->
                sequenceOf(media.originPic, media.bigPic, media.srcPic)
                    .firstOrNull(String::isNotBlank)?.let { add(normalizeUrl(it)) }
            }
            content.filter { it.kind == "image" }.forEach { add(it.originalUrl) }
        }.filter(String::isNotBlank).distinct()
        return ForumThreadDto(
            id.toString(),
            source.title.ifBlank { "无标题" },
            content.plainText().ifBlank { source._abstract.joinToString("") { it.text }.plainText() },
            author?.name.orEmpty(),
            author?.nameShow.orEmpty().ifBlank { author?.name.orEmpty() },
            author?.id ?: source.authorId,
            portraitUrl(author?.portrait.orEmpty()),
            replyCount(source.replyNum).toString(),
            source.viewNum.toString(),
            source.lastTime,
            source.isTop == 1,
            source.isGood == 1,
            images,
            source.forumInfo?.id?.takeIf { it > 0 } ?: source.forumId.takeIf { it > 0 } ?: fallbackForumId,
            source.forumInfo?.name.orEmpty().ifBlank { source.forumName }.ifBlank { fallbackForumName },
            author?.moderatorRole() ?: TiebaModeratorRole.NONE,
        )
    }

    private fun mapThread(
        response: PbPageResponse,
        threadId: Long,
        requestedPage: Int,
        expectedForumId: Long,
        expectedForumName: String,
    ): ThreadPageDto {
        val data = response.data_ ?: error("贴吧帖子响应缺少数据")
        val forum = data.forum ?: error("贴吧帖子响应缺少吧信息")
        requireExpectedForum(forum.id, forum.name, expectedForumId, expectedForumName)
        val page = data.page ?: error("贴吧帖子响应缺少分页信息")
        val thread = data.thread ?: error("贴吧帖子响应缺少主题信息")
        val users = data.user_list.associateBy(User::id)
        val container = data.top_agree_post_list?.post_list.orEmpty() +
            data.hot_post_list?.post_list.orEmpty() +
            data.hot_post_list?.hot_post_list.orEmpty().map { it.toPost(users) } +
            data.post_list
        val merged = linkedMapOf<Long, Post>()
        container.forEach { if (it.id > 0) merged[it.id] = it }
        val originalAuthorId = thread.author?.id ?: data.first_floor_post?.author_id ?: 0
        val mapped = merged.values.map { mapPost(it, users, originalAuthorId) }
        val body = data.first_floor_post?.let { mapPost(it, users, originalAuthorId) }
            ?: mapped.firstOrNull { it.floor == 1L }
        val floors = mapped.filterNot { it.postId == body?.postId || it.floor == 1L }
        logs.append("tieba-pb", "PB thread=$threadId page=$requestedPage posts=${floors.size}")
        return ThreadPageDto(
            thread.title.ifBlank { "帖子" },
            body,
            floors,
            (page.current_page.takeIf { it > 0 } ?: requestedPage).toLong(),
            page.total_page.coerceAtLeast(requestedPage).toLong(),
            replyCount(thread.replyNum).toLong(),
        )
    }

    private fun mapPost(post: Post, users: Map<Long, User>, originalAuthorId: Long): ThreadFloorDto {
        val author = post.author ?: users[post.author_id] ?: User(id = post.author_id)
        return ThreadFloorDto(
            post.id.toString(),
            post.floor.toLong(),
            author.id,
            author.name,
            author.nameShow.ifBlank { author.name },
            portraitUrl(author.portrait),
            author.level_id.toLong(),
            author.level_name,
            author.ip_address.ifBlank { author.ip },
            author.moderatorRole(),
            formatEpoch(post.time.toLong()),
            post.content.toContentDtos(),
            post.sub_post_list?.sub_post_list.orEmpty().map { mapReply(it, users) },
            post.sub_post_number.toLong(),
            author.id > 0 && author.id == originalAuthorId,
        )
    }

    private fun mapReply(reply: SubPostList, users: Map<Long, User> = emptyMap()): FloorReplyDto {
        val author = reply.author ?: users[reply.author_id]
        return FloorReplyDto(
            reply.id.takeIf { it > 0 }?.toString().orEmpty(),
            author?.id ?: reply.author_id,
            author?.name.orEmpty(),
            author?.nameShow.orEmpty().ifBlank { author?.name.orEmpty() },
            portraitUrl(author?.portrait.orEmpty()),
            reply.content.toContentDtos(),
            formatEpoch(reply.time.toLong()),
            (author?.level_id ?: 0).toLong(),
            author?.level_name.orEmpty(),
            author?.ip_address.orEmpty().ifBlank { author?.ip.orEmpty() },
            author?.moderatorRole() ?: TiebaModeratorRole.NONE,
        )
    }

    private fun User.moderatorRole(): TiebaModeratorRole = when {
        is_manager == 1 ||
            (is_bawu == 1 && bawu_type.equals("manager", ignoreCase = true)) -> TiebaModeratorRole.OWNER
        is_bawu == 1 -> TiebaModeratorRole.ASSISTANT
        else -> TiebaModeratorRole.NONE
    }

    private fun mapUserProfile(
        response: ProfileResponse,
        threads: List<TiebaUserPostDto>,
        replies: List<TiebaUserPostDto>,
    ): TiebaUserProfileDto {
        val user = response.data_?.user ?: error("贴吧用户响应缺少用户信息")
        return TiebaUserProfileDto(
            user.id,
            user.name,
            user.nameShow.ifBlank { user.name },
            portraitUrl(user.portraith.ifBlank { user.portrait }),
            user.display_intro.ifBlank { user.intro },
            user.fans_num.toLong(),
            user.concern_num.toLong(),
            user.post_num.toLong(),
            threads,
            replies,
        )
    }

    private fun mapUserThread(post: PostInfoList): TiebaUserPostDto {
        val media = post.media.mapNotNull { item ->
            sequenceOf(item.originPic, item.bigPic, item.srcPic).firstOrNull(String::isNotBlank)
        }
        val rich = post.rich_abstract.toContentDtos()
        return TiebaUserPostDto(
            post.thread_id,
            post.post_id,
            post.title.ifBlank { "无标题" },
            rich.plainText().ifBlank { post._abstract.plainText() },
            formatEpoch(post.create_time.toLong()),
            post.forum_id,
            post.forum_name,
            post.reply_num.toLong(),
            false,
            (media.ifEmpty { rich.filter { it.kind == "image" }.map { it.originalUrl } })
                .map(::normalizeUrl).distinct(),
        )
    }

    private fun mapUserReplies(post: PostInfoList): List<TiebaUserPostDto> {
        if (post.content.isEmpty()) {
            return listOf(
                TiebaUserPostDto(
                    post.thread_id, post.post_id, post.title.ifBlank { "原帖" },
                    post._abstract.plainText(), formatEpoch(post.create_time.toLong()),
                    post.forum_id, post.forum_name, post.reply_num.toLong(), true, emptyList(),
                ),
            )
        }
        return post.content.map { item ->
            TiebaUserPostDto(
                post.thread_id, item.post_id, post.title.ifBlank { "原帖" },
                item.post_content.joinToString("") { it.text }.plainText(),
                formatEpoch(item.create_time), post.forum_id, post.forum_name,
                post.reply_num.toLong(), true, emptyList(),
            )
        }
    }

    private fun HotPost.toPost(users: Map<Long, User>): Post = Post(
        id = post_id,
        floor = floor,
        time = create_time,
        content = content,
        sub_post_number = post_num,
        author_id = user_id,
        author = users[user_id] ?: User(
            id = user_id,
            name = user_name,
            nameShow = user_name,
            portrait = portrait,
        ),
        post_zan = post_zan,
        is_hot_post = 1,
    )

    private fun credentials(cookie: String, uid: Long): TiebaProtoCredentials? {
        val bduss = cookie.cookieValue("BDUSS") ?: return null
        val stoken = cookie.cookieValue("STOKEN") ?: return null
        return TiebaProtoCredentials(uid.coerceAtLeast(0), bduss, stoken)
    }

    private fun <T> execute(name: String, call: Call<T>): T {
        val startedAt = System.nanoTime()
        val response = call.execute()
        val elapsed = (System.nanoTime() - startedAt) / 1_000_000
        logs.append("tieba-pb", "$name -> HTTP ${response.code()} ${elapsed}ms")
        check(response.isSuccessful) { "$name 请求失败（HTTP ${response.code()}）" }
        return response.body() ?: error("$name 响应为空")
    }
}

private data class TiebaProtoCredentials(
    val uid: Long,
    val bduss: String,
    val stoken: String,
)

private interface TiebaProtoApi {
    @Headers("X-Cithub-Tieba-Request: FRS")
    @POST("c/f/frs/page?cmd=301001")
    fun forum(@Body body: RequestBody, @Header("forum_name") forumName: String): Call<FrsPageResponse>

    @Headers("X-Cithub-Tieba-Request: FRS_THREAD_LIST")
    @POST("c/f/frs/threadlist?cmd=301002")
    fun forumThreads(@Body body: RequestBody): Call<ThreadListResponse>

    @Headers("X-Cithub-Tieba-Request: PB")
    @POST("c/f/pb/page?cmd=302001&format=protobuf")
    fun thread(@Body body: RequestBody, @Header("client_user_token") token: String?): Call<PbPageResponse>

    @Headers("X-Cithub-Tieba-Request: PB_FLOOR")
    @POST("c/f/pb/floor?cmd=302002&format=protobuf")
    fun floor(@Body body: RequestBody, @Header("client_user_token") token: String?): Call<PbFloorResponse>

    @Headers("X-Cithub-Tieba-Request: PROFILE")
    @POST("c/u/user/profile?cmd=303012&format=protobuf")
    fun profile(@Body body: RequestBody, @Header("client_user_token") token: String?): Call<ProfileResponse>

    @Headers("X-Cithub-Tieba-Request: USER_POST")
    @POST("c/u/feed/userpost?cmd=303002&format=protobuf")
    fun userPosts(@Body body: RequestBody, @Header("client_user_token") token: String?): Call<UserPostResponse>

    @Headers("X-Cithub-Tieba-Request: FORUM_RULE")
    @POST("c/f/forum/forumRuleDetail?cmd=309690&format=protobuf")
    fun forumRule(@Body body: RequestBody): Call<ForumRuleDetailResponse>
}

private class TiebaProtoIdentity(context: Context) {
    private val appContext = context.applicationContext
    private val androidId = Settings.Secure.getString(appContext.contentResolver, Settings.Secure.ANDROID_ID)
        .orEmpty().ifBlank { "000" }
    private val packageInfo = appContext.packageManager.getPackageInfo(appContext.packageName, 0)
    private val rawCuid = md5("com.baidu$androidId").uppercase(Locale.ROOT)
    val cuid: String = "$rawCuid|V${Base32.encode(Hasher.hash(rawCuid.toByteArray()))}"
    val aid: String = run {
        val uuid = UUID.nameUUIDFromBytes("$androidId:${appContext.packageName}".toByteArray()).toString()
        val encoded = Base32.encode(MessageDigest.getInstance("SHA-1").digest("com.helios$androidId$uuid".toByteArray()))
        val raw = "A00-$encoded-"
        "$raw${Base32.encode(Hasher.hash(raw.toByteArray()))}"
    }
    val clientId = "wappc_${packageInfo.firstInstallTime}_${rawCuid.take(6)}"
    val activeTimestamp: Long = packageInfo.firstInstallTime
    val firstInstallTime: Long = packageInfo.firstInstallTime
    val lastUpdateTime: Long = packageInfo.lastUpdateTime
    val userAgent: String = "$TIEBA_WEB_USER_AGENT tieba/$TIEBA_PROTO_VERSION"

    fun common(credentials: TiebaProtoCredentials?): CommonRequest {
        val metrics = appContext.resources.displayMetrics
        return CommonRequest(
            BDUSS = credentials?.bduss,
            _client_id = clientId,
            _client_type = 2,
            _client_version = TIEBA_PROTO_VERSION,
            _os_version = Build.VERSION.SDK_INT.toString(),
            _phone_imei = "000000000000000",
            _timestamp = System.currentTimeMillis(),
            active_timestamp = activeTimestamp,
            android_id = Base64.encodeToString(androidId.toByteArray(), Base64.DEFAULT),
            brand = Build.BRAND,
            c3_aid = aid,
            cmode = 1,
            cuid = cuid,
            cuid_galaxy2 = cuid,
            cuid_gid = "",
            event_day = SimpleDateFormat("yyyyMdd", Locale.getDefault()).format(Date()),
            extra = "",
            first_install_time = firstInstallTime,
            framework_ver = "3340042",
            from = "1020031h",
            is_teenager = 0,
            last_update_time = lastUpdateTime,
            lego_lib_version = "3.0.0",
            model = Build.MODEL,
            net_type = 1,
            oaid = "",
            personalized_rec_switch = 1,
            pversion = "1.0.3",
            q_type = 0,
            scr_dip = metrics.density.toDouble(),
            scr_h = metrics.heightPixels,
            scr_w = metrics.widthPixels,
            sdk_ver = "2.34.0",
            start_scheme = "",
            start_type = 1,
            stoken = credentials?.stoken,
            swan_game_ver = "1038000",
            user_agent = userAgent,
        )
    }

    private fun md5(value: String): String = MessageDigest.getInstance("MD5")
        .digest(value.toByteArray(StandardCharsets.UTF_8))
        .joinToString("") { "%02x".format(it) }
}

private class TiebaProtoRequestFactory(
    private val context: Context,
    private val identity: TiebaProtoIdentity,
) {
    private val metrics get() = context.resources.displayMetrics

    fun forum(
        page: Int,
        sortType: Int,
        goodOnly: Boolean,
        loadType: Int,
        credentials: TiebaProtoCredentials?,
        forumName: String,
    ): RequestBody = protobufBody(
        FrsPageRequest(
            FrsPageRequestData(
                ad_param = FrsAdParam(load_count = 0, refresh_count = 4, yoga_lib_version = "1.0"),
                app_pos = appPosition(),
                call_from = 0,
                category_id = 0,
                cid = 0,
                common = identity.common(credentials),
                ctime = 0,
                data_size = 0,
                hot_thread_id = 0,
                is_default_navtab = 0,
                is_good = if (goodOnly) 1 else 0,
                is_selection = 0,
                kw = encodedForumName(forumName),
                last_click_tid = 0,
                load_type = loadType,
                net_error = 0,
                pn = page,
                q_type = 2,
                rn = 90,
                rn_need = 30,
                scr_dip = metrics.density.toDouble(),
                scr_h = metrics.heightPixels,
                scr_w = metrics.widthPixels,
                sort_type = if (goodOnly) -1 else sortType,
                st_param = 0,
                st_type = "recom_flist",
                up_schema = "",
                with_group = 1,
                yuelaou_locate = "",
            ),
        ),
        credentials,
        true,
    )

    fun forumThreads(
        forumId: Long,
        forumName: String,
        page: Int,
        sortType: Int,
        threadIds: List<Long>,
        credentials: TiebaProtoCredentials?,
    ): RequestBody = protobufBody(
        ThreadListRequest(
            ThreadListRequestData(
                ad_param = ThreadListAdParam(load_count = 3, refresh_count = 0),
                app_pos = appPosition(),
                common = identity.common(credentials),
                forum_id = forumId,
                forum_name = forumName,
                last_click_tid = 0,
                need_abstract = 0,
                pn = page,
                q_type = 2,
                scr_dip = metrics.density.toDouble(),
                scr_h = metrics.heightPixels,
                scr_w = metrics.widthPixels,
                sort_type = sortType,
                st_type = 0,
                thread_ids = threadIds.joinToString(","),
                user_id = credentials?.uid,
            ),
        ),
        credentials,
        true,
    )

    fun thread(
        threadId: Long,
        page: Int,
        sortType: Int,
        onlyOriginalPoster: Boolean,
        credentials: TiebaProtoCredentials?,
        forumId: Long,
    ): RequestBody = protobufBody(
        PbPageRequest(
            PbPageRequestData(
                common = identity.common(credentials),
                kz = threadId,
                pid = 0,
                pn = page,
                r = sortType,
                lz = if (onlyOriginalPoster) 1 else 0,
                forum_id = forumId,
                ad_param = PbAdParam(load_count = 0, refresh_count = 1, is_req_ad = 1),
                app_pos = appPosition(),
                floor_rn = 4,
                floor_sort_type = 1,
                obj_locate = "",
                obj_param1 = "10",
                obj_source = "",
                q_type = 2,
                rn = 15,
                source_type = 2,
                st_type = "",
                with_floor = 1,
            ),
        ),
        credentials,
        true,
    )

    fun floor(
        threadId: Long,
        postId: Long,
        page: Int,
        credentials: TiebaProtoCredentials?,
        forumId: Long,
    ): RequestBody = protobufBody(
        PbFloorRequest(
            PbFloorRequestData(
                common = identity.common(credentials),
                forum_id = forumId,
                kz = threadId,
                pid = postId,
                pn = page,
                spid = 0,
                scr_dip = metrics.density.toDouble(),
                scr_h = metrics.heightPixels,
                scr_w = metrics.widthPixels,
                is_comm_reverse = 0,
                ori_ugc_type = 0,
            ),
        ),
        credentials,
        false,
    )

    fun profile(uid: Long, credentials: TiebaProtoCredentials?): RequestBody {
        val self = credentials?.uid == uid
        return protobufBody(
            ProfileRequest(
                ProfileRequestData(
                    uid = credentials?.uid,
                    need_post_count = 1,
                    friend_uid = uid.takeUnless { self },
                    is_guest = if (self) 0 else 1,
                    pn = 1,
                    rn = 20,
                    has_plist = 1,
                    common = identity.common(credentials),
                    scr_w = metrics.widthPixels,
                    scr_h = metrics.heightPixels,
                    q_type = 0,
                    scr_dip = metrics.density.toDouble(),
                    is_from_usercenter = 1,
                    page = 1,
                    friend_uid_portrait = "",
                ),
            ),
            credentials,
            true,
        )
    }

    fun userPosts(
        uid: Long,
        page: Int,
        isThread: Boolean,
        credentials: TiebaProtoCredentials?,
    ): RequestBody = protobufBody(
        UserPostRequest(
            UserPostRequestData(
                uid = uid,
                rn = 20,
                is_thread = if (isThread) 1 else 0,
                need_content = 1,
                subtype = 0.takeUnless { isThread },
                pn = page,
                common = identity.common(credentials),
                scr_w = metrics.widthPixels,
                scr_h = metrics.heightPixels,
                scr_dip = metrics.density.toDouble(),
                q_type = 1,
                is_view_card = if (isThread) 1 else 0,
            ),
        ),
        credentials,
        true,
    )

    fun forumRule(forumId: Long, credentials: TiebaProtoCredentials?): RequestBody = protobufBody(
        ForumRuleDetailRequest(
            ForumRuleDetailRequestData(
                forum_id = forumId,
                common = identity.common(credentials),
            ),
        ),
        credentials,
        true,
    )

    private fun appPosition() = AppPosInfo(
        addr_timestamp = 0,
        ap_connected = true,
        ap_mac = "02:00:00:00:00:00",
        asp_shown_info = "",
        coordinate_type = "BD09LL",
    )

    private fun protobufBody(
        message: Message<*, *>,
        credentials: TiebaProtoCredentials?,
        includeStoken: Boolean,
    ): RequestBody = MultipartBody.Builder(TIEBA_PROTO_BOUNDARY)
        .setType(MultipartBody.FORM)
        .apply {
            if (includeStoken && credentials != null) addFormDataPart("stoken", credentials.stoken)
            addFormDataPart("data", "file", message.encode().toRequestBody())
        }
        .build()

    companion object {
        fun encodedForumName(name: String): String = URLEncoder.encode(name, StandardCharsets.UTF_8.name())
    }
}

private fun tiebaProtoHeaders(
    identity: TiebaProtoIdentity,
    logs: RuntimeLogStore,
) = Interceptor { chain ->
    val trace = chain.request().header("X-Cithub-Tieba-Request").orEmpty()
    val request = chain.request().newBuilder()
        .removeHeader("X-Cithub-Tieba-Request")
        .header("Charset", "UTF-8")
        .header("client_type", "2")
        .header("cookie", "ka:open; CUID:${identity.cuid}; TBBRAND:${Build.MODEL}")
        .header("cuid", identity.cuid)
        .header("cuid_galaxy2", identity.cuid)
        .header("cuid_gid", "")
        .header("c3_aid", identity.aid)
        .header("User-Agent", identity.userAgent)
        .header("x_bd_data_type", "protobuf")
        .build()
    try {
        chain.proceed(request)
    } catch (error: Throwable) {
        logs.append("tieba-pb", "$trace failed: ${error.javaClass.simpleName}: ${error.message}")
        throw error
    }
}

private fun List<PbContent>.toContentDtos(): List<TiebaContentDto> = mapNotNull { item ->
    val dimensions = item.dimensions()
    when (item.type) {
        0, 4, 9, 27, 35, 40 -> item.text.takeIf(String::isNotEmpty)?.let {
            TiebaContentDto("text", it, "", "", 0, 0)
        }
        1 -> TiebaContentDto("link", item.text.ifBlank { item.link }, normalizeUrl(item.link), "", 0, 0)
        2 -> TiebaContentDto("emoticon", item.c.ifBlank { item.text.ifBlank { "表情" } }, "", "", 0, 0)
        3, 20 -> {
            val preview = sequenceOf(item.bigCdnSrc, item.cdnSrcActive, item.cdnSrc, item.bigSrc, item.src, item.originSrc)
                .firstOrNull(String::isNotBlank).orEmpty()
            val original = sequenceOf(item.originSrc, item.bigCdnSrc, item.bigSrc, item.cdnSrcActive, item.cdnSrc, item.src)
                .firstOrNull(String::isNotBlank).orEmpty()
            preview.takeIf(String::isNotBlank)?.let {
                TiebaContentDto(
                    "image", "", normalizeUrl(preview), normalizeUrl(original.ifBlank { preview }),
                    dimensions.first.toLong(), dimensions.second.toLong(),
                )
            }
        }
        5 -> {
            val video = sequenceOf(item.link, item.src).firstOrNull { value ->
                value.startsWith("http") && (value.contains(".mp4") || value.contains(".m3u8"))
            }
            if (video == null) {
                TiebaContentDto("text", "[视频]${item.text}", "", "", 0, 0)
            } else {
                TiebaContentDto(
                    "video", "", normalizeUrl(video), normalizeUrl(item.src),
                    dimensions.first.toLong(), dimensions.second.toLong(),
                )
            }
        }
        10 -> TiebaContentDto("text", "[语音]", "", "", 0, 0)
        else -> item.text.takeIf(String::isNotEmpty)?.let { TiebaContentDto("text", it, "", "", 0, 0) }
    }
}

private fun PbContent.dimensions(): Pair<Int, Int> {
    val parsed = bsize.split(',').mapNotNull(String::toIntOrNull)
    return if (parsed.size >= 2) parsed[0].coerceAtLeast(0) to parsed[1].coerceAtLeast(0)
    else width.coerceAtLeast(0) to height.coerceAtLeast(0)
}

private fun List<TiebaContentDto>.plainText(): String = joinToString("") { item ->
    when (item.kind) {
        "text", "link" -> item.text
        "emoticon" -> "#(${item.text})"
        "video" -> "[视频]"
        else -> ""
    }
}.trim()

private fun String.plainText(): String = Jsoup.parse(replace("<br/>", "\n")).text()

private fun normalizeUrl(raw: String): String = when {
    raw.startsWith("//") -> "https:$raw"
    raw.startsWith("http://") -> "https://${raw.removePrefix("http://")}" 
    raw.startsWith("https://") -> raw
    else -> ""
}

private fun portraitUrl(portrait: String): String = when {
    portrait.isBlank() -> ""
    portrait.startsWith("http") || portrait.startsWith("//") -> normalizeUrl(portrait)
    else -> "https://himg.bdimg.com/sys/portrait/item/${portrait.substringBefore('?')}.jpg"
}

private fun replyCount(totalPosts: Int): Int = (totalPosts - 1).coerceAtLeast(0)

private fun formatEpoch(seconds: Long): String = if (seconds <= 0) "" else DateFormat.getDateTimeInstance(
    DateFormat.SHORT,
    DateFormat.SHORT,
).format(Date(seconds * 1000))

private fun String.cookieValue(name: String): String? = split(';').firstNotNullOfOrNull { part ->
    val separator = part.indexOf('=')
    if (separator <= 0 || !part.substring(0, separator).trim().equals(name, ignoreCase = true)) null
    else part.substring(separator + 1).trim().takeIf(String::isNotBlank)
}

private fun requireRequestedForum(actualName: String, expectedName: String) {
    check(actualName.canonicalForumName() == expectedName.canonicalForumName()) { "贴吧响应与请求名称不匹配" }
}

private fun requireExpectedForum(actualId: Long?, actualName: String?, expectedId: Long, expectedName: String) {
    val idMatches = expectedId <= 0 || actualId == expectedId
    val nameMatches = expectedName.isBlank() || actualName.orEmpty().canonicalForumName() == expectedName.canonicalForumName()
    check(idMatches && nameMatches) { "帖子不属于当前贴吧" }
}

private fun String.canonicalForumName(): String = trim().removeSuffix("吧")

internal fun miniTiebaSign(fields: Map<String, String>): String {
    val raw = fields.asSequence()
        .filter { it.key != "sign" }
        .map { "${it.key}=${it.value}" }
        .sorted()
        .joinToString("") + TIEBA_MINI_SECRET
    return MessageDigest.getInstance("MD5")
        .digest(raw.toByteArray(StandardCharsets.UTF_8))
        .joinToString("") { byte -> "%02x".format(Locale.ROOT, byte) }
}

private fun isAuthorizedTiebaImage(raw: String): Boolean =
    raw.startsWith("https://") &&
        (!raw.contains("/forum/pic/item/") || raw.contains("tbpicau="))

private fun FrsPageResponse.requireSuccess(kind: String) {
    val code = error?.error_code ?: 0
    check(code == 0) { "$kind 接口失败（错误码 $code）" }
}

private fun ThreadListResponse.requireSuccess(kind: String) {
    val code = error?.error_code ?: 0
    check(code == 0) { "$kind 接口失败（错误码 $code）" }
}

private fun PbPageResponse.requireSuccess(kind: String) {
    val code = error?.error_code ?: 0
    check(code == 0) { "$kind 接口失败（错误码 $code）" }
}

private fun PbFloorResponse.requireSuccess(kind: String) {
    val code = error?.error_code ?: 0
    check(code == 0) { "$kind 接口失败（错误码 $code）" }
}

private fun ProfileResponse.requireSuccess(kind: String) {
    val code = error?.error_code ?: 0
    check(code == 0) { "$kind 接口失败（错误码 $code）" }
}

private fun UserPostResponse.requireSuccess(kind: String) {
    val code = error?.error_code ?: 0
    check(code == 0) { "$kind 接口失败（错误码 $code）" }
}

private const val TIEBA_PROTO_BASE_URL = "https://tiebac.baidu.com/"
private const val TIEBA_PROTO_VERSION = "22.8.5.0"
private const val TIEBA_PROTO_BOUNDARY = "--------7da3d81520810*"
private const val TIEBA_MINI_VERSION = "7.2.0.0"
private const val TIEBA_MINI_SECRET = "tiebaclient!!!"
private const val TIEBA_MINI_PIC_URL = "https://c.tieba.baidu.com/c/f/pb/picpage"
private const val TIEBA_WEB_USER_AGENT =
    "Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36"
