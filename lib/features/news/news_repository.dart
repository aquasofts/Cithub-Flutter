import 'dart:convert';
import 'dart:async';

import '../../core/logging/runtime_log.dart';
import '../../core/utils/request_queue.dart';
import '../../core/utils/rate_limit.dart';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../../core/logging/logged_preferences.dart';

import 'package:xml/xml.dart';

enum NewsSection { wechat, campus, official }

class NewsArticle {
  const NewsArticle({
    required this.id,
    required this.source,
    required this.title,
    required this.link,
    required this.summary,
    required this.html,
    required this.publishedAt,
    required this.section,
    this.coverUrl = '',
  });

  final String id;
  final String source;
  final String title;
  final String link;
  final String summary;
  final String html;
  final DateTime? publishedAt;
  final NewsSection section;
  final String coverUrl;

  Map<String, Object?> toJson() => {
    'id': id,
    'source': source,
    'title': title,
    'link': link,
    'summary': summary,
    'html': html,
    'publishedAt': publishedAt?.toIso8601String(),
    'section': section.name,
    'coverUrl': coverUrl,
  };

  factory NewsArticle.fromJson(Map<String, Object?> json) => NewsArticle(
    id: json['id']! as String,
    source: json['source']! as String,
    title: json['title']! as String,
    link: json['link']! as String,
    summary: json['summary']! as String,
    html: json['html']! as String,
    publishedAt: DateTime.tryParse(json['publishedAt'] as String? ?? ''),
    section: NewsSection.values.byName(json['section']! as String),
    coverUrl: json['coverUrl'] as String? ?? '',
  );
}

class NewsRepository {
  NewsRepository({http.Client? client})
    : _client = LoggingHttpClient(client ?? http.Client());
  final http.Client _client;

  void close() => _client.close();

  static const defaultSources = {
    NewsSection.wechat: [
      'https://cloudflare-rss-hub-pages.pages.dev/api/rss.xml',
    ],
    NewsSection.campus: ['https://cit-news.pages.dev/rss.xml'],
  };

  Future<List<NewsArticle>> cached({bool includeDemo = true}) async {
    final raw = (await LoggedPreferences.getInstance()).getString(
      'news.cache.v1',
    );
    if (raw == null) return includeDemo ? demoNews : [];
    return runCatchingArticles(raw) ?? (includeDemo ? demoNews : []);
  }

  final failures = <String>[];
  static final _aiQueue = RequestQueue(
    interval: Duration.zero,
    cacheTtl: Duration.zero,
  );
  static bool resumeRequests() => _aiQueue.resume();

  Future<DateTime?> cachedAt(NewsSection section) async => DateTime.tryParse(
    (await LoggedPreferences.getInstance()).getString(
          'news.updated.${section.name}',
        ) ??
        '',
  );

  Future<List<NewsArticle>> refresh([
    Map<NewsSection, List<String>>? sources,
  ]) async {
    final prefs = await LoggedPreferences.getInstance();
    return _refresh({
      ...sources ??
          {
            for (final section in [NewsSection.wechat, NewsSection.campus])
              section:
                  prefs.getStringList('rss.${section.name}') ??
                  defaultSources[section]!,
          },
      NewsSection.official: _officialSources.map((s) => s.listUrl).toList(),
    });
  }

  Future<List<NewsArticle>> refreshSection(NewsSection section) async {
    final prefs = await LoggedPreferences.getInstance();
    return _refresh({
      section: section == NewsSection.official
          ? _officialSources.map((s) => s.listUrl).toList()
          : prefs.getStringList('rss.${section.name}') ??
                defaultSources[section]!,
    });
  }

