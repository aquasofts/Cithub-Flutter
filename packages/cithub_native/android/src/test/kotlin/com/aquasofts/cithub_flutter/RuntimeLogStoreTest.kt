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
}
