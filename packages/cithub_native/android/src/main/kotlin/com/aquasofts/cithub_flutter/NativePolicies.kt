package com.aquasofts.cithub_flutter

internal object TiebaOfficialReplyUri {
    fun build(threadId: Long, postId: Long?): String = if (postId != null) {
        "com.baidu.tieba://unidispatch/pb?obj_locate=comment_lzl_cut_guide&obj_source=wise&obj_name=index&obj_param2=chrome&has_token=0&qd=scheme&refer=tieba.baidu.com&wise_sample_id=3000232_2&hightlight_anchor_pid=$postId&is_anchor_to_comment=1&comment_sort_type=0&fr=bpush&tid=$threadId"
    } else {
        "com.baidu.tieba://unidispatch/pb?obj_locate=pb_reply&obj_source=wise&obj_name=index&obj_param2=chrome&has_token=0&qd=scheme&refer=tieba.baidu.com&wise_sample_id=3000232_2-99999_9&fr=bpush&tid=$threadId"
    }
}

internal object ReleaseAssetPolicy {
    fun expectedName(version: String, autoCaptcha: Boolean): String =
        "Cithub-Flutter-$version-${if (autoCaptcha) "auto" else "manual"}-captcha-performance.apk"

    fun accepts(name: String, version: String, autoCaptcha: Boolean): Boolean =
        name == expectedName(version, autoCaptcha)

    fun sha256ForAsset(manifest: String, assetName: String): String? = manifest
        .lineSequence()
        .map(String::trim)
        .filter(String::isNotEmpty)
        .mapNotNull { line ->
            val match = SHA256_LINE.matchEntire(line) ?: return@mapNotNull null
            match.groupValues[1].lowercase() to match.groupValues[2].substringAfterLast('/')
        }
        .firstOrNull { (_, name) -> name == assetName }
        ?.first

    fun isSha256(value: String?): Boolean = value != null && SHA256.matches(value)

    private val SHA256 = Regex("^[0-9a-fA-F]{64}$")
    private val SHA256_LINE = Regex("^([0-9a-fA-F]{64})\\s+\\*?(.+)$")
}

internal object ReleaseVersionPolicy {
    fun isNewer(candidate: String, current: String): Boolean = compare(candidate, current) > 0

    fun compare(left: String, right: String): Int {
        val a = parse(left)
        val b = parse(right)
        for (index in 0 until maxOf(a.core.size, b.core.size)) {
            val result = (a.core.getOrElse(index) { 0 }).compareTo(b.core.getOrElse(index) { 0 })
            if (result != 0) return result
        }
        if (a.preRelease.isEmpty() && b.preRelease.isNotEmpty()) return 1
        if (a.preRelease.isNotEmpty() && b.preRelease.isEmpty()) return -1
        for (index in 0 until maxOf(a.preRelease.size, b.preRelease.size)) {
            if (index >= a.preRelease.size) return -1
            if (index >= b.preRelease.size) return 1
            val leftPart = a.preRelease[index]
            val rightPart = b.preRelease[index]
            val leftNumber = leftPart.toLongOrNull()
            val rightNumber = rightPart.toLongOrNull()
            val result = when {
                leftNumber != null && rightNumber != null -> leftNumber.compareTo(rightNumber)
                leftNumber != null -> -1
                rightNumber != null -> 1
                else -> leftPart.compareTo(rightPart)
            }
            if (result != 0) return result
        }
        return 0
    }

    private fun parse(raw: String): ParsedVersion {
        val normalized = raw.trim().removePrefix("v").removePrefix("V").substringBefore('+')
        val coreRaw = normalized.substringBefore('-')
        require(coreRaw.matches(Regex("\\d+(?:\\.\\d+)*"))) { "无效的版本号：$raw" }
        return ParsedVersion(
            coreRaw.split('.').map(String::toLong),
            normalized.substringAfter('-', "").split('.').filter(String::isNotEmpty),
        )
    }

    private data class ParsedVersion(val core: List<Long>, val preRelease: List<String>)
}
