import 'package:cithub_flutter/core/native/cithub_api.g.dart';
import 'package:cithub_flutter/core/platform/cithub_platform.dart';
import 'package:cithub_flutter/core/platform/demo_cithub_platform.dart';
import 'package:cithub_flutter/core/settings/app_settings.dart';
import 'package:cithub_flutter/core/theme/cithub_theme.dart';
import 'package:cithub_flutter/features/academic/academic_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('timetable card layout at 390dp in ${brightness.name} theme', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cithubPlatformProvider.overrideWithValue(_LayoutPlatform()),
          ],
          child: MaterialApp(
            theme: buildCithubTheme(const AppSettings(), brightness),
            home: const RepaintBoundary(
              key: Key('timetable-golden'),
              child: TimetableScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const Key('timetable-golden')),
        matchesGoldenFile('goldens/timetable_390_${brightness.name}.png'),
      );
    });
  }

  testWidgets('timetable stays usable at 320dp with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cithubPlatformProvider.overrideWithValue(_LayoutPlatform()),
        ],
        child: MaterialApp(
          theme: buildCithubTheme(const AppSettings(), Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const TimetableScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

class _LayoutPlatform extends DemoCithubPlatform {
  @override
  Future<TimetableDto> loadTimetable([String? term]) async => TimetableDto(
    terms: [
      AcademicTermDto(
        value: '2026-2027-1',
        label: '2026-2027-1',
        selected: true,
      ),
    ],
    selectedTerm: '2026-2027-1',
    referenceDateIso: '2026-11-06',
    referenceWeek: 9,
    totalWeeks: 20,
    note: '',
    periods: [
      for (var i = 0; i < 4; i++)
        TimetablePeriodDto(
          index: i,
          label: '${i * 2 + 1}-${i * 2 + 2}',
          startTime: ['08:00', '10:05', '13:30', '15:35'][i],
          endTime: ['09:35', '11:40', '15:05', '17:10'][i],
        ),
    ],
    courses: [
      for (var i = 0; i < 4; i++)
        TimetableCourseDto(
          id: '$i',
          dayOfWeek: 5,
          periodIndex: i,
          startSection: i * 2 + 1,
          endSection: i * 2 + 2,
          name: ['计算机程序设计基础（C语言）', '土木工程材料', '房屋建筑学', '大学英语'][i],
          teacher: ['薄海玲', '刘春秋', '宿晓萍', '李老师'][i],
          location: i == 0 ? 'XS6-202' : 'XJ6-6301',
          weeks: '1-16周',
          weekNumbers: List.generate(16, (i) => i + 1),
        ),
    ],
  );
}
