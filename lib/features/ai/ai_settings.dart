import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AiModel {
  const AiModel({
    required this.id,
    required this.name,
    this.baseUrl = '',
    this.configId = '',
    this.images = false,
    this.tools = true,
  });
  final String id;
  final String name;
  final String baseUrl;
  final String configId;
  String get selectionId => configId.isEmpty ? id : configId;
  final bool images;
  final bool tools;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'configId': selectionId,
    'images': images,
    'tools': tools,
  };
  factory AiModel.fromJson(Map<String, dynamic> v) => AiModel(
    id: v['id'] as String,
    name: v['name'] as String,
    baseUrl: v['baseUrl'] as String? ?? '',
    configId: v['configId'] as String? ?? '',
    images: v['images'] == true,
    tools: v['tools'] != false,
  );
}

class AiSettings {
  const AiSettings({
    this.baseUrl = 'https://api.openai.com/v1',
    this.models = const [],
    this.defaultModel = '',
    this.timeoutSeconds = 300,
  });
  final String baseUrl;
  final List<AiModel> models;
  final String defaultModel;
  final int timeoutSeconds;
  Duration get timeout => Duration(seconds: timeoutSeconds);
  Uri endpointFor(AiModel model) =>
      AiSettings(baseUrl: model.baseUrl.isEmpty ? baseUrl : model.baseUrl)
          .endpoint;
  AiModel? get model =>
      models.where((m) => m.selectionId == defaultModel).firstOrNull ??
      models.firstOrNull;
  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl,
    'models': models.map((v) => v.toJson()).toList(),
    'defaultModel': defaultModel,
    'timeoutSeconds': timeoutSeconds,
  };
  factory AiSettings.fromJson(Map<String, dynamic> v) => AiSettings(
    baseUrl: v['baseUrl'] as String? ?? 'https://api.openai.com/v1',
    models: (v['models'] as List? ?? [])
        .map((m) => AiModel.fromJson(Map<String, dynamic>.from(m as Map)))
        .toList(),
    defaultModel: v['defaultModel'] as String? ?? '',
    timeoutSeconds: ((v['timeoutSeconds'] as num?)?.toInt() ?? 300).clamp(
      60,
      1800,
    ),
  );
  Uri get endpoint {
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('请填写 HTTPS API 根地址，不包含密钥、查询参数或完整接口路径');
    }
    final path = uri.path.replaceAll(RegExp(r'/+$'), '');
    if (path.endsWith('/chat/completions')) {
      throw const FormatException('请填写 API 根地址，例如 https://example.com/v1');
    }
    return uri.replace(path: '$path/chat/completions');
  }
}

final aiSettingsProvider = FutureProvider<AiSettings>((ref) async {
  final raw = (await SharedPreferences.getInstance()).getString(
    'ai.settings.v1',
  );
  if (raw == null) return const AiSettings();
  try {
    return AiSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    return const AiSettings();
  }
});
Future<void> saveAiSettings(AiSettings settings) async {
  settings.endpoint;
  for (final model in settings.models) {
    settings.endpointFor(model);
  }
  if (settings.timeoutSeconds < 60 || settings.timeoutSeconds > 1800) {
    throw const FormatException('超时需为 60–1800 秒');
  }
  if (settings.models.map((m) => m.selectionId).toSet().length !=
      settings.models.length) {
    throw const FormatException('模型配置标识不能重复');
  }
  await (await SharedPreferences.getInstance()).setString(
    'ai.settings.v1',
    jsonEncode(settings.toJson()),
  );
}
