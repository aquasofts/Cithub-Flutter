import 'dart:async';

import 'package:cithub_flutter/core/native/cithub_api.g.dart';
import 'package:cithub_flutter/core/platform/cithub_platform.dart';
import 'package:cithub_flutter/core/platform/demo_cithub_platform.dart';
import 'package:cithub_flutter/features/academic/academic_screen.dart';
import 'package:cithub_flutter/features/tieba/tieba_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('iOS thread header is compact, single-line and left aligned', (
    tester,
  ) async {
    final thread = ForumThreadDto(
      id: '1000',
      title: '测试主题',
      excerpt: '',
      excerptContent: const [],
      authorName: '楼主',
      authorNickname: '楼主',
      authorId: 1,
      authorPortrait: '',
      replyCount: '1',
      viewCount: '2',
      lastReplyTime: '刚刚',
      isTop: false,
      isGood: false,
      imageUrls: const [],
      forumId: 1,
      forumName: '长春工程学院',
      authorModeratorRole: TiebaModeratorRole.none,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cithubPlatformProvider.overrideWithValue(DemoCithubPlatform()),
        ],
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: ThreadScreen(thread: thread),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.centerTitle, isFalse);
    expect(appBar.toolbarHeight, 56);
    expect(find.text('长春工程学院吧'), findsOneWidget);
    expect(find.text('校园贴吧'), findsNothing);
  });

  testWidgets('academic login keeps its form and hides native stack traces', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cithubPlatformProvider.overrideWithValue(_FailingWebVpnPlatform()),
        ],
        child: const MaterialApp(home: Scaffold(body: AcademicScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == '统一身份认证账号',
      ),
      '20260001',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.labelText == '密码',
      ),
      'wrong',
    );
    final login = find.byKey(const Key('webvpn-login'));
    await tester.ensureVisible(login);
    await tester.tap(login);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('academic-login-error')), findsOneWidget);
    expect(find.text('用户名或密码错误'), findsOneWidget);
    expect(find.textContaining('Stacktrace'), findsNothing);
    expect(find.text('登录 WebVPN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tieba reloads follow and sign status after native login', (
    tester,
  ) async {
    final platform = _TiebaLoginRefreshPlatform();
    addTearDown(platform.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [cithubPlatformProvider.overrideWithValue(platform)],
        child: const MaterialApp(home: Scaffold(body: TiebaScreen())),
      ),
    );
    await tester.pumpAndSettle();
    expect(platform.forumLoads, 1);
    expect(find.text('关注'), findsOneWidget);

    platform.emitLogin();
    await tester.pumpAndSettle();

    expect(platform.forumLoads, 2);
    expect(find.text('已签7天'), findsOneWidget);
  });
}

class _FailingWebVpnPlatform extends DemoCithubPlatform {
  @override
  Future<WebVpnSessionDto> loginWebVpn(LoginRequestDto request) async {
    throw PlatformException(
      code: 'requestFailed("用户名或密码错误")',
      message: 'CithubNativeError',
      details: 'Stacktrace: native frame 1\nnative frame 2',
    );
  }
}

class _TiebaLoginRefreshPlatform extends DemoCithubPlatform {
  final _nativeEvents = StreamController<NativeEventDto>.broadcast();
  int forumLoads = 0;

  @override
  Stream<NativeEventDto> get events => _nativeEvents.stream;

  void emitLogin() {
    _nativeEvents.add(
      NativeEventDto(
        source: 'tieba',
        stage: 'signedIn',
        message: '贴吧登录成功',
        timestampMillis: 1,
      ),
    );
  }

  void dispose() => _nativeEvents.close();

  @override
  Future<ForumPageDto> loadForum(
    String name, {
    int page = 1,
    String sort = 'reply',
    bool goodOnly = false,
  }) async {
    forumLoads++;
    final result = await super.loadForum(
      name,
      page: page,
      sort: sort,
      goodOnly: goodOnly,
    );
    result.forum.isFollowed = forumLoads > 1;
    result.forum.signed = forumLoads > 1;
    result.forum.signedDays = forumLoads > 1 ? 7 : 0;
    return result;
  }
}
