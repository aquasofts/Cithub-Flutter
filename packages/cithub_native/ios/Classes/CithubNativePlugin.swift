import Flutter
import Foundation

@objc(CithubNativePlugin)
public final class CithubNativePlugin: NSObject, FlutterPlugin {
    @objc
    public static func register(with registrar: FlutterPluginRegistrar) {
        let messenger = registrar.messenger()
        let store = KeychainSecretStore()
        let state = IOSSessionState()
        let logger = IOSRuntimeLogStore()
        let events = IOSNativeEvents()

        WebVpnHostApiSetup.setUp(
            binaryMessenger: messenger,
            api: IOSWebVpnApi(store: store, state: state, logger: logger, events: events)
        )
        AcademicHostApiSetup.setUp(
            binaryMessenger: messenger,
            api: IOSAcademicApi(store: store, state: state, logger: logger)
        )
        TiebaHostApiSetup.setUp(
            binaryMessenger: messenger,
            api: IOSTiebaApi(store: store, logger: logger, events: events)
        )
        UpdateHostApiSetup.setUp(binaryMessenger: messenger, api: IOSUpdateApi())
        SettingsHostApiSetup.setUp(binaryMessenger: messenger, api: IOSSettingsApi())
        RuntimeLogHostApiSetup.setUp(binaryMessenger: messenger, api: IOSRuntimeLogApi(logger: logger))
        EventsStreamHandler.register(with: messenger, streamHandler: events)
    }
}
