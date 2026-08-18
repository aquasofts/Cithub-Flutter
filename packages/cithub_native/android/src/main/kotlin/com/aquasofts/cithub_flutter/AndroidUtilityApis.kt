package com.aquasofts.cithub_flutter

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Handler
import androidx.core.content.FileProvider
import com.aquasofts.cithub_flutter.native.RuntimeLogHostApi
import com.aquasofts.cithub_flutter.native.SettingsHostApi
import java.util.concurrent.Executor

internal class AndroidSettingsApi(
    private val context: Context,
    private val executor: Executor,
    private val mainHandler: Handler,
) : SettingsHostApi {
    override fun setThemedIcon(enabled: Boolean, callback: (Result<Boolean>) -> Unit) =
        runAsync(executor, mainHandler, callback) {
            val packageManager = context.packageManager
            val enabledComponent = ComponentName(context, if (enabled) {
                "com.aquasofts.cithub_flutter.ThemedLauncher"
            } else {
                "com.aquasofts.cithub_flutter.DefaultLauncher"
            })
            val disabledComponent = ComponentName(context, if (enabled) {
                "com.aquasofts.cithub_flutter.DefaultLauncher"
            } else {
                "com.aquasofts.cithub_flutter.ThemedLauncher"
            })
            packageManager.setComponentEnabledSetting(
                enabledComponent,
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP,
            )
            packageManager.setComponentEnabledSetting(
                disabledComponent,
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP,
            )
            true
        }
}

internal class AndroidRuntimeLogApi(
    private val context: Context,
    private val logs: RuntimeLogStore,
    private val executor: Executor,
    private val mainHandler: Handler,
) : RuntimeLogHostApi {
    override fun exportLog(callback: (Result<String>) -> Unit) =
        runAsync(executor, mainHandler, callback) {
            logs.append("runtime", "User exported runtime log")
            val file = logs.export()
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
            val share = Intent.createChooser(
                Intent(Intent.ACTION_SEND)
                    .setType("text/plain")
                    .putExtra(Intent.EXTRA_STREAM, uri)
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
                "导出 Cithub Flutter 运行日志",
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(share)
            uri.toString()
        }

    override fun clearLog(callback: (Result<Boolean>) -> Unit) =
        runAsync(executor, mainHandler, callback) {
            logs.clear()
            true
        }
}
