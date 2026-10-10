import 'dart:convert';

import 'package:cithub_flutter/core/logging/runtime_log.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
}