  Future<List<NewsArticle>> _refresh(
    Map<NewsSection, List<String>> sources,
  ) => RuntimeLog.trace(
    'news',
    'refresh',
    {'sources': sources.map((k, v) => MapEntry(k.name, v))},
    () async {
      failures.clear();
      final prefs = await LoggedPreferences.getInstance();
      final old = await cached(includeDemo: false);
      final loaded = <NewsArticle>[];
      final completed = <NewsSection>{};
      final check = Zone.current[requestCancellationKey] as void Function()?;
      for (final entry in sources.entries) {
        var complete = true;
        for (final url in entry.value.map((s) => s.trim()).toSet()) {
          check?.call();
          try {
            final uri = Uri.parse(url);
            if (uri.scheme != 'https' || uri.host.isEmpty) {
              throw StateError('新闻源地址无效：$url');
            }
            loaded.addAll(
              await _aiQueue.run('news:$url', () {
                if (entry.key == NewsSection.official) {
                  final source = _officialSources.firstWhere(
                    (s) => s.listUrl == url,
                  );
                  return _loadOfficial(source);
                }
                return _loadFeed(uri, entry.key);
              }),
            );
          } catch (error, stack) {
            check?.call();
            complete = false;
            failures.add(url);
            RuntimeLog.event('news', 'source-failed', {
              'url': url,
              'error': '$error',
              'stack': '$stack',
            });
          }
        }
        if (complete && entry.value.isNotEmpty) completed.add(entry.key);
      }
      check?.call();
      if (loaded.isEmpty) throw StateError('新闻暂时无法加载，请稍后重试');
      final merged = <String, NewsArticle>{};
      for (final article in [
        ...loaded,
        ...old.where((a) => !completed.contains(a.section)),
      ]) {
        merged.putIfAbsent(
          '${article.section.name}:${article.link.isEmpty ? article.id : article.link}',
          () => article,
        );
      }
      final articles = merged.values.toList()
        ..sort(
          (a, b) => (b.publishedAt ?? DateTime(1970)).compareTo(
            a.publishedAt ?? DateTime(1970),
          ),
        );
      RuntimeLog.event('news', 'cache-change', {
        'before': old.map((a) => a.toJson()).toList(),
        'after': articles.map((a) => a.toJson()).toList(),
        'failedSources': failures,
      });
      await prefs.setString(
        'news.cache.v1',
        jsonEncode(articles.map((a) => a.toJson()).toList()),
      );
      for (final section in completed) {
        await prefs.setString(
          'news.updated.${section.name}',
          DateTime.now().toIso8601String(),
        );
      }
      return articles;
    },
  );

  Future<List<NewsArticle>> _loadFeed(Uri uri, NewsSection section) async {
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 429) {
      throw RequestRateLimited(
        retryAfterDelay(response.headers['retry-after']),
      );
    }
    if (response.statusCode != 200) {
      throw StateError('RSS HTTP ${response.statusCode}');
    }
    return parseFeed(
      response.bodyBytes,
      section: section,
      sourceUrl: uri.toString(),
    );
  }

  Future<List<NewsArticle>> _loadOfficial(_OfficialSource source) async {
    return RuntimeLog.trace('news', 'load-official', {
      'source': source.title,
      'url': source.listUrl,
    }, () => _loadOfficialPage(source));
  }

  Future<List<NewsArticle>> _loadOfficialPage(_OfficialSource source) async {
    final response = await _client
        .get(Uri.parse(source.listUrl))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 429) {
      throw RequestRateLimited(
        retryAfterDelay(response.headers['retry-after']),
      );
    }
    if (response.statusCode != 200) {
      throw StateError('官方新闻 HTTP ${response.statusCode}');
    }
    final listed = parseOfficialList(
      utf8.decode(response.bodyBytes, allowMalformed: true),
      source: source.title,
      listUrl: source.listUrl,
    );
    if (listed.isEmpty) throw StateError('官方新闻列表为空或页面结构已变化');
    return listed;
  }

  Future<NewsArticle> readArticle(
    NewsArticle article,
  ) => RuntimeLog.trace('news', 'read-article', article.toJson(), () async {
    if (article.html.isNotEmpty) return article;
    final uri = Uri.parse(article.link);
    if (uri.scheme != 'https' || uri.host.isEmpty) throw StateError('文章链接无效');
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('正文 HTTP ${response.statusCode}');
    }
    final page = html_parser.parse(
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );
    final body = page.querySelector(
      '#vsb_content, .v_news_content, article, #js_content',
    );
    if (body == null || body.text.trim().isEmpty) {
      throw StateError('正文暂时无法读取，请在浏览器打开原文');
    }
    for (final node in body.querySelectorAll('script,style,nav')) {
      node.remove();
    }
    final summary = body.text.trim();
    return NewsArticle(
      id: article.id,
      source: article.source,
      title: article.title,
      link: article.link,
      summary: summary.length > 160 ? '${summary.substring(0, 160)}…' : summary,
      html: body.innerHtml,
      publishedAt: article.publishedAt,
      section: article.section,
      coverUrl: article.coverUrl.isEmpty
          ? _firstImage(body.innerHtml, baseUrl: article.link)
          : article.coverUrl,
    );
  });
}

class _OfficialSource {
  const _OfficialSource(this.title, this.listUrl);
  final String title;
  final String listUrl;
}

const _officialSources = [
  _OfficialSource('学校新闻', 'https://www.ccit.edu.cn/index/xxyw.htm'),
  _OfficialSource('通知公告', 'https://www.ccit.edu.cn/index/xxgg.htm'),
  _OfficialSource('学术新闻', 'https://kjc.ccit.edu.cn/sylm/kjxw1.htm'),
];

