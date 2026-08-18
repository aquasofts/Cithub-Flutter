import 'package:cithub_flutter/core/platform/demo_cithub_platform.dart';
import 'package:cithub_flutter/features/academic/academic_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('WebVPN login remains usable at 320dp', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final platform = DemoCithubPlatform(autoCaptcha: false);
    final session = await platform.initializeWebVpn();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: RepaintBoundary(
            key: const Key('golden'),
            child: SingleChildScrollView(
              child: WebVpnLoginPanel(
                session: session,
                onLogin: (_) {},
                onRefreshCaptcha: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const Key('golden')),
      matchesGoldenFile('goldens/webvpn_login_320.png'),
    );
  });
}
