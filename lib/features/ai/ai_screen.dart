// RikkaHub-derived message layout and animations: AGPL-3.0-only.
// Pinned upstream source and license: third_party/RikkaHub/README.md.
import '../../core/logging/runtime_log.dart';
import '../../core/logging/runtime_audit.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart' as chat;
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flyer_chat_text_message/flyer_chat_text_message.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/platform/cithub_platform.dart';
import '../../core/widgets/chinese_text_selection.dart';
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
import 'ai_reasoning_card.dart';
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
  bool _busy = false, _loading = true, _controlsSaving = false;
  String? _error;
  String _progress = '';
  @override
  void initState() {
    super.initState();
    RuntimeLog.event('ai-screen', 'entered', {
      'conversationId': _conversation.id,
      'initialText': widget.initialText,
    });
    _input.text = widget.initialText ?? '';
    var previousInput = _input.text;
    _input.addListener(() {
      if (_input.text == previousInput) return;
      RuntimeLog.event('ai-input', 'changed', {
        'conversationId': _conversation.id,
        'before': previousInput,
        'after': _input.text,
      });
      previousInput = _input.text;
    });
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
    RuntimeLog.event('ai-screen', 'left', {
      'conversationId': _conversation.id,
      'busy': _busy,
      'continuesInBackground': _client != null,
    });
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
          metadata: Map<String, dynamic>.from(d),
        )
      : chat.Message.custom(
          id: d['id'] as String,
          authorId: 'assistant',
          metadata: Map<String, dynamic>.from(d),
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
    RuntimeLog.event('attachment', 'picker-opened', {
      'pending': _pending.map((a) => a.manifest).toList(),
      'type': 'any',
    });
    final cancellation = AiCancellation();
    _cancellation = cancellation;
    setState(() {
      _busy = true;
      _progress = '请选择附件…';
    });
    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      RuntimeLog.event(
        'attachment',
        files.isEmpty ? 'picker-cancelled' : 'files-selected',
        {
          'files': files.map((f) => {'name': f.name, 'path': f.path}).toList(),
        },
      );
      if (!mounted) return;
      for (final file in files) {
        cancellation.check();
        if (_pending.length >= 5) {
          _message('每条消息最多 5 个附件');
          break;
        }
        setState(() => _progress = '正在处理 ${file.name}…');
        try {
          final attachment = await importAttachment(file, cancellation);
          if (!mounted || cancellation.cancelled) {
            await deleteAttachment(attachment);
            break;
          }
          final before = _pending.map((a) => a.manifest).toList();
          setState(() => _pending.add(attachment));
          RuntimeLog.event('attachment', 'pending-changed', {
            'before': before,
            'after': _pending.map((a) => a.manifest).toList(),
          });
        } on AiCancelled {
          rethrow;
        } catch (error, stack) {
          RuntimeLog.event('attachment', 'file-failed', {
            'name': file.name,
            'error': '$error',
            'stack': '$stack',
          });
          _message(
            '${file.name}：${error is FormatException ? error.message : '文件无法读取，请检查是否损坏或已加密'}',
          );
        }
      }
    } on AiCancelled {
      RuntimeLog.event('attachment', 'processing-cancelled', {
        'pending': _pending.map((a) => a.manifest).toList(),
      });
    } catch (error, stack) {
      RuntimeLog.event('attachment', 'picker-failed', {
        'error': '$error',
        'stack': '$stack',
      });
      _message('无法选择文件，请重试');
    } finally {
      if (identical(_cancellation, cancellation)) _cancellation = null;
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
                      SelectableText(
                        b['text'] as String? ?? '扫描页面',
                        contextMenuBuilder: chineseEditableTextMenu,
                      ),
                      const Divider(),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _send({bool retry = false}) async {
    if (_busy || _loading || _controlsSaving) return;
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
      await Navigator.of(context).push(
        LoggedMaterialPageRoute<void>(builder: (_) => const AiSettingsScreen()),
      );
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
    var replyId = localId();
    final displayGroupId = localId();
    final sourceDisplays = <Map<String, dynamic>>[];
    Map<String, dynamic>? currentSource;
    final nativeSearchDisplays = <String, Map<String, dynamic>>{};
    Stopwatch? reasoningWatch;
    final conversation = _conversation;
    void updateDisplay(Map<String, dynamic> data) {
      if (!mounted) return;
      final old = _chat.messages.where((m) => m.id == data['id']).firstOrNull;
      if (old != null) _chat.updateMessage(old, _displayMessage(data));
    }

    void updateSource(
      Map<String, dynamic> data,
      void Function() change,
      String action,
    ) {
      final before = Map<String, dynamic>.from(data);
      change();
      RuntimeLog.event('ai-sources', action, {
        'conversationId': conversation.id,
        'replyId': data['replyId'],
        'callId': data['callId'],
        'messageId': data['id'],
        'before': before,
        'after': Map<String, dynamic>.from(data),
        'elapsedMs': DateTime.now()
            .difference(DateTime.parse(data['startedAt'] as String))
            .inMilliseconds,
      });
      updateDisplay(data);
    }

    void finishSources(String status) {
      for (final data in sourceDisplays.where(
        (d) =>
            d['status'] == 'thinking' ||
            (status != 'completed' &&
                d['nativeSearch'] == true &&
                d['searchStatus'] != 'completed'),
      )) {
        updateSource(data, () {
          data['status'] = status;
          data['pending'] = false;
          data['finishedAt'] = DateTime.now().toIso8601String();
          data['elapsedMs'] = DateTime.now()
              .difference(DateTime.parse(data['startedAt'] as String))
              .inMilliseconds;
        }, 'finished');
      }
    }

    void finishReasoning(String status) {
      final data = reasoningDisplay;
      if (data == null || data['status'] != 'thinking') return;
      final before = Map<String, dynamic>.from(data);
      reasoningWatch?.stop();
      data['status'] = status;
      data['finishedAt'] = DateTime.now().toIso8601String();
      data['elapsedMs'] = reasoningWatch?.elapsedMilliseconds ?? 0;
      RuntimeLog.event('ai-reasoning', 'finished', {
        'conversationId': conversation.id,
        'replyId': replyId,
        'messageId': data['id'],
        'before': before,
        'after': Map<String, dynamic>.from(data),
        'result': status,
        'elapsedMs': data['elapsedMs'],
      });
      updateDisplay(data);
    }

    void finishText(String status) {
      final data = assistantDisplay;
      if (data == null || data['streaming'] != true) return;
      final before = Map<String, dynamic>.from(data);
      data['streaming'] = false;
      data['status'] = status;
      RuntimeLog.event('ai-message', 'finished', {
        'conversationId': conversation.id,
        'replyId': replyId,
        'before': before,
        'after': Map<String, dynamic>.from(data),
      });
      updateDisplay(data);
    }

    final repository = _repository;
    Future<void> persist() => repository.save(conversation);
    try {
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
          if (model.tools) {
            continue; // Tool-capable models request only needed blocks.
          }
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
        requestScheduleChange: _requestScheduleChange,
        progress: (text) {
          if (currentSource != null) {
            updateSource(currentSource!, () {
              currentSource!['progress'] = text;
              currentSource!['text'] = text;
            }, 'progress');
          }
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
          finishSources('completed');
          finishReasoning('completed');
          if (mounted && _progress == '正在思考…') {
            setState(() => _progress = '正在生成…');
          }
          assistantText = text;
          if (assistantDisplay == null) {
            assistantDisplay = {
              'kind': 'text',
              'author': 'assistant',
              'replyId': replyId,
              'groupId': displayGroupId,
              'modelName': model.name,
              'streaming': true,
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
          final before = reasoningDisplay == null
              ? null
              : Map<String, dynamic>.from(reasoningDisplay!);
          if (reasoningDisplay == null) {
            reasoningWatch = Stopwatch()..start();
            reasoningDisplay = {
              'kind': 'reasoning',
              'text': text,
              'id': localId(),
              'replyId': replyId,
              'groupId': displayGroupId,
              'modelName': model.name,
              'status': 'thinking',
              'startedAt': DateTime.now().toIso8601String(),
            };
            conversation.display.add(reasoningDisplay!);
            if (mounted) {
              _chat.insertMessage(_displayMessage(reasoningDisplay!));
            }
          } else {
            reasoningDisplay!['text'] = text;
            updateDisplay(reasoningDisplay!);
          }
          RuntimeLog.event(
            'ai-reasoning',
            before == null ? 'started' : 'updated',
            {
              'conversationId': conversation.id,
              'replyId': replyId,
              'groupId': displayGroupId,
              'messageId': reasoningDisplay!['id'],
              'before': before,
              'after': Map<String, dynamic>.from(reasoningDisplay!),
              'elapsedMs': reasoningWatch?.elapsedMilliseconds,
            },
          );
          if (mounted && reasoningDisplay!['status'] == 'thinking') {
            setState(() => _progress = '正在思考…');
          }
        },
        onResponseComplete: () {
          finishReasoning('completed');
          finishText('completed');
        },
        onNativeSearch: (event) {
          final id = event['id'] as String? ?? 'native-search';
          var data = nativeSearchDisplays[id];
          if (data == null) {
            data = {
              'kind': 'sources',
              'nativeSearch': true,
              'id': localId(),
              'callId': id,
              'replyId': replyId,
              'groupId': displayGroupId,
              'modelName': model.name,
              'startedAt': DateTime.now().toIso8601String(),
              'status': 'thinking',
              'pending': true,
              'progress': '模型正在联网搜索…',
              'text': '模型正在联网搜索…',
              'items': <Map<String, dynamic>>[],
            };
            nativeSearchDisplays[id] = data;
            sourceDisplays.add(data);
            RuntimeLog.event('ai-native-search', 'started', {
              'conversationId': conversation.id,
              'callId': id,
              'after': Map<String, dynamic>.from(data),
            });
            conversation.display.add(data);
            if (mounted) _chat.insertMessage(_displayMessage(data));
          }
          final target = data;
          updateSource(target, () {
            if (event['status'] != null) {
              target['searchStatus'] = event['status'];
            }
            target['events'] = [...target['events'] as List? ?? [], event];
            if (event['action'] is Map) {
              target['action'] = event['action'];
              final urls = (event['action']['sources'] as List? ?? [])
                  .whereType<Map>();
              target['items'] = [
                for (final source in urls)
                  {
                    ...Map<String, dynamic>.from(source),
                    'title': source['title'] ?? source['url'],
                  },
              ];
              target['actual'] = (target['items'] as List).length;
            }
            if (event['status'] == 'completed' || event['status'] == 'failed') {
              target['pending'] = false;
              target['progress'] = '';
            }
            target['text'] = _customCopyText(target);
          }, 'native-search-event');
        },
        onToolStart: (name, arguments, callId) async {
          final isContent =
              name == 'latest_content' ||
              (name == 'batch_read' &&
                  (arguments['requests'] as List? ?? []).any(
                    (r) => r is Map && r['name'] == 'latest_content',
                  ));
          if (!isContent) return;
          currentSource = {
            'kind': 'sources',
            'id': localId(),
            'replyId': replyId,
            'groupId': displayGroupId,
            'modelName': model.name,
            'callId': callId,
            'tool': name,
            'arguments': arguments,
            'status': 'thinking',
            'startedAt': DateTime.now().toIso8601String(),
            'pending': true,
            'progress': '正在读取校园资讯…',
            'text': '正在读取校园资讯…',
            'items': <Map<String, dynamic>>[],
          };
          sourceDisplays.add(currentSource!);
          RuntimeLog.event('ai-sources', 'started', {
            'conversationId': conversation.id,
            'callId': callId,
            'messageId': currentSource!['id'],
            'replyId': replyId,
            'before': null,
            'after': Map<String, dynamic>.from(currentSource!),
          });
          await _addDisplay(currentSource!);
        },
        onTool: (result) async {
          if (result['mutation'] == true) {
            await _addDisplay({'kind': 'schedule', ...result});
          }
          final items = <Map<String, dynamic>>[];
          final reads = <Map<String, dynamic>>[];
          void collectSources(Map<String, dynamic> data) {
            if (data['items'] is List) {
              reads.add(data);
              for (final item in data['items'] as List) {
                if (item is Map) items.add(Map<String, dynamic>.from(item));
              }
            }
            for (final nested in data['results'] as List? ?? []) {
              if (nested is Map && nested['result'] is Map) {
                collectSources(
                  Map<String, dynamic>.from(nested['result'] as Map),
                );
              }
            }
          }

          collectSources(result);
          final data = currentSource;
          if (data != null) {
            updateSource(data, () {
              data['items'] = items;
              data['actual'] = items.length;
              data['requested'] = reads.fold<int>(
                0,
                (sum, read) =>
                    sum +
                    ((read['requested'] ?? read['actual']) as num? ?? 0)
                        .toInt(),
              );
              data['partial'] =
                  result['partial'] == true ||
                  result['error'] != null ||
                  reads.any((r) => r['partial'] == true);
              data['message'] = [
                if (result['error'] != null) result['error'],
                ...reads.map((r) => r['message']).whereType<String>(),
              ].join('；');
              data['result'] = result;
              data['pending'] = false;
              data['progress'] = '';
              data['text'] = _customCopyText(data);
            }, 'result');
            currentSource = null;
          }
          if (mounted && result['error'] != null) {
            setState(() => _progress = result['error'].toString());
          }
          assistantDisplay = null;
          reasoningDisplay = null;
          reasoningWatch = null;
          replyId = localId();
        },
        persist: persist,
      );
      finishSources('completed');
      await persist();
    } on AiCancelled {
      finishSources('cancelled');
      finishReasoning('cancelled');
      finishText('cancelled');
      RuntimeLog.event('ai-run', 'cancelled', {
        'conversationId': conversation.id,
        'prompt': prompt,
      });
      await persist();
      if (mounted) {
        setState(() => _error = '已停止，可继续处理');
      }
    } catch (e, stack) {
      finishSources('failed');
      finishReasoning('failed');
      finishText('failed');
      RuntimeLog.event('ai-run', 'failed', {
        'conversationId': conversation.id,
        'model': model.selectionId,
        'prompt': prompt,
        'error': '$e',
        'stack': '$stack',
      });
      await persist();
      if (mounted) {
        setState(() => _error = aiErrorMessage(e));
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

  Future<bool> _requestScheduleChange(ScheduleChangeRequest request) async {
    if (!mounted) return false;
    setState(() => _progress = '');
    final approved = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('允许 AI 修改课表？'),
        content: SelectionArea(
          contextMenuBuilder: chineseSelectionMenu,
          child: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('学期：${request.term}'),
                  const SizedBox(height: 12),
                  Text(request.summary),
                  for (final change in request.changes)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(change),
                    ),
                  const SizedBox(height: 16),
                  const Text('仅修改本机课表，并保存可恢复的历史版本。'),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('不允许'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('允许'),
          ),
        ],
      ),
    );
    if (mounted && approved == true) setState(() => _progress = '正在保存课表…');
    return approved == true;
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
      await RuntimeLog.trace('ai-message', 'open-link', {
        'conversationId': _conversation.id,
        'url': url,
      }, () => launchUrl(uri!, mode: LaunchMode.externalApplication));
    }
  }

  Future<void> _copyText(String text, {required String messageId}) async {
    try {
      await RuntimeLog.trace('ai-message', 'copy', {
        'conversationId': _conversation.id,
        'messageId': messageId,
        'text': text,
      }, () => Clipboard.setData(ClipboardData(text: text)));
      _message('已复制');
    } catch (_) {
      _message('复制失败，请重试');
    }
  }

  Widget _messageBubble(
    BuildContext context,
    chat.Message message,
    int index,
    Animation<double> animation,
    Widget child, {
    required bool isSentByMe,
    bool? isRemoved,
    chat.MessageGroupStatus? groupStatus,
  }) {
    final colors = Theme.of(context).colorScheme;
    final data = message.metadata ?? {};
    final reasoning = data['kind'] == 'reasoning' || data['kind'] == 'sources';
    final previous = index > 0 && index <= _chat.messages.length
        ? _chat.messages[index - 1]
        : null;
    final continuation =
        !isSentByMe &&
        (data['groupId'] ?? data['replyId']) != null &&
        (previous?.metadata?['groupId'] ?? previous?.metadata?['replyId']) ==
            (data['groupId'] ?? data['replyId']);
    final copyText = message is chat.TextMessage
        ? message.text
        : _customCopyText(data);
    final header = Row(
      mainAxisAlignment: isSentByMe
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        if (isSentByMe) ...[
          Text('我', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 8),
        ],
        CircleAvatar(
          radius: 14,
          backgroundColor: colors.secondaryContainer,
          child: Icon(
            isSentByMe ? Icons.person_outline : Icons.auto_awesome,
            size: 18,
            color: colors.onSecondaryContainer,
          ),
        ),
        if (!isSentByMe) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              data['modelName'] as String? ?? '校园助手',
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
    final curve = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: curve,
      child: SizeTransition(
        sizeFactor: curve,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, .06),
            end: Offset.zero,
          ).animate(curve),
          child: LayoutBuilder(
            builder: (context, constraints) => ChatMessage(
              message: message,
              index: index,
              animation: const AlwaysStoppedAnimation(1),
              isRemoved: isRemoved,
              groupStatus: groupStatus,
              padding: EdgeInsets.fromLTRB(
                16,
                continuation ? 0 : 20,
                16,
                reasoning ? 12 : 4,
              ),
              child: SizedBox(
                width: (constraints.maxWidth - 32).clamp(0, 720).toDouble(),
                child: Column(
                  crossAxisAlignment: isSentByMe
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!continuation) ...[header, const SizedBox(height: 12)],
                    Align(
                      alignment: isSentByMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        key: ValueKey('bubble-${message.id}'),
                        constraints: BoxConstraints(
                          maxWidth: isSentByMe
                              ? (constraints.maxWidth - 80)
                                    .clamp(0, 640)
                                    .toDouble()
                              : (constraints.maxWidth - 32)
                                    .clamp(0, 720)
                                    .toDouble(),
                        ),
                        decoration: isSentByMe
                            ? BoxDecoration(
                                color: colors.primaryContainer,
                                borderRadius: BorderRadius.circular(24),
                              )
                            : null,
                        child: child,
                      ),
                    ),
                    if (!reasoning)
                      AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        alignment: isSentByMe
                            ? Alignment.topRight
                            : Alignment.topLeft,
                        child: data['streaming'] == true
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: IconButton(
                                  key: ValueKey('copy-${message.id}'),
                                  tooltip: '复制',
                                  onPressed: () => _copyText(
                                    copyText,
                                    messageId: message.id,
                                  ),
                                  icon: Icon(
                                    Icons.copy_outlined,
                                    size: 19,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _customCopyText(Map<String, dynamic> data) {
    if (data['kind'] == 'reasoning') return data['text'] as String? ?? '';
    if (data['kind'] == 'schedule') {
      return [
        '课表已保存',
        data['summary'] ?? '',
        '版本 ${data['revision']}',
        if ((data['conflicts'] as List? ?? []).isNotEmpty)
          '课程时间冲突：${(data['conflicts'] as List).join('、')}',
      ].join('\n');
    }
    return [
      data['nativeSearch'] == true
          ? '模型自带搜索 · ${data['actual'] ?? (data['items'] as List? ?? []).length} 个来源'
          : '已读取 ${data['actual'] ?? (data['items'] as List? ?? []).length} 条${data['partial'] == true ? '（部分结果）' : ''}',
      if (data['nativeSearch'] == true && data['action'] is Map)
        jsonEncode(data['action']),
      if ((data['message'] as String? ?? '').isNotEmpty)
        data['message'] as String,
      for (final item in (data['items'] as List? ?? []).cast<Map>())
        ['title', 'publishedAt', 'url', 'content', 'summary']
            .map((key) => item[key])
            .whereType<String>()
            .where((value) => value.isNotEmpty)
            .join('\n'),
    ].join('\n\n');
  }

  Widget _custom(BuildContext context, chat.CustomMessage message) =>
      _customContent(context, message);

  Widget _customContent(BuildContext context, chat.CustomMessage message) {
    final d = message.metadata ?? {};
    if (d['kind'] == 'reasoning') {
      return AiReasoningCard(
        key: ValueKey('reasoning-${message.id}'),
        data: d,
        onCopy: () =>
            _copyText(d['text'] as String? ?? '', messageId: message.id),
        onLink: _link,
      );
    }
    if (d['kind'] == 'schedule') {
      return Card(
        color: Colors.transparent,
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
                  LoggedMaterialPageRoute<void>(
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
    final actual = d['actual'] ?? items.length;
    final requested = d['requested'] as num?;
    final insufficient = requested != null && (actual as num) < requested;
    final label = d['nativeSearch'] == true
        ? (d['status'] == 'cancelled'
              ? '联网搜索已停止'
              : d['status'] == 'failed' || d['searchStatus'] == 'failed'
              ? '联网搜索中断'
              : d['searchStatus'] == 'completed'
              ? '联网搜索已完成'
              : '模型正在联网搜索…')
        : d['pending'] == true
        ? '正在读取校园资讯…'
        : '已读取 $actual${insufficient ? '/$requested' : ''} 条${d['status'] == 'cancelled'
              ? '（已停止）'
              : d['status'] == 'failed'
              ? '（处理失败）'
              : ''}${d['partial'] == true
              ? '（部分结果）'
              : insufficient
              ? '（来源不足）'
              : ''}';
    return AiReasoningCard(
      key: ValueKey('sources-${message.id}'),
      data: d,
      title: label,
      icon: Icons.manage_search_outlined,
      onCopy: () => _copyText(_customCopyText(d), messageId: message.id),
      onLink: _link,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (d['pending'] == true)
            Text(d['progress'] as String? ?? '正在读取校园资讯…'),
          if ((d['message'] as String? ?? '').isNotEmpty)
            Text(d['message'] as String),
          for (final item in items)
            TextButton(
              onPressed: () => _link(item['url'] as String? ?? ''),
              style: TextButton.styleFrom(alignment: Alignment.centerLeft),
              child: Text(item['title'] as String? ?? ''),
            ),
        ],
      ),
    );
  }

  Future<void> _applyChatSetting(
    String operation, {
    String? model,
    AiGenerationOptions? options,
  }) async {
    if (_busy || _controlsSaving) return;
    final conversation = _conversation;
    final beforeModel = conversation.model;
    final beforeOptions = conversation.options;
    final operationId = localId();
    final before = {'model': beforeModel, 'options': beforeOptions.toJson()};
    final after = {
      'model': model ?? beforeModel,
      'options': (options ?? beforeOptions).toJson(),
    };
    setState(() => _controlsSaving = true);
    try {
      await RuntimeLog.trace(
        'ai-controls',
        operation,
        {
          'operationId': operationId,
          'conversationId': conversation.id,
          'before': before,
          'after': after,
        },
        () async {
          setState(() {
            conversation.model = model ?? beforeModel;
            conversation.options = options ?? beforeOptions;
          });
          RuntimeLog.event('ai-controls', 'changed', {
            'operationId': operationId,
            'conversationId': conversation.id,
            'operation': operation,
            'before': before,
            'after': after,
          });
          if (conversation.display.isNotEmpty) {
            await _repository.save(conversation);
          }
        },
      );
    } catch (_) {
      if (mounted && identical(conversation, _conversation)) {
        setState(() {
          conversation.model = beforeModel;
          conversation.options = beforeOptions;
        });
        RuntimeLog.event('ai-controls', 'rolled-back', {
          'operationId': operationId,
          'conversationId': conversation.id,
          'before': after,
          'after': before,
        });
        _message('设置保存失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _controlsSaving = false);
    }
  }

  Future<void> _chooseModel(AiSettings settings, String? selectedId) async {
    try {
      final selected = await RuntimeLog.trace(
        'ai-controls',
        'open-model-picker',
        {
          'conversationId': _conversation.id,
          'selectedId': selectedId,
          'models': settings.models.map((m) => m.toJson()).toList(),
        },
        () => showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (ctx) => SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * .65,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      '选择模型',
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final m in settings.models)
                          ListTile(
                            key: ValueKey('model-option-${m.selectionId}'),
                            leading: const Icon(Icons.auto_awesome),
                            title: Text(m.name),
                            subtitle: Text(m.id),
                            trailing: m.selectionId == selectedId
                                ? const Icon(Icons.check)
                                : null,
                            onTap: () {
                              RuntimeLog.event(
                                'ai-controls',
                                'model-option-tapped',
                                {
                                  'conversationId': _conversation.id,
                                  'before': selectedId,
                                  'after': m.selectionId,
                                  'model': m.toJson(),
                                },
                              );
                              Navigator.pop(ctx, m.selectionId);
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (!mounted) return;
      if (selected == null) {
        RuntimeLog.event('ai-controls', 'model-picker-cancelled', {
          'conversationId': _conversation.id,
          'selectedId': selectedId,
        });
      } else {
        await _applyChatSetting('model-selected', model: selected);
      }
    } catch (error, stack) {
      RuntimeLog.event('ai-controls', 'model-picker-failed', {
        'conversationId': _conversation.id,
        'error': '$error',
        'stack': '$stack',
      });
      _message('模型列表打开失败，请重试');
    }
  }

  Future<void> _chooseReasoning(AiModel model) async {
    final levels = ['default', ...model.reasoningEfforts];
    final current = levels.contains(_conversation.options.reasoningEffort)
        ? _conversation.options.reasoningEffort
        : 'default';
    try {
      final selected = await RuntimeLog.trace(
        'ai-controls',
        'open-reasoning-picker',
        {
          'conversationId': _conversation.id,
          'model': model.toJson(),
          'before': current,
          'levels': levels,
        },
        () => showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (ctx) => SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * .65,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      '思考程度',
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final level in levels)
                          ListTile(
                            key: ValueKey('reasoning-option-$level'),
                            title: Text(aiReasoningLabels[level] ?? level),
                            trailing: level == current
                                ? const Icon(Icons.check)
                                : null,
                            onTap: () {
                              RuntimeLog.event(
                                'ai-controls',
                                'reasoning-option-tapped',
                                {
                                  'conversationId': _conversation.id,
                                  'modelId': model.selectionId,
                                  'before': current,
                                  'after': level,
                                },
                              );
                              Navigator.pop(ctx, level);
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (!mounted) return;
      if (selected == null) {
        RuntimeLog.event('ai-controls', 'reasoning-picker-cancelled', {
          'conversationId': _conversation.id,
          'before': current,
        });
      } else {
        await _applyChatSetting(
          'reasoning-selected',
          options: AiGenerationOptions(
            webSearch: _conversation.options.webSearch,
            reasoningEffort: selected,
          ),
        );
      }
    } catch (error, stack) {
      RuntimeLog.event('ai-controls', 'reasoning-picker-failed', {
        'conversationId': _conversation.id,
        'error': '$error',
        'stack': '$stack',
      });
      _message('思考程度列表打开失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(aiSettingsProvider).valueOrNull;
    final modelId =
        settings?.models.any((m) => m.selectionId == _conversation.model) ==
            true
        ? _conversation.model
        : settings?.model?.selectionId;
    final selectedModel = settings?.models
        .where((m) => m.selectionId == modelId)
        .firstOrNull;
    final controlsEnabled = !_busy && !_controlsSaving && !_loading;
    final searchEnabled =
        selectedModel?.nativeSearch == true && _conversation.options.webSearch;
    final effort =
        selectedModel?.reasoning == true &&
            selectedModel!.reasoningEfforts.contains(
              _conversation.options.reasoningEffort,
            )
        ? _conversation.options.reasoningEffort
        : 'default';
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
              LoggedMaterialPageRoute<void>(
                builder: (_) => const AiSettingsScreen(),
              ),
            ),
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: SelectionArea(
        contextMenuBuilder: chineseSelectionMenu,
        child: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Chat(
                      currentUserId: 'user',
                      resolveUser: (id) async => chat.User(
                        id: id,
                        name: id == 'user' ? '我' : 'Cithub',
                      ),
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
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      builders: chat.Builders(
                        emptyChatListBuilder: (context) => Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer,
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  child: Icon(
                                    Icons.auto_awesome,
                                    size: 36,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  '校园生活，随时问我',
                                  style: Theme.of(context).textTheme.titleLarge,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  '聊校园资讯、查看课程，或上传附件整理课表',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 22),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  alignment: WrapAlignment.center,
                                  children: [
                                    for (final prompt in [
                                      '整理最新校园资讯',
                                      '查看本周课程',
                                      '根据附件更新课表',
                                    ])
                                      ActionChip(
                                        label: Text(prompt),
                                        onPressed: _busy
                                            ? null
                                            : () {
                                                RuntimeLog.event(
                                                  'ai-input',
                                                  'suggestion-selected',
                                                  {'text': prompt},
                                                );
                                                _input.text = prompt;
                                              },
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        chatMessageBuilder: _messageBubble,
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
                              padding: isSentByMe
                                  ? const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    )
                                  : EdgeInsets.zero,
                              borderRadius: BorderRadius.zero,
                              sentBackgroundColor: Colors.transparent,
                              receivedBackgroundColor: Colors.transparent,
                              sentTextStyle: Theme.of(ctx).textTheme.bodyLarge!
                                  .copyWith(
                                    color: Theme.of(ctx)
                                        .colorScheme
                                        .onPrimaryContainer,
                                  ),
                              receivedTextStyle: Theme.of(ctx)
                                  .textTheme
                                  .bodyLarge!
                                  .copyWith(
                                    color: Theme.of(ctx).colorScheme.onSurface,
                                  ),
                              sentLinksColor: Theme.of(ctx).colorScheme.primary,
                              showTime: false,
                              showStatus: false,
                              timeStyle: Theme.of(ctx).textTheme.labelSmall!
                                  .copyWith(
                                    color:
                                        (isSentByMe
                                                ? Theme.of(ctx)
                                                      .colorScheme
                                                      .onPrimaryContainer
                                                : Theme.of(ctx)
                                                      .colorScheme
                                                      .onSurfaceVariant)
                                            .withValues(alpha: .7),
                                  ),
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
            if (_progress.isNotEmpty && _progress != '正在思考…')
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
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
                                  if (mounted) {
                                    setState(() => _pending.remove(a));
                                  }
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
                          ListTile(
                            title: Text(a.name),
                            onTap: () => _preview(a),
                          ),
                      ],
                    ),
                  ),
                  child: Text('查看会话附件（${_conversation.attachments.length}）'),
                ),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: DecoratedBox(
                  key: const ValueKey('ai-composer'),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          contextMenuBuilder: chineseEditableTextMenu,
                          controller: _input,
                          enabled: !_busy,
                          minLines: 1,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            hintText: '输入消息与 AI 聊天',
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              key: const ValueKey('ai-model-picker'),
                              tooltip: selectedModel == null
                                  ? '配置 AI 模型'
                                  : '切换模型：${selectedModel.name}',
                              color: Theme.of(context).colorScheme.secondary,
                              onPressed: !controlsEnabled || settings == null
                                  ? null
                                  : () async {
                                      if (settings.models.isEmpty) {
                                        await RuntimeLog.trace(
                                          'ai-controls',
                                          'configure-model',
                                          {'conversationId': _conversation.id},
                                          () => Navigator.of(context).push(
                                            LoggedMaterialPageRoute<void>(
                                              builder: (_) =>
                                                  const AiSettingsScreen(),
                                            ),
                                          ),
                                        );
                                      } else {
                                        await _chooseModel(settings, modelId);
                                      }
                                    },
                              icon: const Icon(Icons.auto_awesome),
                            ),
                            IconButton(
                              key: const ValueKey('ai-native-search'),
                              tooltip: selectedModel?.nativeSearch == true
                                  ? (searchEnabled ? '关闭模型自带搜索' : '开启模型自带搜索')
                                  : '模型自带搜索（需在模型配置中启用支持）',
                              isSelected: searchEnabled,
                              onPressed:
                                  controlsEnabled &&
                                      selectedModel?.nativeSearch == true
                                  ? () => _applyChatSetting(
                                      'native-search-toggled',
                                      options: AiGenerationOptions(
                                        webSearch: !searchEnabled,
                                        reasoningEffort: _conversation
                                            .options
                                            .reasoningEffort,
                                      ),
                                    )
                                  : null,
                              icon: const Icon(Icons.search),
                              selectedIcon: const Icon(Icons.search),
                            ),
                            IconButton(
                              key: const ValueKey('ai-reasoning-picker'),
                              tooltip: selectedModel?.reasoning == true
                                  ? '思考程度：${aiReasoningLabels[effort]}'
                                  : '思考程度（需在模型配置中启用支持）',
                              isSelected:
                                  effort != 'default' && effort != 'none',
                              onPressed:
                                  controlsEnabled &&
                                      selectedModel?.reasoning == true
                                  ? () => _chooseReasoning(selectedModel!)
                                  : null,
                              icon: const Icon(Icons.lightbulb_outline),
                              selectedIcon: const Icon(Icons.lightbulb),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: '上传附件',
                              onPressed: _busy ? null : _pick,
                              icon: const Icon(Icons.add),
                            ),
                            IconButton.filledTonal(
                              tooltip: _busy ? '停止' : '发送',
                              style: _busy
                                  ? IconButton.styleFrom(
                                      backgroundColor: Theme.of(context)
                                          .colorScheme
                                          .errorContainer,
                                      foregroundColor: Theme.of(context)
                                          .colorScheme
                                          .onErrorContainer,
                                    )
                                  : null,
                              onPressed: _controlsSaving
                                  ? null
                                  : _busy
                                  ? () {
                                      RuntimeLog.event(
                                        'ai-run',
                                        'stop-requested',
                                        {
                                          'conversationId': _conversation.id,
                                          'progress': _progress,
                                          'display': _conversation.display,
                                          'pendingAttachments': _pending
                                              .map((a) => a.manifest)
                                              .toList(),
                                        },
                                      );
                                      _cancellation?.cancel();
                                    }
                                  : () => _send(),
                              icon: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: Icon(
                                  _busy ? Icons.close : Icons.arrow_upward,
                                  key: ValueKey(_busy),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
