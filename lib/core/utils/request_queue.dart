import 'dart:async';

import 'rate_limit.dart';

const requestCancellationKey = #cithubRequestCancellation;

/// A single queue shared by foreground browsing and AI. Never bypasses challenges.
class RequestQueue {
  RequestQueue({
    this.interval = const Duration(seconds: 2),
    this.cacheTtl = const Duration(minutes: 2),
    this.rateLimitWait = const Duration(seconds: 30),
  });
  static final tieba = RequestQueue();
  final Duration interval;
  final Duration cacheTtl;
  final Duration rateLimitWait;
  DateTime? retryAt;
  Future<void> _tail = Future.value();
  DateTime? _last;
  bool paused = false;
  final _cache = <String, (DateTime, Object)>{};
  final _pending = <String, Future<Object>>{};
  void clearCache() => _cache.clear();
  bool resume() {
    if (retryAt != null && DateTime.now().isBefore(retryAt!)) return false;
    paused = false;
    retryAt = null;
    clearCache();
    return true;
  }

  Future<T> run<T extends Object>(String key, Future<T> Function() fetch) {
    final cached = _cache[key];
    if (cached != null && DateTime.now().difference(cached.$1) < cacheTtl) {
      return Future.value(cached.$2 as T);
    }
    final pending = _pending[key];
    if (pending != null) return pending.then((v) => v as T);
    final check = Zone.current[requestCancellationKey] as void Function()?;
    final result = Completer<T>();
    _pending[key] = result.future;
    _tail = _tail.then((_) async {
      try {
        check?.call();
        if (paused) throw StateError('请求已暂停，请完成验证码或稍后手动重试');
        for (var attempt = 0; ; attempt++) {
          if (_last != null) {
            final delay = interval - DateTime.now().difference(_last!);
            if (delay > Duration.zero) await Future<void>.delayed(delay);
          }
          check?.call();
          _last = DateTime.now();
          try {
            final value = await fetch();
            _cache[key] = (DateTime.now(), value);
            result.complete(value);
            break;
          } catch (error) {
            final message = error.toString();
            if (RegExp(
              r'429|403|验证码|风控|限流|captcha|too many|risk|频繁',
              caseSensitive: false,
            ).hasMatch(message)) {
              paused = true;
              if (error is RequestRateLimited || message.contains('429')) {
                retryAt = DateTime.now().add(
                  error is RequestRateLimited ? error.wait : rateLimitWait,
                );
              }
              rethrow;
            }
            final network = RegExp(
              r'timeout|socket|network|网络|连接|502|503|504',
              caseSensitive: false,
            ).hasMatch(message);
            if (!network || attempt >= 2) rethrow;
            await Future<void>.delayed(Duration(seconds: 2 << attempt));
          }
        }
      } catch (e, st) {
        result.completeError(e, st);
      } finally {
        _pending.remove(key);
      }
    });
    return result.future;
  }
}
