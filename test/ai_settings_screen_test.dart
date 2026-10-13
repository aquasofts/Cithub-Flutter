import 'package:cithub_flutter/core/platform/cithub_platform.dart';
import 'package:cithub_flutter/core/platform/demo_cithub_platform.dart';
import 'package:cithub_flutter/features/ai/ai_settings.dart';
import 'package:cithub_flutter/features/ai/ai_credentials.dart';
import 'package:cithub_flutter/features/ai/ai_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Finder field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> openSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cithubPlatformProvider.overrideWithValue(DemoCithubPlatform()),
        ],
        child: const MaterialApp(home: AiSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openModel(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, '添加模型'));
    await tester.pumpAndSettle();
    await tester.enterText(field('模型 ID'), 'test-model');
    await tester.enterText(field('显示名称'), '测试模型');
  }

  testWidgets('adding and editing a focused model survives dialog dismissal', (
    tester,
  ) async {
    await openSettings(tester);
    await openModel(tester);
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('保存')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('测试模型'), findsOneWidget);

    await tester.tap(find.text('测试模型'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(field('模型 ID')).controller!.text,
      'test-model',
    );
    await tester.enterText(field('模型 ID'), 'edited-model');
    await tester.enterText(field('显示名称'), '修改后的模型');
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('保存')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('测试模型'), findsNothing);
    expect(find.text('修改后的模型'), findsOneWidget);

    await tester.enterText(field('API Key'), 'test-key');
    await tester.ensureVisible(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AiSettingsScreen)),
    );
    final settings = await container.read(aiSettingsProvider.future);
    expect(settings.models.single.id, 'edited-model');
    expect(settings.model!.id, 'edited-model');
    expect(tester.takeException(), isNull);
  });

  testWidgets('same model ID can bind to two independent addresses and keys', (
    tester,
  ) async {
    await openSettings(tester);
    for (final suffix in ['a', 'b']) {
      await openModel(tester);
      await tester.enterText(field('显示名称'), '服务$suffix');
      await tester.enterText(field('模型 API 地址'), 'https://$suffix.test/v1');
      await tester.enterText(field('模型 API Key'), 'secret-$suffix');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('保存'),
        ),
      );
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AiSettingsScreen)),
    );
    final settings = await container.read(aiSettingsProvider.future);
    expect(settings.models.map((m) => m.id), ['test-model', 'test-model']);
    expect(settings.models.map((m) => m.selectionId).toSet().length, 2);
    final credentials = await AiCredentials.read(
      container.read(cithubPlatformProvider),
    );
    for (var i = 0; i < 2; i++) {
      final suffix = ['a', 'b'][i];
      expect(settings.endpointFor(settings.models[i]).host, '$suffix.test');
      expect(
        credentials.keyFor(settings.models[i].selectionId),
        'secret-$suffix',
      );
    }
    expect(tester.takeException(), isNull);
  });

  for (final dismissal in ['cancel', 'barrier', 'back']) {
    testWidgets('focused model can close via $dismissal and reopen', (
      tester,
    ) async {
      await openSettings(tester);
      await openModel(tester);
      switch (dismissal) {
        case 'cancel':
          await tester.tap(find.text('取消'));
        case 'barrier':
          await tester.tapAt(const Offset(5, 5));
        case 'back':
          await tester.binding.handlePopRoute();
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('测试模型'), findsNothing);
      await tester.tap(find.widgetWithText(TextButton, '添加模型'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('模型 ID')).controller!.text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
