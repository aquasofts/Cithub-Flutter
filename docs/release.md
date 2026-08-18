# Release process

1. Update `version:` in `pubspec.yaml`; versionCode must increase monotonically.
2. Generate Pigeon files and confirm the working tree contains both Dart and Kotlin outputs.
3. Run `flutter analyze`, Dart/Widget/integration tests, Kotlin tests, and Android lint.
4. Build both ARM64 release flavors using the dedicated production keystore.
5. Rename outputs exactly:
   - `Cithub-Flutter-<version>-auto-captcha-performance.apk`
   - `Cithub-Flutter-<version>-manual-captcha-performance.apk`
6. Verify package ID, minSdk, targetSdk, versionName/versionCode, R8 non-debuggable release mode, zipalign, certificate SHA-256, ABI set, and file SHA-256.
7. Confirm the manual APK contains no `mlkit`, OCR model, or ML Kit native library entry.
8. Run all simulated failure cases: expired WebVPN session, captcha error, malformed academic HTML, Tieba paging/sign/follow failures, malformed RSS, offline cache, wrong flavor, corrupted APK, wrong package, and wrong signer.
9. Install both candidates separately and complete `device-acceptance.md` with authorized accounts. Export logs only after the tester explicitly chooses to do so.
10. Fix and repeat every failed item. Only then tag `V<version>` and publish the two APKs plus the CI-generated file named exactly `SHA256SUMS`. The updater fails closed when that asset or the matching APK entry is absent.

Never commit a keystore, passwords, account credentials, session cookies, full runtime logs, or exported diagnostics.
