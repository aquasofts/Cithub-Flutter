package com.aquasofts.cithub_flutter

import com.aquasofts.cithub_flutter.native.FloorReplyDto
import com.aquasofts.cithub_flutter.native.FloorReplyPageDto
import com.aquasofts.cithub_flutter.native.ForumPageDto
import com.aquasofts.cithub_flutter.native.ForumSummaryDto
import com.aquasofts.cithub_flutter.native.ForumThreadDto
import com.aquasofts.cithub_flutter.native.ThreadFloorDto
import com.aquasofts.cithub_flutter.native.ThreadPageDto
import com.aquasofts.cithub_flutter.native.TiebaAccountDto
import com.aquasofts.cithub_flutter.native.TiebaContentDto
import com.aquasofts.cithub_flutter.native.TiebaModeratorRole
import com.aquasofts.cithub_flutter.native.TiebaUserPostDto
import com.aquasofts.cithub_flutter.native.TiebaUserProfileDto
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import org.json.JSONObject
import org.jsoup.Jsoup
import org.jsoup.nodes.Element

internal class TiebaWebClient(private val logs: RuntimeLogStore) {
    fun profile(cookie: String): Pair<TiebaAccountDto, String> {
        val response = getJson("https://tieba.baidu.com/mo/q/newmoindex?need_user=1", cookie)
        check(response.optInt("no", -1) == 0) { response.optString("error", "贴吧登录状态无效") }
        val data = response.optJSONObject("data") ?: error("贴吧未返回账号信息")
        check(data.optBoolean("is_login")) { "贴吧登录状态无效" }
        val account = TiebaAccountDto(
            data.optLong("uid"),
            data.optString("name"),
            data.optString("name_show", data.optString("name")),
            https(data.optString("portrait_url")),
            data.optString("intro"),
            data.optString("fans_num", "0"),
            data.optString("post_num", "0"),
            data.optString("concern_num", "0"),
        )
        return account to data.optString("itb_tbs", data.optString("tbs"))
    }

    fun forum(name: String, page: Long, sort: String, goodOnly: Boolean, cookie: String): ForumPageDto {
        val pn = (page.coerceAtLeast(1) - 1) * 50
        val url = buildString {
            append("https://tieba.baidu.com/f?kw=").append(encode(name))
            append("&ie=utf-8&pn=").append(pn)
            if (goodOnly) append("&tab=good")
            if (sort == "post") append("&st=new")
        }
        val document = Jsoup.parse(get(url, cookie))
        val forumId = document.selectFirst("input#forum_id")?.attr("value")
            ?: document.selectFirst("[data-fid]")?.attr("data-fid")
            ?: "0"
        val member = document.selectFirst("span.card_menNum")?.text().orEmpty()
        val posts = document.selectFirst("span.card_infoNum")?.text().orEmpty()
        val followed = document.selectFirst("a.cancel_focus, a.islike_focus") != null
        val threads = document.select("li.j_thread_list, div.j_thread_list").mapNotNull { element ->
            val titleLink = element.selectFirst("a.j_th_tit, a[href*=/p/]") ?: return@mapNotNull null
            val id = Regex("/p/(\\d+)").find(titleLink.attr("href"))?.groupValues?.get(1)
                ?: dataObject(element).optString("id")
            if (id.isBlank()) return@mapNotNull null
            val data = dataObject(element)
            val author = data.optString("author_name",
                element.selectFirst("[data-field*=user_name]")?.attr("title").orEmpty())
            val images = element.select("img.threadlist_pic").mapNotNull { image ->
                https(image.absUrl("src").ifBlank { image.attr("src") }).takeIf(String::isNotBlank)
            }
            ForumThreadDto(
                id,
                titleLink.text().ifBlank { "无标题" },
                element.selectFirst(".threadlist_abs, .threadlist_text")?.text().orEmpty(),
                author,
                author,
                data.optLong("author_id"),
                "",
                data.optString("reply_num", element.selectFirst(".threadlist_rep_num")?.text().orEmpty()),
                "",
                element.selectFirst(".threadlist_reply_date")?.text().orEmpty(),
                element.hasClass("thread_top_list_folder") || element.selectFirst(".icon-top") != null,
                element.selectFirst(".icon-good, .j_good_icon") != null,
                images,
                forumId.toLongOrNull() ?: 0,
                name,
                data.moderatorRole(),
            )
        }
        check(threads.isNotEmpty()) { "贴吧页面未返回帖子，可能需要登录或页面结构已更新" }
        val hasMore = document.selectFirst("a.next, a[href*=pn]:matchesOwn(下一页)") != null
        return ForumPageDto(
            ForumSummaryDto(
                forumId,
                name,
                "",
                member,
                posts,
                document.selectFirst(".forum_rule, .rules")?.text().orEmpty(),
                followed,
                false,
                0,
            ),
            threads,
            page,
            hasMore,
        )
    }

