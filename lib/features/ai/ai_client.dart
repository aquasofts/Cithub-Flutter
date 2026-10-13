import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/logging/runtime_log.dart';
import '../../core/utils/rate_limit.dart';
import 'ai_settings.dart';
import 'ai_responses.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

final aiClientFactoryProvider = Provider<AiClient Function()>(
  (ref) =>
      () => AiClient(),
);

String aiErrorMessage(Object error) {
  if (error is StateError) return error.message.toString();
  if (error is FormatException) return '服务回复格式不兼容，请检查 API 类型和地址';
  if (error is http.ClientException) return '无法连接 AI 服务，请检查网络、服务地址及证书';
  return '请求失败，请检查连接或模型配置后重试';
}

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

  Future<T> wait<T>(Future<T> future) {
    check();
    final stopped = Completer<T>();
    void stop() => stopped.completeError(AiCancelled());
    _callbacks.add(stop);
    return Future.any([future, stopped.future])
        .whenComplete(() => _callbacks.remove(stop));
  }

  Stream<T> bind<T>(Stream<T> stream) async* {
    final iterator = StreamIterator(stream);
    try {
      while (await wait(iterator.moveNext())) {
        check();
        yield iterator.current;
      }
    } finally {
      await iterator.cancel();
    }
  }

  void cancel() {
    if (cancelled) return;
    RuntimeLog.event('ai', 'cancel');
    cancelled = true;
    for (final c in List<void Function()>.from(_callbacks)) {
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
    this.responseItems = const [],
    this.nativeSearch,
    this.citations = const [],
  });
  final String text;
  final String reasoning;
  final List<Map<String, dynamic>> toolCalls;
  final bool finished;
  final List<Map<String, dynamic>> responseItems;
  final Map<String, dynamic>? nativeSearch;
  final List<Map<String, dynamic>> citations;
}

