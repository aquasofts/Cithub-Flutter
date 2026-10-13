import 'package:cithub_flutter/core/storage/local_database.dart';
import 'package:cithub_flutter/core/platform/demo_cithub_platform.dart';
import 'package:cithub_flutter/features/timetable/timetable_repository.dart';
import 'package:cithub_flutter/features/ai/ai_tools.dart';
import 'package:cithub_flutter/features/ai/ai_client.dart';
import 'package:cithub_flutter/features/ai/ai_runner.dart';
import 'package:cithub_flutter/features/ai/ai_conversations.dart';
import 'package:cithub_flutter/features/ai/ai_settings.dart';
import 'package:flutter_test/flutter_test.dart';
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
  AiToolExecutor executor(String prompt, {bool allowScheduleChanges = true}) =>
      AiToolExecutor(
        platform: DemoCithubPlatform(),
        repository: repo,
        forum: '学校',
        getSession: () => null,
        onSaved: () {},
        prompt: prompt,
        allowScheduleChanges: allowScheduleChanges,
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
  test(
    'explicit read-only toggle blocks mutations even with a write request',
    () async {
      final e = executor('帮我添加数学课', allowScheduleChanges: false);
      expect(e.mayWrite, false);
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
    final query = executor('今天有什么课？');
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
