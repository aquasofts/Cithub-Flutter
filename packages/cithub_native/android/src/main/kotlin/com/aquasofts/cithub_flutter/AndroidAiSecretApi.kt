package com.aquasofts.cithub_flutter

import android.os.Handler
import com.aquasofts.cithub_flutter.native.AiSecretHostApi
import java.util.concurrent.Executor

internal class AndroidAiSecretApi(private val store: SecretStore, private val executor: Executor, private val handler: Handler) : AiSecretHostApi {
    override fun readApiKey(callback: (Result<String?>) -> Unit) = runAsync(executor, handler, callback) { store.get("ai.api_key") }
    override fun writeApiKey(value: String, callback: (Result<Boolean>) -> Unit) = runAsync(executor, handler, callback) {
        require(value.isNotBlank()) { "API Key 不能为空" }
        store.put("ai.api_key", value)
        check(store.get("ai.api_key") == value) { "密钥保存失败" }
        true
    }
    override fun deleteApiKey(callback: (Result<Boolean>) -> Unit) = runAsync(executor, handler, callback) { store.remove("ai.api_key"); true }
}
