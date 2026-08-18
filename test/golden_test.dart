import 'package:cithub_flutter/core/native/cithub_api.g.dart';
import 'package:cithub_flutter/core/platform/cithub_platform.dart';
import 'package:cithub_flutter/core/platform/demo_cithub_platform.dart';
import 'package:cithub_flutter/features/academic/academic_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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

  testWidgets('academic home matches compact single-column layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cithubPlatformProvider.overrideWithValue(_GoldenAcademicPlatform()),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: RepaintBoundary(
            key: const Key('academic-home-golden'),
            child: const Scaffold(body: AcademicScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const Key('academic-home-golden')),
      matchesGoldenFile('goldens/academic_home_360.png'),
    );
  });

  testWidgets('grades match compact filter and card layout', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cithubPlatformProvider.overrideWithValue(_GoldenAcademicPlatform()),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: RepaintBoundary(
            key: const Key('grades-golden'),
            child: const GradesScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const Key('grades-golden')),
      matchesGoldenFile('goldens/grades_360.png'),
    );
  });
}

class _GoldenAcademicPlatform extends DemoCithubPlatform {
  WebVpnSessionDto get _session => WebVpnSessionDto(
    status: AuthStatus.signedIn,
    requiredAction: RequiredAccountAction.none,
    user: UserInfoDto(
      username: '20260001',
      nickname: '测试同学',
      fullName: '测试同学',
      groups: const ['学生'],
      authType: 1,
      bindWechat: true,
      bindOtp: false,
    ),
    savedAccounts: const [],
    requiresCaptcha: false,
  );

  @override
  Future<WebVpnSessionDto> initializeWebVpn() async => _session;

  @override
  Future<WebVpnSessionDto> initializeAcademic(String webVpnUsername) async =>
      _session;
}
