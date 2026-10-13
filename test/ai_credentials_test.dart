import 'dart:convert';

import 'package:cithub_flutter/core/platform/demo_cithub_platform.dart';
import 'package:cithub_flutter/features/ai/ai_credentials.dart';
import 'package:cithub_flutter/features/ai/ai_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'legacy key migrates and model credentials remain independent',
    () async {
      final platform = DemoCithubPlatform();
      await platform.writeAiApiKey('legacy-secret');
      final credentials = await AiCredentials.read(platform);
      credentials.models['a'] = 'secret-a';
      credentials.models['b'] = 'secret-b';
      await credentials.save(platform);
      final restored = await AiCredentials.read(platform);
      expect(restored.keyFor('a'), 'secret-a');
      expect(restored.keyFor('b'), 'secret-b');
      expect(restored.keyFor('old-model'), 'legacy-secret');
      restored.models.remove('a');
      await restored.save(platform);
      expect((await AiCredentials.read(platform)).keyFor('b'), 'secret-b');
    },
  );

  test(
    'model URLs and timeout survive settings serialization without secrets',
    () {
      const settings = AiSettings(
        models: [
          AiModel(id: 'a', name: 'A', baseUrl: 'https://a.test/v1'),
          AiModel(id: 'b', name: 'B', baseUrl: 'https://b.test/api'),
        ],
        timeoutSeconds: 900,
      );
      final restored = AiSettings.fromJson(
        jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
      );
      expect(restored.endpointFor(restored.models[0]).host, 'a.test');
      expect(
        restored.endpointFor(restored.models[1]).path,
        '/api/chat/completions',
      );
      expect(restored.timeout, const Duration(seconds: 900));
      expect(const AiSettings().timeout, const Duration(minutes: 5));
      expect(jsonEncode(settings.toJson()), isNot(contains('apiKey')));
    },
  );
}
