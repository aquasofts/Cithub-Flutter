import 'dart:convert';

import '../../core/platform/cithub_platform.dart';

/// The native secret store encrypts the entire credential bundle. No keys are
/// written to preferences, the conversation database, or model JSON.
class AiCredentials {
  AiCredentials({this.legacy = '', Map<String, String>? models})
    : models = models ?? {};
  String legacy;
  final Map<String, String> models;

  static Future<AiCredentials> read(CithubPlatform platform) async {
    final raw = await platform.readAiApiKey() ?? '';
    try {
      final data = jsonDecode(raw);
      if (data is Map && data['cithubCredentials'] == 1) {
        return AiCredentials(
          legacy: data['legacy'] as String? ?? '',
          models: Map<String, String>.from(data['models'] as Map),
        );
      }
    } catch (_) {
      // Existing installations store a single, unstructured key.
    }
    return AiCredentials(legacy: raw);
  }

  String keyFor(String id) => models[id] ?? legacy;
  Future<void> save(CithubPlatform platform) async {
    if (legacy.isEmpty && models.values.every((key) => key.isEmpty)) {
      await platform.deleteAiApiKey();
      return;
    }
    await platform.writeAiApiKey(
      jsonEncode({'cithubCredentials': 1, 'legacy': legacy, 'models': models}),
    );
  }
}
