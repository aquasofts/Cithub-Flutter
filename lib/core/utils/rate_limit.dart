import 'dart:io';

Duration retryAfterDelay(
  String? value, {
  Duration fallback = const Duration(seconds: 30),
}) {
  final seconds = int.tryParse(value ?? '');
  if (seconds != null) return Duration(seconds: seconds.clamp(0, 86400));
  if (value != null) {
    try {
      final delay = HttpDate.parse(value).difference(DateTime.now());
      return delay.isNegative ? Duration.zero : delay;
    } catch (_) {}
  }
  return fallback;
}

class RequestRateLimited implements Exception {
  RequestRateLimited(this.wait);
  final Duration wait;
  @override
  String toString() => '429 请求受限，请等待 ${wait.inSeconds} 秒';
}
