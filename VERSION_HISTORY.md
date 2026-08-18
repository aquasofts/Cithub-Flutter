# Version history

## 1.0.0 — release candidate

- Created the independent Android-only Flutter application.
- Added `autoCaptcha` and `manualCaptcha` flavors with strict ML Kit separation.
- Added four persistent primary tabs: Tieba, News, Academic, and Mine.
- Added typed Pigeon APIs for WebVPN, academic services, Tieba, updates, settings, runtime logs, and native events.
- Added Android Keystore encryption, local rolling logs, exact-flavor update selection, signer checks, dynamic launcher icons, and official Tieba reply dispatch.
- Added Dart unit/Widget/integration tests, Kotlin policy tests, CI release verification, and device acceptance documentation.

`V1.0.0` must not be tagged until every item in `docs/device-acceptance.md` passes with authorized real-service accounts.
