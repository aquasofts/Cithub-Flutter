import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:cithub_flutter/core/settings/app_settings.dart';
import 'package:cithub_flutter/core/theme/cithub_theme.dart';
import 'package:cithub_flutter/features/mine/mine_screen.dart';
import 'package:cithub_flutter/features/timetable/timetable_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ScheduleSnapshot fixture() {
  final data = timetableFromJson({
    'selectedTerm': '2026-2027-1',
    'referenceDateIso': '2026-10-12',
    'referenceWeek': 6,
    'totalWeeks': 20,
    'periods': [
      {'index': 1, 'label': '第一大节', 'startTime': '08:10', 'endTime': '09:40'},
    ],
    'courses': [],
  });
  return ScheduleSnapshot(
    id: 'fixture',
    revision: 1,
    data: data,
    courses: [
      for (var day = 1; day <= 7; day++)
        LocalCourse(
          id: 'c$day',
          source: day.isEven ? 'ai' : 'academic',
          course: courseFromJson({
            'id': 'c$day',
            'name': [
              '英语精读与写作',
              '概率论与数理统计',
              '计算机程序设计',
              '大学物理',
              '材料力学',
              '房屋建筑学',
              '艺术体验',
            ][day - 1],
            'dayOfWeek': day,
            'startSection': day.isEven ? 3 : 1,
            'endSection': day.isEven ? 4 : 2,
            'location': 'XJ7-7602',
            'teacher': '老师',
            'weekNumbers': day == 7 ? [8] : [6, 7, 8],
          }),
        ),
    ],
  );
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'local weekly timetable respects $brightness theme and spans periods',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var theme = buildCithubTheme(
          const AppSettings(amoled: true),
          brightness,
        );
        const fontPath = String.fromEnvironment('CITHUB_PREVIEW_FONT');
        if (fontPath.isNotEmpty) {
          await tester.runAsync(() async {
            final font = FontLoader('PreviewFont')
              ..addFont(
                Future.value(
                  ByteData.sublistView(await File(fontPath).readAsBytes()),
                ),
              );
            await font.load();
            final icons = FontLoader('MaterialIcons')
              ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
            await icons.load();
          });
          theme = theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'PreviewFont'),
          );
        }
        final s = fixture();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              timetableNowProvider.overrideWithValue(
                () => DateTime(2026, 10, 13),
              ),
              activeScheduleProvider.overrideWith((_) async => s),
              schedulesProvider.overrideWith((_) async => [s]),
            ],
            child: MaterialApp(
              theme: theme,
              home: const RepaintBoundary(
                key: Key('local-grid'),
                child: MineScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('非本周'), findsOneWidget);
        expect(find.textContaining('academic'), findsNothing);
        if (fontPath.isEmpty) {
          await expectLater(
            find.byKey(const Key('local-grid')),
            matchesGoldenFile('goldens/local_grid_390_${brightness.name}.png'),
          );
        } else {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('local-grid')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(format: ImageByteFormat.png);
            await File('/private/tmp/cithub-grid-${brightness.name}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(find.byTooltip('今日列表'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('small screen and large text fit the entire weekly grid', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final base = fixture();
    final s = base.copyWith(
      courses: [
        ...base.courses,
        for (var day = 1; day <= 2; day++)
          LocalCourse(
            id: 'conflict$day',
            source: 'ai',
            course: courseFromJson({
              'id': 'conflict$day',
              'name': '重叠课程$day',
              'dayOfWeek': day,
              'startSection': day == 1 ? 1 : 3,
              'endSection': day == 1 ? 2 : 4,
              'location': 'XS6-101',
              'weekNumbers': [6],
            }),
          ),
        LocalCourse(
          id: 'last',
          source: 'ai',
          course: courseFromJson({
            'id': 'last',
            'name': '晚间课程',
            'dayOfWeek': 7,
            'startSection': 9,
            'endSection': 10,
            'location': 'XS7-401',
            'weekNumbers': [6],
          }),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          timetableNowProvider.overrideWithValue(() => DateTime(2026, 10, 13)),
          activeScheduleProvider.overrideWith((_) async => s),
          schedulesProvider.overrideWith((_) async => [s]),
        ],
        child: MaterialApp(
          theme: buildCithubTheme(const AppSettings(), Brightness.light),
          builder: (ctx, child) => MediaQuery(
            data: MediaQuery.of(ctx)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const MineScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final horizontal = find.byWidgetPredicate(
      (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
    );
    expect(horizontal, findsNothing);
    for (final course in s.courses) {
      final card = find.textContaining(course.course.name);
      expect(card, findsOneWidget);
      final rect = tester.getRect(card);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      expect(rect.bottom, lessThanOrEqualTo(800));
    }
    expect(tester.takeException(), isNull);
  });
}
