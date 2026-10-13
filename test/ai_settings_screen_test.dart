import 'dart:convert';

import 'package:cithub_flutter/features/ai/ai_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
    await tester.enterText(field('模型 API Key'), 'test-key');
  }

  testWidgets('model native search and supported reasoning levels persist', (
    tester,
  ) async {
    await openSettings(tester);
    await openModel(tester);
    await tester.enterText(field('模型 ID'), 'm');
    await tester.enterText(field('显示名称'), '可搜索模型');
    await tester.enterText(field('模型 API Key'), 'test-key');
    for (final label in ['支持模型自带搜索', '支持思考程度']) {
      final toggle = find.widgetWithText(SwitchListTile, label);
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
    }
    final xhigh = find.byKey(const ValueKey('effort-support-xhigh'));
    await tester.ensureVisible(xhigh);
    await tester.pumpAndSettle();
    await tester.tap(xhigh);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('保存')),
    );
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, '保存');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AiSettingsScreen)),
    );
    final model = (await container.read(aiSettingsProvider.future)).model!;
    expect(model.nativeSearch, true);
    expect(model.reasoning, true);
    expect(model.reasoningEfforts, ['low', 'medium', 'high', 'xhigh']);
    expect(tester.takeException(), isNull);
  });

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

    expect(field('API Key'), findsNothing);
    expect(field('Base URL'), findsNothing);
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

  testWidgets('Responses API switch is saved and restored on edit', (
    tester,
  ) async {
    await openSettings(tester);
    await openModel(tester);
    final toggle = find.widgetWithText(SwitchListTile, '支持 Responses API');
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('保存')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '保存'));
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AiSettingsScreen)),
    );
    expect(
      (await container.read(aiSettingsProvider.future)).model!.responsesApi,
      true,
    );
    await tester.tap(find.text('测试模型'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, true);
  });

  for (final responses in [false, true]) {
    testWidgets(
      'saved connection test sends model ID, never display name: responses=$responses',
      (tester) async {
        http.Request? sent;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              cithubPlatformProvider.overrideWithValue(DemoCithubPlatform()),
              aiClientFactoryProvider.overrideWithValue(
                () => AiClient(
                  log: (_) {},
                  client: MockClient((request) async {
                    sent = request;
                    return http.Response(
                      jsonEncode(
                        responses
                            ? {
                                'status': 'completed',
                                'output': [
                                  {
                                    'type': 'message',
                                    'content': [
                                      {'type': 'output_text', 'text': 'OK'},
                                    ],
                                  },
                                ],
                              }
                            : {
                                'choices': [
                                  {
                                    'message': {'content': 'OK'},
                                  },
                                ],
                              },
                      ),
                      200,
                      headers: {'content-type': 'application/json'},
                    );
                  }),
                ),
              ),
            ],
            child: const MaterialApp(home: AiSettingsScreen()),
          ),
        );
        await tester.pumpAndSettle();
        await openModel(tester);
        await tester.enterText(field('模型 ID'), 'gpt-6-sol');
        await tester.enterText(field('显示名称'), '我的校园助手');
        if (responses) {
          final toggle = find.widgetWithText(
            SwitchListTile,
            '支持 Responses API',
          );
          await tester.ensureVisible(toggle);
          await tester.pumpAndSettle();
          await tester.tap(toggle);
          await tester.pumpAndSettle();
        }
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('保存'),
          ),
        );
        await tester.pumpAndSettle();
        final button = find.widgetWithText(TextButton, '保存并测试连接');
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        // Wait for the response body and cleanup, not just request dispatch.
        for (
          var i = 0;
          i < 20 && find.textContaining('连接成功').evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.textContaining('连接成功'), findsOneWidget);
        expect(sent, isNotNull);
        expect(jsonDecode(sent!.body)['model'], 'gpt-6-sol');
        expect(
          sent!.url.path,
          responses ? '/v1/responses' : '/v1/chat/completions',
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(AiSettingsScreen)),
        );
        expect(
          (await container.read(aiSettingsProvider.future)).model!.name,
          '我的校园助手',
        );
      },
    );
  }

  testWidgets(
    'API key uses a regular input connection and toggles only its visual mask',
    (tester) async {
      await openSettings(tester);
      await openModel(tester);
      final input = field('模型 API Key');
      final controller = tester.widget<TextField>(input).controller!;
      final configuration = tester.testTextInput.setClientArgs!;
      expect(configuration['inputType']['name'], 'TextInputType.text');
      expect(configuration['obscureText'], false);
      expect(configuration['enableSuggestions'], true);
      expect(
        controller
            .buildTextSpan(context: tester.element(input), withComposing: false)
            .toPlainText(),
        '•' * 'test-key'.length,
      );
      await tester.ensureVisible(find.byTooltip('显示 API Key'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('显示 API Key'));
      await tester.pumpAndSettle();
      expect(
        controller
            .buildTextSpan(context: tester.element(input), withComposing: false)
            .toPlainText(),
        'test-key',
      );
      expect(controller.text, 'test-key');
      await tester.tap(find.byTooltip('隐藏 API Key'));
      await tester.pumpAndSettle();
      expect(
        controller
            .buildTextSpan(context: tester.element(input), withComposing: false)
            .toPlainText(),
        '•' * 'test-key'.length,
      );
      expect(controller.text, 'test-key');
      expect(tester.takeException(), isNull);
    },
  );

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

  testWidgets(
    'model fields stay separated on narrow screens with keyboard and large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cithubPlatformProvider.overrideWithValue(DemoCithubPlatform()),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: const AiSettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await openModel(tester);
      expect(
        tester.getRect(field('模型 API 地址')).top -
            tester.getRect(field('显示名称')).bottom,
        greaterThanOrEqualTo(16),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      await tester.ensureVisible(field('模型 API Key'));
      await tester.pumpAndSettle();
      await tester.enterText(
        field('模型 API Key'),
        'long-independent-secret-key',
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

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
