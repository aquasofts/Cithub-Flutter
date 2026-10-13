package com.aquasofts.cithub_flutter

import android.content.Context
import java.io.File
import java.util.zip.ZipFile
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class RuntimeLogStoreTest {
    @Test
    fun exportRetainsHistoryAcrossRestartWithoutTruncationOrRedaction() {
        val context = RuntimeEnvironment.getApplication() as Context
        val first = RuntimeLogStore(context)
        first.clear()
        val raw = "password=原始密码 Cookie=SESSION=secret\n" + "完整日志\n".repeat(2100) + "x".repeat(1100000)
        first.append("test", raw)
        File(context.filesDir, "logs/runtime.log.1").writeText("历史日志 Cookie=old")
        val second = RuntimeLogStore(context)
        second.append("test", "after restart")
        val archive = second.export()
        ZipFile(archive).use { zip ->
            val content = zip.getInputStream(zip.getEntry("runtime.log")).bufferedReader().readText()
            assertTrue(content.contains(raw))
            assertTrue(content.contains("after restart"))
            assertEquals("历史日志 Cookie=old", zip.getInputStream(zip.getEntry("runtime.log.1")).bufferedReader().readText())
        }
        second.clear()
        assertFalse(File(context.filesDir, "logs").exists())
        archive.delete()
    }
    @Test
    fun rollingRetentionPreservesBoundaryAndMultilineRecords() {
        val context = RuntimeEnvironment.getApplication() as Context
        val now = java.time.Instant.parse("2026-10-13T12:00:00Z")
        val logger = RuntimeLogStore(context) { now }
        logger.clear()
        val directory = File(context.filesDir, "logs").apply { mkdirs() }
        File(directory, "runtime.log").writeText("2026-10-12T11:59:59Z [test] expired\nold continuation\n2026-10-12T12:00:00Z [test] boundary\nraw password=密码\n2026-10-13T11:00:00Z [test] recent\n")
        val legacy = File(directory, "runtime.log.1").apply {
            writeText("expired legacy")
            setLastModified(now.minusSeconds(86401).toEpochMilli())
        }
        val archive = logger.export()
        ZipFile(archive).use { zip ->
            val content = zip.getInputStream(zip.getEntry("runtime.log")).bufferedReader().readText()
            assertFalse(content.contains("expired"))
            assertFalse(content.contains("old continuation"))
            assertTrue(content.contains("boundary\nraw password=密码"))
            assertTrue(content.contains("recent"))
        }
        assertFalse(legacy.exists())
        logger.clear()
        archive.delete()
    }

}
