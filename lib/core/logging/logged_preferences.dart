import 'package:shared_preferences/shared_preferences.dart';

import 'runtime_log.dart';

/// A single persistence boundary for all preference writes, including caches.
class LoggedPreferences {
  LoggedPreferences._(this._inner);
  final SharedPreferences _inner;
  static Future<LoggedPreferences> getInstance() async =>
      LoggedPreferences._(await SharedPreferences.getInstance());
  String? getString(String key) => _inner.getString(key);
  int? getInt(String key) => _inner.getInt(key);
  bool? getBool(String key) => _inner.getBool(key);
  double? getDouble(String key) => _inner.getDouble(key);
  List<String>? getStringList(String key) => _inner.getStringList(key);
  Object? get(String key) => _inner.get(key);
  Set<String> getKeys() => _inner.getKeys();
  bool containsKey(String key) => _inner.containsKey(key);
  Future<void> reload() => _inner.reload();
  Future<bool> _write(
    String key,
    Object? value,
    Future<bool> Function() operation,
  ) => RuntimeLog.trace('preferences', 'write', {
    'key': key,
    'before': _inner.get(key),
    'after': value,
  }, operation);
  Future<bool> setString(String key, String value) =>
      _write(key, value, () => _inner.setString(key, value));
  Future<bool> setInt(String key, int value) =>
      _write(key, value, () => _inner.setInt(key, value));
  Future<bool> setBool(String key, bool value) =>
      _write(key, value, () => _inner.setBool(key, value));
  Future<bool> setDouble(String key, double value) =>
      _write(key, value, () => _inner.setDouble(key, value));
  Future<bool> setStringList(String key, List<String> value) =>
      _write(key, value, () => _inner.setStringList(key, value));
  Future<bool> remove(String key) =>
      _write(key, null, () => _inner.remove(key));
  Future<bool> clear() => RuntimeLog.trace('preferences', 'clear', {
    for (final key in _inner.getKeys()) key: _inner.get(key),
  }, _inner.clear);
}
