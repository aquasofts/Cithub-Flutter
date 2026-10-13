import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart' as chat;
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flyer_chat_text_message/flyer_chat_text_message.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/platform/cithub_platform.dart';
import '../../core/storage/local_database.dart';
import '../../core/settings/app_settings.dart';
import '../timetable/academic_sync.dart';
import '../timetable/timetable_repository.dart';
import '../mine/mine_screen.dart';
import 'ai_attachments.dart';
import 'ai_client.dart';
import 'ai_credentials.dart';
import 'ai_conversations.dart';
import 'ai_runner.dart';
import 'ai_settings.dart';
import 'ai_settings_screen.dart';
import 'ai_tools.dart';

class AiScreen extends ConsumerStatefulWidget {
  const AiScreen({super.key, this.initialText});
  final String? initialText;
  @override
  ConsumerState<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends ConsumerState<AiScreen> {
  final _chat = chat.InMemoryChatController();
  final _input = TextEditingController();
  final _pending = <AiAttachment>[];
  late AiConversationRepository _repository;
  AiConversation _conversation = AiConversation(id: localId());
  AiCancellation? _cancellation;
  AiClient? _client;
  bool _busy = false, _loading = true;
  String? _error;
  String _progress = '';
  bool _allowScheduleChanges = false;
  @override
  void initState() {
    super.initState();
    _input.text = widget.initialText ?? '';
    _repository = AiConversationRepository(ref.read(localDatabaseProvider));
    _restore();
  }

  Future<void> _restore() async {
    try {
      final list = await _repository.all();
      if (!mounted) return;
      if (widget.initialText == null && list.isNotEmpty) {
        _conversation = list.first;
        await _renderHistory();
      }
    } catch (_) {
      _error = '本地会话读取失败，请稍后重试';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    // Once sent, requests finish and persist even if this route is closed.
    // Attachment parsing has no background result to retain.
    if (_client == null) _cancellation?.cancel();
    _input.dispose();
    _chat.dispose();
    for (final a in _pending) {
      unawaited(deleteAttachment(a));
    }
    super.dispose();
  }

  chat.Message _displayMessage(Map<String, dynamic> d) => d['kind'] == 'text'
      ? chat.Message.text(
          id: d['id'] as String,
          authorId: d['author'] as String,
          text: d['text'] as String,
          createdAt: DateTime.tryParse(d['at'] as String? ?? ''),
        )
      : chat.Message.custom(
          id: d['id'] as String,
          authorId: 'assistant',
          metadata: d,
        );
  Future<void> _renderHistory() => _chat.setMessages(
    _conversation.display.map(_displayMessage).toList(),
    animated: false,
  );
  Future<void> _addDisplay(Map<String, dynamic> d) async {
    d['id'] ??= localId();
    d['at'] ??= DateTime.now().toIso8601String();
    _conversation.display.add(d);
    if (mounted) await _chat.insertMessage(_displayMessage(d));
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _pick() async {
    if (_pending.length >= 5) {
      _message('每条消息最多 5 个附件');
      return;
    }
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'jpg',
        'jpeg',
        'png',
        'webp',
        'txt',
        'md',
        'csv',
        'pdf',
        'docx',
        'xlsx',
      ],
    );
    if (files.isEmpty || !mounted) return;
    setState(() {
      _busy = true;
      _progress = '正在解析附件…';
    });
    final cancellation = AiCancellation();
    _cancellation = cancellation;
    try {
      for (final file in files) {
        if (_pending.length >= 5) {
          _message('最多保留 5 个附件');
          break;
        }
        final attachment = await importAttachment(file, cancellation);
        if (!mounted || cancellation.cancelled) {
          await deleteAttachment(attachment);
          break;
        }
        setState(() => _pending.add(attachment));
      }
    } on AiCancelled {
      // User stopped attachment processing.
    } catch (e) {
      _message(e is FormatException ? e.message : '文件无法解析，可能已加密、损坏或格式不支持');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = '';
        });
      }
    }
  }

  Future<void> _preview(AiAttachment a) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * .8,
        child: Scaffold(
          appBar: AppBar(title: Text(a.name)),
          body: a.image
              ? InteractiveViewer(
                  child: Center(child: Image.file(File(a.path))),
                )
              : a.path.endsWith('.pdf')
              ? PdfViewer.file(a.path)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final b in a.blocks) ...[
                      Text(
                        b['label'] as String,
                        style: Theme.of(ctx).textTheme.titleSmall,
                      ),
                      SelectableText(b['text'] as String? ?? '扫描页面'),
                      const Divider(),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _send({bool retry = false}) async {
    if (_busy || _loading) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _sendImpl(retry: retry);
    } catch (_) {
      _message('无法读取 AI 配置或密钥，请检查设置后重试');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = '';
        });
      }
    }
  }

  Future<void> _sendImpl({bool retry = false}) async {
    final settings = await ref.read(aiSettingsProvider.future);
    if (!mounted) return;
    final model =
        settings.models
            .where((m) => m.selectionId == _conversation.model)
            .firstOrNull ??
        settings.model;
    final credentials = await AiCredentials.read(
      ref.read(cithubPlatformProvider),
    );
    final key = model == null ? '' : credentials.keyFor(model.selectionId);
    if (!mounted) return;
    if (model == null || key.isEmpty) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const AiSettingsScreen()));
      return;
    }
    if (!retry && _input.text.trim().isEmpty && _pending.isEmpty) return;
    if (_pending.any((a) => a.image) && !model.images) {
      _message('请选择支持图片的模型');
      return;
    }
    if (_pending.any((a) => !a.image && a.blocks.length > 1) && !model.tools) {
      _message('分块文件需要支持工具调用的模型');
      return;
    }
    final cancellation = AiCancellation();
    _cancellation = cancellation;
    setState(() {
      _busy = true;
      _error = null;
      _progress = '正在准备…';
    });
    String prompt = '';
    var assistantText = '';
    Map<String, dynamic>? assistantDisplay;
    Map<String, dynamic>? reasoningDisplay;
    final conversation = _conversation;
    final repository = _repository;
    Future<void> persist() => repository.save(conversation);
    try {
      final store = ref.read(localDatabaseProvider);
      if (await store.getMeta('ai.disclosure') != 'accepted') {
        if (!mounted) return;
        setState(() => _progress = '');
        final yes = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('发送到 AI 服务'),
            content: const Text(
              '当前消息、附件和本次查询所需的校园数据会发送到你配置的 AI 服务。账号密码、Cookie 和 API Key 不会作为聊天内容发送。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('同意并发送'),
              ),
            ],
          ),
        );
        if (yes != true) return;
        await store.setMeta('ai.disclosure', 'accepted');
      }
      cancellation.check();
      conversation.model = model.selectionId;
      if (!retry) {
        prompt = _input.text.trim();
        if (prompt.isEmpty) prompt = '请阅读我上传的附件。';
        final attached = [..._pending];
        final manifest = attached.map((a) => a.manifest).toList();
        final content = <Map<String, dynamic>>[
          {
            'type': 'text',
            'text':
                '$prompt${manifest.isEmpty ? '' : '\n用户附件清单（分块从0开始）：${jsonEncode(manifest)}'}',
          },
        ];
        for (final a in attached) {
          cancellation.check();
          if (a.image) {
            final data = await a.read(0, model.images, cancellation);
            content.add({
              'type': 'image_url',
              'image_url': {'url': data['image']},
            });
          } else if (a.blocks.length == 1 &&
              a.blocks.first['scanPage'] != null) {
            final data = await a.read(0, model.images, cancellation);
            content.add({
              'type': 'image_url',
              'image_url': {'url': data['image']},
            });
          } else if (a.blocks.isNotEmpty && a.blocks.first['text'] != null) {
            content.add({
              'type': 'text',
              'text':
                  '附件 ${a.name} / ${a.blocks.first['label']} / 第0块，共${a.blocks.length}块：\n${a.blocks.first['text']}',
            });
          }
        }
        conversation.attachments.addAll(attached);
        _pending.clear();
        final turn = localId();
        conversation.messages.add({
          'role': 'user',
          'content': content,
          '_prompt': prompt,
          '_turn': turn,
        });
        if (conversation.display.isEmpty) {
          conversation.title = prompt.substring(0, prompt.length.clamp(0, 24));
        }
        final attachmentLabel = attached.isEmpty
            ? ''
            : '\n📎 ${attached.map((a) => a.name).join('、')}';
        await _addDisplay({
          'kind': 'text',
          'author': 'user',
          'text': '$prompt$attachmentLabel',
        });
        _input.clear();
        await persist();
      } else {
        final last = conversation.messages.lastWhere(
          (m) => m['_turn'] != null,
          orElse: () => {},
        );
        prompt = last['_prompt'] as String? ?? '';
        if (prompt.isEmpty) throw StateError('没有可重试的消息');
      }
      if (!mounted) return;
      final lastUser = conversation.messages.lastWhere(
        (m) => m['_turn'] != null,
      );
      final turnId = lastUser['_turn'] as String;
      final since = conversation.messages.sublist(
        conversation.messages.indexOf(lastUser),
      );
      final alreadyMutated = since.any(
        (m) =>
            m['role'] == 'tool' &&
            (jsonDecode(m['content'] as String) as Map)['mutation'] == true,
      );
      final revision = ref.read(localRevisionProvider.notifier);
      final pending = ref.read(pendingAcademicProvider.notifier);
      final session = ref.read(academicSessionProvider);
      final executor = AiToolExecutor(
        platform: ref.read(cithubPlatformProvider),
        repository: ref.read(timetableRepositoryProvider),
        forum: ref.read(appSettingsProvider).tiebaHomeForumName,
        getSession: () => session,
        onSaved: () {
          revision.state++;
          pending.state = null;
        },
        prompt: prompt,
        attachments: conversation.attachments,
        supportsImages: model.images,
        cancellation: cancellation,
        turnId: turnId,
        alreadyMutated: alreadyMutated,
        allowScheduleChanges: _allowScheduleChanges,
        progress: (text) {
          if (mounted) setState(() => _progress = text);
        },
      );
      final client = ref.read(aiClientFactoryProvider)();
      _client = client;
      final runner = AiRunner(client: client, tools: executor);
      setState(() => _progress = '正在生成…');
      await runner.run(
        conversation: conversation,
        settings: settings,
        model: model,
        key: key,
        cancellation: cancellation,
        onText: (text) {
          assistantText = text;
          if (assistantDisplay == null) {
            assistantDisplay = {
              'kind': 'text',
              'author': 'assistant',
              'text': text,
              'id': localId(),
              'at': DateTime.now().toIso8601String(),
            };
            conversation.display.add(assistantDisplay!);
            if (mounted) {
              _chat.insertMessage(_displayMessage(assistantDisplay!));
            }
          } else {
            final old = mounted
                ? _chat.messages
                      .where((m) => m.id == assistantDisplay!['id'])
                      .firstOrNull
                : null;
            assistantDisplay!['text'] = text;
            if (old != null) {
              _chat.updateMessage(old, _displayMessage(assistantDisplay!));
            }
          }
        },
        onReasoning: (text) {
          if (reasoningDisplay == null) {
            reasoningDisplay = {
              'kind': 'reasoning',
              'text': text,
              'id': localId(),
            };
            conversation.display.add(reasoningDisplay!);
            if (mounted) {
              _chat.insertMessage(_displayMessage(reasoningDisplay!));
            }
          } else {
            final old = mounted
                ? _chat.messages
                      .where((m) => m.id == reasoningDisplay!['id'])
                      .firstOrNull
                : null;
            reasoningDisplay!['text'] = text;
            if (old != null) {
              _chat.updateMessage(old, _displayMessage(reasoningDisplay!));
            }
          }
          if (mounted) setState(() => _progress = '正在思考…');
        },
        onTool: (result) async {
          if (result['mutation'] == true) {
            await _addDisplay({'kind': 'schedule', ...result});
          }
          if (result['items'] is List && (result['items'] as List).isNotEmpty) {
            await _addDisplay({
              'kind': 'sources',
              'items': result['items'],
              'actual': result['actual'],
              'partial': result['partial'],
            });
          }
          if (mounted && result['error'] != null) {
            setState(() => _progress = result['error'].toString());
          }
          assistantDisplay = null;
          reasoningDisplay = null;
        },
        persist: persist,
      );
      await persist();
    } on AiCancelled {
      await persist();
      if (mounted) {
        setState(() => _error = '已停止，可继续处理');
      }
    } catch (e) {
      await persist();
      if (mounted) {
        setState(
          () => _error = e is StateError
              ? e.message.toString()
              : e is FormatException
              ? e.message
              : '请求失败，请检查连接或模型配置后重试',
        );
        if (assistantText.isNotEmpty) await persist();
      }
    } finally {
      _client?.close();
      _client = null;
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = '';
        });
      }
    }
  }

  Future<void> _new() async {
    if (_busy) return;
    for (final a in _pending) {
      await deleteAttachment(a);
    }
    _pending.clear();
    setState(() {
      _conversation = AiConversation(id: localId());
      _input.clear();
      _error = null;
    });
    await _chat.setMessages([]);
  }

  Future<void> _history() async {
    if (_busy) return;
    final list = await _repository.all();
    if (!mounted) return;
    final selected = await showModalBottomSheet<AiConversation>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * .7,
            child: Column(
              children: [
                const Padding(padding: EdgeInsets.all(20), child: Text('会话历史')),
                Expanded(
                  child: ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) => ListTile(
                      title: Text(list[i].title),
                      onTap: () => Navigator.pop(ctx, list[i]),
                      trailing: IconButton(
                        tooltip: '删除会话及附件',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final yes = await showDialog<bool>(
                            context: ctx,
                            builder: (dialog) => AlertDialog(
                              title: const Text('删除会话及附件？'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dialog, false),
                                  child: const Text('取消'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(dialog, true),
                                  child: const Text('删除'),
                                ),
                              ],
                            ),
                          );
                          if (yes != true) return;
                          final deleted = list[i];
                          await _repository.delete(deleted);
                          if (!ctx.mounted) return;
                          update(() => list.remove(deleted));
                          if (_conversation.id == deleted.id) await _new();
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    for (final a in _pending) {
      await deleteAttachment(a);
    }
    _pending.clear();
    setState(() {
      _conversation = selected;
      _error = null;
    });
    await _renderHistory();
  }

  Future<void> _link(String url) async {
    final uri = Uri.tryParse(url);
    if (uri?.scheme == 'https') {
      await launchUrl(uri!, mode: LaunchMode.externalApplication);
    }
  }

  Widget _custom(BuildContext context, chat.CustomMessage message) {
    final d = message.metadata ?? {};
    if (d['kind'] == 'reasoning') {
      return Card(
        child: ExpansionTile(
          key: PageStorageKey(message.id),
          leading: const Icon(Icons.psychology_outlined),
          title: const Text('思考过程'),
          subtitle: const Text('模型返回的思考内容'),
          childrenPadding: const EdgeInsets.all(16),
          children: [
            SelectableText(
              d['text'] as String? ?? '',
              key: PageStorageKey('reasoning-text-${message.id}'),
            ),
          ],
        ),
      );
    }
    if (d['kind'] == 'schedule') {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('课表已保存'),
              Text(d['summary'] as String? ?? ''),
              Text('版本 ${d['revision']}'),
              if ((d['conflicts'] as List? ?? []).isNotEmpty)
                Text('课程时间冲突：${(d['conflicts'] as List).join('、')}'),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ScheduleHistoryScreen(
                      scheduleId: d['scheduleId'] as String,
                    ),
                  ),
                ),
                child: const Text('查看历史版本'),
              ),
            ],
          ),
        ),
      );
    }
    final items = (d['items'] as List? ?? []).cast<Map>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '已读取 ${d['actual'] ?? items.length} 条${d['partial'] == true ? '（部分结果）' : ''}',
            ),
            for (final item in items.take(3))
              TextButton(
                onPressed: () => _link(item['url'] as String? ?? ''),
                child: Text(
                  item['title'] as String? ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (items.length > 3)
              TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (ctx) => ListView(
                    children: [
                      for (final item in items)
                        ListTile(
                          title: Text(item['title'] as String? ?? ''),
                          subtitle: Text(
                            item['publishedAt'] as String? ?? '时间未知',
                          ),
                          onTap: () => _link(item['url'] as String? ?? ''),
                        ),
                    ],
                  ),
                ),
                child: const Text('查看全部来源'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(aiSettingsProvider).valueOrNull;
    final modelId =
        settings?.models.any((m) => m.selectionId == _conversation.model) ==
            true
        ? _conversation.model
        : settings?.model?.selectionId;
    return Scaffold(
      appBar: AppBar(
        title: const Text('校园助手'),
        actions: [
          IconButton(
            tooltip: '新建会话',
            onPressed: _busy ? null : _new,
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: '会话历史',
            onPressed: _busy ? null : _history,
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: 'AI 设置',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AiSettingsScreen()),
            ),
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: Column(
        children: [
          if (settings != null && settings.models.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DropdownButton<String>(
                isExpanded: true,
                value: modelId,
                items: settings.models
                    .map(
                      (m) => DropdownMenuItem(
                        value: m.selectionId,
                        child: Text(m.name),
                      ),
                    )
                    .toList(),
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _conversation.model = v!),
              ),
            ),
          if (settings != null && settings.models.isEmpty)
            ListTile(
              title: const Text('先配置 AI 服务与模型'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AiSettingsScreen(),
                ),
              ),
            ),
          SwitchListTile(
            dense: true,
            title: const Text('允许本次对话修改本地课表'),
            subtitle: Text(
              _allowScheduleChanges ? '按你的请求修改并保存历史版本' : '当前只读，不会修改课表',
            ),
            value: _allowScheduleChanges,
            onChanged: _busy
                ? null
                : (value) => setState(() => _allowScheduleChanges = value),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Chat(
                    currentUserId: 'user',
                    resolveUser: (id) async =>
                        chat.User(id: id, name: id == 'user' ? '我' : 'Cithub'),
                    chatController: _chat,
                    theme: chat.ChatTheme(
                      colors: chat.ChatColors(
                        primary: Theme.of(context).colorScheme.primary,
                        onPrimary: Theme.of(context).colorScheme.onPrimary,
                        surface: Theme.of(context).colorScheme.surface,
                        onSurface: Theme.of(context).colorScheme.onSurface,
                        surfaceContainer: Theme.of(context)
                            .colorScheme
                            .surfaceContainer,
                        surfaceContainerLow: Theme.of(context)
                            .colorScheme
                            .surfaceContainerLow,
                        surfaceContainerHigh: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHigh,
                      ),
                      typography: chat.ChatTypography(
                        bodyLarge: Theme.of(context).textTheme.bodyLarge!,
                        bodyMedium: Theme.of(context).textTheme.bodyMedium!,
                        bodySmall: Theme.of(context).textTheme.bodySmall!,
                        labelLarge: Theme.of(context).textTheme.labelLarge!,
                        labelMedium: Theme.of(context).textTheme.labelMedium!,
                        labelSmall: Theme.of(context).textTheme.labelSmall!,
                      ),
                      shape: BorderRadius.circular(16),
                    ),
                    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                    builders: chat.Builders(
                      composerBuilder: (_) => const SizedBox.shrink(),
                      textMessageBuilder:
                          (
                            ctx,
                            message,
                            index, {
                            required isSentByMe,
                            groupStatus,
                          }) => FlyerChatTextMessage(
                            message: message,
                            index: index,
                            borderRadius: BorderRadius.circular(16),
                            onLinkTap: (url, _) => _link(url),
                          ),
                      customMessageBuilder: (
                        ctx,
                        message,
                        index, {
                        required isSentByMe,
                        groupStatus,
                      }) => _custom(ctx, message),
                    ),
                  ),
          ),
          if (_progress.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _progress,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => _send(retry: true),
                    child: const Text('继续／重试'),
                  ),
                ],
              ),
            ),
          if (_pending.isNotEmpty)
            SizedBox(
              height: 60,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final a in _pending)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: InputChip(
                        label: Text(a.name),
                        onPressed: () => _preview(a),
                        onDeleted: _busy
                            ? null
                            : () async {
                                await deleteAttachment(a);
                                if (mounted) setState(() => _pending.remove(a));
                              },
                      ),
                    ),
                ],
              ),
            ),
          if (_conversation.attachments.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => ListView(
                    children: [
                      for (final a in _conversation.attachments)
                        ListTile(title: Text(a.name), onTap: () => _preview(a)),
                    ],
                  ),
                ),
                child: Text('查看会话附件（${_conversation.attachments.length}）'),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: '上传附件',
                    onPressed: _busy ? null : _pick,
                    icon: const Icon(Icons.attach_file),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: !_busy,
                      minLines: 1,
                      maxLines: 5,
                      decoration: InputDecoration(
                        hintText: '提问或描述课表修改…',
                        filled: true,
                        fillColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHigh,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: _busy ? '停止' : '发送',
                    onPressed: _busy
                        ? () => _cancellation?.cancel()
                        : () => _send(),
                    icon: Icon(_busy ? Icons.stop_circle_outlined : Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
