import 'dart:convert';

import 'package:cithub_flutter/features/news/news_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
