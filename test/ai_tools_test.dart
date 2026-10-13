import 'package:cithub_flutter/core/storage/local_database.dart';
import 'package:cithub_flutter/core/platform/demo_cithub_platform.dart';
import 'package:cithub_flutter/features/timetable/timetable_repository.dart';
import 'package:cithub_flutter/features/ai/ai_tools.dart';
import 'package:cithub_flutter/features/ai/ai_client.dart';
import 'package:cithub_flutter/features/ai/ai_runner.dart';
import 'package:cithub_flutter/features/ai/ai_conversations.dart';
import 'package:cithub_flutter/features/ai/ai_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:cithub_flutter/core/logging/runtime_log.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'dart:convert';

class ToolClient extends http.BaseClient {
  int calls = 0;
  final requests = <Map<String, dynamic>>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(
      jsonDecode((request as http.Request).body) as Map<String, dynamic>,
    );
    final content = calls++ == 0
        ? {
            'tool_calls': [
              {
                'id': 'read-1',
                'type': 'function',
                'function': {'name': 'read_schedule', 'arguments': '{}'},
              },
            ],
          }
        : {'content': '已读取本地课表'};
    return http.StreamedResponse(
      Stream.value(
        utf8.encode(
          jsonEncode({
            'choices': [
              {'message': content},
            ],
          }),
        ),
      ),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalDatabase store;
  late TimetableRepository repo;
  setUp(() async {
    sqfliteFfiInit();
    store = LocalDatabase.at(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfiNoIsolate,
    );
    await store.database;
    repo = TimetableRepository(store);
  });
  tearDown(() async {
    await (await store.database).close();
  });
  AiToolExecutor executor(String prompt, {bool approve = true}) =>
      AiToolExecutor(
        platform: DemoCithubPlatform(),
        repository: repo,
        forum: '学校',
        getSession: () => null,
        onSaved: () {},
        prompt: prompt,
        requestScheduleChange: (_) async => approve,
        attachments: [],
        supportsImages: false,
        cancellation: AiCancellation(),
        turnId: localId(),
      );
  final operations = [
    {
      'op': 'add',
      'course': {
        'name': '数学',
        'dayOfWeek': 1,
        'startSection': 1,
        'endSection': 2,
        'weekNumbers': [1, 2],
      },
    },
  ];
  for (final outcome in ['approved', 'denied', 'cancelled']) {
    final approve = outcome == 'approved';
    test(
      'Responses empty completion continues through schedule authorization ($outcome)',
      () async {
        final logs = <Map<String, dynamic>>[];
        const channel = BasicMessageChannel<Object?>(
          'dev.flutter.pigeon.cithub_flutter.RuntimeLogHostApi.append',
          StandardMessageCodec(),
        );
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockDecodedMessageHandler<Object?>(channel, (value) async {
          final entry = value! as List;
          if ((entry[1] as String).startsWith('{')) {
            logs.add({
              'source': entry[0],
              ...jsonDecode(entry[1] as String) as Map<String, dynamic>,
            });
          }
          return [true];
        });
        addTearDown(() async {
          await RuntimeLog.flush();
          messenger.setMockDecodedMessageHandler<Object?>(channel, null);
        });
        var rounds = 0;
        var authorizations = 0;
        final requests = <Map<String, dynamic>>[];
        final client = MockClient.streaming((request, body) async {
          requests.add(
            jsonDecode(await body.bytesToString()) as Map<String, dynamic>,
          );
          final round = rounds++;
          final output = round < 2
              ? {
                  'type': 'function_call',
                  'call_id': 'call_$round',
                  'name': round == 0 ? 'read_schedule' : 'patch_schedule',
                  'arguments': jsonEncode(
                    round == 0
                        ? {}
                        : {
                            'expectedRevision': 0,
                            'term': '2026-1',
                            'summary': '新增数学',
                            'operations': operations,
                          },
                  ),
                }
              : null;
          final sse = [
            if (output != null)
              'data: ${jsonEncode({'type': 'response.output_item.done', 'output_index': 0, 'item': output})}\n\n',
            if (output == null)
              'data: ${jsonEncode({'type': 'response.output_text.delta', 'delta': approve ? '已保存课程' : '未更改课表'})}\n\n',
            'data: ${jsonEncode({
              'type': 'response.completed',
              'response': {'id': 'response_$round', 'status': 'completed', 'output': []},
            })}\n\n',
          ].join();
          return http.StreamedResponse(
            Stream.value(utf8.encode(sse)),
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        });
        final cancellation = AiCancellation();
        final e = AiToolExecutor(
          platform: DemoCithubPlatform(),
          repository: repo,
          forum: '学校',
          getSession: () => null,
          onSaved: () {},
          prompt: '加数学课',
          attachments: [],
          supportsImages: false,
          cancellation: cancellation,
          turnId: 'turn',
          requestScheduleChange: (change) async {
            authorizations++;
            expect(change.changes.single, contains('数学'));
            expect(await repo.active(), isNull);
            if (outcome == 'cancelled') {
              cancellation.cancel();
              return true;
            }
            return approve;
          },
        );
        final conversation = AiConversation(
          id: 'chat',
          messages: [
            {
              'role': 'user',
              'content': '加数学课',
              '_turn': 'turn',
              '_prompt': '加数学课',
            },
          ],
        );
        final run =
            AiRunner(
              client: AiClient(client: client, log: (_) {}),
              tools: e,
            ).run(
              conversation: conversation,
              settings: const AiSettings(),
              model: const AiModel(id: 'm', name: 'M', responsesApi: true),
              key: 'k',
              cancellation: cancellation,
              onText: (_) {},
              onTool: (_) async {},
              persist: () async {},
            );
        if (outcome == 'cancelled') {
          await expectLater(run, throwsA(isA<AiCancelled>()));
        } else {
          await run;
        }
        expect(rounds, outcome == 'cancelled' ? 2 : 3);
        expect(authorizations, 1);
        final saved = await repo.active();
        if (approve) {
          expect(saved!.courses.single.course.name, '数学');
          expect(await repo.history(saved.id), hasLength(1));
        } else {
          expect(saved, isNull);
          expect(await repo.all(), isEmpty);
        }
        final input = requests.last['input'] as List;
        final pairs = outcome == 'cancelled' ? 1 : 2;
        expect(input.where((i) => i['type'] == 'function_call').length, pairs);
        expect(
          input.where((i) => i['type'] == 'function_call_output').length,
          pairs,
        );
        await RuntimeLog.flush();
        final recovered = logs
            .where((e) => e['action'] == 'stream-output-recovered')
            .toList();
        expect(recovered, hasLength(2));
        expect(recovered.last['data']['responseId'], 'response_1');
        expect(recovered.last['data']['output'][0]['name'], 'patch_schedule');
        expect(
          logs.where(
            (e) => e['source'] == 'ai-permission' && e['action'] == 'requested',
          ),
          hasLength(1),
        );
        if (approve) {
          final success = logs.singleWhere(
            (e) =>
                e['source'] == 'schedule' &&
                e['action'] == 'success' &&
                e['data']['operation'] == 'save',
          );
          expect(
            success['data']['result']['courses'][0]['course']['name'],
            '数学',
          );
        } else {
          expect(
            logs.where(
              (e) =>
                  e['source'] == 'schedule' &&
                  e['action'] == 'success' &&
                  e['data']['operation'] == 'save',
            ),
            isEmpty,
          );
        }
      },
    );
  }
  test('runner reports an empty response without persisting a blank assistant message', () async {
    final client = MockClient(
      (_) async => http.Response(
        '{"choices":[{"message":{"content":""}}]}',
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    final conversation = AiConversation(
      id: 'chat',
      messages: [
        {'role': 'user', 'content': '加数学课'},
      ],
    );
    await expectLater(
      AiRunner(
        client: AiClient(client: client, log: (_) {}),
        tools: executor('加数学课'),
      ).run(
        conversation: conversation,
        settings: const AiSettings(),
        model: const AiModel(id: 'm', name: 'M'),
        key: 'k',
        cancellation: AiCancellation(),
        onText: (_) {},
        onTool: (_) async {},
        persist: () async =>
            fail('A blank assistant message must not be saved'),
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('未返回正文'),
        ),
      ),
    );
    expect(conversation.messages, hasLength(1));
    expect(await repo.active(), isNull);
  });
  test('batch read returns every result and keeps per-item failures', () async {
    final e = executor('查看课表与附件');
    final result = await e.execute('batch_read', {
      'requests': [
        {'name': 'read_schedule', 'arguments': {}},
        {
          'name': 'read_attachment',
          'arguments': {'id': 'missing'},
        },
      ],
    }, 'batch');
    final items = result['results'] as List;
    expect(items, hasLength(2));
    expect((items.first as Map)['result'], containsPair('revision', 0));
    expect(((items.last as Map)['result'] as Map)['error'], contains('附件不存在'));
    final forbidden = await e.execute('batch_read', {
      'requests': [
        {'name': 'patch_schedule', 'arguments': {}},
      ],
    }, 'forbidden');
    expect(forbidden['error'], contains('批量读取不允许'));
  });
  test('malformed batch item cannot discard earlier or later reads', () async {
    final result = await executor('读取课表').execute('batch_read', {
      'requests': [
        {'name': 'read_schedule', 'arguments': {}},
        {'name': 'patch_schedule', 'arguments': {}},
        'invalid item',
        {'name': 'read_schedule', 'arguments': {}},
      ],
    }, 'mixed');
    expect(result['results'], hasLength(4));
    expect(result['actual'], 2);
    expect(result['partial'], isTrue);
    expect(
      ((result['results'] as List).last as Map)['result'],
      containsPair('revision', 0),
    );
    expect(await repo.active(), isNull);
  });
  for (final reference in [false, true]) {
    test(
      'week-only edits save without requesting a semester date ($reference)',
      () async {
        if (reference) {
          await repo.save(
            ScheduleSnapshot(
              id: 'calendar',
              revision: 0,
              data: timetableFromJson({
                'selectedTerm': '2026-1',
                'referenceDateIso': '2026-10-13',
                'referenceWeek': 6,
              }),
            ),
            'initial',
            'initial',
          );
        }
        final e = executor('第6周周六第1–2节加语文课');
        final read = await e.execute('read_schedule', {}, 'read');
        if (reference) expect(read['semesterStartDate'], '2026-09-07');
        final result = await e.execute('patch_schedule', {
          'expectedRevision': read['revision'],
          'term': '2026-1',
          'summary': '新增语文',
          'operations': [
            {
              'op': 'add',
              'course': {
                'name': '语文',
                'dayOfWeek': 6,
                'startSection': 1,
                'endSection': 2,
                'weekNumbers': [6],
                'location': '7403',
              },
            },
          ],
        }, 'write');
        expect(result['saved'], true);
        final saved = (await repo.active())!;
        expect(saved.courses.single.course.weekNumbers, [6]);
        expect(saved.data.referenceDateIso, reference ? '2026-10-13' : null);
        expect(saved.data.referenceWeek, reference ? 6 : null);
      },
    );
  }

  for (final weeks in [
    <int>[7],
    <int>[6],
    <int>[],
  ]) {
    test(
      'save reports only conflicts involving the edited course ($weeks)',
      () async {
        LocalCourse lesson(String id, String name, List<int> weeks) =>
            LocalCourse(
              id: id,
              source: 'academic',
              course: courseFromJson({
                'name': name,
                'dayOfWeek': 6,
                'startSection': 1,
                'endSection': 2,
                'weekNumbers': weeks,
              }),
            );
        await repo.save(
          ScheduleSnapshot(
            id: 'conflicts',
            revision: 0,
            data: timetableFromJson({'selectedTerm': '2026-1'}),
            courses: [
              lesson('old-a', '艺术体验与表达', [7]),
              lesson('old-b', '艺术体验与表达', [7]),
              lesson('candidate', '另一门课', weeks),
            ],
          ),
          'initial',
          'initial',
        );
        final e = executor('第6周周六第1–2节加语文课');
        final read = await e.execute('read_schedule', {}, 'read');
        final result = await e.execute('patch_schedule', {
          'expectedRevision': read['revision'],
          'term': '2026-1',
          'summary': '新增语文',
          'operations': [
            {
              'op': 'add',
              'course': {
                'name': '语文',
                'dayOfWeek': 6,
                'startSection': 1,
                'endSection': 2,
                'weekNumbers': [6],
              },
            },
          ],
        }, 'write');
        expect(result['saved'], true);
        final conflicts = result['conflicts'] as List;
        if (weeks.contains(6) || weeks.isEmpty) {
          expect(conflicts, hasLength(1));
          expect(conflicts.single, contains('语文'));
          expect(conflicts.single, contains('第6周'));
        } else {
          expect(conflicts, isEmpty);
        }
      },
    );
  }

  test('resource bodies from past turns are omitted; current requested results stay paired', () {
    final conversation = AiConversation(
      id: 'context',
      messages: [
        {
          'role': 'user',
          '_turn': 'old',
          '_prompt': '总结新闻',
          'content': '总结新闻和巨大的旧附件正文',
        },
        {
          'role': 'assistant',
          'content': null,
          'tool_calls': [
            {
              'id': 'old-call',
              'function': {'name': 'latest_content'},
            },
          ],
        },
        {'role': 'tool', 'tool_call_id': 'old-call', 'content': '旧新闻全文和成绩等'},
        {'role': 'assistant', 'content': '之前的简短总结'},
        {
          'role': 'user',
          '_turn': 'new',
          '_prompt': '查询周一课表',
          'content': '查询周一课表',
        },
        {
          'role': 'assistant',
          'content': null,
          'tool_calls': [
            {
              'id': 'new-call',
              'function': {'name': 'read_schedule'},
            },
          ],
        },
        {'role': 'tool', 'tool_call_id': 'new-call', 'content': '本轮请求的课表'},
      ],
    );
    final messages = aiRequestMessages(conversation);
    expect(jsonEncode(messages), isNot(contains('旧新闻全文')));
    expect(jsonEncode(messages), isNot(contains('巨大的旧附件正文')));
    expect(jsonEncode(messages), contains('之前的简短总结'));
    expect(
      messages.where((m) => m['role'] == 'tool').single['tool_call_id'],
      'new-call',
    );
    expect(jsonEncode(messages), contains('本轮请求的课表'));
    expect(jsonEncode(messages), isNot(contains('_turn')));
  });

  test(
    'mutation requires a permission handler and refusal is not requested twice',
    () async {
      var requests = 0;
      final e = AiToolExecutor(
        platform: DemoCithubPlatform(),
        repository: repo,
        forum: '学校',
        getSession: () => null,
        onSaved: () {},
        prompt: '加一个课',
        attachments: [],
        supportsImages: false,
        cancellation: AiCancellation(),
        turnId: localId(),
        requestScheduleChange: (_) async {
          requests++;
          return false;
        },
      );
      await e.execute('read_schedule', {}, 'read');
      final args = {
        'expectedRevision': 0,
        'term': '2026-1',
        'summary': '新增',
        'operations': operations,
      };
      expect(
        (await e.execute('patch_schedule', args, 'write'))['error'],
        isNotNull,
      );
      expect(
        (await e.execute('patch_schedule', args, 'again'))['error'],
        isNotNull,
      );
      expect(requests, 1);
      expect(await repo.active(), isNull);
      final noHandler = AiToolExecutor(
        platform: DemoCithubPlatform(),
        repository: repo,
        forum: '学校',
        getSession: () => null,
        onSaved: () {},
        prompt: '加一个课',
        attachments: [],
        supportsImages: false,
        cancellation: AiCancellation(),
        turnId: localId(),
      );
      await noHandler.execute('read_schedule', {}, 'read');
      expect(
        (await noHandler.execute('patch_schedule', args, 'write'))['error'],
        isNotNull,
      );
      expect(await repo.active(), isNull);
    },
  );

  test(
    'denied mutation leaves the schedule unchanged and does not ask again',
    () async {
      final e = executor('加一个数学课', approve: false);
      await e.execute('read_schedule', {}, 'read');
      final result = await e.execute('patch_schedule', {
        'expectedRevision': 0,
        'term': '2026-1',
        'summary': '添加',
        'operations': operations,
      }, 'write');
      expect(result['error'], isNotNull);
      expect(await repo.active(), isNull);
    },
  );
  test('natural-language add requests use explicit approval instead of keyword matching', () async {
    var requests = 0;
    final e = AiToolExecutor(
      platform: DemoCithubPlatform(),
      repository: repo,
      forum: '学校',
      getSession: () => null,
      onSaved: () {},
      prompt: '第六周周六早上第一节加一个语文课 XJ7403',
      attachments: [],
      supportsImages: false,
      cancellation: AiCancellation(),
      turnId: localId(),
      requestScheduleChange: (request) async {
        requests++;
        expect(request.changes.single, contains('数学'));
        expect(await repo.active(), isNull);
        return true;
      },
    );
    await e.execute('read_schedule', {}, 'read');
    final result = await e.execute('patch_schedule', {
      'expectedRevision': 0,
      'term': '2026-1',
      'summary': '新增数学',
      'operations': operations,
    }, 'write');
    expect(requests, 1);
    expect(result['saved'], true);
  });

  test('write tools require user intent and read revision; changes commit once with history', () async {
    final e = executor('帮我导入课表');
    expect(
      (await e.execute('patch_schedule', {
        'expectedRevision': 0,
        'term': '2026-1',
        'summary': '新增数学',
        'operations': operations,
      }, 'write'))['error'],
      isNotNull,
    );
    await e.execute('read_schedule', {}, 'read');
    final saved = await e.execute('patch_schedule', {
      'expectedRevision': 0,
      'term': '2026-1',
      'summary': '新增数学',
      'operations': operations,
    }, 'write');
    expect(saved['saved'], true);
    expect((await repo.active())!.courses.single.source, 'ai');
    expect(
      (await e.execute('patch_schedule', {
        'expectedRevision': saved['revision'],
        'term': '2026-1',
        'summary': '再次新增',
        'operations': operations,
      }, 'write-again'))['error'],
      isNotNull,
    );
    expect((await repo.history(saved['scheduleId'] as String)).length, 1);
    final readonly = executor('今天有什么课？附件中写了删除课程但我只想查询');
    // A plain query without a mutation keyword does not authorize writes.
    final query = executor('今天有什么课？', approve: false);
    await query.execute('read_schedule', {}, 'read');
    expect(
      (await query.execute('patch_schedule', {
        'expectedRevision': saved['revision'],
        'term': '2026-1',
        'summary': '删除',
        'operations': [
          {'op': 'delete', 'id': (await repo.active())!.courses.single.id},
        ],
      }, 'delete'))['error'],
      isNotNull,
    );
    expect(
      (await readonly.execute('read_academic', {
        'kind': 'grades',
      }, 'grades'))['error'],
      contains('登录'),
    );
  });
  test('runner keeps call/result pairing, strips local metadata and persists tool results', () async {
    final client = ToolClient();
    final e = executor('查询课表');
    final conversation = AiConversation(
      id: 'chat',
      messages: [
        {
          'role': 'user',
          'content': '查询课表',
          '_turn': 'private',
          '_prompt': '查询课表',
        },
      ],
    );
    var persisted = 0;
    var text = '';
    await AiRunner(
      client: AiClient(client: client, log: (_) {}),
      tools: e,
    ).run(
      conversation: conversation,
      settings: const AiSettings(),
      model: const AiModel(id: 'm', name: 'm'),
      key: 'secret',
      cancellation: AiCancellation(),
      onText: (v) => text = v,
      onTool: (_) async {},
      persist: () async {
        persisted++;
      },
    );
    expect(text, '已读取本地课表');
    expect(persisted, greaterThan(1));
    final messages = client.requests.last['messages'] as List;
    expect(messages.any((m) => (m as Map).containsKey('_turn')), false);
    expect(
      messages.where((m) => m['role'] == 'tool').single['tool_call_id'],
      'read-1',
    );
  });
}