    fun search(name: String, keyword: String, page: Long, cookie: String): ForumPageDto {
        val url = "https://tieba.baidu.com/mo/q/search/thread?word=${encode(keyword)}&pn=$page&st=1&tt=1&rn=30&fname=${encode(name)}&ct=2&cv=12.80.1.0&referer=${encode("https://tieba.baidu.com/f?kw=$name")}" 
        val envelope = getJson(url, cookie)
        check(envelope.optInt("no", -1) == 0) { envelope.optString("error", "贴吧搜索失败") }
        val data = envelope.optJSONObject("data") ?: error("贴吧搜索未返回数据")
        val posts = data.optJSONArray("post_list")
        val threads = if (posts == null) emptyList() else (0 until posts.length()).map { index ->
            val post = posts.getJSONObject(index)
            val user = post.optJSONObject("user") ?: JSONObject()
            val forumInfo = post.optJSONObject("forum_info") ?: JSONObject()
            ForumThreadDto(
                post.optString("tid"), post.optString("title", "无标题"),
                Jsoup.parse(post.optString("content")).text(), user.optString("user_name"),
                user.optString("show_nickname", user.optString("user_name")), user.optLong("user_id"),
                portrait(user.optString("portrait")), post.optString("post_num"), "",
                post.optLong("time").takeIf { it > 0 }?.let { java.time.Instant.ofEpochSecond(it).toString() }.orEmpty(),
                false, false, emptyList(), post.optLong("forum_id"),
                post.optString("forum_name", forumInfo.optString("forum_name", name)),
                TiebaModeratorRole.NONE,
            )
        }
        return ForumPageDto(
            ForumSummaryDto("0", name, "", "", "", "", false, false, 0),
            threads,
            page,
            data.optInt("has_more") == 1,
        )
    }

    fun thread(
        threadId: String,
        forumId: Long,
        forumName: String,
        page: Long,
        sort: String,
        onlyOriginalPoster: Boolean,
        cookie: String,
    ): ThreadPageDto {
        val url = "https://tieba.baidu.com/p/$threadId?pn=$page${if (onlyOriginalPoster) "&see_lz=1" else ""}${if (sort == "desc") "&sort=1" else ""}"
        val document = Jsoup.parse(get(url, cookie))
        val title = document.selectFirst("h1.core_title_txt")?.attr("title")
            ?: document.title().substringBefore("_")
        val floors = document.select("div.l_post").mapNotNull { element -> parseFloor(element, threadId) }
        check(floors.isNotEmpty()) { "帖子页面未返回楼层，可能已删除或页面结构已更新" }
        val totalPages = document.select("li.l_reply_num span.red").getOrNull(1)?.text()?.toLongOrNull()
            ?: document.select("a[href*=pn]").mapNotNull { Regex("[?&]pn=(\\d+)").find(it.attr("href"))?.groupValues?.get(1)?.toLongOrNull() }.maxOrNull()
            ?: page
        val replies = document.selectFirst("li.l_reply_num span.red")?.text()?.toLongOrNull() ?: 0
        return ThreadPageDto(title, floors.first(), floors.drop(1), page, totalPages, replies)
    }

