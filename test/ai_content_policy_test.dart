import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cithub_flutter/core/logging/runtime_log.dart';
import 'package:cithub_flutter/features/ai/campus_content.dart';
import 'package:cithub_flutter/features/news/news_repository.dart';
import 'package:cithub_flutter/features/ai/ai_attachments.dart';
import 'package:cithub_flutter/features/ai/ai_client.dart';
import 'package:cithub_flutter/core/platform/demo_cithub_platform.dart';
import 'package:cithub_flutter/core/utils/request_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cithub_flutter/core/native/cithub_api.g.dart';

class ManyPosts extends DemoCithubPlatform {
  int bodies = 0;
  @override
  Future<ForumPageDto> loadForum(
    String name, {
    int page = 1,
    String sort = 'reply',
    bool goodOnly = false,
  }) async {
    expect(sort, 'post');
    final template = await super.loadForum(name);
    return ForumPageDto(
      forum: template.forum,
      page: page,
      hasMore: page < 4,
      threads: List.generate(20, (i) {
        final thread = ForumThreadDto.decode(template.threads.last.encode());
        thread.id = '${(page - 1) * 20 + i}';
        thread.title = '帖子${thread.id}';
        thread.isTop = false;
        return thread;
      }),
    );
  }

  @override
  Future<ThreadPageDto> loadThread(
    String threadId,
    int forumId,
    String forumName, {
    int page = 1,
    String sort = 'asc',
    bool onlyOriginalPoster = false,
  }) {
    bodies++;
    return super.loadThread(
      threadId,
      forumId,
      forumName,
      page: page,
      sort: sort,
      onlyOriginalPoster: onlyOriginalPoster,
    );
  }
}

const fixtureImageUrl = 'https://tiebapic.baidu.com/original.jpg';

class ImagePosts extends DemoCithubPlatform {
  @override
  Future<ThreadPageDto> loadThread(
    String threadId,
    int forumId,
    String forumName, {
    int page = 1,
    String sort = 'asc',
    bool onlyOriginalPoster = false,
  }) async {
    final result = await super.loadThread(
      threadId,
      forumId,
      forumName,
      page: page,
      sort: sort,
      onlyOriginalPoster: onlyOriginalPoster,
    );
    result.body!.content.add(
      TiebaContentDto(
        kind: 'image',
        text: '',
        emoticonId: '',
        url: fixtureImageUrl,
        originalUrl: fixtureImageUrl,
        width: 800,
        height: 600,
      ),
    );
    return result;
  }
}

