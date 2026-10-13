import '../../core/logging/runtime_log.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/cithub_platform.dart';
import '../../core/widgets/chinese_text_selection.dart';
import '../../core/storage/local_database.dart' show localId;
import 'ai_client.dart';
import 'ai_key_controller.dart';
import 'ai_credentials.dart';
import 'ai_settings.dart';

class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});
  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  String _legacyUrl = 'https://api.openai.com/v1';
  final _timeout = TextEditingController(text: '300');
  AiCredentials _credentials = AiCredentials();
  List<AiModel> _models = [];
  String _default = '';
  bool _loaded = false;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await ref.read(aiSettingsProvider.future);
      final credentials = await AiCredentials.read(
        ref.read(cithubPlatformProvider),
      );
      if (!mounted) return;
      setState(() {
        _legacyUrl = settings.baseUrl;
        _models = [...settings.models];
        _default = settings.model?.selectionId ?? '';
        _credentials = credentials;
        _timeout.text = '${settings.timeoutSeconds}';
        _loaded = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _legacyUrl = 'https://api.openai.com/v1';
          _loaded = true;
        });
        _message('密钥读取失败，请重新填写后保存');
      }
    }
  }

  @override
  void dispose() {
    _timeout.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _model([AiModel? old]) async {
    final result = await showDialog<({AiModel model, String key})>(
      context: context,
      builder: (_) => _AiModelDialog(
        model: old,
        apiKey: old == null ? '' : _credentials.keyFor(old.selectionId),
        baseUrl: _legacyUrl,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (old != null && old.selectionId != result.model.selectionId) {
        _credentials.models.remove(old.selectionId);
      }
      if (result.key.isNotEmpty) {
        _credentials.models[result.model.selectionId] = result.key;
      } else {
        _credentials.models.remove(result.model.selectionId);
      }
      if (old != null) {
        _models[_models.indexOf(old)] = result.model;
        if (_default == old.selectionId) _default = result.model.selectionId;
      } else {
        _models.add(result.model);
        if (_default.isEmpty) _default = result.model.selectionId;
      }
    });
  }

  Future<bool> _save() async {
    try {
      final settings = AiSettings(
        baseUrl: _legacyUrl,
        models: _models,
        defaultModel: _default,
        timeoutSeconds:
            int.tryParse(_timeout.text) ??
            (throw const FormatException('请输入有效的超时秒数')),
      );
      if (_models.isEmpty) throw const FormatException('请至少添加一个模型');
      if (_models.any((m) => _credentials.keyFor(m.selectionId).isEmpty)) {
        throw const FormatException('请为每个模型填写 API Key');
      }
      for (final model in _models) {
        settings.endpointFor(model);
      }
      if (settings.timeoutSeconds < 60 || settings.timeoutSeconds > 1800) {
        throw const FormatException('超时需为 60–1800 秒');
      }
      await _credentials.save(ref.read(cithubPlatformProvider));
      await saveAiSettings(settings);
      ref.invalidate(aiSettingsProvider);
      _message('AI 设置已保存');
      return true;
    } catch (e) {
      _message(e is FormatException ? e.message : '保存失败，请重试');
      return false;
    }
  }

  Future<void> _test() async {
    setState(() => _busy = true);
    AiClient? client;
    try {
      if (!await _save()) return;
      final settings = await ref.read(aiSettingsProvider.future);
      final credentials = await AiCredentials.read(
        ref.read(cithubPlatformProvider),
      );
      client = ref.read(aiClientFactoryProvider)();
      await for (final _ in client.complete(
        settings: settings,
        key: credentials.keyFor(settings.model!.selectionId),
        model: settings.model!,
        messages: [
          {'role': 'user', 'content': 'Reply OK.'},
        ],
        cancellation: AiCancellation(),
      )) {}
      _message('连接成功（模型 ID：${settings.model!.id}）');
    } catch (e) {
      _message(aiErrorMessage(e));
    } finally {
      client?.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI 设置')),
    body: !_loaded
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                contextMenuBuilder: chineseEditableTextMenu,
                controller: _timeout,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '请求超时（秒）',
                  helperText: '默认 300 秒，可设为 60–1800 秒；流输出按无数据等待时间计算',
                  helperMaxLines: 3,
                ),
              ),
              const SizedBox(height: 20),
              Text('模型独立配置', style: Theme.of(context).textTheme.titleMedium),
              for (final m in _models)
                Card(
                  child: ListTile(
                    title: Text(m.name),
                    subtitle: Text(
                      '${m.id} · ${m.baseUrl.isEmpty ? _legacyUrl : m.baseUrl}\n${m.responsesApi ? 'Responses API' : 'Chat Completions'} · ${m.images ? '图片 · ' : ''}${m.tools ? '工具调用' : '仅聊天'}',
                    ),
                    leading: IconButton(
                      tooltip: '设为默认模型',
                      icon: Icon(
                        _default == m.selectionId
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                      ),
                      onPressed: () => setState(() => _default = m.selectionId),
                    ),
                    onTap: () => _model(m),
                    trailing: IconButton(
                      tooltip: '删除模型',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _models.remove(m);
                        _credentials.models.remove(m.selectionId);
                        if (_default == m.selectionId) {
                          _default = _models.firstOrNull?.selectionId ?? '';
                        }
                      }),
                    ),
                  ),
                ),
              TextButton.icon(
                onPressed: () => _model(),
                icon: const Icon(Icons.add),
                label: const Text('添加模型'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: const Text('保存'),
              ),
              TextButton(
                onPressed: _busy ? null : _test,
                child: Text(_busy ? '正在测试…' : '保存并测试连接'),
              ),
              const Text(
                '测试连接会向所配置服务发送一条简短消息。图片和校园工具需要相应模型能力。',
                textAlign: TextAlign.center,
              ),
            ],
          ),
  );
}

