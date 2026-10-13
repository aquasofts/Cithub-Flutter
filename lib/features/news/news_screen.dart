import 'dart:async';

import '../../core/logging/runtime_log.dart';
import '../../core/logging/web_audit.dart';
import '../../core/logging/runtime_audit.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:photo_view/photo_view.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'news_html.dart';
import 'news_repository.dart';

class NewsScreen extends StatefulWidget {
  const NewsScreen({
    super.key,
    this.fixedSection,
    this.repository,
    this.active = true,
  });
  final NewsRepository? repository;
  final bool active;
  final NewsSection? fixedSection;

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen>
    with AutomaticKeepAliveClientMixin {
  late final NewsRepository _repository;
  List<NewsArticle> _articles = [];
  String? _error;
  bool _restoring = true;
  bool _restored = false;
  bool _activated = false;
  NewsSection _selected = NewsSection.wechat;
  bool _refreshing = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? NewsRepository();
    _selected = widget.fixedSection ?? NewsSection.wechat;
    RuntimeLog.event('news-page', 'opened', {'section': _selected.name});
    _restoring = widget.active;
    if (widget.active) _restore();
  }

  @override
  void dispose() {
    RuntimeLog.event('news-page', 'closed', {'section': _selected.name});
    if (widget.repository == null) _repository.close();
    super.dispose();
  }

  Future<void> _restore() async {
    _restored = true;
    try {
      final cached = await RuntimeLog.trace('news-page', 'restore', {
        'section': _selected.name,
      }, () => _repository.cached(includeDemo: false));
      if (!mounted) return;
      setState(() {
        _articles = cached;
        _restoring = false;
      });
      await _activate();
    } catch (error, stack) {
      RuntimeLog.event('news-page', 'restore-failed', {
        'error': '$error',
        'stack': '$stack',
      });
      if (!mounted) return;
      setState(() => _restoring = false);
      if (widget.active) await _refresh();
    }
  }

