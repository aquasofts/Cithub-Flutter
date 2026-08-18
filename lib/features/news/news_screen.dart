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
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen>
    with AutomaticKeepAliveClientMixin {
  final _repository = NewsRepository();
  List<NewsArticle> _articles = demoNews;
  NewsSection _selected = NewsSection.wechat;
  bool _refreshing = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final cached = await _repository.cached();
    if (mounted) setState(() => _articles = cached);
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final articles = await _repository.refresh();
      if (mounted) setState(() => _articles = articles);
    } finally {
      if (mounted) setState(() => _refreshing = false);
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
            title: const Text('新闻'),
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
                    onSelected: () =>
                        setState(() => _selected = NewsSection.wechat),
                  ),
                  _SectionChip(
                    label: '校内新闻',
                    selected: _selected == NewsSection.campus,
                    onSelected: () =>
                        setState(() => _selected = NewsSection.campus),
                  ),
                  _SectionChip(
                    label: '官方新闻',
                    selected: _selected == NewsSection.official,
                    onSelected: () =>
                        setState(() => _selected = NewsSection.official),
                  ),
                ],
              ),
            ),
          ),
          if (items.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('暂无内容，下拉刷新')),
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
          MaterialPageRoute(builder: (_) => ArticleScreen(article: article)),
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
                          maxLines: 2,
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
                        width: 104,
                        height: 104,
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
  int? _themeSignature;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'NewsImage',
        onMessageReceived: (message) {
          final uri = Uri.tryParse(message.message);
          if (!mounted || uri == null || uri.scheme != 'https') return;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _NewsImageScreen(url: uri.toString()),
            ),
          );
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
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
    _controller.loadHtmlString(
      buildSafeNewsHtml(
        widget.article,
        backgroundColor: _cssColor(theme.colorScheme.surface),
        textColor: _cssColor(theme.colorScheme.onSurface),
        secondaryTextColor: _cssColor(theme.colorScheme.onSurfaceVariant),
        linkColor: _cssColor(theme.colorScheme.primary),
      ),
    );
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
      bottom: _loading
          ? const PreferredSize(
              preferredSize: Size.fromHeight(2),
              child: LinearProgressIndicator(minHeight: 2),
            )
          : null,
    ),
    body: WebViewWidget(controller: _controller),
  );
}

class _NewsImageScreen extends StatelessWidget {
  const _NewsImageScreen({required this.url});

  final String url;

  Future<void> _save(BuildContext context) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw StateError('HTTP ${response.statusCode}');
      }
      final result = await FilePicker.saveFile(
        dialogTitle: '保存新闻图片',
        fileName: 'cithub-news-${DateTime.now().millisecondsSinceEpoch}.jpg',
        bytes: response.bodyBytes,
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
