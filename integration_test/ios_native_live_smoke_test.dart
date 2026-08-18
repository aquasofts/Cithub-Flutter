import 'dart:io';

import 'package:cithub_flutter/core/platform/cithub_platform.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _runLiveTests = bool.fromEnvironment('CITHUB_LIVE_PROTOCOL_TESTS');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'iOS reaches the live WebVPN and Tieba read-only endpoints',
    (_) async {
      if (!Platform.isIOS) return;

      final platform = PigeonCithubPlatform();
      final webVpn = await platform.initializeWebVpn();
      expect(webVpn.captcha != null, webVpn.requiresCaptcha);

      final forum = await platform.loadForum('长春工程学院');
      expect(forum.forum.name, '长春工程学院');
      expect(forum.threads, isNotEmpty);
    },
    skip: !_runLiveTests,
  );
}
