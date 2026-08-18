package com.aquasofts.cithub_flutter

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.aquasofts.cithub_flutter.native.AcademicHostApi
import com.aquasofts.cithub_flutter.native.EventsStreamHandler
import com.aquasofts.cithub_flutter.native.FlutterError
import com.aquasofts.cithub_flutter.native.NativeEventDto
import com.aquasofts.cithub_flutter.native.PigeonEventSink
import com.aquasofts.cithub_flutter.native.RuntimeLogHostApi
import com.aquasofts.cithub_flutter.native.SettingsHostApi
import com.aquasofts.cithub_flutter.native.TiebaHostApi
import com.aquasofts.cithub_flutter.native.UpdateHostApi
import com.aquasofts.cithub_flutter.native.WebVpnHostApi
import com.aquasofts.cithub_flutter.nativeplugin.BuildConfig
import io.flutter.plugin.common.BinaryMessenger
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

internal object NativeApiBootstrap {
    private var executor: ExecutorService? = null

    @Synchronized
    fun register(context: Context, messenger: BinaryMessenger) {
        val appContext = context.applicationContext
        val secureStore = SecureStore(appContext)
        val logs = RuntimeLogStore(appContext)
        val executor = Executors.newCachedThreadPool()
        this.executor?.shutdownNow()
        this.executor = executor
        val mainHandler = Handler(Looper.getMainLooper())
        val events = NativeEvents(mainHandler)
        val state = NativeSessionState(secureStore)

        WebVpnHostApi.setUp(messenger, AndroidWebVpnApi(appContext, state, logs, executor, mainHandler, events))
        AcademicHostApi.setUp(messenger, AndroidAcademicApi(state, logs, executor, mainHandler))
        TiebaHostApi.setUp(messenger, AndroidTiebaApi(appContext, state, logs, executor, mainHandler, events))
        UpdateHostApi.setUp(messenger, AndroidUpdateApi(appContext, logs, executor, mainHandler, events))
        SettingsHostApi.setUp(messenger, AndroidSettingsApi(appContext, executor, mainHandler))
        RuntimeLogHostApi.setUp(messenger, AndroidRuntimeLogApi(appContext, logs, executor, mainHandler))
        EventsStreamHandler.register(messenger, events)
        logs.append("runtime", "Native Pigeon APIs registered; flavor=${BuildConfig.FLAVOR}")
    }

    @Synchronized
    fun unregister(messenger: BinaryMessenger) {
        WebVpnHostApi.setUp(messenger, null)
        AcademicHostApi.setUp(messenger, null)
        TiebaHostApi.setUp(messenger, null)
        UpdateHostApi.setUp(messenger, null)
        SettingsHostApi.setUp(messenger, null)
        RuntimeLogHostApi.setUp(messenger, null)
        EventsStreamHandler.register(messenger, object : EventsStreamHandler() {})
        executor?.shutdownNow()
        executor = null
    }
}

internal class NativeEvents(private val mainHandler: Handler) : EventsStreamHandler() {
    @Volatile private var sink: PigeonEventSink<NativeEventDto>? = null

    override fun onListen(p0: Any?, sink: PigeonEventSink<NativeEventDto>) {
        this.sink = sink
    }

    override fun onCancel(p0: Any?) {
        sink = null
    }

    fun emit(source: String, stage: String, message: String? = null, progress: Double? = null) {
        val event = NativeEventDto(source, stage, message, progress, System.currentTimeMillis())
        mainHandler.post { sink?.success(event) }
    }
}

internal class NativeSessionState(val secureStore: SecretStore) {
    @Volatile var webVpnSignedIn = false
    @Volatile var webVpnUsername: String? = null
    @Volatile var academicSignedIn = false
    @Volatile var academicUsername: String? = null
    @Volatile var tiebaAccountPresent = secureStore.get("tieba.cookie") != null
}

internal fun <T> runAsync(
    executor: java.util.concurrent.Executor,
    mainHandler: Handler,
    callback: (Result<T>) -> Unit,
    block: () -> T,
) {
    executor.execute {
        val result = try {
            Result.success(block())
        } catch (error: Throwable) {
            Result.failure(error.toFlutterError())
        }
        mainHandler.post { callback(result) }
    }
}

private fun Throwable.toFlutterError(): FlutterError {
    val code = when (this) {
        is AcademicLoginRequired -> "loginRequired"
        is IllegalArgumentException -> "invalidInput"
        else -> "requestFailed"
    }
    return FlutterError(code, message?.takeIf(String::isNotBlank) ?: "操作失败")
}
