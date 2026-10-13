import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/logged_preferences.dart';

const aiReasoningLabels = {
  'default': '默认',
  'none': '关闭',
  'minimal': '极低',
  'low': '低',
  'medium': '中',
  'high': '高',
  'xhigh': '极高',
  'max': '最高',
};

class AiGenerationOptions {
  const AiGenerationOptions({
    this.webSearch = false,
    this.reasoningEffort = 'default',
  });
  final bool webSearch;
  final String reasoningEffort;
  Map<String, dynamic> toJson() => {
    'webSearch': webSearch,
    'reasoningEffort': reasoningEffort,
  };
  factory AiGenerationOptions.fromJson(Map<String, dynamic> data) =>
      AiGenerationOptions(
        webSearch: data['webSearch'] == true,
        reasoningEffort: aiReasoningLabels.containsKey(data['reasoningEffort'])
            ? data['reasoningEffort'] as String
            : 'default',
      );
}

class AiModel {
  const AiModel({
    required this.id,
    required this.name,
    this.baseUrl = '',
    this.configId = '',
    this.images = false,
    this.tools = true,
    this.responsesApi = false,
    this.nativeSearch = false,
    this.reasoning = false,
    this.reasoningEfforts = const ['low', 'medium', 'high'],
  });
  final String id;
  final String name;
  final String baseUrl;
  final String configId;
  String get selectionId => configId.isEmpty ? id : configId;
  final bool images;
  final bool tools;
  final bool responsesApi;
  final bool nativeSearch, reasoning;
  final List<String> reasoningEfforts;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'configId': selectionId,
    'images': images,
    'tools': tools,
    'responsesApi': responsesApi,
    'nativeSearch': nativeSearch,
    'reasoning': reasoning,
    'reasoningEfforts': reasoningEfforts,
  };
  factory AiModel.fromJson(Map<String, dynamic> v) => AiModel(
    id: v['id'] as String,
    name: v['name'] as String,
    baseUrl: v['baseUrl'] as String? ?? '',
    configId: v['configId'] as String? ?? '',
    images: v['images'] == true,
    tools: v['tools'] != false,
    responsesApi: v['responsesApi'] == true,
    nativeSearch: v['nativeSearch'] == true,
    reasoning: v['reasoning'] == true,
    reasoningEfforts:
        (v['reasoningEfforts'] as List? ?? ['low', 'medium', 'high'])
            .whereType<String>()
            .where((e) => e != 'default' && aiReasoningLabels.containsKey(e))
            .toList(),
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
  Uri endpointFor(AiModel model) => _endpoint(
    model.baseUrl.isEmpty ? baseUrl : model.baseUrl,
    responsesApi: model.responsesApi,
  );
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
  Uri get endpoint => _endpoint(baseUrl);
  static Uri _endpoint(String address, {bool responsesApi = false}) {
    final uri = Uri.tryParse(address.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('请填写 HTTPS API 根地址，不包含密钥、查询参数或完整接口路径');
    }
    var path = uri.path.replaceAll(RegExp(r'/+$'), '');
    path = path.replaceFirst(RegExp(r'/(chat/completions|responses)$'), '');
    if (path.isEmpty) path = '/v1';
    return uri.replace(
      path: '$path/${responsesApi ? 'responses' : 'chat/completions'}',
    );
  }
}

final aiSettingsProvider = FutureProvider<AiSettings>((ref) async {
  final raw = (await LoggedPreferences.getInstance()).getString(
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
  if (settings.models.isEmpty) settings.endpoint;
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
  await (await LoggedPreferences.getInstance()).setString(
    'ai.settings.v1',
    jsonEncode(settings.toJson()),
  );
}
