import '../../core/logging/runtime_log.dart';

import 'dart:convert';
import 'dart:async';

import '../../core/utils/request_queue.dart';
import '../../core/utils/text_chunks.dart';

import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

import '../../core/platform/cithub_platform.dart';
import '../../core/settings/app_settings.dart';
import '../news/news_repository.dart';
import 'ai_client.dart';

int requestedLimit(String prompt, String source) {
  final label =
      {
        'tieba': '贴吧|帖子',
        'wechat': '公众号',
        'campus': '校内新闻|校园新闻',
        'official': '官方新闻',
      }[source] ??
      '评论|回复|讨论';
  final specific = RegExp(
    '(?:$label)[^，。；\\n]{0,16}?(\\d+|五十|四十|三十|二十|十五|十|九|八|七|六|五|四|三|二|两|一)\\s*(?:条|篇|个|帖)',
  ).firstMatch(prompt);
  final general = RegExp(
    r'(?:最近|最新|前|近|读取|读|看|获取|整理|总结|只要|仅要)\s*(\d+|五十|四十|三十|二十|十五|十|九|八|七|六|五|四|三|二|两|一)\s*(?:条|篇|个|帖)',
  ).firstMatch(prompt);
  final raw = specific?[1] ?? general?[1];
  if (raw == null &&
      RegExp(r'更多|多(?:读|看|取|加载)|全部|所有|尽量多|扩大范围').hasMatch(prompt) &&
      !RegExp(r'不要[^，。；\n]{0,12}(?:更多|全部|所有)').hasMatch(prompt)) {
    return 50;
  }
  final value =
      int.tryParse(raw ?? '') ??
      {
        '五十': 50,
        '四十': 40,
        '三十': 30,
        '二十': 20,
        '十五': 15,
        '十': 10,
        '九': 9,
        '八': 8,
        '七': 7,
        '六': 6,
        '五': 5,
        '四': 4,
        '三': 3,
        '二': 2,
        '两': 2,
        '一': 1,
      }[raw] ??
      10;
  return value.clamp(1, 50);
}

String tiebaText(List<dynamic> content) => content
    .map(
      (c) => c.text.isNotEmpty
          ? c.text
          : c.kind == 'image'
          ? '[图片：${c.url}]'
          : c.url.isNotEmpty
          ? c.url
          : '',
    )
    .join('\n');

List<String> tiebaImageUrls(List<dynamic> content) => content
    .where((item) => item.kind == 'image')
    .map(
      (item) => (item.originalUrl as String).isNotEmpty
          ? item.originalUrl as String
          : item.url as String,
    )
    .where((url) => url.isNotEmpty)
    .toList();

class CampusContentReader {
  CampusContentReader({
    required this.platform,
    required this.prompt,
    required this.forum,
    required this.cancellation,
    this.progress,
    NewsRepository? news,
    http.Client Function()? clientFactory,
  }) : news = news ?? NewsRepository(),
       _clientFactory = clientFactory ?? http.Client.new;
  final http.Client Function() _clientFactory;
  final CithubPlatform platform;
  final String prompt, forum;
  final AiCancellation cancellation;
  final void Function(String)? progress;
  final NewsRepository news;
  final records = <String, Map<String, dynamic>>{};
  final _allowedImages = <String>{};
  final _bodies = <String, String>{};
  final _admitted = <String, Set<String>>{};
  final _commentRecords = <String, List<Map<String, dynamic>>>{};
  bool get commentsAllowed => RegExp(
    r'评论|回复|讨论|楼层|楼中楼|大家.*说|网友.*说|comment|repl',
    caseSensitive: false,
  ).hasMatch(prompt);
  Future<T> _request<T>(Future<T> Function() operation) => runZoned(
    operation,
    zoneValues: {requestCancellationKey: cancellation.check},
  );
  Map<String, dynamic> bodyBlock(String source, String id, int block) {
    final text = _bodies['$source:$id'];
    if (text == null) throw StateError('请先获取这条内容');
    final chunks = chunkText(text);
    final count = chunks.length;
    if (block < 0 || block >= count) throw RangeError('正文分块编号无效');
    return {
      'source': source,
      'id': id,
      'block': block,
      'blocks': count,
      'content': chunks[block],
    };
  }

