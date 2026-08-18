import 'package:cithub_flutter/app/cithub_app.dart';
import 'package:cithub_flutter/core/platform/cithub_platform.dart';
import 'package:cithub_flutter/core/platform/demo_cithub_platform.dart';
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

    await tester.tap(find.text('新闻'));
    await tester.pumpAndSettle();
    expect(find.text('公众号'), findsOneWidget);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('关于 Cithub Flutter'), findsOneWidget);

    await tester.tap(find.text('贴吧'));
    await tester.pumpAndSettle();
    expect(find.text('欢迎来到 长春工程学院 吧'), findsOneWidget);

    await tester.tap(find.text('欢迎来到 长春工程学院 吧'));
    await tester.pumpAndSettle();
    expect(find.text('这是主题内容。'), findsOneWidget);

    await tester.tap(find.text('新闻'));
    await tester.pumpAndSettle();
    expect(find.text('公众号'), findsOneWidget);

    await tester.tap(find.text('贴吧'));
    await tester.pumpAndSettle();
    expect(find.text('这是主题内容。'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('长春工程学院吧'), findsOneWidget);
  });
}