// Controllers must live until the dialog is unmounted, including its exit animation.
class _AiModelDialog extends StatefulWidget {
  const _AiModelDialog({
    required this.model,
    required this.apiKey,
    required this.baseUrl,
  });

  final AiModel? model;
  final String apiKey, baseUrl;

  @override
  State<_AiModelDialog> createState() => _AiModelDialogState();
}

class _AiModelDialogState extends State<_AiModelDialog> {
  late final TextEditingController _id;
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final AiKeyController _key;
  late bool _images;
  late bool _tools;
  late bool _responsesApi;
  late bool _nativeSearch, _reasoning;
  late Set<String> _reasoningEfforts;
  String? _error;

  @override
  void initState() {
    super.initState();
    _id = TextEditingController(text: widget.model?.id);
    _name = TextEditingController(text: widget.model?.name);
    _url = TextEditingController(
      text: widget.model?.baseUrl.isNotEmpty == true
          ? widget.model!.baseUrl
          : widget.baseUrl,
    );
    _key = AiKeyController(text: widget.apiKey);
    _images = widget.model?.images ?? false;
    _tools = widget.model?.tools ?? true;
    _responsesApi = widget.model?.responsesApi ?? false;
    _nativeSearch = widget.model?.nativeSearch ?? false;
    _reasoning = widget.model?.reasoning ?? false;
    _reasoningEfforts =
        (widget.model?.reasoningEfforts ?? ['low', 'medium', 'high']).toSet();
  }

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  void _save() {
    final id = _id.text.trim();
    final name = _name.text.trim();
    try {
      if (id.isEmpty || name.isEmpty) {
        throw const FormatException('请填写模型 ID 和显示名称');
      }
      AiSettings(baseUrl: _url.text.trim()).endpoint;
      if (_key.text.trim().isEmpty) {
        throw const FormatException('请填写此模型的 API Key');
      }
    } on FormatException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    Navigator.pop(context, (
      model: AiModel(
        id: id,
        name: name,
        configId: widget.model?.selectionId ?? localId(),
        baseUrl: _url.text.trim(),
        images: _images,
        tools: _tools,
        responsesApi: _responsesApi,
        nativeSearch: _nativeSearch,
        reasoning: _reasoning,
        reasoningEfforts: _reasoningEfforts.toList(),
      ),
      key: _key.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.model == null ? '添加模型' : '编辑模型'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            TextField(
              contextMenuBuilder: chineseEditableTextMenu,
              controller: _id,
              decoration: const InputDecoration(
                labelText: '模型 ID',
                hintText: 'gpt-6-sol',
                helperText: '实际发送给服务的 model，需与服务商提供的 ID 完全一致',
                helperMaxLines: 3,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              contextMenuBuilder: chineseEditableTextMenu,
              controller: _name,
              decoration: const InputDecoration(
                labelText: '显示名称',
                helperText: '仅在本机显示，不作为请求的模型 ID',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              contextMenuBuilder: chineseEditableTextMenu,
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '模型 API 地址',
                helperText: '例如 https://api.openai.com/v1，也可填写完整接口地址',
                helperMaxLines: 3,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              contextMenuBuilder: chineseEditableTextMenu,
              controller: _key,
              keyboardType: TextInputType.text,
              obscureText: false,
              autocorrect: false,
              enableSuggestions: true,
              enableIMEPersonalizedLearning: false,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              decoration: InputDecoration(
                labelText: '模型 API Key',
                helperText: '仅用于此模型，密钥加密保存在本机',
                helperMaxLines: 3,
                suffixIcon: IconButton(
                  tooltip: _key.revealed ? '隐藏 API Key' : '显示 API Key',
                  icon: Icon(
                    _key.revealed
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () => setState(_key.toggleVisibility),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('支持 Responses API'),
              subtitle: const Text('开启后使用 /responses；关闭使用 Chat Completions'),
              value: _responsesApi,
              onChanged: (value) => setState(() => _responsesApi = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('支持模型自带搜索'),
              subtitle: const Text('由当前模型服务执行联网搜索'),
              value: _nativeSearch,
              onChanged: (value) {
                RuntimeLog.event('ai-model', 'native-search-support-changed', {
                  'modelId': _id.text,
                  'before': _nativeSearch,
                  'after': value,
                });
                setState(() => _nativeSearch = value);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('支持思考程度'),
              subtitle: const Text('选择当前模型支持的思考档位'),
              value: _reasoning,
              onChanged: (value) {
                RuntimeLog.event('ai-model', 'reasoning-support-changed', {
                  'modelId': _id.text,
                  'before': _reasoning,
                  'after': value,
                });
                setState(() => _reasoning = value);
              },
            ),
            if (_reasoning)
              Wrap(
                spacing: 8,
                children: [
                  for (final level in aiReasoningLabels.entries.where(
                    (e) => e.key != 'default',
                  ))
                    FilterChip(
                      key: ValueKey('effort-support-${level.key}'),
                      label: Text(level.value),
                      selected: _reasoningEfforts.contains(level.key),
                      onSelected: (selected) {
                        final before = _reasoningEfforts.toList();
                        setState(
                          () => selected
                              ? _reasoningEfforts.add(level.key)
                              : _reasoningEfforts.remove(level.key),
                        );
                        RuntimeLog.event(
                          'ai-model',
                          'reasoning-levels-changed',
                          {
                            'modelId': _id.text,
                            'before': before,
                            'after': _reasoningEfforts.toList(),
                          },
                        );
                      },
                    ),
                ],
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('支持图片'),
              value: _images,
              onChanged: (value) => setState(() => _images = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('支持工具调用'),
              value: _tools,
              onChanged: (value) => setState(() => _tools = value),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _save, child: const Text('保存')),
    ],
  );
}
