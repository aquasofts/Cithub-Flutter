package com.aquasofts.cithub_flutter

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import com.aquasofts.cithub_flutter.native.UpdateHostApi
import com.aquasofts.cithub_flutter.native.UpdateReleaseDto
import com.aquasofts.cithub_flutter.nativeplugin.BuildConfig
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.Executor
import org.json.JSONArray

internal class AndroidUpdateApi(
    private val context: Context,
    private val logs: RuntimeLogStore,
    private val executor: Executor,
    private val mainHandler: Handler,
    private val events: NativeEvents,
) : UpdateHostApi {
    private val downloads = context.getSystemService(DownloadManager::class.java)
    private val preferences = context.getSharedPreferences("cithub_update", Context.MODE_PRIVATE)
    @Volatile private var downloadId: Long? = preferences.getLong("download_id", -1L).takeIf { it >= 0L }
    @Volatile private var downloadFile: File? = preferences.getString("download_file", null)?.let(::File)
    @Volatile private var downloadVersion: String? = preferences.getString("download_version", null)
    @Volatile private var expectedSha256: String? = preferences.getString("expected_sha256", null)
    @Volatile private var expectedSize: Long? = preferences.getLong("expected_size", -1L).takeIf { it >= 0L }

    init {
        downloadId?.let(::monitorDownload)
    }

    override fun check(includePrereleases: Boolean, callback: (Result<UpdateReleaseDto?>) -> Unit) =
        runAsync(executor, mainHandler, callback) {
            events.emit("update", "checking", "正在检查更新")
            val response = request("https://api.github.com/repos/aquasofts/Cithub-Flutter/releases")
            val releases = JSONArray(response)
            val currentVersion = installedVersionName()
            var selected: UpdateReleaseDto? = null
            for (index in 0 until releases.length()) {
                val release = releases.getJSONObject(index)
                if (release.optBoolean("draft")) continue
                val prerelease = release.optBoolean("prerelease")
                if (prerelease && !includePrereleases) continue
                val tag = release.optString("tag_name")
                val version = tag.trim().removePrefix("v").removePrefix("V")
                if (!runCatching { ReleaseVersionPolicy.isNewer(version, currentVersion) }.getOrDefault(false)) continue
                val assets = release.optJSONArray("assets") ?: JSONArray()
                var assetName: String? = null
                var assetSize: Long? = null
                var assetUrl: String? = null
                var sumsUrl: String? = null
                for (assetIndex in 0 until assets.length()) {
                    val asset = assets.getJSONObject(assetIndex)
                    val name = asset.optString("name")
                    if (name == CHECKSUM_ASSET) sumsUrl = asset.optString("browser_download_url")
                    if (ReleaseAssetPolicy.accepts(name, version, BuildConfig.CAPTCHA_AUTOFILL_ENABLED)) {
                        assetName = name
                        assetSize = asset.optLong("size")
                        assetUrl = asset.optString("browser_download_url")
                        break
                    }
                }
                if (assetUrl == null || assetName == null || sumsUrl.isNullOrBlank()) continue
                val assetUri = Uri.parse(assetUrl)
                val sumsUri = Uri.parse(sumsUrl)
                if (!isTrustedReleaseUri(assetUri) || !isTrustedReleaseUri(sumsUri)) continue
                val expectedHash = runCatching {
                    ReleaseAssetPolicy.sha256ForAsset(request(sumsUrl), assetName)
                }.getOrElse {
                    logs.append("update", "Checksum fetch failed for $tag: ${it.message}")
                    null
                }
                if (!ReleaseAssetPolicy.isSha256(expectedHash)) continue
                selected = UpdateReleaseDto(
                    version,
                    tag,
                    release.optString("name", tag),
                    release.optString("body"),
                    release.optString("html_url"),
                    assetName,
                    assetSize,
                    assetUrl,
                    expectedHash,
                    prerelease,
                )
                break
            }
            events.emit("update", if (selected == null) "idle" else "available", selected?.version)
            selected
        }

    override fun startDownload(release: UpdateReleaseDto, callback: (Result<Boolean>) -> Unit) =
        runAsync(executor, mainHandler, callback) {
            val assetName = requireNotNull(release.assetName) { "Release 没有对应 flavor 的 APK" }
            val assetUrl = requireNotNull(release.assetUrl) { "Release APK 地址为空" }
            val hash = requireNotNull(release.assetSha256) { "Release 缺少 SHA256 校验值" }.lowercase()
            require(ReleaseAssetPolicy.accepts(assetName, release.version, BuildConfig.CAPTCHA_AUTOFILL_ENABLED)) {
                "更新包 flavor 或版本不匹配"
            }
            require(ReleaseVersionPolicy.isNewer(release.version, installedVersionName())) { "更新版本必须高于当前版本" }
            require(ReleaseAssetPolicy.isSha256(hash)) { "Release SHA256 格式错误" }
            require(isTrustedReleaseUri(Uri.parse(assetUrl))) { "只允许从 GitHub HTTPS Release 下载更新" }
            val target = File(context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), assetName)
            if (target.exists()) target.delete()
            val request = DownloadManager.Request(Uri.parse(assetUrl))
                .setTitle(assetName)
                .setDescription("Cithub Flutter ${release.version}")
                .setMimeType(APK_MIME)
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                .setDestinationInExternalFilesDir(context, Environment.DIRECTORY_DOWNLOADS, assetName)
                .setAllowedOverMetered(true)
            downloadId = downloads.enqueue(request)
            downloadFile = target
            downloadVersion = release.version
            expectedSha256 = hash
            expectedSize = release.assetSize
            preferences.edit()
                .putLong("download_id", requireNotNull(downloadId))
                .putString("download_file", target.absolutePath)
                .putString("download_version", release.version)
                .putString("expected_sha256", hash)
                .putLong("expected_size", release.assetSize ?: -1L)
                .apply()
            logs.append("update", "Download enqueued: $assetName")
            events.emit("update", "downloading", assetName, 0.0)
            monitorDownload(requireNotNull(downloadId))
            true
        }

    override fun cancelDownload(callback: (Result<Boolean>) -> Unit) =
        runAsync(executor, mainHandler, callback) {
            val id = downloadId ?: return@runAsync false
            downloads.remove(id)
            downloadFile?.delete()
            clearDownloadState()
            events.emit("update", "idle", "下载已取消")
            true
        }

    override fun installDownloaded(callback: (Result<Boolean>) -> Unit) =
        runAsync(executor, mainHandler, callback) {
            val id = downloadId ?: error("没有已下载的更新")
            val file = downloadFile ?: error("更新文件不存在")
            val version = downloadVersion ?: error("更新版本信息不存在")
            kotlin.check(file.isFile && file.length() > 0L) { "更新包尚未下载完成或已损坏" }
            verifyPayload(file)
            verifyArchive(file, version)
            val uri = downloads.getUriForDownloadedFile(id) ?: error("无法获取安装包 URI")
            val intent = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, APK_MIME)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
            context.startActivity(intent)
            logs.append("update", "Installer opened; sha256=${sha256(file)}")
            true
        }

    override fun checkAccelerators(urls: List<String>, callback: (Result<List<String>>) -> Unit) =
        runAsync(executor, mainHandler, callback) {
            urls.filter { raw ->
                runCatching {
                    val uri = Uri.parse(raw)
                    require(uri.scheme == "https")
                    val connection = URL(raw).openConnection() as HttpURLConnection
                    connection.requestMethod = "HEAD"
                    connection.connectTimeout = 4_000
                    connection.readTimeout = 4_000
                    connection.instanceFollowRedirects = true
                    connection.responseCode in 200..399
                }.getOrDefault(false)
            }
        }

    private fun request(url: String): String {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout = 10_000
        connection.readTimeout = 10_000
        connection.setRequestProperty("Accept", "application/vnd.github+json")
        connection.setRequestProperty("User-Agent", "Cithub-Flutter/${installedVersionName()}")
        kotlin.check(connection.responseCode in 200..299) { "GitHub HTTP ${connection.responseCode}" }
        return connection.inputStream.bufferedReader().use { it.readText() }
    }

    private fun monitorDownload(id: Long) {
        executor.execute {
            while (downloadId == id) {
                val cursor = downloads.query(DownloadManager.Query().setFilterById(id))
                val keepGoing = cursor.use {
                    if (!it.moveToFirst()) return@use false
                    val status = it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                    val downloaded = it.getLong(it.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                    val total = it.getLong(it.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
                    val progress = if (total > 0) downloaded.toDouble() / total else null
                    when (status) {
                        DownloadManager.STATUS_SUCCESSFUL -> {
                            val failure = runCatching { verifyPayload(requireNotNull(downloadFile)) }.exceptionOrNull()
                            if (failure == null) {
                                events.emit("update", "ready", "下载完成且完整性校验通过，可以安装", 1.0)
                            } else {
                                logs.append("update", "Downloaded APK rejected: ${failure.message}")
                                downloadFile?.delete()
                                clearDownloadState()
                                events.emit("update", "failed", "更新包完整性校验失败：${failure.message}", progress)
                            }
                            false
                        }
                        DownloadManager.STATUS_FAILED -> {
                            events.emit("update", "failed", "更新下载失败", progress)
                            false
                        }
                        else -> {
                            events.emit("update", "downloading", "正在下载更新", progress)
                            true
                        }
                    }
                }
                if (!keepGoing) break
                Thread.sleep(750)
            }
        }
    }

    private fun verifyPayload(file: File) {
        val size = expectedSize
        if (size != null && size > 0L) kotlin.check(file.length() == size) { "更新包大小不匹配" }
        val expected = expectedSha256 ?: error("更新包缺少预期 SHA256")
        kotlin.check(sha256(file).equals(expected, ignoreCase = true)) { "更新包 SHA256 不匹配" }
    }

    private fun verifyArchive(file: File, expectedVersion: String) {
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else @Suppress("DEPRECATION") PackageManager.GET_SIGNATURES
        val archive = context.packageManager.getPackageArchiveInfo(file.absolutePath, flags)
            ?: error("无法解析 APK，文件可能损坏")
        kotlin.check(archive.packageName == context.packageName) { "更新包包名不匹配" }
        val installed = context.packageManager.getPackageInfo(context.packageName, flags)
        kotlin.check(archive.versionName == expectedVersion) { "更新包版本与 Release 不匹配" }
        kotlin.check(longVersionCode(archive) > longVersionCode(installed)) { "更新包 versionCode 未提升" }
        val currentDigests = signerDigests(installed)
        val archiveDigests = signerDigests(archive)
        kotlin.check(currentDigests.isNotEmpty() && archiveDigests.any(currentDigests::contains)) {
            "更新包签名与当前应用不一致"
        }
    }

    private fun installedVersionName(): String =
        context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "0.0.0"

    private fun longVersionCode(info: android.content.pm.PackageInfo): Long = if (Build.VERSION.SDK_INT >= 28) {
        info.longVersionCode
    } else {
        @Suppress("DEPRECATION") info.versionCode.toLong()
    }

    private fun isTrustedReleaseUri(uri: Uri): Boolean =
        uri.scheme == "https" && uri.host?.lowercase() in TRUSTED_RELEASE_HOSTS

    @Synchronized
    private fun clearDownloadState() {
        downloadId = null
        downloadFile = null
        downloadVersion = null
        expectedSha256 = null
        expectedSize = null
        preferences.edit().clear().apply()
    }

    private fun signerDigests(info: android.content.pm.PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= 28) {
            info.signingInfo?.apkContentsSigners.orEmpty()
        } else {
            @Suppress("DEPRECATION") info.signatures.orEmpty()
        }
        return signatures.map { signature ->
            MessageDigest.getInstance("SHA-256").digest(signature.toByteArray())
                .joinToString("") { "%02x".format(it) }
        }.toSet()
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private companion object {
        const val APK_MIME = "application/vnd.android.package-archive"
        const val CHECKSUM_ASSET = "SHA256SUMS"
        val TRUSTED_RELEASE_HOSTS = setOf("github.com", "objects.githubusercontent.com")
    }
}
