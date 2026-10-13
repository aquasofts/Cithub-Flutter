import 'dart:async';
import 'dart:convert';

import 'package:cithub_flutter/features/ai/ai_client.dart';
import 'package:cithub_flutter/features/ai/ai_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class StreamingClient extends http.BaseClient {
  StreamingClient(this.chunks, {this.status = 200});
  final List<List<int>> chunks;
  final int status;
  http.BaseRequest? request;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest r) async {
    request = r;
    return http.StreamedResponse(
      Stream.fromIterable(chunks),
      status,
      headers: {'content-type': 'text/event-stream'},
    );
  }
}

class WaitingClient extends http.BaseClient {
  final response = Completer<http.StreamedResponse>();
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      response.future;
  @override
  void close() {
    closed = true;
  }
}

void main() {
  testWidgets(
    'configured timeout closes a stalled connection with a retry message',
    (tester) async {
      final mock = WaitingClient();
      final future = expectLater(
        AiClient(client: mock, log: (_) {})
            .complete(
              settings: const AiSettings(timeoutSeconds: 300),
              key: 'k',
              model: const AiModel(id: 'm', name: 'M'),
              messages: [],
              cancellation: AiCancellation(),
            )
            .toList(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('300 秒'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 299));
      expect(mock.closed, false);
      await tester.pump(const Duration(seconds: 2));
      await future;
      expect(mock.closed, true);
    },
  );

  test(
    'completion finish marker is accepted without a separate DONE event',
    () async {
      final mock = StreamingClient([
        utf8.encode(
          'data: {"choices":[{"delta":{"content":"完成"},"finish_reason":"stop"}]}\n\n',
        ),
      ]);
      final events = await AiClient(client: mock, log: (_) {})
          .complete(
            settings: const AiSettings(),
            key: 'k',
            model: const AiModel(id: 'm', name: 'M'),
            messages: [],
            cancellation: AiCancellation(),
          )
          .toList();
      expect(events.map((e) => e.text).join(), '完成');
      expect(events.last.finished, true);
    },
  );

  test('streams reasoning separately and sends to the selected model endpoint', () async {
    final mock = StreamingClient([
      utf8.encode(
        'data: {"choices":[{"delta":{"reasoning_content":"检查课程"}}]}\n\n'
        'data: {"choices":[{"delta":{"reasoning":"完成检查","content":"结果"}}]}\n\n'
        'data: [DONE]\n\n',
      ),
    ]);
    final events = await AiClient(client: mock, log: (_) {})
        .complete(
          settings: const AiSettings(baseUrl: 'https://legacy.test/v1'),
          key: 'model-key',
          model: const AiModel(
            id: 'm',
            name: 'M',
            baseUrl: 'https://model.test/v1',
          ),
          messages: [],
          cancellation: AiCancellation(),
        )
        .toList();
    expect(events.map((e) => e.reasoning).join(), '检查课程完成检查');
    expect(events.map((e) => e.text).join(), '结果');
    expect(mock.request!.url.host, 'model.test');
    expect(mock.request!.headers['Authorization'], 'Bearer model-key');
  });

  test('AI logs contain status only, never key or message text', () async {
    final logs = <String>[];
    final mock = StreamingClient([utf8.encode('data: [DONE]\n\n')]);
    await AiClient(client: mock, log: logs.add)
        .complete(
          settings: const AiSettings(),
          key: 'private-key',
          model: const AiModel(id: 'm', name: 'm'),
          messages: [
            {'role': 'user', 'content': 'private-chat'},
          ],
          cancellation: AiCancellation(),
        )
        .toList();
    expect(logs.join(), contains('status=200'));
    expect(logs.join(), isNot(contains('private-key')));
    expect(logs.join(), isNot(contains('private-chat')));
  });
  test('SSE parses fragmented UTF8 and split tool arguments without buffering response', () async {
    final payload =
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': '你好'},
            },
          ],
        })}\n\n'
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 'call_1',
                    'function': {'name': 'read_schedule', 'arguments': '{'},
                  },
                ],
              },
            },
          ],
        })}\n\n'
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'function': {'arguments': '}'},
                  },
                ],
              },
            },
          ],
        })}\n\n'
        'data: [DONE]\n\n';
    final bytes = utf8.encode(payload);
    final mock = StreamingClient([
      for (var i = 0; i < bytes.length; i += 3)
        bytes.sublist(i, (i + 3).clamp(0, bytes.length)),
    ]);
    final events = await AiClient(client: mock, log: (_) {})
        .complete(
          settings: const AiSettings(baseUrl: 'https://service.test/v1/'),
          key: 'secret',
          model: const AiModel(id: 'model', name: 'Model'),
          messages: [
            {'role': 'user', 'content': 'hi'},
          ],
          cancellation: AiCancellation(),
        )
        .toList();
    expect(events.map((d) => d.text).join(), '你好');
    expect(events.last.toolCalls.single['function']['arguments'], '{}');
    expect(
      mock.request!.url.toString(),
      'https://service.test/v1/chat/completions',
    );
    expect(mock.request!.followRedirects, false);
  });
  test('errors do not expose server bodies or keys', () async {
    final client = AiClient(
      log: (_) {},
      client: StreamingClient([utf8.encode('secret in error')], status: 401),
    );
    await expectLater(
      client
          .complete(
            settings: const AiSettings(),
            key: 'secret',
            model: const AiModel(id: 'm', name: 'm'),
            messages: [],
            cancellation: AiCancellation(),
          )
          .toList(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'safe error',
          isNot(contains('secret')),
        ),
      ),
    );
  });
  test('cancelled requests stop before network', () async {
    final mock = StreamingClient([]);
    final cancel = AiCancellation()..cancel();
    await expectLater(
      AiClient(client: mock, log: (_) {})
          .complete(
            settings: const AiSettings(),
            key: 'k',
            model: const AiModel(id: 'm', name: 'm'),
            messages: [],
            cancellation: cancel,
          )
          .toList(),
      throwsA(isA<AiCancelled>()),
    );
    expect(mock.request, isNull);
  });
  test('full completion URL and credential URLs are rejected', () {
    expect(
      () =>
          const AiSettings(baseUrl: 'https://test/v1/chat/completions')
              .endpoint,
      throwsFormatException,
    );
    expect(
      () => const AiSettings(baseUrl: 'https://user:secret@test/v1').endpoint,
      throwsFormatException,
    );
  });
}
