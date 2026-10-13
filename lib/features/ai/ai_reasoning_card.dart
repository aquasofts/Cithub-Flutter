// SPDX-License-Identifier: AGPL-3.0-only
// Flutter adaptation of RikkaHub's ChatMessageReasoning / ChainOfThought.
// Source and upstream license: third_party/RikkaHub/README.md.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../core/logging/runtime_log.dart';
import '../../core/widgets/chinese_text_selection.dart';

enum _ReasoningState { collapsed, preview, expanded }

/// RikkaHub's three states: a live 100dp preview, full expansion, and a
/// compact finished chip. Finishing always collapses a previously open card.
class AiReasoningCard extends StatefulWidget {
  const AiReasoningCard({
    super.key,
    required this.data,
    required this.onCopy,
    required this.onLink,
    this.content,
    this.title,
    this.icon = Icons.lightbulb_outline,
  });

  final Map<String, dynamic> data;
  final Widget? content;
  final String? title;
  final IconData icon;
  final VoidCallback onCopy;
  final void Function(String) onLink;

  @override
  State<AiReasoningCard> createState() => _AiReasoningCardState();
}

class _AiReasoningCardState extends State<AiReasoningCard>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  late final AnimationController _shimmer;
  late _ReasoningState _state;
  Timer? _timer;

  bool get _loading => widget.data['status'] == 'thinking';
  String get _text => widget.data['text'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    _state = _loading ? _ReasoningState.preview : _ReasoningState.collapsed;
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _syncTimer();
    _followTail();
  }

  @override
  void didUpdateWidget(AiReasoningCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data['status'] != widget.data['status']) {
      _state = _loading ? _ReasoningState.preview : _ReasoningState.collapsed;
      _syncTimer();
    }
    if (_loading && oldWidget.data['text'] != _text) _followTail();
  }

  void _syncTimer() {
    _timer?.cancel();
    if (_loading) {
      _shimmer.repeat();
      _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _shimmer.stop();
    }
  }

  void _followTail() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_loading || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _toggle() {
    final before = _state;
    final next = _state == _ReasoningState.expanded
        ? (_loading ? _ReasoningState.preview : _ReasoningState.collapsed)
        : _ReasoningState.expanded;
    unawaited(
      RuntimeLog.trace(
        'ai-reasoning',
        'toggle',
        {
          'messageId': widget.data['id'],
          'replyId': widget.data['replyId'],
          'before': before.name,
          'after': next.name,
          'content': widget.data,
        },
        () async {
          setState(() => _state = next);
          RuntimeLog.event('ai-reasoning', 'visibility-changed', {
            'messageId': widget.data['id'],
            'replyId': widget.data['replyId'],
            'before': before.name,
            'after': next.name,
            'text': _text,
          });
          if (_loading) _followTail();
        },
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _shimmer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String get _title {
    final started = DateTime.tryParse(
      widget.data['startedAt'] as String? ?? '',
    );
    final ms = _loading && started != null
        ? DateTime.now().difference(started).inMilliseconds.clamp(0, 1 << 53)
        : widget.data['elapsedMs'] as num?;
    final seconds = ms == null ? '' : ' ${(ms / 1000).toStringAsFixed(1)} 秒';
    return switch (widget.data['status']) {
      'thinking' => '正在思考$seconds',
      'cancelled' => '思考已停止$seconds',
      'failed' => '思考中断$seconds',
      _ => ms == null ? '思考过程' : '思考了$seconds',
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final preview = _state == _ReasoningState.preview;
    final expanded = _state == _ReasoningState.expanded;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 300);
    Widget content =
        widget.content ??
        GptMarkdown(
          _text,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: colors.onSurfaceVariant, height: 1.5),
          onLinkTap: (url, _) => widget.onLink(url),
        );
    if (!_loading) {
      content = SelectionArea(
        contextMenuBuilder: chineseSelectionMenu,
        child: content,
      );
    } else {
      content = SelectionContainer.disabled(child: content);
    }
    final title = Text(
      widget.title ?? _title,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: colors.onSurfaceVariant,
        fontWeight: FontWeight.w500,
      ),
    );
    return AnimatedSize(
      duration: duration,
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topLeft,
      child: Material(
        color: _state == _ReasoningState.collapsed
            ? colors.surfaceContainerLow
            : colors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              key: ValueKey('reasoning-toggle-${widget.data['id']}'),
              onTap: _toggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Icon(widget.icon, size: 16, color: colors.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _loading && !reduceMotion
                          ? AnimatedBuilder(
                              animation: _shimmer,
                              builder: (_, child) => ShaderMask(
                                blendMode: BlendMode.srcATop,
                                shaderCallback: (rect) => LinearGradient(
                                  begin: Alignment(-3 + _shimmer.value * 6, 0),
                                  end: Alignment(-1 + _shimmer.value * 6, 0),
                                  colors: [
                                    colors.secondary.withValues(alpha: 0),
                                    colors.surface.withValues(alpha: .65),
                                    colors.secondary.withValues(alpha: 0),
                                  ],
                                ).createShader(rect),
                                child: child,
                              ),
                              child: title,
                            )
                          : title,
                    ),
                    const SizedBox(width: 12),
                    AnimatedRotation(
                      turns: expanded ? .5 : 0,
                      duration: duration,
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        size: 18,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_state != _ReasoningState.collapsed)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: preview
                    ? ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (rect) => const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black,
                            Colors.black,
                            Colors.transparent,
                          ],
                          stops: [0, .15, .85, 1],
                        ).createShader(rect),
                        child: ConstrainedBox(
                          key: ValueKey(
                            'reasoning-preview-${widget.data['id']}',
                          ),
                          constraints: const BoxConstraints(maxHeight: 100),
                          child: SingleChildScrollView(
                            controller: _scroll,
                            child: content,
                          ),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          content,
                          if (!_loading)
                            IconButton(
                              key: ValueKey('copy-${widget.data['id']}'),
                              tooltip: widget.content == null
                                  ? '复制思考内容'
                                  : '复制读取结果',
                              onPressed: widget.onCopy,
                              icon: const Icon(Icons.copy_outlined, size: 18),
                            ),
                        ],
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
