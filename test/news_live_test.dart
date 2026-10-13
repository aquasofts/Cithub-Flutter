import 'dart:io';

import 'package:cithub_flutter/core/logging/runtime_log.dart';
import 'package:cithub_flutter/features/news/news_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'official sources load real lists, distinct dates and article bodies',
    () async {
      // Explicit opt-in; ordinary regression tests never depend on school servers.
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({});
      const channel = BasicMessageChannel<Object?>(
        'dev.flutter.pigeon.cithub_flutter.RuntimeLogHostApi.append',
        StandardMessageCodec(),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(channel, (_) async => [true]);
      final repository = NewsRepository();
      addTearDown(repository.close);
      final articles = await repository.refreshSection(NewsSection.official);
      expect(repository.failures, isEmpty);
      expect(articles.length, greaterThanOrEqualTo(20));
      final academic = articles.where((a) => a.source == '学术新闻').toList();
      expect(academic.map((a) => a.publishedAt).toSet().length, greaterThan(1));
      for (final source in ['学校新闻', '通知公告', '学术新闻']) {
        final article = articles.firstWhere((a) => a.source == source);
        final body = await repository.readArticle(article);
        expect(body.html.length, greaterThan(100));
        expect(body.title, article.title);
      }
      await RuntimeLog.flush();
    },
    skip: !const bool.fromEnvironment('CITHUB_LIVE_NEWS'),
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
