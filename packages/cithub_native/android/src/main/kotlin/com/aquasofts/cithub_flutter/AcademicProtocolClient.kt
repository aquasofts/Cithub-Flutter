package com.aquasofts.cithub_flutter

import com.aquasofts.cithub_flutter.native.AcademicTermDto
import com.aquasofts.cithub_flutter.native.CourseGradeDto
import com.aquasofts.cithub_flutter.native.EvaluationAnswerDto
import com.aquasofts.cithub_flutter.native.EvaluationBatchDto
import com.aquasofts.cithub_flutter.native.EvaluationCourseDto
import com.aquasofts.cithub_flutter.native.EvaluationFormDto
import com.aquasofts.cithub_flutter.native.EvaluationHiddenFieldDto
import com.aquasofts.cithub_flutter.native.EvaluationOptionDto
import com.aquasofts.cithub_flutter.native.EvaluationQuestionDto
import com.aquasofts.cithub_flutter.native.SelectedCourseDto
import com.aquasofts.cithub_flutter.native.TimetableCourseDto
import com.aquasofts.cithub_flutter.native.TimetableDto
import com.aquasofts.cithub_flutter.native.TimetablePeriodDto
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.time.LocalDate
import java.util.Base64
import org.json.JSONObject
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element

internal class AcademicLoginRequired(message: String) : IllegalStateException(message)

internal object AcademicServerRouter {
    const val STORE_KEY = "academic.base_url"
    private const val DEFAULT_BASE_URL =
        "https://http-10-198-47-148-8080.webvpn.ccit.edu.cn/jsxsd/"

    fun baseUrl(store: SecretStore): String =
        store.get(STORE_KEY)?.let(::normalize) ?: DEFAULT_BASE_URL

    fun remember(store: SecretStore, candidate: String): String? = normalize(candidate)?.also {
        store.put(STORE_KEY, it)
    }

    private fun normalize(candidate: String): String? = runCatching {
        val parsed = URL(candidate.trim())
        val path = parsed.path.trimEnd('/')
        if (parsed.protocol != "https" ||
            !parsed.host.endsWith(".webvpn.ccit.edu.cn", ignoreCase = true) ||
            !path.endsWith("/jsxsd", ignoreCase = true)
        ) return@runCatching null
        URL(parsed.protocol, parsed.host, parsed.port, "$path/").toString()
    }.getOrNull()
}

internal fun JSONObject.findAcademicBaseUrl(): String? {
    val groups = optJSONObject("data")?.optJSONArray("list") ?: return null
    for (groupIndex in 0 until groups.length()) {
        val sites = groups.optJSONObject(groupIndex)?.optJSONArray("sites") ?: continue
        for (siteIndex in 0 until sites.length()) {
            val site = sites.optJSONObject(siteIndex) ?: continue
            val name = site.optString("name")
            val url = site.optString("url")
            if (name.contains("教务") && url.contains("/jsxsd", ignoreCase = true)) return url
        }
    }
    return null
}