class AiClient {
  AiClient({http.Client? client, void Function(String)? log})
    : _client = LoggingHttpClient(client ?? http.Client(), streaming: true),
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
    AiGenerationOptions options = const AiGenerationOptions(),
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
    final webSearch = model.nativeSearch && options.webSearch;
    final effort =
        model.reasoning &&
            model.reasoningEfforts.contains(options.reasoningEffort)
        ? options.reasoningEffort
        : 'default';
    RuntimeLog.event('ai-options', 'request-resolved', {
      'requestId': 'request-${DateTime.now().microsecondsSinceEpoch}',
      'model': model.toJson(),
      'requested': options.toJson(),
      'effective': {'webSearch': webSearch, 'reasoningEffort': effort},
      'nativeSearchObservability': 'provider-returned API events, arguments, sources and citations; provider internal HTTP requests are not exposed',
    });
    final request = http.Request('POST', settings.endpointFor(model))
      ..followRedirects = false
      ..headers.addAll({
        'Authorization': 'Bearer $key',
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      })
      ..body = jsonEncode(
        model.responsesApi
            ? responsesBody(
                model.id,
                messages,
                model.tools ? tools : [],
                webSearch: webSearch,
                reasoningEffort: effort,
                reasoning: model.reasoning,
              )
            : {
                'model': model.id,
                'messages': messages,
                'stream': true,
                if (webSearch) 'web_search_options': <String, dynamic>{},
                if (effort != 'default') 'reasoning_effort': effort,
                if (model.tools && tools.isNotEmpty) 'tools': tools,
                if (model.tools && tools.isNotEmpty) 'tool_choice': 'auto',
              },
      );
    try {
      final response = await cancellation.wait(
        _client.send(request).timeout(settings.timeout),
      );
      _log(
        'Response status=${response.statusCode} elapsedMs=${timer.elapsedMilliseconds}',
      );
      if (response.statusCode != 200) {
        if (response.statusCode == 429) {
          _cooldowns[endpoint] = DateTime.now().add(
            retryAfterDelay(response.headers['retry-after']),
          );
        }
        String? errorCode;
        try {
          final raw = await cancellation
              .bind(response.stream)
              .transform(utf8.decoder)
              .join()
              .timeout(const Duration(seconds: 5));
          final body = jsonDecode(raw);
          if (body is Map && body['error'] is Map) {
            errorCode = body['error']['code']?.toString();
          }
        } catch (_) {
          // Error bodies are captured by the transport logger; keep UI errors concise.
        }
        if (errorCode == 'model_not_found') {
          throw StateError('模型不存在或当前密钥没有可用渠道，请核对模型 ID（区分大小写）或联系服务商');
        }
        if (errorCode == 'insufficient_quota') {
          throw StateError('AI 服务额度不足，请检查余额或联系服务商');
        }
        throw StateError(switch (response.statusCode) {
          401 || 403 => 'API Key 无效或没有访问权限，请检查 AI 设置',
          429 =>
            'AI 服务请求受限，请稍后重试${response.headers['retry-after'] == null ? '' : '（等待 ${response.headers['retry-after']}）'}',
          400 || 422 => '服务不支持当前模型或参数，请检查模型 ID、API 类型、图片、工具、搜索和思考程度设置',
          404 => '接口或模型不存在（HTTP 404），请检查 API 地址、API 类型与模型 ID',
          _ => 'AI 服务暂时不可用（HTTP ${response.statusCode}）',
        });
      }
      if (!(response.headers['content-type'] ?? '').contains(
        'text/event-stream',
      )) {
        final raw = await cancellation
            .bind(response.stream)
            .transform(utf8.decoder)
            .join()
            .timeout(settings.timeout);
        cancellation.check();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        if (model.responsesApi) {
          final output = responseOutput(json);
          for (final item in output.where(
            (i) => i['type'] == 'web_search_call',
          )) {
            yield AiDelta(nativeSearch: item);
          }
          yield AiDelta(
            text: responseText(output),
            reasoning: responseText(output, reasoning: true),
            toolCalls: responseCalls(output),
            responseItems: output,
            citations: responseCitations(output),
            finished: true,
          );
          return;
        }
        if (json['choices'] is! List || (json['choices'] as List).isEmpty) {
          throw StateError('服务回复格式不兼容，请检查 API 类型、模型 ID 和地址');
        }
        final message = (json['choices'] as List).first['message'] as Map;
        yield AiDelta(
          text: message['content'] as String? ?? '',
          citations: normalizeCitations(message['annotations'] as List? ?? []),
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
      final outputItems = <int, Map<String, dynamic>>{};
      await for (final payload in ssePayloads(
        cancellation.bind(response.stream.timeout(settings.timeout)),
      )) {
        cancellation.check();
        if (payload == '[DONE]') {
          if (model.responsesApi) throw StateError('Responses 回复缺少完成事件，可重试继续');
          yield AiDelta(toolCalls: calls.values.toList(), finished: true);
          return;
        }
        final chunk = jsonDecode(payload) as Map<String, dynamic>;
        if (chunk.containsKey('error')) {
          throw StateError('AI 服务返回错误，请检查模型与接口配置');
        }
        if (model.responsesApi) {
          final type = chunk['type'];
          if ((type as String? ?? '').startsWith('response.web_search_call.')) {
            yield AiDelta(
              nativeSearch: {
                'id': chunk['item_id'],
                'status': type.toString().split('.').last,
                'event': chunk,
              },
            );
          } else if ((type == 'response.output_item.added' ||
                  type == 'response.output_item.done') &&
              (chunk['item'] as Map?)?['type'] == 'web_search_call') {
            yield AiDelta(
              nativeSearch: Map<String, dynamic>.from(chunk['item'] as Map),
            );
          }
          if (type == 'response.output_text.delta') {
            yield AiDelta(text: chunk['delta'] as String? ?? '');
          } else if (type == 'response.reasoning_summary_text.delta') {
            yield AiDelta(reasoning: chunk['delta'] as String? ?? '');
          } else if (type == 'response.output_item.done') {
            outputItems[(chunk['output_index'] as num).toInt()] =
                Map<String, dynamic>.from(chunk['item'] as Map);
          } else if (type == 'response.completed') {
            final response = Map<String, dynamic>.from(
              chunk['response'] as Map,
            );
            final completedOutput = responseOutput(response);
            final indices = outputItems.keys.toList()..sort();
            // Some compatible services send output: [] in the completion
            // envelope even after emitting complete tool/reasoning items.
            // Only recover items marked done, and only after successful
            // completion; partial arguments must never trigger a write.
            final output = completedOutput.isNotEmpty
                ? completedOutput
                : [for (final index in indices) outputItems[index]!];
            if (completedOutput.isEmpty && output.isNotEmpty) {
              RuntimeLog.event('ai-response', 'stream-output-recovered', {
                'responseId': response['id'],
                'completion': response,
                'output': output,
              });
            }
            for (final item in output.where(
              (i) => i['type'] == 'web_search_call',
            )) {
              yield AiDelta(nativeSearch: item);
            }
            yield AiDelta(
              toolCalls: responseCalls(output),
              responseItems: output,
              citations: responseCitations(output),
              finished: true,
            );
            return;
          } else if (type == 'response.failed' ||
              type == 'response.incomplete' ||
              type == 'error') {
            throw StateError('Responses API 返回错误或未完成，请检查模型、额度及接口配置');
          }
          continue;
        }
        final choices = chunk['choices'] as List? ?? [];
        if (choices.isEmpty) continue;
        final delta = choices.first['delta'] as Map? ?? {};
        final annotations = normalizeCitations(
          delta['annotations'] as List? ?? [],
        );
        if (annotations.isNotEmpty) yield AiDelta(citations: annotations);
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
    } catch (error, stack) {
      _log(
        'Request failed elapsedMs=${timer.elapsedMilliseconds} error=$error\n$stack',
      );
      cancellation.check();
      rethrow;
    } finally {
      _log('Request finished elapsedMs=${timer.elapsedMilliseconds}');
    }
  }
}