    fun floorReplies(threadId: String, postId: String, page: Long, cookie: String): FloorReplyPageDto {
        val html = get("https://tieba.baidu.com/p/comment?tid=$threadId&pid=$postId&pn=$page", cookie)
        val document = Jsoup.parse(html)
        val replies = document.select("li.lzl_single_post").mapNotNull { element ->
            val data = dataObject(element)
            val id = data.optString("spid", data.optString("post_id"))
            if (id.isBlank()) return@mapNotNull null
            val author = data.optString("user_name", element.selectFirst("a.j_user_card")?.text().orEmpty())
            FloorReplyDto(
                id, data.optLong("user_id"), author, author,
                portrait(data.optString("portrait")), listOf(text(element.selectFirst(".lzl_content_main")?.text().orEmpty())),
                element.selectFirst(".lzl_time")?.text().orEmpty(),
                data.optLong("level_id"),
                data.optString("level_name"),
                data.optString("ip_address", data.optString("ip")),
                data.moderatorRole(),
            )
        }
        val totalPages = document.select("a[href*=pn]").mapNotNull { link ->
            Regex("[?&]pn=(\\d+)").find(link.attr("href"))?.groupValues?.get(1)?.toLongOrNull()
        }.maxOrNull()?.coerceAtLeast(page) ?: page
        val totalReplies = sequenceOf(
            document.selectFirst(".lzl_cnt")?.text(),
            document.selectFirst("[data-total-count]")?.attr("data-total-count"),
            document.selectFirst("[data-total]")?.attr("data-total"),
        ).filterNotNull().mapNotNull { value ->
            Regex("\\d+").find(value)?.value?.toLongOrNull()
        }.firstOrNull()?.coerceAtLeast(replies.size.toLong()) ?: replies.size.toLong()
        return FloorReplyPageDto(replies, page, totalPages, totalReplies)
    }

    fun userProfile(uid: Long, cookie: String): TiebaUserProfileDto {
        val document = Jsoup.parse(get("https://tieba.baidu.com/home/main?id=$uid&fr=pb", cookie))
        val name = document.selectFirst(".userinfo_username")?.text().orEmpty().ifBlank { "贴吧用户 $uid" }
        val intro = document.selectFirst(".userinfo_userdata span")?.text().orEmpty()
        return TiebaUserProfileDto(uid, name, name, "", intro, 0, 0, 0, emptyList<TiebaUserPostDto>(), emptyList())
    }

    fun sign(name: String, tbs: String, cookie: String): String {
        check(tbs.isNotBlank()) { "贴吧签到凭据无效，请重新登录" }
        val result = postJson(
            "https://tieba.baidu.com/sign/add",
            mapOf("ie" to "utf-8", "kw" to name, "tbs" to tbs),
            cookie,
            "https://tieba.baidu.com/f?kw=${encode(name)}&ie=utf-8",
        )
        val code = result.optInt("no", -1)
        val message = result.opt("error")?.toString().orEmpty()
        val days = result.optJSONObject("data")?.optJSONObject("uinfo")?.optInt("cont_sign_num")
        return when {
            code == 0 -> days?.let { "已签${it}天" } ?: "签到成功"
            code == 1101 || message.contains("已签") -> days?.let { "已签${it}天" } ?: "今日已经签到"
            else -> error(message.ifBlank { "贴吧签到失败（错误码 $code）" })
        }
    }

    fun follow(forumId: String, name: String, tbs: String, cookie: String): String {
        check(tbs.isNotBlank()) { "贴吧关注凭据无效，请重新登录" }
        val result = postJson(
            "https://tieba.baidu.com/mo/q/favolike",
            mapOf("cmd" to "add", "fid" to forumId, "kw" to name, "tbs" to tbs),
            cookie,
            "https://tieba.baidu.com/f?kw=${encode(name)}&ie=utf-8",
        )
        val code = result.optInt("no", result.optInt("error_code", -1))
        check(code == 0 || code == 1101) {
            result.optString("error", result.optString("error_msg", "贴吧关注失败（错误码 $code）"))
        }
        return "已关注 $name"
    }

    fun forumRule(name: String, cookie: String): String {
        val document = Jsoup.parse(get(
            "https://tieba.baidu.com/bawu2/platform/listBawuTeamInfo?word=${encode(name)}&ie=utf-8",
            cookie,
        ))
        return document.select(".rules, .forum_rule, .bawu_single_type").text()
            .ifBlank { "该吧未提供可读取的公开吧规。" }
    }

