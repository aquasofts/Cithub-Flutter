package com.aquasofts.cithub_flutter

import android.content.Context
import java.io.File
import java.time.Instant
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

internal class RuntimeLogStore(private val context: Context, private val now: () -> Instant = { Instant.now() }) {
    private val directory = File(context.filesDir, "logs")
    private val file = File(directory, "runtime.log")

    private var lastPrune: Instant? = null
    private val retentionSeconds = 24L * 60 * 60

    @Synchronized
    fun append(source: String, message: String) {
        check(directory.isDirectory || directory.mkdirs()) { "无法创建日志目录" }
        if (lastPrune == null || now().epochSecond - lastPrune!!.epochSecond >= 60) prune()
        file.appendText("${now()} [$source] $message\n")
    }

    @Synchronized
    fun export(): File {
        append("runtime", "Exporting all retained logs as ZIP; redaction=false")
        prune()
        File(context.cacheDir, "exports").listFiles()?.filter {
            it.name.startsWith("cithub-logs-") && it.lastModified() < now().minusSeconds(retentionSeconds).toEpochMilli()
        }?.forEach { check(it.delete()) { "无法清除过期日志导出" } }
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

    private fun prune() {
        val cutoff = now().minusSeconds(retentionSeconds)
        directory.listFiles()?.filter { it.isFile }?.forEach { source ->
            var timestamped = false
            var keep = Instant.ofEpochMilli(source.lastModified()) >= cutoff
            val temporary = File(directory, "${source.name}.pruning")
            try {
                temporary.bufferedWriter().use { output ->
                    source.useLines { lines ->
                        lines.forEach { line ->
                            val timestamp = line.substringBefore(" [", "")
                            val date = runCatching { Instant.parse(timestamp) }.getOrNull()
                            if (date != null) { timestamped = true; keep = date >= cutoff }
                            if (keep) { output.write(line); output.newLine() }
                        }
                    }
                }
                if (temporary.length() == 0L) {
                    check(source.delete()) { "无法清除过期日志" }
                } else if (timestamped) {
                    // Atomic replacement in the same directory.
                    check(temporary.renameTo(source)) { "无法更新日志保留范围" }
                }
            } finally { temporary.delete() }
        }
        lastPrune = now()
    }

    @Synchronized
    fun clear() {
        lastPrune = null
        check(!directory.exists() || directory.deleteRecursively()) { "无法清除日志" }
    }
}
