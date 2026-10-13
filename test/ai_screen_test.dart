import 'dart:convert';
import 'dart:async';

import 'package:cithub_flutter/features/ai/ai_conversations.dart';
import 'package:cithub_flutter/core/logging/runtime_log.dart';
import 'package:cithub_flutter/features/ai/ai_reasoning_card.dart';

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
import 'package:flutter/services.dart';
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
        'reasoning_content': '先读取当前课表。',
        'tool_calls': [
          {
            'id': 'read',
            'type': 'function',
            'function': {'name': 'read_schedule', 'arguments': '{}'},
          },
        ],
      },
      1 => {
        'reasoning_content': '根据现有课表申请新增数学。',
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

class StreamingReplyClient extends http.BaseClient {
  final chunks = StreamController<List<int>>();
  bool started = false, closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    started = true;
    return http.StreamedResponse(
      chunks.stream,
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  }

  void delta(Map<String, dynamic> delta) => chunks.add(
    utf8.encode(
      'data: ${jsonEncode({
        'choices': [
          {'delta': delta},
        ],
      })}\n\n',
    ),
  );

  @override
  void close() => closed = true;
}

class SourceReplyClient extends StreamingReplyClient {
  int calls = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (calls++ > 0) return super.send(request);
    return http.StreamedResponse(
      Stream.value(
        utf8.encode(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'tool_calls': [
                    {
                      'id': 'news-read',
                      'type': 'function',
                      'function': {
                        'name': 'latest_content',
                        'arguments': jsonEncode({
                          'source': 'official',
                          'count': 1,
                        }),
                      },
                    },
                  ],
                },
              },
            ],
          }),
        ),
      ),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

class CapturingReplyClient extends StreamingReplyClient {
  http.Request? request;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest r) {
    request = r as http.Request;
    return super.send(r);
  }

  void event(Map<String, dynamic> event) =>
      chunks.add(utf8.encode('data: ${jsonEncode(event)}\n\n'));
}