List<NewsArticle> parseOfficialList(
  String markup, {
  required String source,
  required String listUrl,
}) {
  final page = html_parser.parse(markup);
  final base = Uri.parse(listUrl);
  final rows = page.querySelectorAll('.listimg > li, .listpage > li');
  final academic = rows.isEmpty;
  final candidates = academic
      ? page.querySelectorAll('a[href*="info/"]')
      : rows;
  final output = <NewsArticle>[];
  final seen = <String>{};
  for (final row in candidates) {
    final anchor = academic ? row : row.querySelector('a[href]');
    if (anchor == null) continue;
    final link = safeNewsUrl(anchor.attributes['href'] ?? '', baseUrl: base);
    if (link.isEmpty ||
        !Uri.parse(link).path.contains('/info/') ||
        !seen.add(link)) {
      continue;
    }
    final title =
        (academic
                ? anchor.attributes['title'] ?? anchor.text
                : row.querySelector('h1')?.text ??
                      row.querySelector('h2')?.text ??
                      anchor.attributes['title'] ??
                      anchor.text)
            .trim();
    if (title.isEmpty) continue;
    String date = '';
    if (academic) {
      var row = anchor.parent;
      while (row != null && row.localName != 'tr' && row.localName != 'li') {
        row = row.parent;
      }
      if (row != null) {
        date =
            RegExp(r'20\d{2}-\d{1,2}-\d{1,2}').firstMatch(row.text)?.group(0) ??
            '';
      } else {
        // The research site emits tr/td outside a table. HTML parsing removes
        // those wrappers, so associate a date only with this anchor's siblings.
        var sibling = anchor.nextElementSibling;
        while (sibling != null) {
          if (sibling.localName == 'a' ||
              sibling.querySelector('a[href*="info/"]') != null) {
            break;
          }
          final text = sibling.text;
          final match = RegExp(r'20\d{2}-\d{1,2}-\d{1,2}').firstMatch(text);
          if (match != null) {
            date = match.group(0)!;
            break;
          }
          sibling = sibling.nextElementSibling;
        }
      }
    } else {
      final year = row.querySelector('.time h6')?.text.trim() ?? '';
      final monthDay = row.querySelector('.time h3')?.text.trim() ?? '';
      date = '$year-${monthDay.replaceAll('.', '-')}';
    }
    final excerpt = row.querySelector('p')?.text.trim() ?? '';
    final cover = row.querySelector('img')?.attributes['src'] ?? '';
    output.add(
      NewsArticle(
        id: link,
        source: source,
        title: title,
        link: link,
        summary: excerpt,
        html: '',
        publishedAt: DateTime.tryParse(date),
        section: NewsSection.official,
        coverUrl: safeNewsUrl(cover, baseUrl: base),
      ),
    );
    if (output.length >= 10) break;
  }
  return output;
}

List<NewsArticle> parseFeed(
  List<int> bytes, {
  required NewsSection section,
  required String sourceUrl,
}) {
  final xml = XmlDocument.parse(utf8.decode(bytes, allowMalformed: true));
  final channelTitle =
      _firstText(xml, const ['channel', 'title']) ?? Uri.parse(sourceUrl).host;
  final entries = <XmlElement>[
    ...xml.findAllElements('item'),
    ...xml.findAllElements('entry'),
  ];
  return entries.map((entry) {
    String field(List<String> names) {
      for (final name in names) {
        final element = entry.children
            .whereType<XmlElement>()
            .where(
              (candidate) =>
                  candidate.name.qualified == name ||
                  candidate.name.local == name.split(':').last,
            )
            .firstOrNull;
        if (element != null && element.innerText.trim().isNotEmpty) {
          return element.innerText.trim();
        }
      }
      return '';
    }

    final sourceUri = Uri.parse(sourceUrl);
    var link = field(const ['link']);
    final atomLink = entry
        .findElements('link')
        .firstOrNull
        ?.getAttribute('href');
    if (atomLink != null && atomLink.isNotEmpty) link = atomLink;
    link = safeNewsUrl(link, baseUrl: sourceUri);
    final html = field(const [
      'content:encoded',
      'content',
      'description',
      'summary',
    ]);
    final summary = html_parser.parseFragment(html).text?.trim() ?? '';
    final rawTitle = field(const ['title']);
    final source = field(const ['dc:creator']).isNotEmpty
        ? field(const ['dc:creator'])
        : field(const ['source']).isNotEmpty
        ? field(const ['source'])
        : _leadingTitleSource(rawTitle).isNotEmpty
        ? _leadingTitleSource(rawTitle)
        : channelTitle;
    final title = _stripDuplicatedSource(rawTitle, source);
    final guid = field(const ['guid', 'id']);
    final date = field(const ['pubDate', 'published', 'updated', 'dc:date']);
    return NewsArticle(
      id: guid.isEmpty ? '$sourceUrl#$title' : guid,
      source: source,
      title: title.isEmpty ? '无标题' : title,
      link: link,
      summary: summary,
      html: html,
      publishedAt: DateTime.tryParse(date) ?? _parseRfcDate(date),
      section: section,
      coverUrl: _firstImage(html, baseUrl: link.isEmpty ? sourceUrl : link),
    );
  }).toList();
}