internal class AcademicProtocolClient(
    private val store: SecretStore,
    private val logs: RuntimeLogStore,
    baseUrl: String? = null,
) {
    private val automaticServerRouting = baseUrl == null
    @Volatile private var baseUrl = (baseUrl ?: AcademicServerRouter.baseUrl(store)).let {
        if (it.endsWith('/')) it else "$it/"
    }
    @Volatile private var timetableSchemeId: String? = null

    fun refreshServerRoute(): Boolean {
        if (!automaticServerRouting) return false
        val next = AcademicServerRouter.baseUrl(store)
        if (next == baseUrl) return false
        baseUrl = next
        timetableSchemeId = null
        return true
    }

    fun webOrigin(): String = baseUrl.substringBefore("/jsxsd/") + "/"

    fun initialize(): List<AcademicTermDto>? {
        val html = get("kscj/cjcx_query", "连接教务系统失败")
        if (isLoginPage(html)) return null
        return parseTerms(Jsoup.parse(html), "kksj").ifEmpty {
            error("无法识别教务系统的学期列表，页面结构可能已更新")
        }
    }

    fun loadCaptcha(): String {
        val response = request("verifycode.servlet?ts=${System.currentTimeMillis()}")
        check(response.status in 200..299 && response.bytes.isNotEmpty()) { "教务系统未返回验证码图片" }
        return Base64.getEncoder().encodeToString(response.bytes)
    }

    fun login(username: String, password: String, captchaCode: String): List<AcademicTermDto> {
        require(username.isNotBlank()) { "请输入教务系统账号" }
        require(password.isNotBlank()) { "请输入教务系统密码" }
        require(captchaCode.isNotBlank()) { "请输入教务系统验证码" }
        val encoded = Base64.getEncoder().encodeToString(username.toByteArray()) + "%%%" +
            Base64.getEncoder().encodeToString(password.toByteArray())
        val response = request(
            "xk/LoginToXk",
            method = "POST",
            form = mapOf(
                "userAccount" to "",
                "userPassword" to "",
                "RANDOMCODE" to captchaCode.trim(),
                "encoded" to encoded,
            ),
            followRedirects = false,
        )
        val location = response.location.orEmpty().substringBefore('?').trimEnd('/')
        // Tomcat may return an absolute URL, /jsxsd/... or a path relative to
        // the current /jsxsd/ context.  All three are the same successful
        // login redirect.
        val successful = response.status in 300..399 &&
            location.endsWith("framework/xsMain.jsp", ignoreCase = true)
        if (!successful) {
            val document = Jsoup.parse(response.text)
            val alert = Regex("alert\\s*\\(\\s*['\"]([^'\"]+)['\"]").find(response.text)?.groupValues?.get(1)
            throw AcademicLoginRequired(alert ?: document.selectFirst("#showMsg, [id^=error]")?.text()
            ?: "教务系统账号、密码或验证码错误")
        }
        return initialize() ?: throw AcademicLoginRequired("教务系统登录未建立")
    }

    fun loadGrades(term: String, bestOnly: Boolean): List<CourseGradeDto> {
        val html = get("kscj/cjcx_list?kksj=${encode(term)}&xsfs=${if (bestOnly) "max" else "all"}", "加载成绩失败")
        requireSession(html)
        return Jsoup.parse(html).select("table#dataList tr").mapNotNull { row ->
            val cells = row.select("td").map(Element::text)
            if (cells.size < 20) return@mapNotNull null
            CourseGradeDto(
                cells[0], cells[1], cells[2], cells[3], cells[4], cells[5], cells[6],
                cells[7], cells[8], cells[9], cells[10], cells[11], cells[12], cells[13],
                cells[14], cells[15], cells[16], cells[17], cells[18], cells[19],
            )
        }
    }

    fun loadSelectionTerms(): List<AcademicTermDto> {
        val html = get("xkgl/xsxkjgcx", "加载选课结果查询条件失败")
        requireSession(html)
        return parseTerms(Jsoup.parse(html), "xnxqid")
    }

    fun loadSelectionResults(term: String): List<SelectedCourseDto> {
        val html = post("xkgl/loadXsxkjgList", mapOf("xnxqid" to term), "加载选课结果失败")
        requireSession(html)
        return Jsoup.parse(html).select("tr").mapNotNull { row ->
            val cells = row.select("td").map(Element::text)
            if (cells.size < 8) return@mapNotNull null
            SelectedCourseDto(cells[0], cells[1], cells[2], cells[3], cells[4], cells[5], cells[6], cells[7])
        }
    }

    fun loadEvaluationBatches(): List<EvaluationBatchDto> {
        val html = get("xspj/xspj_find.do", "加载学生评价批次失败")
        requireSession(html)
        return Jsoup.parse(html.replace(Regex("<!--.*?-->", RegexOption.DOT_MATCHES_ALL), ""))
            .select("tr").mapNotNull { row ->
                val cells = row.select("td").map(Element::text)
                val path = row.selectFirst("a[href]")?.attr("href")
                if (cells.size < 7 || path.isNullOrBlank()) return@mapNotNull null
                EvaluationBatchDto(cells[0], cells[1], cells[2], cells[3], cells[4], cells[5], path)
            }
    }

    fun loadEvaluationCourses(path: String): List<EvaluationCourseDto> {
        val html = get(safePath(path), "加载待评价课程失败")
        requireSession(html)
        return Jsoup.parse(html).select("table#dataList tr").mapNotNull { row ->
            val cells = row.select("td").map(Element::text)
            val formPath = row.selectFirst("a[href]")?.attr("href")
            if (cells.size < 9 || formPath.isNullOrBlank()) return@mapNotNull null
            EvaluationCourseDto(
                cells[0], cells[1], cells[2], cells[3], cells[4], cells[5],
                cells[6] == "是", cells[7] == "是", cells[8], formPath,
            )
        }
    }

    fun loadEvaluationForm(path: String): EvaluationFormDto {
        val html = get(safePath(path), "加载课程评价表失败")
        requireSession(html)
        val document = Jsoup.parse(html)
        val form = document.select("form").firstOrNull { it.attr("action").contains("xspj_save.do") }
            ?: error("无法识别课程评价表，页面结构可能已更新")
        val hidden = form.select("input[type=hidden][name]").map {
            EvaluationHiddenFieldDto(it.attr("name"), it.attr("value"))
        }
        val scores = hidden.filter { it.name.startsWith("pj0601fz_") }
            .associate { it.name to it.value }
        val questions = form.select("tr").mapNotNull { row ->
            val id = row.selectFirst("input[name=pj06xh]")?.attr("value") ?: return@mapNotNull null
            val options = row.select("input[type=radio][name=pj0601id_$id]").map { input ->
                val optionId = input.attr("value")
                val label = input.nextSibling()?.toString()?.let { Jsoup.parseBodyFragment(it).text() }.orEmpty()
                EvaluationOptionDto(
                    optionId,
                    label,
                    scores["pj0601fz_${id}_$optionId"].orEmpty(),
                    input.hasAttr("checked"),
                )
            }
            if (options.isEmpty()) return@mapNotNull null
            EvaluationQuestionDto(id, row.selectFirst("td")?.text().orEmpty(), options)
        }
        val textarea = form.selectFirst("textarea[name]")
        val heading = Regex("课程名称\\s*[：:]\\s*(.*?)\\s+评教大类\\s*[：:]\\s*(.*?)(?:<|$)", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL))
            .find(html)
        return EvaluationFormDto(
            heading?.groupValues?.getOrNull(1)?.let { Jsoup.parse(it).text() }.orEmpty(),
            heading?.groupValues?.getOrNull(2)?.let { Jsoup.parse(it).text() }.orEmpty(),
            form.attr("action"),
            hidden,
            questions,
            textarea?.attr("name"),
            textarea?.text().orEmpty(),
            form.select("[onclick*=saveData]").isEmpty(),
        )
    }

    fun saveEvaluation(
        form: EvaluationFormDto,
        answers: List<EvaluationAnswerDto>,
        suggestion: String,
        submit: Boolean,
    ): Boolean {
        check(!form.readOnly) { "该评价已提交，不能再修改" }
        val selected = answers.associate { it.questionId to it.optionId }
        check(form.questions.all { selected[it.id].orEmpty().isNotBlank() }) { "请完成每一项评价指标" }
        val fields = linkedMapOf<String, String>()
        form.hiddenFields.filterNot { it.name == "issubmit" || it.name == "sfxyt" }
            .forEach { fields[it.name] = it.value }
        form.questions.forEach { fields["pj0601id_${it.id}"] = selected.getValue(it.id) }
        form.suggestionField?.let { fields[it] = suggestion }
        fields["issubmit"] = if (submit) "1" else "0"
        fields["sfxyt"] = "0"
        val html = post(safePath(form.actionPath), fields, if (submit) "提交学生评价失败" else "保存学生评价失败")
        requireSession(html)
        return true
    }

    fun loadTimetable(term: String?): TimetableDto {
        var html = get("xskb/xskb_list.do", "加载理论课表失败")
        requireSession(html)
        var parsed = parseTimetable(html)
        timetableSchemeId = parsed.schemeId.ifBlank { timetableSchemeId.orEmpty() }
        if (!term.isNullOrBlank() && term != parsed.dto.selectedTerm) {
            html = post("xskb/xskb_list.do", mapOf(
                "jx0404id" to "", "cj0701id" to "", "zc" to "", "demo" to "",
                "xnxq01id" to term, "sfFD" to "1", "kbjcmsid" to timetableSchemeId.orEmpty(),
            ), "加载理论课表失败")
            parsed = parseTimetable(html)
        }
        // The student home page is the authoritative source for the calendar
        // date, weekday, and teaching week.  The full timetable page is kept as
        // a fallback because the home page can legitimately have no classes.
        val today = LocalDate.now()
        val homeTimetable = runCatching {
            val weekHtml = post("framework/main_index_loadkb.jsp", mapOf(
                "rq" to today.toString(), "sjmsValue" to parsed.schemeId,
            ), "加载教学周失败")
            requireSession(weekHtml)
            val week = parseTeachingWeek(weekHtml)
            val courses = parseHomeTimetable(weekHtml, today.dayOfWeek.value)
            week to courses
        }.getOrElse { error ->
            if (error is AcademicLoginRequired) throw error
            null
        }
        val teachingWeek = homeTimetable?.first
        val homeCourses = homeTimetable?.second.orEmpty()
        val expectedTodayCourses = parsed.dto.courses.filter { course ->
            course.dayOfWeek == today.dayOfWeek.value.toLong() &&
                (teachingWeek?.first == null ||
                    course.weekNumbers.isEmpty() || course.weekNumbers.contains(teachingWeek.first))
        }
        return TimetableDto(
            parsed.dto.terms, parsed.dto.selectedTerm, parsed.dto.periods,
            homeCourses.ifEmpty { expectedTodayCourses }, parsed.dto.note,
            today.toString(), teachingWeek?.first, teachingWeek?.second,
        )
    }

    fun webPageUrl(path: String): String = baseUrl + safePath(path)

    fun cookieHeader(): String = store.get(COOKIE_KEY).orEmpty()

    fun logout() {
        val current = cookieHeader().split(';').map(String::trim)
            .filterNot { it.startsWith("JSESSIONID=") }
            .joinToString("; ")
        if (current.isBlank()) store.remove(COOKIE_KEY) else store.put(COOKIE_KEY, current)
    }

    private data class ParsedTimetable(val dto: TimetableDto, val schemeId: String)

    private fun parseTimetable(html: String): ParsedTimetable {
        val document = Jsoup.parse(html)
        val rows = document.select("table#kbtable tr")
        check(rows.size >= 2) { "无法识别理论课表，页面结构可能已更新" }
        val periods = mutableListOf<TimetablePeriodDto>()
        val courses = mutableListOf<TimetableCourseDto>()
        rows.drop(1).forEachIndexed { rowIndex, row ->
            val cells = row.select(":scope > th, :scope > td")
            if (cells.size < 8) return@forEachIndexed
            val periodIndex = rowIndex + 1L
            val periodText = cells[0].text()
            val time = Regex("(\\d{1,2}:\\d{2})\\s*-\\s*(\\d{1,2}:\\d{2})").find(periodText)
            periods += TimetablePeriodDto(
                periodIndex,
                periodText.substringBefore(time?.value.orEmpty()).trim().ifBlank { "第${periodIndex}大节" },
                time?.groupValues?.get(1).orEmpty(),
                time?.groupValues?.get(2).orEmpty(),
            )
            cells.drop(1).take(7).forEachIndexed { day, cell ->
                courses += parseTimetableCell(cell, day + 1L, periodIndex)
            }
        }
        val terms = parseTerms(document, "xnxq01id")
        val selected = terms.firstOrNull { it.selected }?.value ?: terms.firstOrNull()?.value.orEmpty()
        val scheme = document.selectFirst("select[name=kbjcmsid] option[selected]")?.attr("value")
            ?.ifBlank { null }
            ?: document.selectFirst("select[name=kbjcmsid] option")?.attr("value")
            ?.ifBlank { null }
            ?: document.selectFirst("input[name=kbjcmsid]")?.attr("value").orEmpty()
        return ParsedTimetable(TimetableDto(terms, selected, periods, courses, "", null, null, null), scheme)
    }

    private fun parseTimetableCell(cell: Element, day: Long, period: Long): List<TimetableCourseDto> {
        // This system uses both kbcontent and kbcontent1.  The latter is the
        // visible class in the captured production response.
        return cell.select("div[class*=kbcontent]")
            .flatMap { content ->
                content.html().split(
                    Regex("(?:<br\\s*/?>\\s*)?-{5,}(?:\\s*<br\\s*/?>)?", RegexOption.IGNORE_CASE),
                ).mapNotNull { parseCourseMarkup(it, day, period) }
            }
            .groupBy { "${it.name}|${it.weeks}|${it.location}|${it.startSection}|${it.endSection}" }
            .values
            .map { alternatives ->
                alternatives.maxBy { course ->
                    (if (course.teacher.isBlank()) 0 else 1) +
                        (if (course.location.isBlank()) 0 else 1)
                }
            }
    }

    private fun parseHomeTimetable(html: String, dayOfWeek: Int): List<TimetableCourseDto> {
        val table = Jsoup.parse(html).selectFirst("table.kb_table") ?: return emptyList()
        val headers = table.select("thead th").map(Element::text)
        val column = headers.indexOfFirst { it.contains("星期${weekdayName(dayOfWeek)}") }
        if (column < 1) return emptyList()
        return table.select("tbody tr").flatMapIndexed { index, row ->
            val cells = row.select(":scope > th, :scope > td")
            val period = index + 1L
            cells.getOrNull(column)?.let { parseTimetableCell(it, dayOfWeek.toLong(), period) }.orEmpty()
        }
    }

    private fun parseCourseMarkup(markup: String, day: Long, period: Long): TimetableCourseDto? {
        val block = Jsoup.parseBodyFragment(markup).body()
        val details = block.select("font[title]").associate { it.attr("title") to it.text() }
        val clone = block.clone().also { it.select("font[title]").remove() }
        val name = clone.text().removeSuffix("P").trim()
        if (name.isBlank()) return null
        val weeksAndSections = details["周次(节次)"].orEmpty()
        val section = Regex("(?:\\[|（)(\\d{1,2})\\s*[-~,，]\\s*(\\d{1,2})(?:节|小节)?(?:\\]|）)").find(weeksAndSections)
        val start = section?.groupValues?.get(1)?.toLongOrNull() ?: period * 2 - 1
        val end = section?.groupValues?.get(2)?.toLongOrNull() ?: period * 2
        val weeks = weeksAndSections.replace(
            Regex("(?:\\[|（)\\d{1,2}\\s*[-~,，]\\s*\\d{1,2}(?:节|小节)?(?:\\]|）)"), "",
        ).trim()
        val location = details["教室"].orEmpty()
        return TimetableCourseDto(
            "$day-$period-$name-$weeks-$location", day, period, start, end,
            name, details["老师"].orEmpty(), weeks, parseWeeks(weeks), location,
        )
    }

    private fun parseTeachingWeek(html: String): Pair<Long, Long>? =
        Regex("第\\s*(\\d+)\\s*周.*?/(\\d+)\\s*周", RegexOption.DOT_MATCHES_ALL)
            .find(html)?.let { it.groupValues[1].toLong() to it.groupValues[2].toLong() }

    private fun weekdayName(dayOfWeek: Int): String = "一二三四五六日".getOrNull(dayOfWeek - 1)?.toString().orEmpty()

    private fun parseWeeks(source: String): List<Long> {
        val rangeText = source.substringBefore("(周").substringBefore("（周")
        val odd = source.contains("单")
        val even = source.contains("双")
        return Regex("(\\d+)(?:\\s*-\\s*(\\d+))?").findAll(rangeText).flatMap { match ->
            val start = match.groupValues[1].toLong()
            val end = match.groupValues[2].toLongOrNull() ?: start
            (start..end).asSequence()
        }.filter { (!odd || it % 2L == 1L) && (!even || it % 2L == 0L) }.distinct().toList()
    }

    private fun parseTerms(document: Document, name: String): List<AcademicTermDto> =
        document.select("select[name=$name] option").map {
            AcademicTermDto(it.attr("value"), it.text(), it.hasAttr("selected"))
        }.filter { it.label.isNotBlank() }

    private fun get(path: String, message: String): String {
        val response = request(path)
        check(response.status in 200..299) { "$message（HTTP ${response.status}）" }
        return response.text
    }

    private fun post(path: String, form: Map<String, String>, message: String): String {
        val response = request(path, "POST", form)
        check(response.status in 200..299) { "$message（HTTP ${response.status}）" }
        return response.text
    }

    private data class Response(val status: Int, val location: String?, val bytes: ByteArray) {
        val text: String get() = bytes.toString(Charsets.UTF_8)
    }

    private fun request(
        path: String,
        method: String = "GET",
        form: Map<String, String>? = null,
        followRedirects: Boolean = true,
    ): Response {
        val safePath = if (path.startsWith(baseUrl)) path.removePrefix(baseUrl) else safePath(path)
        val connection = URL(baseUrl + safePath).openConnection() as HttpURLConnection
        connection.requestMethod = method
        connection.connectTimeout = 20_000
        connection.readTimeout = 20_000
        connection.instanceFollowRedirects = followRedirects
        connection.setRequestProperty("User-Agent", BROWSER_USER_AGENT)
        connection.setRequestProperty("Accept-Language", "zh-CN,zh;q=0.9")
        cookieHeader().takeIf(String::isNotBlank)?.let { connection.setRequestProperty("Cookie", it) }
        if (form != null) {
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
            connection.outputStream.use { output ->
                output.write(form.entries.joinToString("&") { "${encode(it.key)}=${encode(it.value)}" }.toByteArray())
            }
        }
        val status = connection.responseCode
        mergeCookies(connection.headerFields.entries
            .firstOrNull { it.key?.equals("set-cookie", true) == true }?.value.orEmpty())
        val stream = if (status in 200..399) connection.inputStream else connection.errorStream
        val bytes = stream?.use { it.readBytes() } ?: byteArrayOf()
        logs.append("academic", "$method /jsxsd/$safePath -> HTTP $status")
        return Response(status, connection.getHeaderField("Location"), bytes)
    }

    @Synchronized
    private fun mergeCookies(headers: List<String>) {
        if (headers.isEmpty()) return
        val cookies = linkedMapOf<String, String>()
        cookieHeader().split(';').map(String::trim).filter { it.contains('=') }.forEach {
            cookies[it.substringBefore('=')] = it.substringAfter('=')
        }
        headers.forEach { raw ->
            val pair = raw.substringBefore(';').trim()
            if (pair.contains('=')) cookies[pair.substringBefore('=')] = pair.substringAfter('=')
            if (raw.contains("Max-Age=0", ignoreCase = true) ||
                raw.contains("expires=Thu, 01 Jan 1970", ignoreCase = true)
            ) {
                cookies.remove(pair.substringBefore('='))
            }
        }
        val value = cookies.entries.joinToString("; ") { "${it.key}=${it.value}" }
        if (value.isBlank()) store.remove(COOKIE_KEY) else store.put(COOKIE_KEY, value)
    }

    private fun requireSession(html: String) {
        if (isLoginPage(html)) throw AcademicLoginRequired("教务系统登录已过期，请重新登录")
    }

    private fun isLoginPage(html: String): Boolean = html.contains("LoginToXk", true) ||
        html.contains("verifycode.servlet", true) ||
        (html.contains("userAccount", true) && html.contains("RANDOMCODE", true)) ||
        (html.contains("browser-compatibility", true) && html.contains("WebVPN", true))

    private fun safePath(path: String): String {
        val normalized = path.substringAfter("/jsxsd/", path).trimStart('/')
        require(!normalized.startsWith("http", true) && !normalized.contains("..")) { "教务系统返回了无效页面地址" }
        return normalized
    }

    private fun encode(value: String): String = URLEncoder.encode(value, Charsets.UTF_8.name())

    private companion object {
        const val COOKIE_KEY = "webvpn.session.cookies"
        const val BROWSER_USER_AGENT = "Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Mobile Safari/537.36"
    }
}