  @override
  void didUpdateWidget(covariant NewsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      if (_restored) {
        unawaited(_activate());
      } else {
        setState(() => _restoring = true);
        unawaited(_restore());
      }
    }
  }

  Future<void> _activate() async {
    if (!widget.active || _activated || _restoring) return;
    _activated = true;
    final updated = await _repository.cachedAt(_selected);
    if (!mounted || !widget.active) {
      _activated = false;
      return;
    }
    if (updated == null ||
        DateTime.now().difference(updated) > const Duration(minutes: 5) ||
        !_articles.any((a) => a.section == _selected)) {
      await _refresh();
    }
  }

  void _selectSection(NewsSection section) {
    RuntimeLog.event('news-page', 'section-selected', {
      'before': _selected.name,
      'after': section.name,
    });
    setState(() {
      _selected = section;
      _error = null;
    });
    if (!_articles.any((a) => a.section == section)) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_refreshing || !mounted) return;
    final section = _selected;
    if (!NewsRepository.resumeRequests()) {
      RuntimeLog.event('news-page', 'refresh-rate-limited', {
        'section': section.name,
      });
      setState(() => _error = '请求暂时受限，请稍后重试');
      return;
    }
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      final articles = await RuntimeLog.trace('news-page', 'refresh', {
        'section': section.name,
      }, () => _repository.refreshSection(section));
      if (mounted) {
        setState(() {
          _articles = articles;
          _error = _repository.failures.isEmpty ? null : '部分来源暂时不可用，已保留缓存';
        });
      }
    } catch (error, stack) {
      RuntimeLog.event('news-page', 'refresh-failed', {
        'section': section.name,
        'error': '$error',
        'stack': '$stack',
      });
      if (mounted) setState(() => _error = '暂时无法加载，请检查网络后重试');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
    if (mounted &&
        _selected != section &&
        !_articles.any((a) => a.section == _selected)) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final items = _articles.where((item) => item.section == _selected).toList();
    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        key: PageStorageKey('news-${_selected.name}'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            toolbarHeight: 72,
            titleSpacing: 20,
            title: Text(
              widget.fixedSection == null
                  ? '新闻'
                  : ['公众号', '校内新闻', '官方新闻'][_selected.index],
            ),
            actions: [
              if (_refreshing)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                IconButton(
                  onPressed: _refresh,
                  tooltip: '刷新',
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
          if (widget.fixedSection == null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
              sliver: SliverToBoxAdapter(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SectionChip(
                      label: '公众号',
                      selected: _selected == NewsSection.wechat,
                      onSelected: () => _selectSection(NewsSection.wechat),
                    ),
                    _SectionChip(
                      label: '校内新闻',
                      selected: _selected == NewsSection.campus,
                      onSelected: () => _selectSection(NewsSection.campus),
                    ),
                    _SectionChip(
                      label: '官方新闻',
                      selected: _selected == NewsSection.official,
                      onSelected: () => _selectSection(NewsSection.official),
                    ),
                  ],
                ),
              ),
            ),
          if (_error != null && items.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          if (items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_refreshing || _restoring)
                        const CircularProgressIndicator()
                      else
                        Icon(
                          Icons.newspaper_outlined,
                          size: 52,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      const SizedBox(height: 20),
                      Text(
                        _refreshing || _restoring ? '正在加载校园资讯…' : '校园资讯',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error ??
                            (_refreshing || _restoring
                                ? '稍等片刻，最新消息即将呈现'
                                : '暂无新闻，可下拉刷新'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (!_refreshing && !_restoring) ...[
                        const SizedBox(height: 20),
                        FilledButton.tonalIcon(
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh),
                          label: const Text('重新加载'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, index) => _NewsCard(article: items[index]),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionChip extends StatelessWidget {
  const _SectionChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => FilterChip(
    label: Text(label),
    selected: selected,
    showCheckmark: false,
    onSelected: (_) => onSelected(),
  );
}

class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.article});

  final NewsArticle article;

  @override
  Widget build(BuildContext context) {
    final showThumbnail =
        article.section != NewsSection.wechat && article.coverUrl.isNotEmpty;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          LoggedMaterialPageRoute(
            builder: (_) => ArticleScreen(article: article),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.article_outlined,
                    size: 17,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      article.source,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  if (article.publishedAt case final date?)
                    Text(
                      '${date.toLocal().month}-${date.toLocal().day}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
              const SizedBox(height: 9),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          article.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (article.summary.isNotEmpty) ...[
                          const SizedBox(height: 7),
                          Text(
                            article.summary,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (showThumbnail) ...[
                    const SizedBox(width: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CachedNetworkImage(
                        key: const Key('news-thumbnail'),
                        imageUrl: article.coverUrl,
                        width: MediaQuery.sizeOf(context).width < 360 ? 76 : 96,
                        height: MediaQuery.sizeOf(context).width < 360
                            ? 76
                            : 96,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ArticleScreen extends StatefulWidget {
  const ArticleScreen({super.key, required this.article});

  final NewsArticle article;

  @override
  State<ArticleScreen> createState() => _ArticleScreenState();
}

class _ArticleScreenState extends State<ArticleScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _fetching = false;
  String? _loadError;
  late NewsArticle _article;
  final _repository = NewsRepository();
  late final Future<void> _auditReady;
  int? _themeSignature;

  @override
  void initState() {
    super.initState();
    _article = widget.article;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'NewsImage',
        onMessageReceived: (message) {
          final uri = Uri.tryParse(message.message);
          if (!mounted || uri == null || uri.scheme != 'https') return;
          Navigator.of(context).push(
            LoggedMaterialPageRoute(
              builder: (_) => _NewsImageScreen(url: uri.toString()),
            ),
          );
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            RuntimeLog.event('news-webview', 'load-start', {'url': url});
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (url) {
            RuntimeLog.event('news-webview', 'load-finished', {'url': url});
            unawaited(_controller.runJavaScript(webAuditScript));
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) =>
              RuntimeLog.event('news-webview', 'resource-failed', {
                'url': error.url,
                'code': error.errorCode,
                'description': error.description,
              }),
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri?.scheme == 'data' || uri?.scheme == 'about') {
              return NavigationDecision.navigate;
            }
            if (uri != null && uri.scheme == 'https') {
              launchUrl(uri, mode: LaunchMode.externalApplication);
            }
            return NavigationDecision.prevent;
          },
        ),
      );
    _auditReady = configureWebAudit(_controller, 'news-webview');
    RuntimeLog.event('news-webview', 'observability', {
      'article': widget.article.toJson(),
      'network': '正文由 LoggingHttpClient 完整记录；WebView 图片等子资源仅记录 Resource Timing 元数据，不提供请求头或响应体。',
    });
    if (_article.html.isEmpty && _article.link.isNotEmpty) {
      unawaited(_loadArticle());
    }
  }

  @override
  void dispose() {
    _repository.close();
    super.dispose();
  }

  Future<void> _loadArticle() async {
    if (_fetching) return;
    setState(() {
      _fetching = true;
      _loadError = null;
    });
    try {
      final article = await _repository.readArticle(widget.article);
      if (!mounted) return;
      setState(() => _article = article);
      await _render();
    } catch (error, stack) {
      RuntimeLog.event('news-page', 'article-failed', {
        'url': widget.article.link,
        'error': '$error',
        'stack': '$stack',
      });
      if (mounted) setState(() => _loadError = '正文加载失败，可重试或在浏览器打开原文');
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Future<void> _render() async {
    await _auditReady;
    if (!mounted) return;
    final theme = Theme.of(context);
    await _controller.loadHtmlString(
      buildSafeNewsHtml(
        _article,
        backgroundColor: _cssColor(theme.colorScheme.surface),
        textColor: _cssColor(theme.colorScheme.onSurface),
        secondaryTextColor: _cssColor(theme.colorScheme.onSurfaceVariant),
        linkColor: _cssColor(theme.colorScheme.primary),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = Theme.of(context);
    final signature = Object.hash(
      theme.brightness,
      theme.colorScheme.surface,
      theme.colorScheme.onSurface,
      theme.colorScheme.primary,
    );
    if (_themeSignature == signature) return;
    _themeSignature = signature;
    unawaited(_render());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.article.source),
      actions: [
        if (widget.article.link.isNotEmpty)
          IconButton(
            tooltip: '在浏览器打开',
            onPressed: () {
              final uri = Uri.tryParse(widget.article.link);
              if (uri != null && uri.scheme == 'https') {
                launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            icon: const Icon(Icons.open_in_browser),
          ),
      ],
      bottom: _loading || _fetching
          ? const PreferredSize(
              preferredSize: Size.fromHeight(2),
              child: LinearProgressIndicator(minHeight: 2),
            )
          : null,
    ),
    body: Column(
      children: [
        if (_loadError != null)
          Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(child: Text(_loadError!)),
                  TextButton(onPressed: _loadArticle, child: const Text('重试')),
                ],
              ),
            ),
          ),
        Expanded(child: WebViewWidget(controller: _controller)),
      ],
    ),
  );
}

class _NewsImageScreen extends StatelessWidget {
  const _NewsImageScreen({required this.url});

  final String url;

  Future<void> _save(BuildContext context) async {
    final client = LoggingHttpClient(http.Client());
    try {
      final result = await RuntimeLog.trace(
        'news-image',
        'save',
        {'url': url},
        () async {
          final response = await client
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 30));
          if (response.statusCode != 200) {
            throw StateError('HTTP ${response.statusCode}');
          }
          final result = await FilePicker.saveFile(
            dialogTitle: '保存新闻图片',
            fileName:
                'cithub-news-${DateTime.now().millisecondsSinceEpoch}.jpg',
            bytes: response.bodyBytes,
          );
          RuntimeLog.event(
            'news-image',
            result == null ? 'save-cancelled' : 'saved',
            {'url': url, 'path': result},
          );
          return result;
        },
      );
      if (context.mounted && result != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('图片已保存')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('图片保存失败：$error')));
      }
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      foregroundColor: Colors.white,
      backgroundColor: Colors.black,
      actions: [
        IconButton(
          tooltip: '保存图片',
          onPressed: () => _save(context),
          icon: const Icon(Icons.download_outlined),
        ),
      ],
    ),
    body: PhotoView(
      imageProvider: CachedNetworkImageProvider(url),
      backgroundDecoration: const BoxDecoration(color: Colors.black),
    ),
  );
}

String _cssColor(Color color) =>
    '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