    private fun parseFloor(element: Element, threadId: String): ThreadFloorDto? {
        val data = dataObject(element)
        val author = data.optJSONObject("author") ?: JSONObject()
        val contentData = data.optJSONObject("content") ?: JSONObject()
        val postId = contentData.optString("post_id")
            .ifBlank { element.attr("data-pid") }
        if (postId.isBlank()) return null
        val contentElement = element.selectFirst("div.d_post_content")
        val contents = mutableListOf<TiebaContentDto>()
        contentElement?.let { node ->
            val clone = node.clone()
            clone.select("img").forEach { image ->
                val url = https(image.absUrl("src").ifBlank { image.attr("src") })
                if (url.isNotBlank()) contents += TiebaContentDto("image", "", url, url, 0, 0)
                image.remove()
            }
            if (clone.text().isNotBlank()) contents.add(0, text(clone.text()))
        }
        return ThreadFloorDto(
            postId,
            contentData.optLong("post_no"),
            author.optLong("user_id"),
            author.optString("user_name"),
            author.optString("user_nickname", author.optString("user_name")),
            portrait(author.optString("portrait")),
            author.optLong("level_id"),
            author.optString("level_name"),
            author.optString("ip_address", author.optString("ip")),
            author.moderatorRole(),
            contentData.optString("date", element.selectFirst(".tail-info:last-child")?.text().orEmpty()),
            contents.ifEmpty { listOf(text("")) },
            emptyList(),
            contentData.optLong("comment_num"),
            contentData.optLong("post_no") == 1L,
        )
    }

    private fun JSONObject.moderatorRole(): TiebaModeratorRole = when {
        optInt("is_manager") == 1 ||
            (optInt("is_bawu") == 1 && optString("bawu_type").equals("manager", ignoreCase = true)) ->
            TiebaModeratorRole.OWNER
        optInt("is_bawu") == 1 -> TiebaModeratorRole.ASSISTANT
        else -> TiebaModeratorRole.NONE
    }

    private fun getJson(url: String, cookie: String): JSONObject = JSONObject(get(url, cookie))

    private fun get(url: String, cookie: String): String {
        val connection = open(url, "GET", cookie)
        val status = connection.responseCode
        val stream = if (status in 200..299) connection.inputStream else connection.errorStream
        val body = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
        logs.append("tieba", "GET ${URL(url).path} -> HTTP $status")
        check(status in 200..299) { "贴吧请求失败（HTTP $status）" }
        return body
    }

    private fun postJson(url: String, form: Map<String, String>, cookie: String, referer: String): JSONObject {
        val connection = open(url, "POST", cookie)
        connection.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
        connection.setRequestProperty("Referer", referer)
        connection.doOutput = true
        connection.outputStream.use { output ->
            output.write(form.entries.joinToString("&") { "${encode(it.key)}=${encode(it.value)}" }.toByteArray())
        }
        val status = connection.responseCode
        val stream = if (status in 200..299) connection.inputStream else connection.errorStream
        val body = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
        logs.append("tieba", "POST ${URL(url).path} -> HTTP $status")
        check(status in 200..299) { "贴吧请求失败（HTTP $status）" }
        return JSONObject(body)
    }

    private fun open(url: String, method: String, cookie: String): HttpURLConnection =
        (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 20_000
            readTimeout = 20_000
            instanceFollowRedirects = true
            setRequestProperty("Accept", "application/json,text/html,*/*")
            setRequestProperty("Accept-Language", "zh-CN,zh;q=0.9")
            setRequestProperty("User-Agent", WEB_USER_AGENT)
            if (cookie.isNotBlank()) setRequestProperty("Cookie", cookie)
        }

    private fun dataObject(element: Element): JSONObject = runCatching {
        JSONObject(element.attr("data-field").ifBlank { "{}" })
    }.getOrDefault(JSONObject())

    private fun encode(value: String): String = URLEncoder.encode(value, Charsets.UTF_8.name())
    private fun text(value: String) = TiebaContentDto("text", value, "", "", 0, 0)
    private fun portrait(value: String): String = value.takeIf(String::isNotBlank)?.let {
        "https://himg.bdimg.com/sys/portrait/item/$it.jpg"
    }.orEmpty()
    private fun https(value: String): String = when {
        value.startsWith("//") -> "https:$value"
        value.startsWith("http://") -> "https://${value.removePrefix("http://")}"
        value.startsWith("https://") -> value
        else -> ""
    }

    private companion object {
        const val WEB_USER_AGENT = "Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36"
    }
}