String? _firstText(XmlNode root, List<String> path) {
  Iterable<XmlElement> nodes = root is XmlDocument
      ? root.children.whereType<XmlElement>()
      : [root as XmlElement];
  for (final name in path) {
    nodes = nodes.expand((node) => node.findAllElements(name));
  }
  return nodes.firstOrNull?.innerText.trim();
}

DateTime? _parseRfcDate(String value) {
  final match = RegExp(
    r'^(?:\w{3},\s*)?(\d{1,2})\s+(\w{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})',
  ).firstMatch(value);
  if (match == null) return null;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return DateTime.utc(
    int.parse(match[3]!),
    months.indexOf(match[2]!) + 1,
    int.parse(match[1]!),
    int.parse(match[4]!),
    int.parse(match[5]!),
    int.parse(match[6]!),
  );
}

String _firstImage(String markup, {required Object baseUrl}) {
  final image = html_parser.parseFragment(markup).querySelector('img,vsbimg');
  if (image == null) return '';
  final raw =
      image.attributes['src'] ??
      image.attributes['data-src'] ??
      image.attributes['orisrc'] ??
      '';
  return safeNewsUrl(raw, baseUrl: baseUrl);
}

String safeNewsUrl(String raw, {required Object? baseUrl}) {
  final value = raw.trim();
  if (value.isEmpty) return '';
  final base = baseUrl is Uri
      ? baseUrl
      : Uri.tryParse(baseUrl?.toString() ?? '');
  final expanded = _expandVsbImagePath(value);
  final parsed = Uri.tryParse(expanded);
  if (parsed == null) return '';
  final resolved = parsed.hasScheme ? parsed : base?.resolveUri(parsed);
  if (resolved == null) return '';
  if (resolved.host.isEmpty) return '';
  if (resolved.scheme == 'https') return resolved.toString();
  if (resolved.scheme == 'http' && _isTrustedCcitHost(resolved.host)) {
    return resolved.replace(scheme: 'https').toString();
  }
  return '';
}

String _expandVsbImagePath(String value) {
  final match = RegExp(r'^(/_vsl/)([0-9a-fA-F]{32})/([^/?#]+)/([^/?#]+)')
      .firstMatch(value);
  if (match == null) return value;
  final hash = match.group(2)!;
  return '/__local/${hash.substring(0, 1)}/${hash.substring(1, 3)}/'
      '${hash.substring(3, 5)}/${hash.substring(5)}_${match.group(3)}_'
      '${match.group(4)}.jpg';
}

bool _isTrustedCcitHost(String host) {
  final normalized = host.toLowerCase();
  return normalized == 'ccit.edu.cn' || normalized.endsWith('.ccit.edu.cn');
}

String _leadingTitleSource(String title) =>
    RegExp(r'^[\[【]([^\]】]+)[\]】]\s*').firstMatch(title)?.group(1)?.trim() ??
    '';

String _stripDuplicatedSource(String title, String source) {
  final match = RegExp(r'^[\[【]([^\]】]+)[\]】]\s*').firstMatch(title);
  if (match == null || match.group(1)?.trim() != source.trim()) return title;
  return title.substring(match.end).trim();
}

List<NewsArticle>? runCatchingArticles(String raw) {
  try {
    return (jsonDecode(raw) as List<Object?>)
        .map((item) => NewsArticle.fromJson(item! as Map<String, Object?>))
        .toList();
  } catch (_) {
    return null;
  }
}

final demoNews = <NewsArticle>[
  NewsArticle(
    id: 'welcome',
    source: 'Cithub Flutter',
    title: '欢迎使用 Cithub Flutter',
    link: '',
    summary: '新闻、公众号与校内资讯会在这里合并展示，支持缓存和下拉刷新。',
    html: '<p>新闻、公众号与校内资讯会在这里合并展示，支持缓存和下拉刷新。</p>',
    publishedAt: DateTime(2026, 8, 18),
    section: NewsSection.official,
  ),
];