  Future<Map<String, dynamic>> latest(String source, int count) {
    final readId = 'read-${DateTime.now().microsecondsSinceEpoch}';
    return RuntimeLog.trace('campus-content', 'latest', {
      'readId': readId,
      'source': source,
      'modelCount': count,
      'prompt': prompt,
    }, () => _latest(source, count, readId));
  }

  Future<Map<String, dynamic>> _latest(
    String source,
    int count,
    String readId,
  ) async {
    cancellation.check();
    if (!['tieba', 'wechat', 'campus', 'official'].contains(source)) {
      throw const FormatException('数据来源无效');
    }
    final cap = requestedLimit(prompt, source);
    // The user's quantity (or the default ten) controls reads. Model tool
    // arguments cannot silently shrink the requested campus summary to one.
    final requested = cap;
    RuntimeLog.event('campus-content', 'quantity-resolved', {
      'readId': readId,
      'source': source,
      'prompt': prompt,
      'modelCount': count,
      'requested': requested,
      'policy': 'user-quantity-or-default-ten',
    });
    final ids = _admitted.putIfAbsent(source, () => {});
    final selected = records.values
        .where((r) => r['sourceType'] == source)
        .take(requested)
        .toList();
    if (selected.length >= requested) {
      return {
        'source': source,
        'items': selected,
        'limit': cap,
        'requested': requested,
        'actual': selected.length,
        'partial': false,
      };
    }
    var partial = false;
    String? failure;
    try {
      if (source == 'tieba') {
        var page = 1;
        final seen = <String>{};
        while (selected.length < requested && page <= 10) {
          cancellation.check();
          progress?.call('正在读取贴吧第$page页（${selected.length}/$requested）');
          final result = await _request(
            () => platform.loadForum(
              normalizeTiebaForumName(forum),
              page: page,
              sort: 'post',
            ),
          );
          for (final thread in result.threads.where((t) => !t.isTop)) {
            cancellation.check();
            if (!seen.add(thread.id)) continue;
            if (records.containsKey('tieba:${thread.id}')) {
              if (!selected.any((r) => r['id'] == thread.id)) {
                selected.add(records['tieba:${thread.id}']!);
              }
              continue;
            }
            if (ids.length >= cap || selected.length >= requested) break;
            ids.add(thread.id);
            progress?.call('正在读取帖子主楼（${selected.length + 1}/$requested）');
            final content = await _request(
              () => platform.loadThread(
                thread.id,
                thread.forumId,
                thread.forumName,
                onlyOriginalPoster: true,
              ),
            );
            final body = content.body;
            final text = body == null
                ? thread.excerpt
                : tiebaText(body.content);
            final images = body == null
                ? <String>[]
                : tiebaImageUrls(body.content);
            _allowedImages.addAll(images);
            final record = <String, dynamic>{
              'sourceType': source,
              'id': thread.id,
              'title': thread.title,
              'author': body?.authorNickname ?? thread.authorNickname,
              'publishedAt': body?.time,
              'lastReplyAt': thread.lastReplyTime,
              'kind': 'main_post',
              'url': 'https://tieba.baidu.com/p/${thread.id}',
              'forumId': thread.forumId,
              'forumName': thread.forumName,
              'images': images,
            };
            _bodies['tieba:${thread.id}'] = text;
            record.addAll(bodyBlock('tieba', thread.id, 0));
            records['tieba:${thread.id}'] = record;
            selected.add(record);
          }
          if (!result.hasMore ||
              selected.length >= requested ||
              ids.length >= cap) {
            break;
          }
          page++;
        }
      } else {
        final section = NewsSection.values.byName(source);
        var articles = await news.cached(includeDemo: false);
        final cachedAt = await news.cachedAt(section);
        if (cachedAt == null ||
            DateTime.now().difference(cachedAt) > const Duration(minutes: 5)) {
          cancellation.check();
          try {
            articles = await _request(() => news.refreshSection(section));
            if (news.failures.isNotEmpty) {
              partial = true;
              failure = '部分新闻源未能加载，当前仅包含成功读取的内容';
            }
          } on AiCancelled {
            rethrow;
          } catch (error, stack) {
            RuntimeLog.event('campus-content', 'refresh-failed', {
              'readId': readId,
              'source': source,
              'error': '$error',
              'stack': '$stack',
            });
            partial = true;
            failure = '刷新失败，使用已有缓存，可能不是最新内容';
          }
        }
        final items = articles.where((a) => a.section == section).toList()
          ..sort(
            (a, b) => (b.publishedAt ?? DateTime(1970)).compareTo(
              a.publishedAt ?? DateTime(1970),
            ),
          );
        for (final article in items) {
          cancellation.check();
          if (selected.length >= requested) break;
          if (records.containsKey('$source:${article.id}')) {
            if (!selected.any((r) => r['id'] == article.id)) {
              selected.add(records['$source:${article.id}']!);
            }
            continue;
          }
          if (ids.length >= cap) break;
          ids.add(article.id);
          progress?.call(
            '正在读取${article.source}（${selected.length + 1}/$requested）',
          );
          final parsed = html.parse(article.html);
          for (final element in parsed.querySelectorAll('script,style,nav')) {
            element.remove();
          }
          var text = parsed.body?.text.trim() ?? '';
          var complete = text.isNotEmpty;
          if (text.isEmpty && article.link.isNotEmpty) {
            try {
              text = await _articleText(Uri.parse(article.link));
              complete = text.isNotEmpty;
            } on AiCancelled {
              rethrow;
            } catch (_) {
              text = article.summary;
            }
          }
          if (text.isEmpty) text = article.summary;
          final record = <String, dynamic>{
            'sourceType': source,
            'id': article.id,
            'title': article.title,
            'source': article.source,
            'publishedAt': article.publishedAt?.toIso8601String(),
            'url': article.link,
            'kind': 'news',
            'fullBodyAvailable': complete,
          };
          _bodies['$source:${article.id}'] = text;
          record.addAll(bodyBlock(source, article.id, 0));
          records['$source:${article.id}'] = record;
          selected.add(record);
        }
      }
    } on AiCancelled {
      rethrow;
    } catch (error, stack) {
      RuntimeLog.event('campus-content', 'read-failed', {
        'readId': readId,
        'source': source,
        'error': '$error',
        'stack': '$stack',
      });
      partial = true;
      failure = '部分内容未能获取，可能需要登录、处理风控或稍后重试';
    }
    return {
      'source': source,
      'readId': readId,
      'requested': requested,
      'items': selected.take(requested).toList(),
      'limit': cap,
      'actual': selected.take(requested).length,
      'partial': partial,
      'message':
          failure ??
          (selected.length < requested
              ? '本次来源仅返回 ${selected.length}/$requested 条，不能据此声称已覆盖全部校园资讯'
              : null),
    };
  }

