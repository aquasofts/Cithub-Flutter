package com.aquasofts.cithub_flutter

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NativePoliciesTest {
    @Test
    fun `reply dispatch matches official Tieba routes`() {
        assertEquals(
            "com.baidu.tieba://unidispatch/pb?obj_locate=pb_reply&obj_source=wise&obj_name=index&obj_param2=chrome&has_token=0&qd=scheme&refer=tieba.baidu.com&wise_sample_id=3000232_2-99999_9&fr=bpush&tid=123",
            TiebaOfficialReplyUri.build(123, null),
        )
        assertEquals(
            "com.baidu.tieba://unidispatch/pb?obj_locate=comment_lzl_cut_guide&obj_source=wise&obj_name=index&obj_param2=chrome&has_token=0&qd=scheme&refer=tieba.baidu.com&wise_sample_id=3000232_2&hightlight_anchor_pid=456&is_anchor_to_comment=1&comment_sort_type=0&fr=bpush&tid=123",
            TiebaOfficialReplyUri.build(123, 456),
        )
    }

    @Test
    fun `release policy only accepts exact version and flavor`() {
        assertTrue(ReleaseAssetPolicy.accepts(
            "Cithub-Flutter-1.0.0-auto-captcha-performance.apk",
            "1.0.0",
            true,
        ))
        assertFalse(ReleaseAssetPolicy.accepts(
            "Cithub-Flutter-1.0.0-manual-captcha-performance.apk",
            "1.0.0",
            true,
        ))
        assertFalse(ReleaseAssetPolicy.accepts(
            "Cithub-Flutter-1.0.1-auto-captcha-performance.apk",
            "1.0.0",
            true,
        ))
    }

    @Test
    fun `release policy extracts only exact SHA256 manifest entry`() {
        val expected = "a".repeat(64)
        val manifest = """
            ${"b".repeat(64)}  Cithub-Flutter-1.0.1-manual-captcha-performance.apk
            $expected *Cithub-Flutter-1.0.1-auto-captcha-performance.apk
        """.trimIndent()
        assertEquals(
            expected,
            ReleaseAssetPolicy.sha256ForAsset(
                manifest,
                "Cithub-Flutter-1.0.1-auto-captcha-performance.apk",
            ),
        )
        assertEquals(null, ReleaseAssetPolicy.sha256ForAsset(manifest, "missing.apk"))
        assertTrue(ReleaseAssetPolicy.isSha256(expected))
        assertFalse(ReleaseAssetPolicy.isSha256("not-a-hash"))
    }

    @Test
    fun `version policy only accepts a strictly newer semantic version`() {
        assertTrue(ReleaseVersionPolicy.isNewer("1.0.1", "1.0.0"))
        assertTrue(ReleaseVersionPolicy.isNewer("2.0.0", "1.99.99"))
        assertTrue(ReleaseVersionPolicy.isNewer("1.0.0", "1.0.0-rc.2"))
        assertFalse(ReleaseVersionPolicy.isNewer("1.0.0", "1.0.0"))
        assertFalse(ReleaseVersionPolicy.isNewer("1.0.0-rc.1", "1.0.0"))
        assertTrue(ReleaseVersionPolicy.isNewer("1.0.0-rc.10", "1.0.0-rc.2"))
    }
}
