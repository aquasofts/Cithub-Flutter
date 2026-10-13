import 'dart:convert';

import 'package:cithub_flutter/features/news/news_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('academic dates follow each article even with unwrapped table rows', () {
    final articles = parseOfficialList(
      '''<div class="inner">
      <tr><td><a class="c246496" href="../info/1206/1.htm" title="第一条">第一条</a></td>
      <td><span class="timestyle246496">2026-09-04</span></td></tr>
      <tr><td><a class="c246496" href="../info/1206/2.htm" title="第二条">第二条</a></td>
      <td><span class="timestyle246496">2026-08-20</span></td></tr></div>''',
      source: '学术新闻',
      listUrl: 'https://kjc.ccit.edu.cn/sylm/kjxw1.htm',
    );
    expect(articles.map((a) => a.publishedAt), [
      DateTime(2026, 9, 4),
      DateTime(2026, 8, 20),
    ]);
  });
  test(
    'partial official refresh retains articles from unavailable sources',
    () async {
      final old = NewsArticle(
        id: 'old',
        source: '学术新闻',
        title: '缓存新闻',
        link: 'https://kjc.ccit.edu.cn/info/1206/old.htm',
        summary: '缓存正文',
        html: '<p>缓存正文</p>',
        publishedAt: DateTime(2026, 8, 20),
        section: NewsSection.official,
      );
      SharedPreferences.setMockInitialValues({
        'news.cache.v1': jsonEncode([old.toJson()]),
      });
      NewsRepository.resumeRequests();
      final repository = NewsRepository(
        client: MockClient((request) async {
          if (request.url.path.endsWith('xxyw.htm')) {
            return http.Response(
              '<ul class="listimg"><li><a href="../info/1007/1.htm"><h1>New</h1></a></li></ul>',
              200,
            );
          }
          return http.Response('Unavailable', 503);
        }),
      );
      addTearDown(repository.close);
      final articles = await repository.refreshSection(NewsSection.official);
      expect(articles.map((a) => a.id), contains('old'));
      expect(articles.map((a) => a.title), contains('New'));
    },
  );
  test(
    'official refresh reads the live site layout and article body',
    () async {
      SharedPreferences.setMockInitialValues({});
      final requested = <String>[];
      http.Response response(String body) =>
          http.Response.bytes(utf8.encode(body), 200);
      final repository = NewsRepository(
        client: MockClient((request) async {
          requested.add(request.url.toString());
          if (request.url.path.contains('/info/')) {
            return response('<div id="vsb_content"><p>完整新闻正文</p></div>');
          }
          if (request.url.path.contains('kjxw1')) {
            return response('''<table><tr><td><a class="c246496"
          href="../info/1206/3541.htm" title="学术新闻">学术新闻</a></td>
          <td>2026-09-04</td></tr></table>''');
          }
          if (request.url.path.contains('xxgg')) {
            return response(
              '''<ul class="listpage"><li><a href="../info/1008/10989.htm">
              <div class="time"><h3>10.11</h3><h6>2026</h6></div>
              <h1>通知公告</h1></a></li></ul>''',
            );
          }
          return response(
            '''<ul class="listimg"><li><a href="../info/1007/10988.htm">
        <div class="time"><h3>10.10</h3><h6>2026</h6></div>
        <h1>学校新闻</h1><p>摘要</p></a></li></ul>''',
          );
        }),
      );
      final articles = await repository.refreshSection(NewsSection.official);
      expect(articles, hasLength(3));
      expect(requested, hasLength(3));
      final complete = await Future.wait(articles.map(repository.readArticle));
      expect(
        complete.every((article) => article.html.contains('完整新闻正文')),
        isTrue,
      );
      expect(
        requested.where((url) => url.contains('gateway.ccit.edu.cn')),
        isEmpty,
      );
    },
  );
  test('official site list pages provide article links and dates', () {
    final news = parseOfficialList(
      '''
      <ul class="listimg"><li><a href="../info/1007/10988.htm">
      <div class="time"><h3>10.10</h3><h6>2026</h6></div>
      <h1>学校举办活动</h1><p>活动内容</p>
      <img src="/__local/a.jpg"></a></li></ul>
    ''',
      source: '学校新闻',
      listUrl: 'https://www.ccit.edu.cn/index/xxyw.htm',
    );
    expect(news.single.title, '学校举办活动');
    expect(news.single.link, 'https://www.ccit.edu.cn/info/1007/10988.htm');
    expect(news.single.publishedAt, DateTime(2026, 10, 10));
    expect(news.single.coverUrl, 'https://www.ccit.edu.cn/__local/a.jpg');

    final academic = parseOfficialList(
      '''
      <table><tr><td><a class="c246496" href="../info/1206/3541.htm"
      title="科研新闻">科研新闻</a></td><td>2026-09-04</td></tr></table>
    ''',
      source: '学术新闻',
      listUrl: 'https://kjc.ccit.edu.cn/sylm/kjxw1.htm',
    );
    expect(academic.single.link, 'https://kjc.ccit.edu.cn/info/1206/3541.htm');
    expect(academic.single.publishedAt, DateTime(2026, 9, 4));
  });
  test('parses RSS items into typed articles', () {
    final articles = parseFeed(
      utf8.encode('''
        <rss version="2.0"><channel><title>校园新闻</title>
          <item><guid>article-1</guid><title>测试新闻</title>
            <link>https://example.edu/news/1</link>
            <pubDate>Tue, 18 Aug 2026 12:30:00 +0800</pubDate>
            <description><![CDATA[<p>新闻摘要</p><img src="https://example.edu/1.jpg" />]]></description>
          </item>
        </channel></rss>
      '''),
      section: NewsSection.campus,
      sourceUrl: 'https://example.edu/rss.xml',
    );

    expect(articles, hasLength(1));
    expect(articles.single.source, '校园新闻');
    expect(articles.single.title, '测试新闻');
    expect(articles.single.summary, contains('新闻摘要'));
    expect(articles.single.coverUrl, 'https://example.edu/1.jpg');
  });

  test('rejects neither Atom entries nor ISO dates', () {
    final articles = parseFeed(
      utf8.encode('''
        <feed xmlns="http://www.w3.org/2005/Atom"><title>Atom Source</title>
          <entry><id>2</id><title>Atom Article</title>
            <link href="https://example.edu/2"/><updated>2026-08-18T01:00:00Z</updated>
            <content type="html">正文</content>
          </entry>
        </feed>
      '''),
      section: NewsSection.wechat,
      sourceUrl: 'https://example.edu/atom.xml',
    );
    expect(articles.single.link, 'https://example.edu/2');
    expect(articles.single.publishedAt, DateTime.utc(2026, 8, 18, 1));
  });

  test('resolves relative HTTPS media and rejects insecure links', () {
    final articles = parseFeed(
      utf8.encode('''
        <rss version="2.0"><channel><title>安全源</title>
          <item><title>相对图片</title><link>http://unsafe.example/post</link>
            <description><![CDATA[<img src="../images/cover.jpg" />]]></description>
          </item>
        </channel></rss>
      '''),
      section: NewsSection.campus,
      sourceUrl: 'https://example.edu/feeds/news.xml',
    );

    expect(articles.single.link, isEmpty);
    expect(articles.single.coverUrl, 'https://example.edu/images/cover.jpg');
  });

  test(
    'uses the RSS item publisher and removes its duplicated title prefix',
    () {
      final articles = parseFeed(
        utf8.encode('''
        <rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/"><channel>
          <title>校园公众号合集</title>
          <item><title>[学生工作处] 青春逐梦</title>
            <dc:creator>学生工作处</dc:creator>
            <source>长春工程学院</source>
            <link>https://example.edu/post/1</link>
            <description><![CDATA[<p>正文</p>]]></description>
          </item>
        </channel></rss>
      '''),
        section: NewsSection.wechat,
        sourceUrl: 'https://example.edu/rss.xml',
      );

      expect(articles.single.source, '学生工作处');
      expect(articles.single.title, '青春逐梦');
    },
  );

  test('upgrades trusted CCIT and expands VSB image URLs', () {
    final articles = parseFeed(
      utf8.encode('''
        <rss version="2.0"><channel><title>学校新闻</title>
          <item><title>图片测试</title><link>https://www.ccit.edu.cn/info/1.htm</link>
            <description><![CDATA[
              <vsbimg src="/_vsl/0123456789ABCDEF0123456789ABCDEF/1234/5678"></vsbimg>
            ]]></description>
          </item>
        </channel></rss>
      '''),
      section: NewsSection.official,
      sourceUrl: 'https://www.ccit.edu.cn/rss.xml',
    );

    expect(
      articles.single.coverUrl,
      'https://www.ccit.edu.cn/__local/0/12/34/56789ABCDEF0123456789ABCDEF_1234_5678.jpg',
    );
  });
}
