import 'package:cithub_flutter/app/cithub_app.dart';
import 'package:cithub_flutter/core/native/cithub_api.g.dart';
import 'package:cithub_flutter/core/platform/cithub_platform.dart';
import 'package:cithub_flutter/core/platform/demo_cithub_platform.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'images in one floor swipe and double tap zooms around the tapped point',
    (tester) async {
      final platform = _GalleryTiebaPlatform();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [cithubPlatformProvider.overrideWithValue(platform)],
          child: const CithubApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('欢迎来到 长春工程学院 吧'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const Key('tieba-floor-image-0')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byKey(const Key('tieba-image-gallery')), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget);

      await tester.drag(
        find.byKey(const Key('tieba-image-gallery')),
        const Offset(-500, 0),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('2 / 2'), findsOneWidget);

      await tester.drag(
        find.byKey(const Key('tieba-image-gallery')),
        const Offset(500, 0),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('1 / 2'), findsOneWidget);

      final viewerFinder = find.byKey(const Key('tieba-photo-view-0'));
      final viewer = tester.widget<InteractiveViewer>(viewerFinder);
      final topLeft = tester.getTopLeft(viewerFinder);
      final size = tester.getSize(viewerFinder);
      final localTap = Offset(size.width * 0.8, size.height * 0.3);
      final globalTap = topLeft + localTap;

      await tester.tapAt(globalTap);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(globalTap);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final matrix = viewer.transformationController!.value;
      final scale = matrix.getMaxScaleOnAxis();
      expect(scale, greaterThan(1));
      final fixedPoint = Offset(
        matrix.entry(0, 3) / (1 - scale),
        matrix.entry(1, 3) / (1 - scale),
      );
      expect(fixedPoint.dx, greaterThan(size.width * 0.7));
      expect(fixedPoint.dy, lessThan(size.height * 0.4));
      expect(platform.resolvedIndexes, containsAll(<int>[1, 2]));
    },
  );
}

class _GalleryTiebaPlatform extends DemoCithubPlatform {
  final resolvedIndexes = <int>[];

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
      _image('https://example.edu/preview-1.jpg'),
      _image('https://example.edu/preview-2.jpg'),
    ];
    return result;
  }

  @override
  Future<String> resolveOriginalImage(TiebaImageRequestDto request) async {
    resolvedIndexes.add(request.imageIndex);
    return 'https://example.edu/original-${request.imageIndex}.jpg';
  }

  TiebaContentDto _image(String url) => TiebaContentDto(
    kind: 'image',
    text: '',
    emoticonId: '',
    url: url,
    originalUrl: url,
    width: 1200,
    height: 800,
  );
}
