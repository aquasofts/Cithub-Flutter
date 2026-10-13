import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/cithub_platform.dart';
import '../../core/storage/local_database.dart' show localId;
import 'ai_client.dart';
import 'ai_credentials.dart';
import 'ai_settings.dart';

class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});
  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  final _url = TextEditingController();
  final _key = TextEditingController();
  final _timeout = TextEditingController(text: '300');
  AiCredentials _credentials = AiCredentials();
  List<AiModel> _models = [];
  String _default = '';
  bool _loaded = false;
  bool _hasKey = false;
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
        _url.text = settings.baseUrl;
        _models = [...settings.models];
        _default = settings.model?.selectionId ?? '';
        _credentials = credentials;
        _hasKey = credentials.legacy.isNotEmpty;
        _timeout.text = '${settings.timeoutSeconds}';
        _loaded = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _url.text = 'https://api.openai.com/v1';
          _loaded = true;
        });
        _message('密钥读取失败，请重新填写后保存');
      }
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    _timeout.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _model([AiModel? old]) async {
    final result = await showDialog<({AiModel model, String key})>(
      context: context,
      builder: (_) => _AiModelDialog(
        model: old,
        models: _models,
        apiKey: old == null ? '' : _credentials.models[old.selectionId] ?? '',
        baseUrl: _url.text.trim(),
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
        baseUrl: _url.text.trim(),
        models: _models,
        defaultModel: _default,
        timeoutSeconds:
            int.tryParse(_timeout.text) ??
            (throw const FormatException('请输入有效的超时秒数')),
      );
      settings.endpoint;
      if (_models.isEmpty) throw const FormatException('请至少添加一个模型');
      if (_key.text.trim().isNotEmpty) {
        _credentials.legacy = _key.text.trim();
        _hasKey = true;
        _key.clear();
      }
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
      client = AiClient();
      await for (final _ in client.complete(
        settings: settings,
        key: credentials.keyFor(settings.model!.selectionId),
        model: settings.model!,
        messages: [
          {'role': 'user', 'content': 'Reply OK.'},
        ],
        cancellation: AiCancellation(),
      )) {}
      _message('连接成功');
    } catch (_) {
      _message('连接失败，请检查地址、密钥和模型配置');
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
                controller: _url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  helperText: '旧配置的默认地址；每个模型可设置独立地址和密钥',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _key,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'API Key',
                  hintText: _hasKey ? '已加密保存，留空保持原密钥' : '填写服务提供的密钥',
                ),
              ),
              if (_hasKey)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () async {
                      _credentials.legacy = '';
                      await _credentials.save(ref.read(cithubPlatformProvider));
                      if (mounted) setState(() => _hasKey = false);
                    },
                    child: const Text('删除已保存密钥'),
                  ),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _timeout,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '请求超时（秒）',
                  helperText: '默认 300 秒，可设为 60–1800 秒；流输出按无数据等待时间计算',
                ),
              ),
              const SizedBox(height: 20),
              Text('模型独立配置', style: Theme.of(context).textTheme.titleMedium),
              for (final m in _models)
                Card(
                  child: ListTile(
                    title: Text(m.name),
                    subtitle: Text(
                      '${m.id} · ${m.baseUrl.isEmpty ? _url.text : m.baseUrl}\n${m.images ? '图片 · ' : ''}${m.tools ? '工具调用' : '仅聊天'}',
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
    required this.models,
    required this.apiKey,
    required this.baseUrl,
  });

  final AiModel? model;
  final List<AiModel> models;
  final String apiKey, baseUrl;

  @override
  State<_AiModelDialog> createState() => _AiModelDialogState();
}

class _AiModelDialogState extends State<_AiModelDialog> {
  late final TextEditingController _id;
  late final TextEditingController _name;
  late final TextEditingController _url, _key;
  late bool _images;
  late bool _tools;

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
    _key = TextEditingController(text: widget.apiKey);
    _images = widget.model?.images ?? false;
    _tools = widget.model?.tools ?? true;
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
    if (id.isEmpty || name.isEmpty) {
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
      ),
      key: _key.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.model == null ? '添加模型' : '编辑模型'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _id,
            decoration: const InputDecoration(labelText: '模型 ID'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: '显示名称'),
          ),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: '模型 API 地址'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _key,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: '模型 API Key',
              helperText: '独立加密保存；留空使用旧配置默认密钥',
            ),
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
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _save, child: const Text('保存')),
    ],
  );
}