class LimitedNews extends NewsRepository {
  LimitedNews({this.fail = false})
    : super(client: MockClient((_) async => http.Response('', 200)));
  final bool fail;
  List<NewsArticle> get articles => [
    NewsArticle(
      id: 'only-news',
      source: '教育部',
      title: '大赛通知',
      link: 'https://example.test/news',
      summary: '通知',
      html: '<p>完整通知</p>',
      publishedAt: DateTime(2026, 10, 13),
      section: NewsSection.official,
    ),
  ];
  @override
  Future<List<NewsArticle>> cached({bool includeDemo = true}) async => articles;
  @override
  Future<DateTime?> cachedAt(NewsSection section) async =>
      fail ? null : DateTime.now();
  @override
  Future<List<NewsArticle>> refreshSection(NewsSection section) async {
    failures.add('https://example.test/failed-source');
    return articles;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final logs = <String>[];
  setUp(() {
    logs.clear();
    const channel = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.cithub_flutter.RuntimeLogHostApi.append',
      StandardMessageCodec(),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(channel, (value) async {
          logs.add((value! as List)[1] as String);
          return [true];
        });
  });
  Future<CampusContentReader> imageReader(
    http.Client client,
    AiCancellation cancellation,
  ) async {
    final reader = CampusContentReader(
      platform: ImagePosts(),
      prompt: '读取贴吧图片',
      forum: '学校',
      cancellation: cancellation,
      clientFactory: () => client,
    );
    await reader.latest('tieba', 1);
    return reader;
  }

  test(
    'admitted Tieba image is returned with full bytes and chunk logs',
    () async {
      final reader = await imageReader(
        MockClient(
          (_) async => http.Response.bytes(
            [255, 216, 255, 0],
            200,
            headers: {'content-type': 'image/jpeg'},
          ),
        ),
        AiCancellation(),
      );
      final result = await reader.image(fixtureImageUrl);
      expect(
        result['image'],
        'data:image/jpeg;base64,${base64Encode([255, 216, 255, 0])}',
      );
      await RuntimeLog.flush();
      expect(
        logs.any((s) => s.contains('CHUNK') && s.contains('/9j/AA==')),
        isTrue,
      );
    },
  );
  test('cancelling an idle image stream stops immediately and cancels subscription', () async {
    final cancellation = AiCancellation();
    final listening = Completer<void>();
    var stopped = false;
    final stream = StreamController<List<int>>(
      onListen: () => listening.complete(),
      onCancel: () {
        stopped = true;
      },
    );
    final reader = await imageReader(
      MockClient.streaming((request, body) async {
        await body.drain<void>();
        return http.StreamedResponse(
          stream.stream,
          200,
          headers: {'content-type': 'image/jpeg'},
        );
      }),
      cancellation,
    );
    final task = reader.image(fixtureImageUrl);
    final check = expectLater(task, throwsA(isA<AiCancelled>()));
    await listening.future;
    cancellation.cancel();
    await check;
    expect(stopped, isTrue);
    await stream.close();
    await RuntimeLog.flush();
    expect(
      logs.any(
        (s) => s.contains('STREAM END') && s.contains('completed=false'),
      ),
      isTrue,
    );
  });
  test('oversized image is refused before buffering its body', () async {
    var listened = false;
    final stream = StreamController<List<int>>(
      onListen: () {
        listened = true;
      },
    );
    final reader = await imageReader(
      MockClient.streaming((request, body) async {
        await body.drain<void>();
        return http.StreamedResponse(
          stream.stream,
          200,
          contentLength: 20 * 1024 * 1024 + 1,
          headers: {'content-type': 'image/jpeg'},
        );
      }),
      AiCancellation(),
    );
    await expectLater(reader.image(fixtureImageUrl), throwsStateError);
    expect(listened, isFalse);
  });
  test('Tieba images are listed and unknown image reads are refused', () async {
    final urls = tiebaImageUrls([
      TiebaContentDto(
        kind: 'image',
        text: '',
        emoticonId: '',
        url: 'https://tiebapic.baidu.com/preview.jpg',
        originalUrl: 'https://tiebapic.baidu.com/original.jpg',
        width: 800,
        height: 600,
      ),
    ]);
    expect(urls, ['https://tiebapic.baidu.com/original.jpg']);
    final reader = CampusContentReader(
      platform: DemoCithubPlatform(),
      prompt: '查看图片',
      forum: '学校',
      cancellation: AiCancellation(),
    );
    await expectLater(reader.image(urls.single), throwsStateError);
  });
  test(
    'repeated tool calls cannot enlarge the default ten or exceed fifty',
    () async {
      final platform = ManyPosts();
      final reader = CampusContentReader(
        platform: platform,
        prompt: '总结最新帖子',
        forum: '学校',
        cancellation: AiCancellation(),
      );
      expect((await reader.latest('tieba', 50))['actual'], 10);
      expect((await reader.latest('tieba', 50))['actual'], 10);
      expect(platform.bodies, 10);
      final expandedPlatform = ManyPosts();
      final expanded = CampusContentReader(
        platform: expandedPlatform,
        prompt: '读取最近100条帖子',
        forum: '学校',
        cancellation: AiCancellation(),
      );
      expect((await expanded.latest('tieba', 100))['actual'], 50);
      expect(expandedPlatform.bodies, 50);
      expect(requestedLimit('再多看一些帖子', 'tieba'), 50);
    },
  );
  test('a model count of one cannot reduce the default ten posts', () async {
    final platform = ManyPosts();
    final reader = CampusContentReader(
      platform: platform,
      prompt: '整理最新校园资讯',
      forum: '学校',
      cancellation: AiCancellation(),
    );
    final result = await reader.latest('tieba', 1);
    expect(result['actual'], 10);
    expect(platform.bodies, 10);
  });
  test('an explicit single post request stays single', () async {
    final reader = CampusContentReader(
      platform: ManyPosts(),
      prompt: '只读最新一条帖子',
      forum: '学校',
      cancellation: AiCancellation(),
    );
    expect((await reader.latest('tieba', 10))['actual'], 1);
  });
  for (final failure in [false, true]) {
    test(
      'one available news item reports target and partial failure ($failure)',
      () async {
        final news = LimitedNews(fail: failure);
        addTearDown(news.close);
        final reader = CampusContentReader(
          platform: DemoCithubPlatform(),
          prompt: '整理最新校园资讯',
          forum: '学校',
          cancellation: AiCancellation(),
          news: news,
        );
        final result = await reader.latest('official', 1);
        expect(result['actual'], 1);
        expect(result['requested'], 10);
        expect(result['partial'], failure);
        expect(result['message'], contains(failure ? '新闻源未能加载' : '1/10'));
      },
    );
  }
  test('each source defaults to ten; explicit quantities clamp at fifty', () {
    for (final source in ['tieba', 'wechat', 'campus', 'official']) {
      expect(requestedLimit('总结学校最近的消息', source), 10);
    }
    expect(requestedLimit('最近50条贴吧帖子', 'tieba'), 50);
    expect(requestedLimit('公众号20篇，贴吧10条', 'wechat'), 20);
    expect(requestedLimit('公众号20篇，贴吧10条', 'tieba'), 10);
    expect(requestedLimit('读取100条', 'official'), 50);
  });
  test('comments require intent and known thread', () async {
    final reader = CampusContentReader(
      platform: DemoCithubPlatform(),
      prompt: '最新帖子',
      forum: '学校',
      cancellation: AiCancellation(),
    );
    await expectLater(reader.comments('1', 50), throwsStateError);
  });
  test('attachments split without dropping text', () {
    final text = '课程' * 15000;
    final blocks = textBlocks(text, 'sheet');
    expect(blocks.map((b) => b['text']).join(), text);
    expect(blocks.length, 3);
  });
  test(
    'queue serializes, deduplicates, caches and pauses at challenges',
    () async {
      final queue = RequestQueue(
        interval: Duration.zero,
        rateLimitWait: Duration.zero,
      );
      var calls = 0;
      Future<int> fetch() async {
        calls++;
        return 1;
      }

      expect(
        await Future.wait([queue.run('a', fetch), queue.run('a', fetch)]),
        [1, 1],
      );
      expect(await queue.run('a', fetch), 1);
      expect(calls, 1);
      await expectLater(
        queue.run('bad', () async => throw StateError('429 captcha')),
        throwsStateError,
      );
      expect(queue.paused, true);
      await expectLater(queue.run('b', fetch), throwsStateError);
      queue.resume();
      expect(await queue.run('b', fetch), 1);
    },
  );
}
