import 'dart:convert';
import 'dart:async';

import 'package:cithub_flutter/features/ai/ai_conversations.dart';

import 'package:cithub_flutter/core/platform/cithub_platform.dart';
import 'package:cithub_flutter/core/platform/demo_cithub_platform.dart';
import 'package:cithub_flutter/core/storage/local_database.dart';
import 'package:cithub_flutter/core/settings/app_settings.dart';
import 'package:cithub_flutter/core/theme/cithub_theme.dart';
import 'package:cithub_flutter/features/ai/ai_screen.dart';
import 'package:cithub_flutter/features/ai/ai_client.dart';
import 'package:cithub_flutter/features/ai/ai_settings.dart';
import 'package:cithub_flutter/features/timetable/timetable_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class ScheduleClient extends http.BaseClient {
  int calls = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = jsonDecode((request as http.Request).body) as Map;
    expect(body['model'], 'test-model');
    final message = switch (calls++) {
      0 => {
        'tool_calls': [
          {
            'id': 'read',
            'type': 'function',
            'function': {'name': 'read_schedule', 'arguments': '{}'},
          },
        ],
      },
      1 => {
        'tool_calls': [
          {
            'id': 'write',
            'type': 'function',
            'function': {
              'name': 'patch_schedule',
              'arguments': jsonEncode({
                'expectedRevision': 0,
                'term': '2026-1',
                'summary': '新增数学',
                'operations': [
                  {
                    'op': 'add',
                    'course': {
                      'name': '数学',
                      'dayOfWeek': 1,
                      'startSection': 1,
                      'endSection': 2,
                      'weekNumbers': [1, 2, 3],
                    },
                  },
                ],
              }),
            },
          },
        ],
      },
      _ => {'content': '已添加数学课程，可以查看历史版本。'},
    };
    return http.StreamedResponse(
      Stream.value(
        utf8.encode(
          jsonEncode({
            'choices': [
              {'message': message},
            ],
          }),
        ),
      ),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

class DelayedReplyClient extends http.BaseClient {
  final reply = Completer<http.StreamedResponse>();
  bool started = false, closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    started = true;
    return reply.future;
  }

  @override
  void close() {
    closed = true;
  }
}

void main() {
  testWidgets(
    'chat uses Cithub theme, consent, tool saving and local conversation persistence',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      sqfliteFfiInit();
      final store = LocalDatabase.at(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      await tester.runAsync(() async {
        await store.database;
      });
      final platform = DemoCithubPlatform();
      await platform.writeAiApiKey('test-key');
      final mock = ScheduleClient();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localDatabaseProvider.overrideWithValue(store),
            cithubPlatformProvider.overrideWithValue(platform),
            aiSettingsProvider.overrideWith(
              (_) async => const AiSettings(
                baseUrl: 'https://test.invalid/v1',
                models: [AiModel(id: 'test-model', name: '测试模型')],
                defaultModel: 'test-model',
              ),
            ),
            aiClientFactoryProvider.overrideWithValue(
              () => AiClient(client: mock, log: (_) {}),
            ),
          ],
          child: MaterialApp(
            theme: buildCithubTheme(const AppSettings(), Brightness.dark),
            home: const AiScreen(),
          ),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 20; i++) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
        }
        await tester.pumpAndSettle();
      }

      await settle();
      await tester.enterText(
        find.byType(TextField),
        '请添加数学课程，2026-1学期周一第1-2节，第1-3周',
      );
      await tester.tap(find.byType(SwitchListTile));
      await tester.tap(find.byTooltip('发送'));
      await settle();
      expect(find.text('发送到 AI 服务'), findsOneWidget);
      expect(mock.calls, 0);
      await tester.tap(find.text('同意并发送'));
      await settle();
      expect(find.text('课表已保存'), findsOneWidget);
      expect(find.text('新增数学'), findsOneWidget);
      expect(mock.calls, 3);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        expect(
          (await TimetableRepository(
            store,
          ).active())!.courses.single.course.name,
          '数学',
        );
        expect((await (await store.database).query('conversations')).length, 1);
      });
      await tester.tap(find.byTooltip('新建会话'));
      await settle();
      expect(find.text('课表已保存'), findsNothing);
      await tester.tap(find.byTooltip('会话历史'));
      await settle();
      expect(find.text('会话历史'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await (await store.database).close();
      });
    },
  );
  testWidgets(
    'closing a chat route keeps the request alive and saves reasoning and output',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      sqfliteFfiInit();
      final store = LocalDatabase.at(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      await tester.runAsync(() async {
        await store.database;
        await store.setMeta('ai.disclosure', 'accepted');
      });
      final platform = DemoCithubPlatform();
      await platform.writeAiApiKey('test-key');
      final mock = DelayedReplyClient();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localDatabaseProvider.overrideWithValue(store),
            cithubPlatformProvider.overrideWithValue(platform),
            aiSettingsProvider.overrideWith(
              (_) async => const AiSettings(
                models: [AiModel(id: 'm', name: 'M')],
              ),
            ),
            aiClientFactoryProvider.overrideWithValue(
              () => AiClient(client: mock, log: (_) {}),
            ),
          ],
          child: MaterialApp(
            navigatorKey: navigator,
            home: const Scaffold(body: Text('其他页面')),
          ),
        ),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const AiScreen()),
      );
      Future<void> tick() async {
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
        }
      }

      await tick();
      expect(find.text('当前只读，不会修改课表'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '查询课程');
      await tester.tap(find.byTooltip('发送'));
      await tick();
      expect(mock.started, true);
      navigator.currentState!.pop();
      await tick();
      expect(find.text('其他页面'), findsOneWidget);
      expect(mock.closed, false);
      mock.reply.complete(
        http.StreamedResponse(
          Stream.value(
            utf8.encode(
              jsonEncode({
                'choices': [
                  {
                    'message': {
                      'content': '后台完成的回复',
                      'reasoning_content': '接口返回的思考',
                    },
                  },
                ],
              }),
            ),
          ),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await tick();
      expect(mock.closed, true);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final conversation = (await AiConversationRepository(
          store,
        ).all()).single;
        expect(conversation.display.any((m) => m['text'] == '后台完成的回复'), true);
        expect(
          conversation.display.any(
            (m) => m['kind'] == 'reasoning' && m['text'] == '接口返回的思考',
          ),
          true,
        );
      });
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const AiScreen()),
      );
      await tick();
      expect(find.text('思考过程'), findsOneWidget);
      await tester.tap(find.text('思考过程'));
      await tick();
      expect(find.text('接口返回的思考'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await (await store.database).close();
      });
    },
  );
}
