import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../native/cithub_api.g.dart';

/// Serializes writes so export includes every entry queued before the tap.
class RuntimeLog {
  static final _api = RuntimeLogHostApi();
  static Future<void> _pending = Future<void>.value();

  static void write(String source, String message) {
    _pending = _pending.then((_) async {
      try {
        await _api.append(source, message);
      } catch (error) {
        // Report persistence failures without recursively calling the logger.
        Zone.root.print('Cithub log persistence failed: $error');
      }
    });
  }

  static Future<void> flush() => _pending;

  static void installErrorHandlers() {
    final previousPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) write('flutter-console', message);
      previousPrint(message, wrapWidth: wrapWidth);
    };
    final previousError = FlutterError.onError;
    FlutterError.onError = (details) {
      write('flutter-error', details.toString());
      previousError?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      write('dart-error', '$error\n$stack');
      return false;
    };
    write('runtime', 'Application started; redaction=false');
  }
}

class LoggingHttpClient extends http.BaseClient {
  LoggingHttpClient(this._inner);
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().toBytes();
    RuntimeLog.write(
      'http',
      'REQUEST ${request.method} ${request.url} headers=${request.headers} bodyBase64=${base64Encode(body)}',
    );
    final copy = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = body
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection;
    try {
      final response = await _inner.send(copy);
      final bytes = await response.stream.toBytes();
      RuntimeLog.write(
        'http',
        'RESPONSE ${response.statusCode} ${request.url} headers=${response.headers} bodyBase64=${base64Encode(bytes)}',
      );
      return http.StreamedResponse(
        Stream.value(bytes),
        response.statusCode,
        contentLength: bytes.length,
        request: request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } catch (error, stack) {
      RuntimeLog.write('http', 'FAILURE ${request.url} $error\n$stack');
      rethrow;
    }
  }

  @override
  void close() => _inner.close();
}
