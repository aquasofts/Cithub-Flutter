import 'dart:async';
import 'dart:convert';

import 'package:cithub_flutter/core/logging/runtime_log.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('logging preserves HTTP abort triggers and records failed stream completion', () async {
    final entries = <String>[];
    const channel = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.cithub_flutter.RuntimeLogHostApi.append',
      StandardMessageCodec(),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(channel, (value) async {
          entries.add((value! as List)[1] as String);
          return [true];
        });
    final abort = Completer<void>();
    final client = LoggingHttpClient(
      MockClient.streaming((request, body) async {
        expect(request, isA<http.Abortable>());
        expect((request as http.Abortable).abortTrigger, same(abort.future));
        await body.drain<void>();
        return http.StreamedResponse(
          Stream<List<int>>.error(StateError('broken stream')),
          200,
        );
      }),
      streaming: true,
    );
    addTearDown(client.close);
    final response = await client.send(
      http.AbortableRequest(
        'GET',
        Uri.parse('https://example.test/aborted'),
        abortTrigger: abort.future,
      ),
    );
    await expectLater(response.stream.toList(), throwsStateError);
    await RuntimeLog.flush();
    expect(
      entries.any(
        (e) => e.contains('STREAM FAILURE') && e.contains('broken stream'),
      ),
      isTrue,
    );
    expect(
      entries.any(
        (e) => e.contains('STREAM END') && e.contains('completed=false'),
      ),
      isTrue,
    );
  });

  test('HTTP diagnostics preserve credentials and binary bodies across the native log bridge', () async {
    final entries = <List<Object?>>[];
    const channel = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.cithub_flutter.RuntimeLogHostApi.append',
      StandardMessageCodec(),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(channel, (value) async {
          entries.add((value! as List).cast<Object?>());
          return [true];
        });
    final binary = List<int>.generate(256, (i) => i);
    final client = LoggingHttpClient(
      MockClient((request) async {
        expect(request.headers['cookie'], 'SESSION=secret');
        expect(request.body, 'password=原始密码');
        return http.Response.bytes(
          binary,
          200,
          headers: {'set-cookie': 'token=raw'},
        );
      }),
    );
    addTearDown(client.close);
    final response = await client.post(
      Uri.parse('https://example.test/diagnostics'),
      headers: {'cookie': 'SESSION=secret'},
      body: 'password=原始密码',
    );
    await RuntimeLog.flush();
    expect(response.bodyBytes, binary);
    expect(entries, hasLength(2));
    expect(entries[0][1], contains('SESSION=secret'));
    expect(entries[0][1], contains(base64Encode(utf8.encode('password=原始密码'))));
    expect(entries[1][1], contains('token=raw'));
    expect(entries[1][1], contains(base64Encode(binary)));
  });
  test(
    'streaming logs each binary chunk without waiting for response completion',
    () async {
      final entries = <List<Object?>>[];
      const channel = BasicMessageChannel<Object?>(
        'dev.flutter.pigeon.cithub_flutter.RuntimeLogHostApi.append',
        StandardMessageCodec(),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(channel, (value) async {
            entries.add((value! as List).cast<Object?>());
            return [true];
          });
      final stream = StreamController<List<int>>();
      final client = LoggingHttpClient(
        MockClient.streaming((request, body) async {
          await body.drain<void>();
          return http.StreamedResponse(stream.stream, 200);
        }),
        streaming: true,
      );
      addTearDown(client.close);
      final response = await client.send(
        http.Request('GET', Uri.parse('https://example.test/stream')),
      );
      final first = Completer<List<int>>();
      final received = <int>[];
      final subscription = response.stream.listen((bytes) {
        received.addAll(bytes);
        if (!first.isCompleted) first.complete(bytes);
      });
      stream.add([0, 255]);
      expect(await first.future, [0, 255]);
      await RuntimeLog.flush();
      expect(
        entries.any(
          (e) =>
              (e[1] as String).contains('CHUNK') &&
              (e[1] as String).contains('AP8='),
        ),
        isTrue,
      );
      await subscription.cancel();
      await stream.close();
      await RuntimeLog.flush();
      expect(
        entries.any((e) => (e[1] as String).contains('completed=false')),
        isTrue,
      );
    },
  );

  test(
    'operations retain arguments, results and failures with correlation IDs',
    () async {
      final entries = <List<Object?>>[];
      const channel = BasicMessageChannel<Object?>(
        'dev.flutter.pigeon.cithub_flutter.RuntimeLogHostApi.append',
        StandardMessageCodec(),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(channel, (value) async {
            entries.add((value! as List).cast<Object?>());
            return [true];
          });
      expect(
        await RuntimeLog.trace('manual', 'save', {
          'before': '旧',
          'after': '新',
        }, () async => {'revision': 2}),
        {'revision': 2},
      );
      await expectLater(
        RuntimeLog.trace('ai-tool', 'update', {
          'id': 'call-1',
        }, () async => throw StateError('conflict')),
        throwsStateError,
      );
      await RuntimeLog.flush();
      final events = entries
          .map((e) => jsonDecode(e[1] as String) as Map)
          .toList();
      expect(events.map((e) => e['action']), [
        'start',
        'success',
        'start',
        'failure',
      ]);
      expect(events[0]['data']['id'], events[1]['data']['id']);
      expect(events[0]['data']['arguments']['before'], '旧');
      expect(events[1]['data']['result']['revision'], 2);
      expect(events[3]['data']['error'], contains('conflict'));
    },
  );
}
