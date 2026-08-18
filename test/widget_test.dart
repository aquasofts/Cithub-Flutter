import 'dart:async';
import 'dart:convert';

import 'package:cithub_flutter/app/cithub_app.dart';
import 'package:cithub_flutter/core/platform/cithub_platform.dart';
import 'package:cithub_flutter/core/platform/demo_cithub_platform.dart';
import 'package:cithub_flutter/core/native/cithub_api.g.dart';
import 'package:cithub_flutter/core/settings/app_settings.dart';
import 'package:cithub_flutter/features/academic/academic_screen.dart';
import 'package:cithub_flutter/features/news/news_repository.dart';
import 'package:cithub_flutter/features/news/news_screen.dart';
import 'package:cithub_flutter/features/tieba/tieba_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget app() => ProviderScope(
    overrides: [cithubPlatformProvider.overrideWithValue(DemoCithubPlatform())],
    child: const CithubApp(),
  );

  testWidgets('shows four primary tabs and opens a Tieba thread', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('贴吧'), findsWidgets);
    expect(find.text('新闻'), findsOneWidget);
    expect(find.text('教务'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('欢迎来到 长春工程学院 吧'), findsOneWidget);

    await tester.tap(find.text('欢迎来到 长春工程学院 吧'));
    await tester.pumpAndSettle();
    expect(find.text('回复 18'), findsOneWidget);
    expect(find.text('这是主题内容。'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.textContaining('第 1 页'), findsNothing);
    expect(find.text('新闻'), findsOneWidget);

    await tester.tap(find.text('新闻'));
    await tester.pumpAndSettle();
    expect(find.text('公众号'), findsOneWidget);
    await tester.tap(find.text('贴吧'));
    await tester.pumpAndSettle();
    expect(find.text('这是主题内容。'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('长春工程学院吧'), findsOneWidget);
    expect(find.text('这是主题内容。'), findsNothing);
  });

  testWidgets(
    'Tieba detail matches full-width layout and handles compact replies',
    (tester) async {
      final platform = _TiebaLayoutPlatform();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [cithubPlatformProvider.overrideWithValue(platform)],
          child: const CithubApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tieba-emoticon-滑稽')), findsOneWidget);
      expect(find.byKey(const Key('tieba-emoticon-笑尿')), findsOneWidget);
      expect(
        find.byKey(const Key('thread-multi-image-preview')),
        findsOneWidget,
      );
      final left = tester.getTopLeft(
        find.byKey(const Key('thread-preview-image-0')),
      );
      final middle = tester.getTopLeft(
        find.byKey(const Key('thread-preview-image-1')),
      );
      final right = tester.getTopLeft(
        find.byKey(const Key('thread-preview-image-2')),
      );
      expect(left.dx, lessThan(middle.dx));
      expect(middle.dx, lessThan(right.dx));

      await tester.tap(find.text('欢迎来到 长春工程学院 吧'));
      await tester.pumpAndSettle();

      final titleLeft = tester.getTopLeft(find.text('欢迎来到 长春工程学院 吧').first).dx;
      final authorLeft = tester.getTopLeft(find.text('楼主').first).dx;
      expect(titleLeft, lessThan(authorLeft));
      expect(find.byKey(const Key('tieba-emoticon-滑稽')), findsOneWidget);
      expect(find.byKey(const Key('tieba-emoticon-笑尿')), findsOneWidget);
      expect(find.byKey(const Key('tieba-emoticon-笑尿-2')), findsOneWidget);
      expect(find.textContaining('#（未知）', findRichText: true), findsOneWidget);
      expect(find.textContaining('可见用户名', findRichText: true), findsOneWidget);
      expect(find.textContaining('可见用户名：：', findRichText: true), findsNothing);
      expect(
        find.byKey(const Key('thread-body-replies-divider')),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byKey(const Key('floor-reply-preview'))).width,
        greaterThan(200),
      );
      expect(find.byIcon(Icons.school), findsNothing);
      expect(find.text('查看 1 条回复'), findsNothing);

      expect(find.byTooltip('回到顶部'), findsNothing);
      await tester.drag(
        find.byKey(const Key('thread-1000')),
        const Offset(0, -520),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('回到顶部'), findsOneWidget);
      await tester.tap(find.byTooltip('回到顶部'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('回到顶部'), findsNothing);
    },
  );

  testWidgets('primary section headers stay compact and Mine owns settings', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final tiebaAppBar = tester.widget<SliverAppBar>(
      find.descendant(
        of: find.byKey(const PageStorageKey('tieba-scroll')),
        matching: find.byType(SliverAppBar),
      ),
    );
    expect(tiebaAppBar.scrolledUnderElevation, 0);
    expect(tiebaAppBar.surfaceTintColor, Colors.transparent);

    for (final tab in ['新闻', '教务', '我的']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      final scrollKey = switch (tab) {
        '新闻' => const PageStorageKey('news-wechat'),
        '教务' => const PageStorageKey('academic-scroll'),
        _ => const PageStorageKey('mine-scroll'),
      };
      final title = find.descendant(
        of: find.byKey(scrollKey),
        matching: find.text(switch (tab) {
          '教务' => '教务系统',
          '我的' => '个人信息',
          _ => tab,
        }),
      );
      expect(title, findsOneWidget);
      expect(tester.getTopLeft(title).dy, lessThan(80));
    }

    expect(find.byTooltip('设置'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const PageStorageKey('mine-scroll')),
        matching: find.text('我的'),
      ),
      findsNothing,
    );
    expect(find.text('个人信息'), findsOneWidget);
  });

  testWidgets('Mine shows account details before explicit logout actions', (
    tester,
  ) async {
    final platform = _SignedInMinePlatform();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [cithubPlatformProvider.overrideWithValue(platform)],
        child: const CithubApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();

    expect(find.text('贴吧同学'), findsOneWidget);
    expect(find.text('已连接'), findsOneWidget);
    expect(find.text('退出贴吧账号'), findsOneWidget);
    expect(find.text('退出 WebVPN'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('贴吧同学')).dy,
      lessThan(tester.getTopLeft(find.text('退出贴吧账号')).dy),
    );

    await tester.tap(find.text('退出贴吧账号'));
    await tester.pumpAndSettle();
    expect(platform.tiebaLogouts, 1);
    expect(find.text('登录'), findsOneWidget);
  });

  testWidgets('Tieba login entry exists only in Mine', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byTooltip('贴吧登录'), findsNothing);
    expect(find.text('百度贴吧'), findsNothing);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('百度贴吧'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
  });

  testWidgets('changing home forum immediately resets the Tieba request', (
    tester,
  ) async {
    final platform = _TiebaRecordingPlatform();
    final container = ProviderContainer(
      overrides: [cithubPlatformProvider.overrideWithValue(platform)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: TiebaScreen())),
      ),
    );
    await tester.pumpAndSettle();
    expect(platform.loadedForums.last, defaultTiebaHomeForum);

    await container
        .read(appSettingsProvider.notifier)
        .setTiebaHomeForumName('南湖吧');
    await tester.pumpAndSettle();

    expect(find.text('南湖吧'), findsOneWidget);
    expect(platform.loadedForums.last, '南湖');
  });

  testWidgets('stale forum responses cannot mix into a new home forum', (
    tester,
  ) async {
    final platform = _DelayedTiebaPlatform();
    final container = ProviderContainer(
      overrides: [cithubPlatformProvider.overrideWithValue(platform)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: TiebaScreen())),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(platform.requests, contains(defaultTiebaHomeForum));

    await container
        .read(appSettingsProvider.notifier)
        .setTiebaHomeForumName('南湖');
    await tester.pump();
    await tester.pump();
    expect(platform.requests, contains('南湖'));

    platform.release('南湖');
    await tester.pumpAndSettle();
    expect(find.text('南湖 讨论帖 2'), findsOneWidget);

    platform.release(defaultTiebaHomeForum);
    await tester.pumpAndSettle();
    expect(find.text('南湖 讨论帖 2'), findsOneWidget);
    expect(find.text('长春工程学院 讨论帖 2'), findsNothing);
  });

  testWidgets('long press replies through official client with floor post id', (
    tester,
  ) async {
    final platform = _TiebaRecordingPlatform();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [cithubPlatformProvider.overrideWithValue(platform)],
        child: const MaterialApp(home: Scaffold(body: TiebaScreen())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('欢迎来到 长春工程学院 吧'));
    await tester.pumpAndSettle();

    expect(find.text('这是主题内容。'), findsOneWidget);
    expect(find.byKey(const Key('thread-main-floor')), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);

    final floor = find.byKey(const Key('floor-menu-10000002'));
    await tester.ensureVisible(floor);
    await tester.longPress(floor);
    await tester.pumpAndSettle();
    await tester.tap(find.text('回复'));
    await tester.pumpAndSettle();

    expect(platform.lastReplyThreadId, 1000);
    expect(platform.lastReplyPostId, 10000002);
  });

  testWidgets('Tieba home and thread remain usable at 320dp with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('长春工程学院吧'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('欢迎来到 长春工程学院 吧'));
    await tester.pumpAndSettle();
    expect(find.text('这是主题内容。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('news cards remain compact at 320dp with large text', (
    tester,
  ) async {
    final articles = [
      NewsArticle(
        id: 'wechat',
        source: '校园公众号合集',
        title: '这是一条用于验证公众号紧凑卡片不会显示大封面的长标题',
        link: 'https://example.edu/wechat',
        summary: '摘要需要最多显示三行，并且在窄屏和大字体下仍然不能产生横向溢出。',
        html: '<p>正文</p>',
        publishedAt: DateTime(2026, 8, 18),
        section: NewsSection.wechat,
        coverUrl: 'https://example.edu/wechat.jpg',
      ),
      NewsArticle(
        id: 'campus',
        source: '校内新闻',
        title: '校内新闻右侧使用小封面',
        link: 'https://example.edu/campus',
        summary: '校内新闻摘要。',
        html: '<p>正文</p>',
        publishedAt: DateTime(2026, 8, 17),
        section: NewsSection.campus,
        coverUrl: 'https://example.edu/campus.jpg',
      ),
    ];
    SharedPreferences.setMockInitialValues({
      'news.cache.v1': jsonEncode(
        articles.map((article) => article.toJson()).toList(),
      ),
    });
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: NewsScreen())),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('公众号紧凑卡片'), findsOneWidget);
    expect(find.byKey(const Key('news-thumbnail')), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('校内新闻'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('news-thumbnail')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('academic tab presents WebVPN login on a 320dp screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('教务'));
    await tester.pumpAndSettle();

    expect(find.text('登录 WebVPN'), findsOneWidget);
    expect(find.text('统一身份认证账号'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('academic login and captcha refresh expose pending interaction', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final platform = _PendingWebVpnPlatform();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [cithubPlatformProvider.overrideWithValue(platform)],
        child: const CithubApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('教务').last);
    await tester.pumpAndSettle();

    final refresh = find.byKey(const Key('webvpn-captcha-refresh'));
    expect(refresh, findsOneWidget);
    await tester.tap(refresh);
    await tester.pump();
    expect(platform.webVpnCaptchaRefreshes, 1);
    expect(tester.widget<IconButton>(refresh).onPressed, isNull);

    platform.completeCaptchaRefresh();
    await tester.pumpAndSettle();
    final login = find.byKey(const Key('webvpn-login'));
    await tester.ensureVisible(login);
    await tester.tap(login);
    await tester.pump();
    expect(platform.webVpnLogins, 1);
    expect(tester.widget<FilledButton>(login).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('academic captcha refresh uses its dedicated native call', (
    tester,
  ) async {
    final platform = _PendingAcademicCaptchaPlatform();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [cithubPlatformProvider.overrideWithValue(platform)],
        child: const CithubApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('教务').last);
    await tester.pumpAndSettle();

    expect(find.text('登录教务系统'), findsOneWidget);
    final refresh = find.byKey(const Key('webvpn-captcha-refresh'));
    await tester.tap(refresh);
    await tester.pump();

    expect(platform.academicCaptchaRefreshes, 1);
    expect(platform.academicInitializations, 1);
    expect(tester.widget<IconButton>(refresh).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('captcha refresh clears the code from the previous image', (
    tester,
  ) async {
    WebVpnSessionDto session(String id, String recognizedCode) =>
        WebVpnSessionDto(
          status: AuthStatus.signedOut,
          requiredAction: RequiredAccountAction.none,
          user: null,
          savedAccounts: const [],
          captcha: CaptchaDto(
            id: id,
            base64Image: '',
            recognizedCode: recognizedCode,
          ),
          requiresCaptcha: true,
          message: null,
        );

    Widget panel(WebVpnSessionDto value) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: WebVpnLoginPanel(
            key: const ValueKey('captcha-panel'),
            session: value,
            onLogin: (_) {},
            onRefreshCaptcha: () {},
          ),
        ),
      ),
    );

    await tester.pumpWidget(panel(session('captcha-1', '1234')));
    await tester.pumpAndSettle();
    TextField captchaField() => tester.widget<TextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == '验证码',
      ),
    );
    expect(captchaField().controller!.text, '1234');

    await tester.pumpWidget(panel(session('captcha-2', '')));
    await tester.pumpAndSettle();
    expect(captchaField().controller!.text, isEmpty);
  });

  testWidgets('signed-in academic UI uses compact rows and grade filtering', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final platform = _SignedInAcademicPlatform();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [cithubPlatformProvider.overrideWithValue(platform)],
        child: const CithubApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('教务').last);
    await tester.pumpAndSettle();

    expect(find.text('9 项学生服务'), findsOneWidget);
    expect(find.byType(SliverGrid), findsNothing);
    expect(
      tester.getTopLeft(find.text('成绩查询').first).dx,
      tester.getTopLeft(find.text('我的课表').first).dx,
    );
    expect(
      tester.getTopLeft(find.text('成绩查询').first).dy,
      lessThan(tester.getTopLeft(find.text('我的课表').first).dy),
    );

    await tester.tap(find.text('成绩查询').first);
    await tester.pumpAndSettle();
    expect(find.text('同一课程只显示最好成绩'), findsOneWidget);
    await tester.tap(find.text('同一课程只显示最好成绩'));
    await tester.tap(find.text('查询成绩'));
    await tester.pumpAndSettle();
    expect(platform.lastBestOnly, isTrue);
    expect(find.text('程序设计基础'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('student evaluation loads typed form and confirms submission', (
    tester,
  ) async {
    final platform = _RecordingPlatform();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [cithubPlatformProvider.overrideWithValue(platform)],
        child: MaterialApp(
          home: EvaluationFormScreen(
            course: EvaluationCourseDto(
              sequence: '1',
              courseCode: 'CS101',
              courseName: '程序设计基础',
              teacher: '王老师',
              category: '理论课',
              totalScore: '100',
              evaluated: false,
              submitted: false,
              teachingHours: '64',
              formPath: '/evaluation/form/1',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('教学态度认真'), findsOneWidget);
    await tester.tap(find.text('提交评价'));
    await tester.pumpAndSettle();
    expect(find.text('确认提交评价？'), findsOneWidget);
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();

    expect(platform.submissions, 1);
  });
}

class _RecordingPlatform extends DemoCithubPlatform {
  int submissions = 0;

  @override
  Future<bool> saveEvaluation(
    EvaluationFormDto form,
    List<EvaluationAnswerDto> answers,
    String suggestion, {
    required bool submit,
  }) async {
    if (submit) submissions++;
    return true;
  }
}

class _TiebaRecordingPlatform extends DemoCithubPlatform {
  final loadedForums = <String>[];
  int? lastReplyThreadId;
  int? lastReplyPostId;

  @override
  Future<ForumPageDto> loadForum(
    String name, {
    int page = 1,
    String sort = 'reply',
    bool goodOnly = false,
  }) {
    loadedForums.add(name);
    return super.loadForum(name, page: page, sort: sort, goodOnly: goodOnly);
  }

  @override
  Future<bool> launchOfficialReply(int threadId, [int? postId]) async {
    lastReplyThreadId = threadId;
    lastReplyPostId = postId;
    return true;
  }
}

class _DelayedTiebaPlatform extends DemoCithubPlatform {
  final requests = <String>[];
  final _gates = <String, Completer<void>>{};

  void release(String forumName) => _gates[forumName]?.complete();

  @override
  Future<ForumPageDto> loadForum(
    String name, {
    int page = 1,
    String sort = 'reply',
    bool goodOnly = false,
  }) async {
    requests.add(name);
    await _gates.putIfAbsent(name, Completer<void>.new).future;
    return super.loadForum(name, page: page, sort: sort, goodOnly: goodOnly);
  }
}

class _TiebaLayoutPlatform extends DemoCithubPlatform {
  @override
  Future<ForumPageDto> loadForum(
    String name, {
    int page = 1,
    String sort = 'reply',
    bool goodOnly = false,
  }) async {
    final result = await super.loadForum(
      name,
      page: page,
      sort: sort,
      goodOnly: goodOnly,
    );
    result.threads.first.imageUrls = const [
      'https://example.edu/left.jpg',
      'https://example.edu/middle.jpg',
      'https://example.edu/right.jpg',
    ];
    result.threads.first.isTop = false;
    result.threads[1].authorModeratorRole = TiebaModeratorRole.assistant;
    return result;
  }

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
    result.body!.content = [
      TiebaContentDto(
        kind: 'text',
        text: '正文开头#(滑稽)#（笑尿）#（未知）正文结尾',
        emoticonId: '',
        url: '',
        originalUrl: '',
        width: 0,
        height: 0,
      ),
      TiebaContentDto(
        kind: 'emoticon',
        text: '笑尿',
        emoticonId: 'image_emoticon89',
        url: '',
        originalUrl: '',
        width: 0,
        height: 0,
      ),
    ];
    final previewFloor = result.floors.first;
    previewFloor.replies = [
      FloorReplyDto(
        id: 'single-reply',
        authorId: 42,
        authorName: '可见用户名',
        authorNickname: '',
        authorPortrait: '',
        content: [
          TiebaContentDto(
            kind: 'text',
            text: '：只有一条楼中楼回复',
            emoticonId: '',
            url: '',
            originalUrl: '',
            width: 0,
            height: 0,
          ),
        ],
        time: '刚刚',
        authorLevel: 1,
        authorTitle: '',
        authorIp: '吉林',
        authorModeratorRole: TiebaModeratorRole.none,
      ),
    ];
    previewFloor.replyCount = 1;
    return result;
  }
}

class _SignedInMinePlatform extends DemoCithubPlatform {
  int tiebaLogouts = 0;

  @override
  Future<WebVpnSessionDto> initializeWebVpn() async => WebVpnSessionDto(
    status: AuthStatus.signedIn,
    requiredAction: RequiredAccountAction.none,
    user: UserInfoDto(
      username: '2505422545',
      nickname: '孙嘉',
      fullName: '孙嘉',
      groups: const ['学生', '默认'],
      authType: 1,
      bindWechat: false,
      bindOtp: false,
    ),
    savedAccounts: const [],
    requiresCaptcha: false,
  );

  @override
  Future<TiebaAccountDto?> currentTiebaAccount() async => TiebaAccountDto(
    uid: 42,
    username: 'tieba_user',
    nickname: '贴吧同学',
    avatarUrl: '',
    intro: '',
    fans: '3',
    posts: '8',
    concerned: '2',
  );

  @override
  Future<bool> logoutTieba() async {
    tiebaLogouts++;
    return true;
  }
}

class _SignedInAcademicPlatform extends DemoCithubPlatform {
  bool? lastBestOnly;

  WebVpnSessionDto get _signedInSession => WebVpnSessionDto(
    status: AuthStatus.signedIn,
    requiredAction: RequiredAccountAction.none,
    user: UserInfoDto(
      username: '20260001',
      nickname: '测试同学',
      fullName: '测试同学',
      groups: const ['学生'],
      authType: 1,
      bindWechat: true,
      bindOtp: false,
    ),
    savedAccounts: const [],
    requiresCaptcha: false,
  );

  @override
  Future<WebVpnSessionDto> initializeWebVpn() async => _signedInSession;

  @override
  Future<WebVpnSessionDto> initializeAcademic(String webVpnUsername) async =>
      _signedInSession;

  @override
  Future<List<CourseGradeDto>> loadGrades(
    String term, {
    bool bestOnly = false,
  }) {
    lastBestOnly = bestOnly;
    return super.loadGrades(term, bestOnly: bestOnly);
  }
}

class _PendingWebVpnPlatform extends DemoCithubPlatform {
  int webVpnCaptchaRefreshes = 0;
  int webVpnLogins = 0;
  Completer<WebVpnSessionDto>? _captchaRefresh;
  final _login = Completer<WebVpnSessionDto>();

  WebVpnSessionDto get _signedOutSession => WebVpnSessionDto(
    status: AuthStatus.signedOut,
    requiredAction: RequiredAccountAction.none,
    user: null,
    savedAccounts: const [],
    captcha: CaptchaDto(
      id: 'pending-captcha',
      base64Image: '',
      recognizedCode: '1234',
    ),
    requiresCaptcha: true,
    message: null,
  );

  @override
  Future<WebVpnSessionDto> initializeWebVpn() async => _signedOutSession;

  @override
  Future<WebVpnSessionDto> refreshWebVpnCaptcha() {
    webVpnCaptchaRefreshes++;
    _captchaRefresh = Completer<WebVpnSessionDto>();
    return _captchaRefresh!.future;
  }

  void completeCaptchaRefresh() => _captchaRefresh!.complete(_signedOutSession);

  @override
  Future<WebVpnSessionDto> loginWebVpn(LoginRequestDto request) {
    webVpnLogins++;
    return _login.future;
  }
}

class _PendingAcademicCaptchaPlatform extends DemoCithubPlatform {
  int academicInitializations = 0;
  int academicCaptchaRefreshes = 0;
  final _refresh = Completer<WebVpnSessionDto>();

  WebVpnSessionDto get _webVpnSession => WebVpnSessionDto(
    status: AuthStatus.signedIn,
    requiredAction: RequiredAccountAction.none,
    user: UserInfoDto(
      username: '20260001',
      nickname: '测试同学',
      fullName: '测试同学',
      groups: const ['学生'],
      authType: 1,
      bindWechat: false,
      bindOtp: false,
    ),
    savedAccounts: const [],
    requiresCaptcha: false,
  );

  WebVpnSessionDto get _academicSession => WebVpnSessionDto(
    status: AuthStatus.signedOut,
    requiredAction: RequiredAccountAction.none,
    user: null,
    savedAccounts: const [],
    captcha: CaptchaDto(
      id: 'academic-captcha',
      base64Image: '',
      recognizedCode: '5678',
    ),
    requiresCaptcha: true,
    message: null,
  );

  @override
  Future<WebVpnSessionDto> initializeWebVpn() async => _webVpnSession;

  @override
  Future<WebVpnSessionDto> initializeAcademic(String webVpnUsername) async {
    academicInitializations++;
    return _academicSession;
  }

  @override
  Future<WebVpnSessionDto> refreshAcademicCaptcha() {
    academicCaptchaRefreshes++;
    return _refresh.future;
  }
}
