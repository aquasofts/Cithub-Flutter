import 'package:flutter/services.dart';

String userFacingError(Object? error, {String fallback = '操作失败'}) {
  if (error == null) return fallback;
  if (error is PlatformException) {
    for (final candidate in [error.message, error.code]) {
      final message = _cleanErrorText(candidate);
      if (message != null && !_isErrorTypeName(message)) return message;
    }
    return fallback;
  }
  return _cleanErrorText(error.toString()) ?? fallback;
}

String? _cleanErrorText(String? value) {
  var text = value?.trim() ?? '';
  if (text.isEmpty) return null;

  final swiftCase = RegExp(
    r'^[A-Za-z_][A-Za-z0-9_]*\("(.*)"\)$',
    dotAll: true,
  ).firstMatch(text);
  if (swiftCase != null) {
    text = swiftCase.group(1)!.replaceAll(r'\"', '"').replaceAll(r'\n', '\n');
  }

  text = text.replaceFirst(
    RegExp(r'^[A-Za-z0-9_.$]+(?:Exception|Error):\s*'),
    '',
  );
  final stackIndex = text.indexOf('Stacktrace:');
  if (stackIndex >= 0) text = text.substring(0, stackIndex);
  text = text.trim().replaceFirst(RegExp(r'[,;:]$'), '');
  return text.isEmpty ? null : text;
}

bool _isErrorTypeName(String value) =>
    RegExp(r'^[A-Za-z0-9_.$]+(?:Exception|Error)$').hasMatch(value);
