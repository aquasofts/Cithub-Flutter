import 'dart:async';
import 'dart:convert';

import 'package:cithub_flutter/features/ai/ai_client.dart';
import 'package:cithub_flutter/features/ai/ai_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cithub_flutter/features/ai/ai_responses.dart';

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
  for (final emptyOutput in [false, true]) {
    test(
      'Responses keeps completed stream items when final output is ${emptyOutput ? 'empty' : 'missing'}',
      () async {
        final output = [
          {
            'type': 'reasoning',
            'id': 'rs_1',
            'summary': [],
            'encrypted_content': 'encrypted',
          },
          for (final name in ['read_attachment', 'read_schedule'])
            {
              'type': 'function_call',
              'call_id': 'call_$name',
              'name': name,
              'arguments': name == 'read_attachment'
                  ? '{"id":"attachment"}'
                  : '{}',
            },
        ];
        final sse = [
          for (var i = 0; i < output.length; i++)
            'data: ${jsonEncode({'type': 'response.output_item.done', 'output_index': i, 'item': output[i]})}\n\n',
          'data: ${jsonEncode({
            'type': 'response.completed',
            'response': {'status': 'completed', if (emptyOutput) 'output': []},
          })}\n\n',
        ].join();
        final mock = StreamingClient([
          for (var i = 0; i < sse.length; i += 31)
            utf8.encode(
              sse.substring(i, i + 31 < sse.length ? i + 31 : sse.length),
            ),
        ]);
        final events = await AiClient(client: mock, log: (_) {})
            .complete(
              settings: const AiSettings(),
              key: 'k',
              model: const AiModel(id: 'm', name: 'M', responsesApi: true),
              messages: [],
              cancellation: AiCancellation(),
            )
            .toList();
        expect(events.last.toolCalls.map((c) => c['function']['name']), [
          'read_attachment',
          'read_schedule',
        ]);
        expect(events.last.responseItems, output);
      },
    );
  }
  for (final responses in [false, true]) {
    test(
      'native search and reasoning use the $responses protocol without local tools',
      () async {
        final mock = StreamingClient([
          utf8.encode(
            responses
                ? 'data: {"type":"response.completed","response":{"status":"completed","output":[]}}\n\n'
                : 'data: [DONE]\n\n',
          ),
        ]);
        await AiClient(client: mock, log: (_) {})
            .complete(
              settings: const AiSettings(),
              key: 'fake-key',
              model: AiModel(
                id: 'm',
                name: 'M',
                responsesApi: responses,
                tools: false,
                nativeSearch: true,
                reasoning: true,
              ),
              options: const AiGenerationOptions(
                webSearch: true,
                reasoningEffort: 'high',
              ),
              messages: [],
              cancellation: AiCancellation(),
            )
            .toList();
        final body = jsonDecode((mock.request! as http.Request).body) as Map;
        if (responses) {
          expect(body['tools'], [
            {'type': 'web_search'},
          ]);
          expect(body['reasoning'], {'effort': 'high', 'summary': 'auto'});
          expect(body['include'], contains('web_search_call.action.sources'));
          expect(body.containsKey('web_search_options'), false);
        } else {
          expect(body['web_search_options'], isEmpty);
          expect(body['reasoning_effort'], 'high');
          expect(body.containsKey('tools'), false);
          expect(body.containsKey('reasoning'), false);
        }
      },
    );
    test(
      'unsupported capabilities omit stale conversation options ($responses)',
      () async {
        final mock = StreamingClient([
          utf8.encode(
            responses
                ? 'data: {"type":"response.completed","response":{"status":"completed","output":[]}}\n\n'
                : 'data: [DONE]\n\n',
          ),
        ]);
        await AiClient(client: mock, log: (_) {})
            .complete(
              settings: const AiSettings(),
              key: 'fake-key',
              model: AiModel(id: 'm', name: 'M', responsesApi: responses),
              options: const AiGenerationOptions(
                webSearch: true,
                reasoningEffort: 'high',
              ),
              messages: [],
              cancellation: AiCancellation(),
            )
            .toList();
        final body = jsonDecode((mock.request! as http.Request).body) as Map;
        expect(body.containsKey('web_search_options'), false);
        expect(body.containsKey('reasoning_effort'), false);
        expect(body.containsKey('reasoning'), false);
        expect(body.containsKey('tools'), false);
      },
    );
  }

  test('native search events and inline citations stay distinct from local calls', () async {
    final search = {
      'id': 'ws_1',
      'type': 'web_search_call',
      'status': 'completed',
      'action': {
        'type': 'search',
        'query': '校园消息',
        'sources': [
          {'type': 'url', 'title': '通知', 'url': 'https://example.test/news'},
        ],
      },
    };
    final output = [
      search,
      {
        'type': 'message',
        'content': [
          {
            'type': 'output_text',
            'text': '公告😀',
            'annotations': [
              {
                'type': 'url_citation',
                'title': '通知',
                'url': 'https://example.test/news',
                'start_index': 0,
                'end_index': 3,
              },
            ],
          },
        ],
      },
    ];
    final mock = StreamingClient([
      utf8.encode(
        'data: {"type":"response.web_search_call.searching","item_id":"ws_1"}\n\n'
        'data: {"type":"response.output_text.delta","delta":"公告😀"}\n\n'
        'data: ${jsonEncode({'type': 'response.output_item.done', 'output_index': 0, 'item': search})}\n\n'
        'data: ${jsonEncode({
          'type': 'response.completed',
          'response': {'status': 'completed', 'output': output},
        })}\n\n',
      ),
    ]);
    final events = await AiClient(client: mock, log: (_) {})
        .complete(
          settings: const AiSettings(),
          key: 'fake-key',
          model: const AiModel(
            id: 'm',
            name: 'M',
            responsesApi: true,
            nativeSearch: true,
          ),
          options: const AiGenerationOptions(webSearch: true),
          messages: [],
          cancellation: AiCancellation(),
        )
        .toList();
    expect(events.where((e) => e.nativeSearch != null), hasLength(3));
    expect(events.last.toolCalls, isEmpty);
    expect(events.last.citations.single['url'], 'https://example.test/news');
    expect(
      textWithCitations('公告😀', events.last.citations),
      '公告😀 [来源 1](https://example.test/news)',
    );
  });

  test('model capabilities and supported levels survive serialization', () {
    final model = AiModel.fromJson(
      const AiModel(
        id: 'm',
        name: 'M',
        nativeSearch: true,
        reasoning: true,
        reasoningEfforts: ['none', 'low', 'xhigh'],
      ).toJson(),
    );
    expect(model.nativeSearch, true);
    expect(model.reasoningEfforts, ['none', 'low', 'xhigh']);
    expect(AiModel.fromJson({'id': 'old', 'name': 'Old'}).nativeSearch, false);
    expect(
      AiGenerationOptions.fromJson({'reasoningEffort': 'invalid'})
          .reasoningEffort,
      'default',
    );
  });

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
  test('SSE final event is parsed even without a trailing blank line', () async {
    final mock = StreamingClient([
      utf8.encode(
        'data: {"choices":[{"delta":{"content":"OK"},"finish_reason":"stop"}]}',
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
    expect(events.map((e) => e.text).join(), 'OK');
    expect(events.last.finished, true);
  });
  test(
    'Responses SSE uses input protocol and returns text, reasoning and calls',
    () async {
      final output = [
        {
          'type': 'reasoning',
          'id': 'rs_1',
          'summary': [],
          'encrypted_content': 'encrypted',
        },
        {
          'type': 'function_call',
          'id': 'fc_1',
          'call_id': 'call_1',
          'name': 'read_schedule',
          'arguments': '{}',
        },
      ];
      final mock = StreamingClient([
        utf8.encode(
          'data: {"type":"response.output_text.delta","delta":"OK"}\n\n'
          'data: {"type":"response.reasoning_summary_text.delta","delta":"检查"}\n\n'
          'data: ${jsonEncode({
            'type': 'response.completed',
            'response': {'status': 'completed', 'output': output},
          })}',
        ),
      ]);
      final events = await AiClient(client: mock, log: (_) {})
          .complete(
            settings: const AiSettings(),
            key: 'k',
            model: const AiModel(id: 'm', name: 'M', responsesApi: true),
            messages: [
              {'role': 'system', 'content': 'System'},
              {
                'role': 'user',
                'content': [
                  {'type': 'text', 'text': 'hi'},
                  {
                    'type': 'image_url',
                    'image_url': {'url': 'data:image/png;base64,abc'},
                  },
                ],
              },
              {
                'role': 'assistant',
                'content': null,
                'tool_calls': [
                  {
                    'id': 'old_call',
                    'function': {'name': 'read_schedule', 'arguments': '{}'},
                  },
                ],
              },
              {'role': 'tool', 'tool_call_id': 'old_call', 'content': '{}'},
            ],
            tools: [
              {
                'type': 'function',
                'function': {
                  'name': 'read_schedule',
                  'parameters': {'type': 'object'},
                },
              },
            ],
            cancellation: AiCancellation(),
          )
          .toList();
      expect(mock.request!.url.path, '/v1/responses');
      final body = jsonDecode((mock.request! as http.Request).body) as Map;
      expect(body.containsKey('messages'), false);
      expect(body['store'], false);
      expect(body['tools'][0]['name'], 'read_schedule');
      expect(body['tools'][0]['strict'], false);
      expect(body['input'][1]['content'][1]['type'], 'input_image');
      expect(body['input'][2]['type'], 'function_call');
      expect(body['input'][3]['call_id'], 'old_call');
      expect(events.map((e) => e.text).join(), 'OK');
      expect(events.map((e) => e.reasoning).join(), '检查');
      expect(events.last.toolCalls.single['id'], 'call_1');
      expect(events.last.responseItems, output);
    },
  );

  test(
    'server model_not_found is explained without exposing response body',
    () async {
      final mock = StreamingClient([
        utf8.encode(
          jsonEncode({
            'error': {'code': 'model_not_found', 'message': 'secret'},
          }),
        ),
      ], status: 503);
      await expectLater(
        AiClient(client: mock, log: (_) {})
            .complete(
              settings: const AiSettings(),
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
            allOf(contains('可用渠道'), isNot(contains('secret'))),
          ),
        ),
      );
    },
  );

  test(
    'Responses JSON reply and reasoning output replay are supported',
    () async {
      final output = [
        {
          'type': 'reasoning',
          'id': 'rs_1',
          'encrypted_content': 'opaque',
          'summary': [
            {'type': 'summary_text', 'text': '检查'},
          ],
        },
        {
          'type': 'message',
          'role': 'assistant',
          'content': [
            {'type': 'output_text', 'text': 'OK'},
          ],
        },
        {
          'type': 'function_call',
          'call_id': 'c1',
          'name': 'read_schedule',
          'arguments': '{}',
        },
      ];
      final mock = MockClient(
        (request) async => http.Response(
          jsonEncode({'status': 'completed', 'output': output}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      final events = await AiClient(client: mock, log: (_) {})
          .complete(
            settings: const AiSettings(),
            key: 'k',
            model: const AiModel(id: 'm', name: 'M', responsesApi: true),
            messages: [],
            cancellation: AiCancellation(),
          )
          .toList();
      expect(events.single.text, 'OK');
      expect(events.single.reasoning, '检查');
      expect(events.single.toolCalls.single['id'], 'c1');
      final body = responsesBody('m', [
        {
          'role': 'assistant',
          'content': 'OK',
          'tool_calls': events.single.toolCalls,
          '_responsesOutput': events.single.responseItems,
        },
        {'role': 'tool', 'tool_call_id': 'c1', 'content': '{}'},
      ], []);
      expect((body['input'] as List).take(3).toList(), output);
      expect(body['input'][3]['type'], 'function_call_output');
    },
  );

  test(
    'Responses incomplete stream fails instead of executing partial tool calls',
    () async {
      final mock = StreamingClient([
        utf8.encode(
          'data: {"type":"response.output_item.done","output_index":0,"item":{"type":"function_call","call_id":"partial","name":"patch_schedule","arguments":"{}"}}\n\n'
          'data: {"type":"response.incomplete","response":{"status":"incomplete"}}\n\n',
        ),
      ]);
      await expectLater(
        AiClient(client: mock, log: (_) {})
            .complete(
              settings: const AiSettings(),
              key: 'k',
              model: const AiModel(id: 'm', name: 'M', responsesApi: true),
              messages: [],
              cancellation: AiCancellation(),
            )
            .toList(),
        throwsA(isA<StateError>()),
      );
    },
  );
  test('API type persists and endpoint addresses normalize', () {
    final model = AiModel.fromJson(
      const AiModel(id: 'm', name: 'M', responsesApi: true).toJson(),
    );
    expect(model.responsesApi, true);
    expect(AiModel.fromJson({'id': 'm', 'name': 'M'}).responsesApi, false);
    for (final address in [
      'https://test',
      'https://test/v1/',
      'https://test/v1/chat/completions',
      'https://test/v1/responses/',
    ]) {
      expect(
        AiSettings(baseUrl: address).endpointFor(model).toString(),
        'https://test/v1/responses',
      );
    }
  });
  test('full completion URLs are normalized and credential URLs rejected', () {
    expect(
      const AiSettings(baseUrl: 'https://test/v1/chat/completions').endpoint
          .toString(),
      'https://test/v1/chat/completions',
    );
    expect(
      () => const AiSettings(baseUrl: 'https://user:secret@test/v1').endpoint,
      throwsFormatException,
    );
  });
}
