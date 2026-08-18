import 'package:cithub_flutter/features/news/news_html.dart';
import 'package:cithub_flutter/features/news/news_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('safe article HTML keeps text and images in DOM order', () {
    const article = NewsArticle(
      id: '1',
      source: '校园新闻',
      title: '测试文章',
      link: 'https://example.edu/news/1',
      summary: '摘要',
      html: '''
        <p>第一段</p>
        <img src="/images/a.jpg" onerror="alert(1)">
        <p>第二段</p>
      ''',
      publishedAt: null,
      section: NewsSection.campus,
    );

    final html = buildSafeNewsHtml(article);
    expect(html.indexOf('第一段'), lessThan(html.indexOf('/images/a.jpg')));
    expect(html.indexOf('/images/a.jpg'), lessThan(html.indexOf('第二段')));
    expect(html, contains('https://example.edu/images/a.jpg'));
    expect(html, contains('max-width: 100%'));
    expect(html, isNot(contains('onerror')));
    expect(html, isNot(contains('alert(1)')));
  });

  test('safe article HTML removes active content and insecure resources', () {
    const article = NewsArticle(
      id: '2',
      source: '通知公告',
      title: '安全测试',
      link: 'https://example.edu/news/2',
      summary: '',
      html: '''
        <script>stealCookies()</script>
        <form action="https://attacker.test"><input name="password"></form>
        <img src="http://unsafe.test/image.jpg">
        <a href="http://unsafe.test">不安全链接</a>
      ''',
      publishedAt: null,
      section: NewsSection.official,
    );

    final html = buildSafeNewsHtml(article);
    expect(html, isNot(contains('stealCookies')));
    expect(html, isNot(contains('<form')));
    expect(html, isNot(contains('<input')));
    expect(html, isNot(contains('http://unsafe.test')));
    expect(html, contains('不安全链接'));
  });

  test('safe article HTML removes empty spacer blocks from feed markup', () {
    const article = NewsArticle(
      id: '3',
      source: '校园公众号',
      title: '间距测试',
      link: 'https://example.edu/news/3',
      summary: '',
      html: '''
        <section><p><br></p><section>&nbsp;</section></section>
        <p>第一段</p>
        <section><br></section>
        <p>第二段</p>
      ''',
      publishedAt: null,
      section: NewsSection.wechat,
    );

    final html = buildSafeNewsHtml(article);
    expect(html, isNot(contains('<p><br></p>')));
    expect(html, isNot(contains('<section><br></section>')));
    expect(html, isNot(contains('&nbsp;')));
    expect(html.indexOf('第一段'), lessThan(html.indexOf('第二段')));
  });

  test(
    'safe article HTML keeps safe WeChat layout and lazy image attributes',
    () {
      const article = NewsArticle(
        id: '4',
        source: '学生工作处',
        title: '公众号排版测试',
        link: 'https://mp.weixin.qq.com/s/example',
        summary: '',
        html: '''
        <section style="display:flex;width:677px;margin:0 auto;position:fixed;background-image:url(https://unsafe.test/a.png)">
          <img data-src="https://mmbiz.qpic.cn/example.jpg" onload="steal()">
        </section>
      ''',
        publishedAt: null,
        section: NewsSection.wechat,
      );

      final html = buildSafeNewsHtml(article);
      expect(html, contains('display: flex'));
      expect(html, contains('width: 677px'));
      expect(html, contains('https://mmbiz.qpic.cn/example.jpg'));
      expect(html, isNot(contains('position: fixed')));
      expect(html, isNot(contains('background-image')));
      expect(html, isNot(contains('steal()')));
    },
  );

  test('safe article HTML upgrades only trusted CCIT HTTP images', () {
    const article = NewsArticle(
      id: '5',
      source: '学校新闻',
      title: '官方图片测试',
      link: 'https://www.ccit.edu.cn/info/1.htm',
      summary: '',
      html: '''
        <img src="http://www.ccit.edu.cn/__local/a.jpg">
        <img src="http://unsafe.test/a.jpg">
      ''',
      publishedAt: null,
      section: NewsSection.official,
    );

    final html = buildSafeNewsHtml(article);
    expect(html, contains('https://www.ccit.edu.cn/__local/a.jpg'));
    expect(html, isNot(contains('http://unsafe.test')));
  });
}
