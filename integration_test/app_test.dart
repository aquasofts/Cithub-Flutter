import 'package:cithub_flutter/app/cithub_app.dart';
import 'package:cithub_flutter/core/platform/cithub_platform.dart';
import 'package:cithub_flutter/core/platform/demo_cithub_platform.dart';
import 'package:flutter/material.dart' show BackButton;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('primary navigation retains tab state', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cithubPlatformProvider.overrideWithValue(DemoCithubPlatform()),
        ],
        child: const CithubApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('AI'));
    await tester.pumpAndSettle();
    expect(find.text('先配置 AI 服务与模型'), findsOneWidget);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('我的课表'), findsOneWidget);

    await tester.tap(find.text('贴吧'));
    await tester.pumpAndSettle();
    expect(find.text('欢迎来到 长春工程学院 吧'), findsOneWidget);

    await tester.tap(find.text('欢迎来到 长春工程学院 吧'));
    await tester.pumpAndSettle();
    expect(find.text('这是主题内容。'), findsOneWidget);

    await tester.tap(find.text('AI'));
    await tester.pumpAndSettle();
    expect(find.text('先配置 AI 服务与模型'), findsOneWidget);

    await tester.tap(find.text('贴吧'));
    await tester.pumpAndSettle();
    expect(find.text('这是主题内容。'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('长春工程学院吧'), findsOneWidget);
  });
}
