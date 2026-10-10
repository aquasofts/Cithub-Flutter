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

    func append(source: String, message: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        runNative(completion: completion) { [logger] in
            await logger.append(source: source, message: message)
            return true
        }
    }

    func exportLog(completion: @escaping (Result<String, Error>) -> Void) {
        runNative(completion: completion) { [logger] in
            let path = try await logger.export()
            await MainActor.run {
                guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
                      var presenter = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
                while let presented = presenter.presentedViewController { presenter = presented }
                let share = UIActivityViewController(activityItems: [URL(fileURLWithPath: path)], applicationActivities: nil)
                share.popoverPresentationController?.sourceView = presenter.view
                share.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
                presenter.present(share, animated: true)
            }
            return path
        }
    }

    func clearLog(completion: @escaping (Result<Bool, Error>) -> Void) {
        runNative(completion: completion) { [logger] in
            try await logger.clear()
            return true
        }
    }
}
