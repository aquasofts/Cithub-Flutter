package com.aquasofts.cithub_flutter

import android.content.Context
import java.io.File
import java.time.Instant
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

internal class RuntimeLogStore(private val context: Context) {
    private val directory = File(context.filesDir, "logs")
    private val file = File(directory, "runtime.log")

    @Synchronized
    fun append(source: String, message: String) {
        check(directory.isDirectory || directory.mkdirs()) { "无法创建日志目录" }
        file.appendText("${Instant.now()} [$source] $message\n")
    }

    @Synchronized
    fun export(): File {
        append("runtime", "Exporting all retained logs as ZIP; redaction=false")
        val target = File(context.cacheDir, "exports/cithub-logs-${java.util.UUID.randomUUID()}.zip")
        check(target.parentFile!!.isDirectory || target.parentFile!!.mkdirs()) { "无法创建导出目录" }
        try {
            ZipOutputStream(target.outputStream().buffered()).use { zip ->
                directory.walkTopDown().filter { it.isFile }.sortedBy { it.path }.forEach { source ->
                    zip.putNextEntry(ZipEntry(source.relativeTo(directory).invariantSeparatorsPath))
                    source.inputStream().use { it.copyTo(zip) }
                    zip.closeEntry()
                }
            }
        } catch (error: Throwable) {
            target.delete()
            throw error
        }
        return target
    }

    @Synchronized
    fun clear() {
        check(!directory.exists() || directory.deleteRecursively()) { "无法清除日志" }
    }
}