void main() {
  final logEntries = <String>[];
  const logChannel = BasicMessageChannel<Object?>(
    'dev.flutter.pigeon.cithub_flutter.RuntimeLogHostApi.append',
    StandardMessageCodec(),
  );
  setUp(() {
    logEntries.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(logChannel, (value) async {
          logEntries.add((value! as List)[1] as String);
          return [true];
        });
  });

  testWidgets(
    'composer model, native search and reasoning selections reach the request and restore',
    (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      sqfliteFfiInit();
      final store = LocalDatabase.at(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      await tester.runAsync(() async {
        await AiConversationRepository(store).save(
          AiConversation(
            id: 'controls',
            model: 'a',
            display: [
              {
                'kind': 'text',
                'id': 'old',
                'author': 'assistant',
                'text': '欢迎',
              },
            ],
          ),
        );
      });
      final platform = DemoCithubPlatform();
      await platform.writeAiApiKey('test-key');
      final mock = CapturingReplyClient();
      final app = ProviderScope(
        overrides: [
          localDatabaseProvider.overrideWithValue(store),
          cithubPlatformProvider.overrideWithValue(platform),
          aiSettingsProvider.overrideWith(
            (_) async => const AiSettings(
              models: [
                AiModel(id: 'a', name: '普通模型'),
                AiModel(
                  id: 'b',
                  name: '搜索模型',
                  responsesApi: true,
                  nativeSearch: true,
                  reasoning: true,
                ),
              ],
            ),
          ),
          aiClientFactoryProvider.overrideWithValue(
            () => AiClient(client: mock, log: (_) {}),
          ),
        ],
        child: const MaterialApp(home: AiScreen()),
      );
      Future<void> tick() async {
        for (var i = 0; i < 15; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
        }
      }

      await tester.pumpWidget(app);
      await tick();
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(
        tester
            .getRect(find.byKey(const ValueKey('ai-composer')))
            .contains(
              tester.getCenter(find.byKey(const ValueKey('ai-model-picker'))),
            ),
        isTrue,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('ai-native-search')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('ai-model-picker')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(2, 2));
      await tick();
      expect(find.text('选择模型'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('ai-model-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('model-option-b')));
      await tick();
      await tester.tap(find.byKey(const ValueKey('ai-native-search')));
      await tick();
      expect(find.byTooltip('关闭模型自带搜索'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ai-reasoning-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reasoning-option-high')));
      await tick();
      expect(find.byTooltip('思考程度：高'), findsOneWidget);
      await tester.runAsync(() async {
        final saved = (await AiConversationRepository(store).all()).single;
        expect(saved.model, 'b');
        expect(saved.options.webSearch, true);
        expect(saved.options.reasoningEffort, 'high');
      });
      await tester.enterText(find.byType(TextField), '搜索最新校园消息');
      await tester.tap(find.byTooltip('发送'));
      await tick();
      final request = jsonDecode(mock.request!.body) as Map;
      expect(mock.request!.url.path, '/v1/responses');
      expect(request['model'], 'b');
      expect(request['reasoning']['effort'], 'high');
      expect(
        (request['tools'] as List).any((t) => t['type'] == 'web_search'),
        isTrue,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('ai-model-picker')))
            .onPressed,
        isNull,
      );
      mock.event({
        'type': 'response.web_search_call.searching',
        'item_id': 'ws',
      });
      await tick();
      expect(find.text('模型正在联网搜索…'), findsWidgets);
      mock.event({'type': 'response.output_text.delta', 'delta': '校园公告。'});
      await tick();
      final output = [
        {
          'id': 'ws',
          'type': 'web_search_call',
          'status': 'completed',
          'action': {
            'type': 'search',
            'query': '校园消息',
            'sources': [
              {
                'type': 'url',
                'title': '公告',
                'url': 'https://example.test/news',
              },
            ],
          },
        },
        {
          'type': 'message',
          'content': [
            {
              'type': 'output_text',
              'text': '校园公告。',
              'annotations': [
                {
                  'type': 'url_citation',
                  'url': 'https://example.test/news',
                  'end_index': 5,
                },
              ],
            },
          ],
        },
      ];
      mock.event({
        'type': 'response.completed',
        'response': {'status': 'completed', 'output': output},
      });
      await mock.chunks.close();
      await tick();
      await tester.pumpAndSettle();
      expect(find.text('联网搜索已完成'), findsOneWidget);
      await tester.runAsync(() async {
        final saved = (await AiConversationRepository(store).all()).single;
        final native = saved.display.singleWhere(
          (d) => d['nativeSearch'] == true,
        );
        expect(native['status'], 'completed');
        expect(native['events'], hasLength(2));
        expect(
          saved.display.any(
            (d) => (d['text'] as String? ?? '').contains(
              '[来源 1](https://example.test/news)',
            ),
          ),
          isTrue,
        );
      });
      await tester.runAsync(RuntimeLog.flush);
      for (final action in [
        'model-picker-cancelled',
        'native-search-toggled',
        'reasoning-selected',
      ]) {
        expect(logEntries.any((e) => e.contains(action)), isTrue);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(app);
      await tick();
      expect(find.byTooltip('切换模型：搜索模型'), findsOneWidget);
      expect(find.byTooltip('关闭模型自带搜索'), findsOneWidget);
      expect(find.byTooltip('思考程度：高'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await (await store.database).close();
      });
    },
  );

  for (final outcome in ['cancelled', 'failed']) {
    testWidgets(
      'native search without a completion event ends on $outcome after partial text',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        sqfliteFfiInit();
        final store = LocalDatabase.at(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfiNoIsolate,
        );
        await tester.runAsync(() async {
          await AiConversationRepository(store).save(
            AiConversation(
              id: 'native',
              model: 'm',
              options: const AiGenerationOptions(webSearch: true),
              display: [
                {
                  'kind': 'text',
                  'id': 'old',
                  'author': 'assistant',
                  'text': '欢迎',
                },
              ],
            ),
          );
        });
        final platform = DemoCithubPlatform();
        await platform.writeAiApiKey('test-key');
        final mock = CapturingReplyClient();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              localDatabaseProvider.overrideWithValue(store),
              cithubPlatformProvider.overrideWithValue(platform),
              aiSettingsProvider.overrideWith(
                (_) async => const AiSettings(
                  models: [
                    AiModel(
                      id: 'm',
                      name: 'M',
                      responsesApi: true,
                      nativeSearch: true,
                    ),
                  ],
                ),
              ),
              aiClientFactoryProvider.overrideWithValue(
                () => AiClient(client: mock, log: (_) {}),
              ),
            ],
            child: const MaterialApp(home: AiScreen()),
          ),
        );
        Future<void> tick() async {
          for (var i = 0; i < 15; i++) {
            await tester.pump(const Duration(milliseconds: 50));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 5)),
            );
          }
        }

        await tick();
        await tester.enterText(find.byType(TextField), '搜索消息');
        await tester.tap(find.byTooltip('发送'));
        await tick();
        mock.event({
          'type': 'response.web_search_call.searching',
          'item_id': 'ws-stopped',
        });
        await tick();
        mock.event({'type': 'response.output_text.delta', 'delta': '部分回答'});
        await tick();
        if (outcome == 'cancelled') {
          await tester.tap(find.byTooltip('停止'));
          unawaited(mock.chunks.close());
        } else {
          mock.chunks.addError(StateError('failed during native search'));
          await mock.chunks.close();
        }
        await tick();
        await tester.pumpAndSettle();
        expect(
          find.text(outcome == 'cancelled' ? '联网搜索已停止' : '联网搜索中断'),
          findsOneWidget,
        );
        await tester.runAsync(() async {
          final saved = (await AiConversationRepository(store).all()).single;
          final source = saved.display.singleWhere(
            (d) => d['nativeSearch'] == true,
          );
          expect(source['status'], outcome);
          expect(source['pending'], false);
          expect(saved.display.any((d) => d['text'] == '部分回答'), true);
        });
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await (await store.database).close();
        });
      },
    );
  }

  testWidgets(
    'restored source results use a collapsed Rikka card beside the body',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      sqfliteFfiInit();
      final store = LocalDatabase.at(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfiNoIsolate,
      );
      await tester.runAsync(() async {
        await AiConversationRepository(store).save(
          AiConversation(
            id: 'sources',
            display: [
              {
                'kind': 'sources',
                'id': 'source-card',
                'actual': 1,
                'items': [
                  {
                    'title': '教育部关于举办中国国际大学生创新大赛的通知',
                    'url': 'https://example.test/news',
                  },
                ],
              },
              {
                'kind': 'text',
                'id': 'body',
                'author': 'assistant',
                'text': '最新校园资讯整理如下。',
              },
            ],
          ),
        );
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localDatabaseProvider.overrideWithValue(store),
            aiSettingsProvider.overrideWith((_) async => const AiSettings()),
          ],
          child: const MaterialApp(home: AiScreen()),
        ),
      );
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
      expect(
        find.byKey(const ValueKey('reasoning-toggle-source-card')),
        findsOneWidget,
      );
      expect(find.text('教育部关于举办中国国际大学生创新大赛的通知'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('reasoning-toggle-source-card')),
      );
      await tester.pumpAndSettle();
      expect(find.text('教育部关于举办中国国际大学生创新大赛的通知'), findsOneWidget);
      expect(find.text('最新校园资讯整理如下。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await (await store.database).close();
      });
    },
  );
  for (final outcome in ['completed', 'cancelled', 'failed']) {
    testWidgets(
      'tool-only news preview collapses on $outcome and retains ten items',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({
          'news.updated.official': DateTime.now().toIso8601String(),
          'news.cache.v1': jsonEncode(
            List.generate(
              12,
              (i) => {
                'id': 'news-$i',
                'source': '教育部',
                'title': '校园通知 $i',
                'link': 'https://example.test/news-$i',
                'summary': '通知正文 $i',
                'html': '<p>通知正文 $i</p>',
                'publishedAt': DateTime(
                  2026,
                  10,
                  13,
                ).subtract(Duration(days: i)).toIso8601String(),
                'section': 'official',
              },
            ),
          ),
        });
        sqfliteFfiInit();
        final store = LocalDatabase.at(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfiNoIsolate,
        );
        await tester.runAsync(() async {
          await store.database;
        });
        final platform = DemoCithubPlatform();
        await platform.writeAiApiKey('key');
        final mock = SourceReplyClient();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              localDatabaseProvider.overrideWithValue(store),
              cithubPlatformProvider.overrideWithValue(platform),
              aiSettingsProvider.overrideWith(
                (_) async => const AiSettings(
                  models: [AiModel(id: 'm', name: 'Gpt6')],
                ),
              ),
              aiClientFactoryProvider.overrideWithValue(
                () => AiClient(client: mock, log: (_) {}),
              ),
            ],
            child: const MaterialApp(home: AiScreen()),
          ),
        );
        Future<void> tick() async {
          for (var i = 0; i < 15; i++) {
            await tester.pump(const Duration(milliseconds: 50));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 5)),
            );
          }
        }

        await tick();
        await tester.enterText(find.byType(TextField), '整理最新校园资讯');
        await tester.tap(find.byTooltip('发送'));
        await tick();
        expect(mock.calls, 2);
        final card = tester.widget<AiReasoningCard>(
          find.byType(AiReasoningCard),
        );
        final id = card.data['id'];
        expect(card.data['actual'], 10);
        expect(find.byKey(ValueKey('reasoning-preview-$id')), findsOneWidget);
        await tester.tap(find.byKey(ValueKey('reasoning-toggle-$id')));
        await tick();
        expect(find.text('校园通知 0'), findsOneWidget);
        if (outcome == 'completed') {
          mock.delta({'content': '最新校园资讯整理如下。'});
          await tick();
          expect(find.text('校园通知 0'), findsNothing);
          expect(find.text('最新校园资讯整理如下。'), findsOneWidget);
          expect(find.text('Gpt6'), findsOneWidget);
          mock.chunks.add(utf8.encode('data: [DONE]\n\n'));
          await mock.chunks.close();
        } else if (outcome == 'cancelled') {
          await tester.tap(find.byTooltip('停止'));
          unawaited(mock.chunks.close());
        } else {
          mock.chunks.addError(StateError('news response failed'));
          await mock.chunks.close();
        }
        await tick();
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('reasoning-preview-$id')), findsNothing);
        expect(find.text('校园通知 0'), findsNothing);
        await tester.runAsync(() async {
          final saved = (await AiConversationRepository(store).all()).single;
          final source = saved.display.singleWhere(
            (d) => d['kind'] == 'sources',
          );
          expect(source['items'], hasLength(10));
          expect(source['requested'], 10);
          expect(source['status'], outcome);
          expect(source['finishedAt'], isNotNull);
          expect(source['elapsedMs'], isA<int>());
        });
        await tester.ensureVisible(
          find.byKey(ValueKey('reasoning-toggle-$id')),
        );
        await tester.tap(find.byKey(ValueKey('reasoning-toggle-$id')));
        await tester.pumpAndSettle();
        expect(find.text('校园通知 0'), findsOneWidget);
        await tester.runAsync(RuntimeLog.flush);
        expect(
          logEntries.any(
            (e) => e.contains('"action":"result"') && e.contains('news-read'),
          ),
          isTrue,
        );
        expect(
          logEntries.any(
            (e) =>
                e.contains('"action":"finished"') &&
                e.contains('"status":"$outcome"') &&
                e.contains('news-read'),
          ),
          isTrue,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await (await store.database).close();
        });
      },
    );
  }

  for (final outcome in ['completed', 'cancelled', 'failed']) {
    testWidgets(
      'live reasoning previews, follows its tail and collapses on $outcome',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
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
        final mock = StreamingReplyClient();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              localDatabaseProvider.overrideWithValue(store),
              cithubPlatformProvider.overrideWithValue(platform),
              aiSettingsProvider.overrideWith(
                (_) async => const AiSettings(
                  models: [AiModel(id: 'm', name: '测试模型')],
                ),
              ),
              aiClientFactoryProvider.overrideWithValue(
                () => AiClient(client: mock, log: (_) {}),
              ),
            ],
            child: MaterialApp(home: const AiScreen()),
          ),
        );
        Future<void> tick() async {
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 50));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 5)),
            );
          }
        }

        await tick();
        await tester.enterText(find.byType(TextField), '原神是什么');
        await tester.tap(find.byTooltip('发送'));
        await tick();
        expect(mock.started, isTrue);
        mock.delta({
          'reasoning_content': List.generate(20, (i) => '思考段落 $i。\n\n').join(),
        });
        await tick();
        final card = find.byType(AiReasoningCard);
        expect(card, findsOneWidget);
        expect(find.textContaining('正在思考 '), findsOneWidget);
        final reasoning = tester.widget<AiReasoningCard>(card);
        final id = reasoning.data['id'];
        final preview = find.byKey(ValueKey('reasoning-preview-$id'));
        expect(tester.getSize(preview).height, lessThanOrEqualTo(100));
        final scroll = tester.widget<SingleChildScrollView>(
          find.descendant(
            of: preview,
            matching: find.byType(SingleChildScrollView),
          ),
        );
        expect(scroll.controller!.offset, greaterThan(0));
        await tester.tap(find.byKey(ValueKey('reasoning-toggle-$id')));
        await tick();
        expect(preview, findsNothing);
        mock.delta({'reasoning_content': '最新的思考。'});
        await tick();
        expect(
          tester.widget<AiReasoningCard>(card).data['text'],
          endsWith('最新的思考。'),
        );
        // Return from full expansion to the live preview, just like upstream.
        await tester.ensureVisible(
          find.byKey(ValueKey('reasoning-toggle-$id')),
        );
        await tester.tap(find.byKey(ValueKey('reasoning-toggle-$id')));
        await tick();
        expect(preview, findsOneWidget);
        if (outcome == 'completed') {
          mock.delta({'content': '原神是一款开放世界游戏。'});
          await tick();
          // Collapse on the first body chunk, while the stream remains open.
          expect(find.textContaining('思考了 '), findsOneWidget);
          expect(preview, findsNothing);
          expect(find.text('原神是一款开放世界游戏。'), findsOneWidget);
          // One shared header for reasoning and body; model picker is icon-only.
          expect(find.text('测试模型'), findsOneWidget);
          mock.chunks.add(utf8.encode('data: [DONE]\n\n'));
          await mock.chunks.close();
        } else if (outcome == 'cancelled') {
          await tester.tap(find.byTooltip('停止'));
          unawaited(mock.chunks.close());
        } else {
          mock.chunks.addError(StateError('stream failed'));
          await mock.chunks.close();
        }
        await tick();
        await tester.pumpAndSettle();
        expect(preview, findsNothing);
        expect(mock.closed, isTrue);
        late AiConversation saved;
        await tester.runAsync(() async {
          saved = (await AiConversationRepository(store).all()).single;
        });
        final data = saved.display.singleWhere((d) => d['kind'] == 'reasoning');
        expect(data['status'], outcome);
        expect(data['text'], endsWith('最新的思考。'));
        expect(data['finishedAt'], isNotNull);
        expect(data['elapsedMs'], isA<int>());
        await tester.ensureVisible(
          find.byKey(ValueKey('reasoning-toggle-$id')),
        );
        await tester.tap(find.byKey(ValueKey('reasoning-toggle-$id')));
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('copy-$id')), findsOneWidget);
        await tester.runAsync(RuntimeLog.flush);
        final events = logEntries
            .where((e) => e.startsWith('{'))
            .map((e) => jsonDecode(e) as Map)
            .toList();
        expect(
          events.any(
            (e) => e['action'] == 'started' && e['data']['messageId'] == id,
          ),
          isTrue,
        );
        expect(
          events.any(
            (e) =>
                e['action'] == 'updated' &&
                e['data']['after']['text'] == data['text'],
          ),
          isTrue,
        );
        expect(
          events.any(
            (e) => e['action'] == 'finished' && e['data']['result'] == outcome,
          ),
          isTrue,
        );
        expect(
          events.any(
            (e) =>
                e['action'] == 'visibility-changed' &&
                e['data']['messageId'] == id,
          ),
          isTrue,
        );
        if (outcome == 'failed') {
          expect(
            events.any(
              (e) => e['action'] == 'failed' && e['data']['stack'] is String,
            ),
            isTrue,
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await (await store.database).close();
        });
      },
    );
  }

  for (final approve in [true, false]) {
    testWidgets(
      'chat requests write permission and persists the ${approve ? 'approved' : 'denied'} result',
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
        await tester.tap(find.byTooltip('发送'));
        await settle();
        expect(find.text('允许 AI 修改课表？'), findsOneWidget);
        expect(find.byType(SwitchListTile), findsNothing);
        expect(mock.calls, 2);
        await tester.runAsync(() async {
          expect(await TimetableRepository(store).active(), isNull);
        });
        await tester.tap(find.text(approve ? '允许' : '不允许'));
        await settle();
        await tester.runAsync(() async {
          final reasoning = (await AiConversationRepository(store).all())
              .single
              .display
              .where((d) => d['kind'] == 'reasoning')
              .toList();
          expect(reasoning, hasLength(2));
          expect(reasoning.every((d) => d['status'] == 'completed'), isTrue);
          expect(reasoning.map((d) => d['replyId']).toSet(), hasLength(2));
        });
        if (!approve) {
          expect(find.text('课表已保存'), findsNothing);
          expect(mock.calls, 3);
          await tester.runAsync(() async {
            expect(await TimetableRepository(store).active(), isNull);
          });
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() async {
            await (await store.database).close();
          });
          return;
        }
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
          expect(
            (await (await store.database).query('conversations')).length,
            1,
          );
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
  }

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
      expect(find.byType(SwitchListTile), findsNothing);
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
      expect(find.textContaining('思考了'), findsOneWidget);
      await tester.tap(find.textContaining('思考了'));
      await tick();
      expect(find.text('接口返回的思考'), findsOneWidget);
      final clipboard = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      late AiConversation saved;
      await tester.runAsync(() async {
        saved = (await AiConversationRepository(store).all()).single;
      });
      for (final text in ['查询课程', '后台完成的回复', '接口返回的思考']) {
        final id = saved.display.firstWhere((d) => d['text'] == text)['id'];
        final button = find.byKey(ValueKey('copy-$id'));
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pump();
        expect(clipboard.last, text);
      }
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await (await store.database).close();
      });
    },
  );
}