  Future<String> _articleText(Uri uri) async {
    if (uri.scheme != 'https') throw StateError('文章链接须为 HTTPS');
    final client = LoggingHttpClient(_clientFactory(), streaming: true);
    cancellation.onCancel(client.close);
    try {
      for (var redirects = 0; redirects < 3; redirects++) {
        cancellation.check();
        final response = await cancellation.wait(
          client
              .send(http.Request('GET', uri)..followRedirects = false)
              .timeout(const Duration(seconds: 15)),
        );
        if (response.statusCode >= 300 && response.statusCode < 400) {
          await response.stream.drain<void>();
          uri = uri.resolve(response.headers['location'] ?? '');
          if (uri.scheme != 'https') throw StateError('文章重定向无效');
          continue;
        }
        if (response.statusCode != 200) throw StateError('文章读取失败');
        final bytes = <int>[];
        await for (final chunk in cancellation.bind(
          response.stream.timeout(const Duration(seconds: 15)),
        )) {
          cancellation.check();
          bytes.addAll(chunk);
          if (bytes.length > 5 * 1024 * 1024) throw StateError('文章过大');
        }
        final document = html.parse(utf8.decode(bytes, allowMalformed: true));
        for (final e in document.querySelectorAll(
          'script,style,nav,header,footer',
        )) {
          e.remove();
        }
        return (document.querySelector(
                      '#vsb_content, .v_news_content, article, #js_content',
                    ) ??
                    document.body)
                ?.text
                .trim() ??
            '';
      }
      throw StateError('文章重定向过多');
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> comments(String id, int count) async {
    if (!commentsAllowed) throw StateError('当前问题未要求读取评论');
    final record = records['tieba:$id'];
    if (record == null) throw StateError('请先从最新帖子列表获取该帖子');
    final cap = requestedLimit(prompt, 'comments');
    final requested = count.clamp(1, cap);
    final output = _commentRecords.putIfAbsent(id, () => []);
    final seen = output.map((v) => v['id']).toSet();
    try {
      for (var page = 1; output.length < requested && page <= 10; page++) {
        cancellation.check();
        progress?.call('正在读取评论（${output.length}/$requested）');
        final result = await _request(
          () => platform.loadThread(
            id,
            record['forumId'] as int,
            record['forumName'] as String,
            page: page,
            sort: 'desc',
          ),
        );
        for (final floor in result.floors.where((f) => f.floor != 1)) {
          if (output.length >= requested) break;
          if (seen.add(floor.postId)) {
            output.add({
              'id': floor.postId,
              'threadId': id,
              'kind': 'comment',
              'floor': floor.floor,
              'author': floor.authorNickname,
              'time': floor.time,
              'content': tiebaText(floor.content),
              'images': tiebaImageUrls(floor.content),
            });
            _allowedImages.addAll(tiebaImageUrls(floor.content));
          }
          final replies = [...floor.replies];
          if (floor.replyCount > replies.length && output.length < requested) {
            for (
              var replyPage = 1;
              replyPage <= 10 && output.length + replies.length < requested;
              replyPage++
            ) {
              cancellation.check();
              final replyResult = await _request(
                () => platform.loadFloorReplies(
                  id,
                  floor.postId,
                  page: replyPage,
                ),
              );
              replies.addAll(replyResult.replies);
              if (replyPage >= replyResult.totalPages) break;
            }
          }
          for (final reply in replies) {
            if (output.length >= requested) break;
            if (seen.add(reply.id)) {
              output.add({
                'id': reply.id,
                'threadId': id,
                'parentPostId': floor.postId,
                'kind': 'nested_comment',
                'floor': floor.floor,
                'author': reply.authorNickname,
                'time': reply.time,
                'content': tiebaText(reply.content),
                'images': tiebaImageUrls(reply.content),
              });
              _allowedImages.addAll(tiebaImageUrls(reply.content));
            }
          }
        }
        if (page >= result.totalPages) break;
      }
      return {
        'comments': output.take(requested).toList(),
        'actual': output.take(requested).length,
        'limit': cap,
      };
    } on AiCancelled {
      rethrow;
    } catch (_) {
      return {
        'comments': output.take(requested).toList(),
        'actual': output.take(requested).length,
        'limit': cap,
        'partial': true,
        'message': '评论读取已暂停，保留已获取内容',
      };
    }
  }

  Future<Map<String, dynamic>> image(String url) => RuntimeLog.trace(
    'ai-content',
    'read-tieba-image',
    {'url': url},
    () async {
      cancellation.check();
      if (!_allowedImages.contains(url)) throw StateError('请先获取包含该图片的帖子或评论');
      final uri = Uri.tryParse(url);
      if (uri == null || uri.scheme != 'https') throw StateError('图片地址无效');
      final client = LoggingHttpClient(_clientFactory(), streaming: true);
      cancellation.onCancel(client.close);
      try {
        final response = await cancellation.wait(
          client
              .send(http.Request('GET', uri))
              .timeout(const Duration(seconds: 15)),
        );
        if (response.statusCode != 200) {
          throw StateError('图片 HTTP ${response.statusCode}');
        }
        final contentType =
            response.headers['content-type']?.split(';').first ?? '';
        if (!contentType.startsWith('image/')) throw StateError('返回内容不是图片');
        if ((response.contentLength ?? 0) > 20 * 1024 * 1024) {
          throw StateError('图片超过20 MB');
        }
        final bytes = <int>[];
        await for (final chunk in cancellation.bind(
          response.stream.timeout(const Duration(seconds: 15)),
        )) {
          cancellation.check();
          bytes.addAll(chunk);
          if (bytes.length > 20 * 1024 * 1024) throw StateError('图片超过20 MB');
        }
        cancellation.check();
        return {
          'url': url,
          'image': 'data:$contentType;base64,${base64Encode(bytes)}',
        };
      } finally {
        client.close();
      }
    },
  );
}
