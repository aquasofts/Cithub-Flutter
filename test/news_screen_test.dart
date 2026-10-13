import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:cithub_flutter/core/logging/runtime_log.dart';
import 'package:cithub_flutter/core/settings/app_settings.dart';
import 'package:cithub_flutter/core/theme/cithub_theme.dart';
import 'package:cithub_flutter/features/news/news_repository.dart';
import 'package:cithub_flutter/features/news/news_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NewsFixture extends NewsRepository {
  NewsFixture({this.fail = false})
    : super(client: MockClient((_) async => http.Response('', 200)));
  bool fail;
  int calls = 0;
  @override
  Future<List<NewsArticle>> cached({bool includeDemo = true}) async => [];
  @override
  Future<DateTime?> cachedAt(NewsSection section) async => null;
  @override
  Future<List<NewsArticle>> refreshSection(NewsSection section) async {
    calls++;
    if (fail) throw StateError('offline');
    return [
      for (var i = 0; i < 3; i++)
        NewsArticle(
          id: '$i',
          source: ['学校新闻', '通知公告', '学术新闻'][i],
          title: ['校园里的一周：把热爱写进青春', '关于本学期教学安排的通知', '学术交流，让新的想法在这里发生'][i],
          summary: '校园里的新鲜事、学习与生活的最新动态。及时了解学校资讯，让每一天都有新的收获。',
          link: '',
          html: '<p>正文</p>',
          publishedAt: DateTime(2026, 10, 13 - i),
          section: section,
        ),
    ];
  }
}

void main() {
  final events = <Map>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    events.clear();
    const channel = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.cithub_flutter.RuntimeLogHostApi.append',
      StandardMessageCodec(),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(channel, (value) async {
          final entry = value! as List;
          events.add(jsonDecode(entry[1] as String) as Map);
          return [true];
        });
  });
  testWidgets(
    'first visit loads official news automatically and logs refresh',
    (tester) async {
      final repo = NewsFixture();
      addTearDown(repo.close);
      await tester.pumpWidget(
        MaterialApp(
          home: NewsScreen(
            fixedSection: NewsSection.official,
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.calls, 1);
      expect(find.text('校园里的一周：把热爱写进青春'), findsOneWidget);
      await tester.runAsync(RuntimeLog.flush);
      expect(
        events.any(
          (e) =>
              e['action'] == 'success' && e['data']['operation'] == 'refresh',
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('failed first load has a working retry', (tester) async {
    final repo = NewsFixture(fail: true);
    addTearDown(repo.close);
    await tester.pumpWidget(
      MaterialApp(
        home: NewsScreen(fixedSection: NewsSection.official, repository: repo),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('检查网络'), findsOneWidget);
    repo.fail = false;
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(repo.calls, 2);
    expect(find.text('校园里的一周：把热爱写进青春'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('embedded news waits until its section becomes visible', (
    tester,
  ) async {
    final repo = NewsFixture();
    addTearDown(repo.close);
    await tester.pumpWidget(
      MaterialApp(
        home: NewsScreen(
          fixedSection: NewsSection.official,
          repository: repo,
          active: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repo.calls, 0);
    await tester.pumpWidget(
      MaterialApp(
        home: NewsScreen(
          fixedSection: NewsSection.official,
          repository: repo,
          active: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repo.calls, 1);
    expect(find.text('校园里的一周：把热爱写进青春'), findsOneWidget);
  });
  for (final brightness in Brightness.values) {
    testWidgets('news cards fit narrow screen with large text $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = NewsFixture();
      addTearDown(repo.close);
      var theme = buildCithubTheme(const AppSettings(), brightness);
      const fontPath = String.fromEnvironment('CITHUB_PREVIEW_FONT');
      if (fontPath.isNotEmpty) {
        await tester.runAsync(() async {
          await (FontLoader('PreviewFont')..addFont(
                Future.value(
                  ByteData.sublistView(await File(fontPath).readAsBytes()),
                ),
              ))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        });
        theme = theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'PreviewFont'),
        );
      }
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          builder: (ctx, child) => MediaQuery(
            data: MediaQuery.of(ctx)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: RepaintBoundary(
            key: const Key('news-preview'),
            child: Scaffold(
              body: NewsScreen(
                fixedSection: NewsSection.official,
                repository: repo,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (fontPath.isNotEmpty) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('news-preview')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ImageByteFormat.png);
          await File('/private/tmp/cithub-news-${brightness.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}
