import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/logging/runtime_log.dart';
import '../../core/utils/rate_limit.dart';
import 'ai_settings.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

final aiClientFactoryProvider = Provider<AiClient Function()>(
  (ref) =>
      () => AiClient(),
);

class AiCancelled implements Exception {}

class AiCancellation {
  bool cancelled = false;
  final _callbacks = <void Function()>[];
  void check() {
    if (cancelled) throw AiCancelled();
  }

  void onCancel(void Function() callback) {
    if (cancelled) {
      callback();
    } else {
      _callbacks.add(callback);
    }
  }

  void cancel() {
    cancelled = true;
    for (final c in _callbacks) {
      c();
    }
    _callbacks.clear();
  }
}

class AiDelta {
  AiDelta({
    this.text = '',
    this.reasoning = '',
    this.toolCalls = const [],
    this.finished = false,
  });
  final String text;
  final String reasoning;
  final List<Map<String, dynamic>> toolCalls;
  final bool finished;
}

class AiClient {
  AiClient({http.Client? client, void Function(String)? log})
    : _client = client ?? http.Client(),
      _log = log ?? ((message) => RuntimeLog.write('ai', message));
  static final _cooldowns = <String, DateTime>{};
  final http.Client _client;
  final void Function(String) _log;
  void close() => _client.close();
  Stream<AiDelta> complete({
    required AiSettings settings,
    required String key,
    required AiModel model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools = const [],
    required AiCancellation cancellation,
  }) async* {
    cancellation.check();
    final endpoint = settings.endpointFor(model).toString();
    final cooldown = _cooldowns[endpoint];
    if (cooldown != null && DateTime.now().isBefore(cooldown)) {
      throw StateError(
        '服务限流，请等待 ${cooldown.difference(DateTime.now()).inSeconds + 1} 秒后重试',
      );
    }
    cancellation.onCancel(close);
    final timer = Stopwatch()..start();
    final request = http.Request('POST', settings.endpointFor(model))
      ..followRedirects = false
      ..headers.addAll({
        'Authorization': 'Bearer $key',
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      })
      ..body = jsonEncode({
        'model': model.id,
        'messages': messages,
        'stream': true,
        if (model.tools && tools.isNotEmpty) 'tools': tools,
        if (model.tools && tools.isNotEmpty) 'tool_choice': 'auto',
      });
    try {
      final response = await _client.send(request).timeout(settings.timeout);
      _log(
        'Response status=${response.statusCode} elapsedMs=${timer.elapsedMilliseconds}',
      );
      if (response.statusCode != 200) {
        if (response.statusCode == 429) {
          _cooldowns[endpoint] = DateTime.now().add(
            retryAfterDelay(response.headers['retry-after']),
          );
        }
        await response.stream.drain<void>().timeout(const Duration(seconds: 5));
        throw StateError(switch (response.statusCode) {
          401 || 403 => 'API Key 无效或没有访问权限，请检查 AI 设置',
          429 =>
            'AI 服务请求受限，请稍后重试${response.headers['retry-after'] == null ? '' : '（等待 ${response.headers['retry-after']}）'}',
          400 || 422 => '服务不支持当前模型、图片或工具参数，请检查模型能力设置',
          _ => 'AI 服务暂时不可用（HTTP ${response.statusCode}）',
        });
      }
      if (!(response.headers['content-type'] ?? '').contains(
        'text/event-stream',
      )) {
        final raw = await response.stream.bytesToString().timeout(
          settings.timeout,
        );
        cancellation.check();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final message = (json['choices'] as List).first['message'] as Map;
        yield AiDelta(
          text: message['content'] as String? ?? '',
          reasoning:
              (message['reasoning_content'] ?? message['reasoning'])
                  as String? ??
              '',
          toolCalls: (message['tool_calls'] as List? ?? [])
              .map((v) => Map<String, dynamic>.from(v as Map))
              .toList(),
          finished: true,
        );
        return;
      }
      final calls = <int, Map<String, dynamic>>{};
      final data = <String>[];
      await for (final line
          in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .timeout(settings.timeout)) {
        cancellation.check();
        if (line.startsWith('data:')) {
          data.add(line.substring(5).trimLeft());
          continue;
        }
        if (line.isNotEmpty || data.isEmpty) continue;
        final payload = data.join('\n');
        data.clear();
        if (payload == '[DONE]') {
          yield AiDelta(toolCalls: calls.values.toList(), finished: true);
          return;
        }
        final chunk = jsonDecode(payload) as Map<String, dynamic>;
        if (chunk.containsKey('error')) {
          throw StateError('AI 服务返回错误，请检查模型与接口配置');
        }
        final choices = chunk['choices'] as List? ?? [];
        if (choices.isEmpty) continue;
        final delta = choices.first['delta'] as Map? ?? {};
        for (final raw in delta['tool_calls'] as List? ?? []) {
          final index = (raw['index'] as num?)?.toInt() ?? 0;
          final call = calls.putIfAbsent(
            index,
            () => {
              'id': '',
              'type': 'function',
              'function': {'name': '', 'arguments': ''},
            },
          );
          if (raw['id'] != null) call['id'] = '${call['id']}${raw['id']}';
          final function = raw['function'] as Map? ?? {};
          for (final name in ['name', 'arguments']) {
            if (function[name] != null) {
              call['function'][name] =
                  '${call['function'][name]}${function[name]}';
            }
          }
        }
        final reasoning = delta['reasoning_content'] ?? delta['reasoning'];
        if (reasoning is String && reasoning.isNotEmpty) {
          yield AiDelta(reasoning: reasoning);
        }
        if (delta['content'] is String) {
          yield AiDelta(text: delta['content'] as String);
        }
        if (choices.first['finish_reason'] != null) {
          yield AiDelta(toolCalls: calls.values.toList(), finished: true);
          return;
        }
      }
      throw StateError('回复流意外中断，可重试继续');
    } on TimeoutException {
      close();
      cancellation.check();
      throw StateError('等待 AI 超过 ${settings.timeoutSeconds} 秒，可在设置中增加超时后继续／重试');
    } on AiCancelled {
      rethrow;
    } catch (_) {
      cancellation.check();
      rethrow;
    } finally {
      _log('Request finished elapsedMs=${timer.elapsedMilliseconds}');
    }
  }
}
