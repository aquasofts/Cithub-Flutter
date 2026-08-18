import Foundation
import UIKit

final class IOSUpdateApi: UpdateHostApi {
    func check(includePrereleases: Bool, completion: @escaping (Result<UpdateReleaseDto?, Error>) -> Void) {
        completion(.success(nil))
    }

    func startDownload(release: UpdateReleaseDto, completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(false))
    }

    func cancelDownload(completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(false))
    }

    func installDownloaded(completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(false))
    }

    func checkAccelerators(urls: [String], completion: @escaping (Result<[String], Error>) -> Void) {
        completion(.success(urls))
    }
}

final class IOSSettingsApi: SettingsHostApi {
    func setThemedIcon(enabled: Bool, completion: @escaping (Result<Bool, Error>) -> Void) {
        Task { @MainActor in
            guard UIApplication.shared.supportsAlternateIcons else {
                completion(.success(false))
                return
            }
            do {
                try await UIApplication.shared.setAlternateIconName(enabled ? "AppIconThemed" : nil)
                completion(.success(true))
            } catch {
                completion(.success(false))
            }
        }
    }
}

final class IOSRuntimeLogApi: RuntimeLogHostApi {
    private let logger: IOSRuntimeLogStore

    init(logger: IOSRuntimeLogStore) {
        self.logger = logger
    }

    func exportLog(completion: @escaping (Result<String, Error>) -> Void) {
        runNative(completion: completion) { [logger] in try await logger.export() }
    }

    func clearLog(completion: @escaping (Result<Bool, Error>) -> Void) {
        runNative(completion: completion) { [logger] in
            await logger.clear()
            return true
        }
    }
}
