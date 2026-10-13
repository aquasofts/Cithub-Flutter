import Foundation

final class IOSAiSecretApi: AiSecretHostApi {
    private let store: any SecretStore
    init(store: any SecretStore) { self.store = store }
    func readApiKey(completion: @escaping (Result<String?, Error>) -> Void) {
        runNative(completion: completion) { [store] in await store.get("ai.api_key") }
    }
    func writeApiKey(value: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        runNative(completion: completion) { [store] in
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CithubNativeError.invalidInput("API Key 不能为空") }
            await store.put("ai.api_key", value)
            guard await store.get("ai.api_key") == value else { throw CithubNativeError.invalidInput("密钥保存失败") }
            return true
        }
    }
    func deleteApiKey(completion: @escaping (Result<Bool, Error>) -> Void) {
        runNative(completion: completion) { [store] in await store.remove("ai.api_key"); return true }
    }
}
