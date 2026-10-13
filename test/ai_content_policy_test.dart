import 'package:cithub_flutter/features/ai/campus_content.dart';
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

void main() {
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
