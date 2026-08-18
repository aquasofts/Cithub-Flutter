import 'dart:io';

import 'package:cithub_flutter/core/native/cithub_api.g.dart';
import 'package:cithub_flutter/core/platform/cithub_platform.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS registers and serves the native Pigeon channels', (_) async {
    if (!Platform.isIOS) return;

    final platform = PigeonCithubPlatform();
    final capabilities = await platform.capabilities();

    expect(capabilities.flavor, CaptchaFlavor.manualCaptcha);
    expect(capabilities.captchaAutofillEnabled, isFalse);
    expect(capabilities.versionName, isNotEmpty);
    expect(await platform.clearRuntimeLog(), isTrue);

    await expectLater(
      platform.initializeAcademic('20260001'),
      throwsA(
        predicate<Object>(
          (error) => error.toString().contains('请先登录 WebVPN'),
          '教务 iOS 原生通道返回预期的会话校验错误',
        ),
      ),
    );
    await expectLater(
      platform.loadTiebaUserProfile(0),
      throwsA(
        predicate<Object>(
          (error) => error.toString().contains('无效的贴吧用户 ID'),
          '贴吧 iOS 原生通道返回预期的参数校验错误',
        ),
      ),
    );
  });
}
