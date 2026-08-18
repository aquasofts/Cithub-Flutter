package com.aquasofts.cithub_flutter

import android.content.Context
import java.io.File
import java.time.Instant

internal class RuntimeLogStore(private val context: Context) {
    private val file = File(context.filesDir, "logs/runtime.log")

    @Synchronized
    fun append(source: String, message: String) {
        file.parentFile?.mkdirs()
        if (file.length() >= MAX_BYTES) {
            val old = File(file.parentFile, "runtime.log.1")
            old.delete()
            file.renameTo(old)
        }
        file.appendText("${Instant.now()} [$source] $message\n")
    }

    @Synchronized
    fun export(): File {
        file.parentFile?.mkdirs()
        if (!file.exists()) file.writeText("No runtime entries.\n")
        val target = File(context.cacheDir, "exports/cithub-runtime-${System.currentTimeMillis()}.log")
        target.parentFile?.mkdirs()
        file.copyTo(target, overwrite = true)
        return target
    }

    @Synchronized
    fun clear() {
        file.delete()
        File(file.parentFile, "runtime.log.1").delete()
    }

    private companion object {
        const val MAX_BYTES = 1024L * 1024L
    }
}
