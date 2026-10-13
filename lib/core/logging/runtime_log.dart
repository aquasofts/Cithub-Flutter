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
    // Log persistence outlives the operation's zone (including background work
    // and tests with separate fake clocks). Keep the serialized writer on the
    // application event loop so an abandoned caller cannot strand export.
    Zone.root.run(() {
      _pending = _pending.then((_) async {
        try {
          await _api.append(source, message);
        } catch (error) {
          // Report persistence failures without recursively calling the logger.
          Zone.root.print('Cithub log persistence failed: $error');
        }
      });
    });
  }

  static int _sequence = 0;

  static String describe(Object? value) {
    try {
      return jsonEncode(
        value,
        toEncodable: (dynamic object) {
          try {
            return object.toJson();
          } catch (_) {
            /* Native DTOs use encode. */
          }
          try {
            return object.encode();
          } catch (_) {
            return object.toString();
          }
        },
      );
    } catch (error) {
      return jsonEncode({'value': '$value', 'serializationError': '$error'});
    }
  }

  static void event(String source, String action, [Object? data]) =>
      write(source, describe({'action': action, 'data': data}));

  static Future<T> trace<T>(
    String source,
    String action,
    Object? arguments,
    Future<T> Function() operation,
  ) async {
    final id = '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
    final watch = Stopwatch()..start();
    event(source, 'start', {
      'id': id,
      'operation': action,
      'arguments': arguments,
    });
    try {
      final result = await operation();
      event(source, 'success', {
        'id': id,
        'operation': action,
        'elapsedMs': watch.elapsedMilliseconds,
        'result': result,
      });
      return result;
    } catch (error, stack) {
      event(source, 'failure', {
        'id': id,
        'operation': action,
        'elapsedMs': watch.elapsedMilliseconds,
        'error': '$error',
        'stack': '$stack',
      });
      rethrow;
    }
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
  LoggingHttpClient(this._inner, {this.streaming = false});
  final bool streaming;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final watch = Stopwatch()..start();
    final id =
        '${DateTime.now().microsecondsSinceEpoch}-${RuntimeLog._sequence++}';
    final body = await request.finalize().toBytes();
    RuntimeLog.write(
      'http',
      'REQUEST id=$id ${request.method} ${request.url} headers=${request.headers} bodyBase64=${base64Encode(body)}',
    );
    final copy =
        (request is http.Abortable
              ? http.AbortableRequest(
                  request.method,
                  request.url,
                  abortTrigger: request.abortTrigger,
                )
              : http.Request(request.method, request.url))
          ..headers.addAll(request.headers)
          ..bodyBytes = body
          ..followRedirects = request.followRedirects
          ..maxRedirects = request.maxRedirects
          ..persistentConnection = request.persistentConnection;
    try {
      final response = await _inner.send(copy);
      if (streaming) {
        RuntimeLog.write(
          'http',
          'RESPONSE id=$id ${response.statusCode} ${request.url} headers=${response.headers}',
        );
        var chunk = 0;
        var ended = false;
        var failed = false;
        late StreamSubscription<List<int>> subscription;
        late StreamController<List<int>> controller;
        void end(bool completed) {
          if (ended) return;
          ended = true;
          RuntimeLog.write(
            'http',
            'STREAM END id=$id completed=$completed chunks=$chunk elapsedMs=${watch.elapsedMilliseconds}',
          );
        }

        controller = StreamController<List<int>>(
          onListen: () {
            subscription = response.stream.listen(
              (bytes) {
                RuntimeLog.write(
                  'http',
                  'CHUNK id=$id index=${chunk++} bodyBase64=${base64Encode(bytes)}',
                );
                controller.add(bytes);
              },
              onError: (Object error, StackTrace stack) {
                failed = true;
                RuntimeLog.write(
                  'http',
                  'STREAM FAILURE id=$id $error\n$stack',
                );
                controller.addError(error, stack);
              },
              onDone: () {
                end(!failed);
                controller.close();
              },
            );
          },
          onPause: () => subscription.pause(),
          onResume: () => subscription.resume(),
          onCancel: () {
            end(false);
            return subscription.cancel();
          },
        );
        return http.StreamedResponse(
          controller.stream,
          response.statusCode,
          contentLength: response.contentLength,
          request: request,
          headers: response.headers,
          isRedirect: response.isRedirect,
          persistentConnection: response.persistentConnection,
          reasonPhrase: response.reasonPhrase,
        );
      }
      final bytes = await response.stream.toBytes();
      RuntimeLog.write(
        'http',
        'RESPONSE id=$id ${response.statusCode} ${request.url} headers=${response.headers} bodyBase64=${base64Encode(bytes)} elapsedMs=${watch.elapsedMilliseconds}',
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
      RuntimeLog.write(
        'http',
        'FAILURE id=$id ${request.url} elapsedMs=${watch.elapsedMilliseconds} $error\n$stack',
      );
      rethrow;
    }
  }

  @override
  void close() => _inner.close();
}
