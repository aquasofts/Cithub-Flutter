import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
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
  NewsRepository({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const defaultSources = {
    NewsSection.wechat: [
      'https://cloudflare-rss-hub-pages.pages.dev/api/rss.xml',
    ],
    NewsSection.campus: ['https://cit-news.pages.dev/rss.xml'],
  };

  Future<List<NewsArticle>> cached() async {
    final raw = (await SharedPreferences.getInstance()).getString(
      'news.cache.v1',
    );
    if (raw == null) return demoNews;
    return runCatchingArticles(raw) ?? demoNews;
  }

  Future<List<NewsArticle>> refresh([
    Map<NewsSection, List<String>>? sources,
  ]) async {
    final preferences = await SharedPreferences.getInstance();
    final selected =
        sources ??
        {
          NewsSection.wechat:
              preferences.getStringList('rss.wechat') ??
              defaultSources[NewsSection.wechat]!,
          NewsSection.campus:
              preferences.getStringList('rss.campus') ??
              defaultSources[NewsSection.campus]!,
        };
    final tasks = <Future<List<NewsArticle>>>[];
    for (final entry in selected.entries) {
      for (final url in entry.value.map((item) => item.trim()).toSet()) {
        if (Uri.tryParse(url) case final uri?
            when uri.scheme == 'https' && uri.host.isNotEmpty) {
          tasks.add(_loadFeed(uri, entry.key));
        }
      }
    }
    for (final source in _officialSources) {
      tasks.add(_loadOfficial(source));
    }
    final results = await Future.wait(
      tasks.map((task) async {
        try {
          return await task;
        } catch (_) {
          return <NewsArticle>[];
        }
      }),
    );
    final loaded = results.expand((items) => items).toList();
    if (loaded.isEmpty) {
      final stale = preferences.getString('news.cache.v1');
      return stale == null
          ? demoNews
          : (runCatchingArticles(stale) ?? demoNews);
    }
    final merged = <String, NewsArticle>{};
    for (final article in loaded) {
      final key = article.section == NewsSection.official
          ? article.id
          : (article.link.isEmpty ? article.id : article.link);
      merged.putIfAbsent(key, () => article);
    }
    final articles = merged.values.toList()
      ..sort(
        (a, b) => (b.publishedAt ?? DateTime(1970)).compareTo(
          a.publishedAt ?? DateTime(1970),
        ),
      );
    await (await SharedPreferences.getInstance()).setString(
      'news.cache.v1',
      jsonEncode(articles.map((item) => item.toJson()).toList()),
    );
    return articles;
  }

  Future<List<NewsArticle>> _loadFeed(Uri uri, NewsSection section) async {
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 10));
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
    final envelope =
        '''
      <soapenv:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:web="http://webservice.vsb.webber">
        <soapenv:Header/><soapenv:Body><web:getListByContentId soapenv:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <owner xsi:type="xsd:string">${source.ownerId}</owner>
          <contentid xsi:type="xsd:string">${source.contentId}</contentid>
          <start xsi:type="xsd:int">0</start><count xsi:type="xsd:int">100</count>
        </web:getListByContentId></soapenv:Body>
      </soapenv:Envelope>
    ''';
    final response = await _client
        .post(
          Uri.parse('https://gateway.ccit.edu.cn/ccit/news/getList'),
          headers: const {
            'Accept': 'text/xml, application/xml;q=0.9',
            'Content-Type': 'text/xml; charset=utf-8',
            'User-Agent': 'Cithub Official News Reader',
          },
          body: envelope,
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('官方新闻 HTTP ${response.statusCode}');
    }
    final document = XmlDocument.parse(utf8.decode(response.bodyBytes));
    final payload = document.descendants
        .whereType<XmlElement>()
        .firstWhere(
          (element) =>
              element.name.local.toLowerCase() == 'getlistbycontentidreturn',
        )
        .innerText;
    final decoded = jsonDecode(payload) as List<Object?>;
    return decoded.map((raw) {
      final item = raw! as Map<String, Object?>;
      final markup = item['content']?.toString() ?? '';
      final summary = html_parser.parseFragment(markup).text?.trim() ?? '';
      final rawTitle = item['title']?.toString().trim() ?? '';
      return NewsArticle(
        id: '${source.ownerId}:${item['id']}',
        source: source.title,
        title: rawTitle.isEmpty ? '无标题' : rawTitle,
        link: source.baseUrl,
        summary: summary.length > 160
            ? '${summary.substring(0, 160)}…'
            : summary,
        html: markup,
        publishedAt: DateTime.tryParse(item['date']?.toString() ?? ''),
        section: NewsSection.official,
        coverUrl: _firstImage(markup, baseUrl: source.baseUrl),
      );
    }).toList();
  }
}

class _OfficialSource {
  const _OfficialSource(this.title, this.ownerId, this.contentId, this.baseUrl);
  final String title;
  final String ownerId;
  final String contentId;
  final String baseUrl;
}

const _officialSources = [
  _OfficialSource('学校新闻', '2144790275', '1074518', 'https://www.ccit.edu.cn/'),
  _OfficialSource('通知公告', '2144790275', '1074519', 'https://www.ccit.edu.cn/'),
  _OfficialSource('学术新闻', '1913672758', '1073128', 'https://kjc.ccit.edu.cn/'),
];

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
        final element = entry.findElements(name).firstOrNull;
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
    link = _safeHttpsUrl(link, baseUrl: sourceUri);
    final html = field(const [
      'content:encoded',
      'content',
      'description',
      'summary',
    ]);
    final summary = html_parser.parseFragment(html).text?.trim() ?? '';
    final title = field(const ['title']);
    final guid = field(const ['guid', 'id']);
    final date = field(const ['pubDate', 'published', 'updated', 'dc:date']);
    return NewsArticle(
      id: guid.isEmpty ? '$sourceUrl#$title' : guid,
      source: channelTitle,
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
  final raw = html_parser
      .parseFragment(markup)
      .querySelector('img')
      ?.attributes['src'];
  return _safeHttpsUrl(raw ?? '', baseUrl: baseUrl);
}

String _safeHttpsUrl(String raw, {required Object baseUrl}) {
  final value = raw.trim();
  if (value.isEmpty) return '';
  final base = baseUrl is Uri ? baseUrl : Uri.tryParse(baseUrl.toString());
  final parsed = Uri.tryParse(value);
  if (base == null || parsed == null) return '';
  final resolved = parsed.hasScheme ? parsed : base.resolveUri(parsed);
  return resolved.scheme == 'https' && resolved.host.isNotEmpty
      ? resolved.toString()
      : '';
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
