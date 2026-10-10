import 'dart:async';

import 'package:cithub_flutter/core/native/cithub_api.g.dart';
import 'package:cithub_flutter/core/platform/cithub_platform.dart';
import 'package:cithub_flutter/core/platform/demo_cithub_platform.dart';
import 'package:cithub_flutter/features/academic/academic_screen.dart';
import 'package:cithub_flutter/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    const channel = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.cithub_flutter.RuntimeLogHostApi.append',
      StandardMessageCodec(),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(channel, (_) async => [true]);
  });

  Future<void> show(
    WidgetTester tester,
    Widget page,
    DemoCithubPlatform platform,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [cithubPlatformProvider.overrideWithValue(platform)],
        child: MaterialApp(home: page),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'unrecognized academic page exposes the original webpage and WebVPN recovery',
    (tester) async {
      final platform = _UnknownAcademicPlatform();
      await platform.loginWebVpn(
        LoginRequestDto(
          username: 'test',
          password: 'test',
          captchaId: '',
          captchaCode: '',
          rememberPassword: false,
          useSavedPassword: false,
        ),
      );
      await show(tester, const Scaffold(body: AcademicScreen()), platform);
      expect(find.textContaining('无法识别教务系统页面'), findsOneWidget);
      expect(find.text('使用教务原始页面'), findsOneWidget);
      expect(find.text('重新连接 WebVPN'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selection results use their own term list and retain course details',
    (tester) async {
      final platform = _SelectionPlatform();
      await show(tester, const SelectionResultsScreen(), platform);
      expect(platform.selectionTermsLoaded, isTrue);
      expect(platform.requestedTerm, 'selection-term');
      expect(find.textContaining('CS305'), findsOneWidget);
      expect(find.textContaining('学时 48'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  Future<void> selectTimetable(
    WidgetTester tester,
    String label,
    String value,
  ) async {
    await tester.tap(find.widgetWithText(DropdownMenu<int>, label));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(value).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(value).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'timetable defaults to reference day and switches day, week and whole week',
    (tester) async {
      await show(tester, const TimetableScreen(), _WeekPlatform());
      expect(find.text('课程2'), findsOneWidget);
      expect(find.text('课程1'), findsNothing);
      expect(find.text('10月6日'), findsNWidgets(2));
      expect(find.text('08:00'), findsOneWidget);
      expect(find.text('09:35'), findsOneWidget);
      expect(find.text('教室 · A101'), findsOneWidget);

      await selectTimetable(tester, '星期', '周五');
      expect(find.text('课程5'), findsOneWidget);
      expect(find.text('课程2'), findsNothing);
      expect(find.text('10月9日'), findsNWidgets(2));

      await selectTimetable(tester, '周次', '第 3 周');
      expect(find.text('10月16日'), findsNWidgets(2));
      await selectTimetable(tester, '周次', '第 4 周');
      expect(find.text('当天暂无课程'), findsOneWidget);
      expect(find.text('0 门课程'), findsOneWidget);
      await selectTimetable(tester, '周次', '全部周次');
      expect(find.text('课程5'), findsOneWidget);
      expect(find.text('10月23日'), findsNothing);

      await selectTimetable(tester, '星期', '整周课表');
      expect(find.text('课程1'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('课程7'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('课程7'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final page in <String, Widget>{
    'grades': const GradesScreen(),
    'selection': const SelectionResultsScreen(),
    'timetable': const TimetableScreen(),
  }.entries) {
    testWidgets('${page.key} filters scroll with results', (tester) async {
      await show(tester, page.value, _DenseAcademicPlatform());
      final filter = find.byType(DropdownMenu<String>);
      final before = tester.getTopLeft(filter).dy;
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -60));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(filter).dy, lessThan(before - 30));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -360));
      await tester.pumpAndSettle();
      expect(filter.hitTestable(), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'historical timetable does not invent a date without a reference week',
    (tester) async {
      await show(
        tester,
        const TimetableScreen(),
        _HistoricalTimetablePlatform(),
      );
      expect(find.text('课程2'), findsOneWidget);
      expect(find.text('10月6日'), findsNothing);
      expect(find.text('1-16周'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('grade cards expose the fields omitted from their summary', (
    tester,
  ) async {
    await show(tester, const GradesScreen(), DemoCithubPlatform());
    await tester.tap(find.text('完整成绩明细').first);
    await tester.pumpAndSettle();
    expect(find.text('原始成绩'), findsOneWidget);
    expect(find.text('考试性质'), findsOneWidget);
    expect(find.text('课程类别'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'evaluation course status refreshes after returning from its form',
    (tester) async {
      final platform = _EvaluationPlatform();
      await show(
        tester,
        EvaluationCoursesScreen(
          batch: EvaluationBatchDto(
            sequence: '1',
            semester: '2026',
            category: '理论',
            name: '评教',
            startDate: '',
            endDate: '',
            courseListPath: 'xspj/list',
          ),
        ),
        platform,
      );
      expect(platform.loads, 1);
      await tester.tap(find.text('评教课程'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(platform.loads, 2);
      expect(find.text('已提交'), findsOneWidget);
    },
  );

  testWidgets('ZIP export disables repeated taps and displays failures', (
    tester,
  ) async {
    final platform = _ExportPlatform();
    await show(tester, const RuntimeLogScreen(), platform);
    await tester.tap(find.byKey(const Key('export-runtime-log')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('export-runtime-log')))
          .onPressed,
      isNull,
    );
    platform.export.completeError(StateError('存储空间不足'));
    await tester.pumpAndSettle();
    expect(find.textContaining('存储空间不足'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('export-runtime-log')))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });
}

class _SelectionPlatform extends DemoCithubPlatform {
  bool selectionTermsLoaded = false;
  String? requestedTerm;
  @override
  Future<List<AcademicTermDto>> loadAcademicTerms() =>
      throw StateError('错误的成绩学期接口');
  @override
  Future<List<AcademicTermDto>> loadSelectionTerms() async {
    selectionTermsLoaded = true;
    return [
      AcademicTermDto(value: 'selection-term', label: '选课学期', selected: true),
    ];
  }

  @override
  Future<List<SelectedCourseDto>> loadSelectionResults(String term) async {
    requestedTerm = term;
    return super.loadSelectionResults(term);
  }
}

class _WeekPlatform extends DemoCithubPlatform {
  @override
  Future<TimetableDto> loadTimetable([String? term]) async => TimetableDto(
    terms: [AcademicTermDto(value: '2026', label: '2026 学期', selected: true)],
    selectedTerm: '2026',
    periods: [
      TimetablePeriodDto(
        index: 1,
        label: '1-2',
        startTime: '08:00',
        endTime: '09:35',
      ),
    ],
    note: '',
    referenceDateIso: '2026-10-06',
    referenceWeek: 2,
    totalWeeks: 20,
    courses: [
      for (var day = 1; day <= 7; day++)
        TimetableCourseDto(
          id: '$day',
          dayOfWeek: day,
          periodIndex: 1,
          startSection: 1,
          endSection: 2,
          name: '课程$day',
          teacher: '教师',
          weeks: '1-16周',
          weekNumbers: [1, 2, 3],
          location: 'A101',
        ),
    ],
  );
}

class _EvaluationPlatform extends DemoCithubPlatform {
  int loads = 0;
  @override
  Future<List<EvaluationCourseDto>> loadEvaluationCourses(String path) async {
    loads++;
    return [
      EvaluationCourseDto(
        sequence: '1',
        courseName: '评教课程',
        teacher: '教师',
        category: '理论',
        teachingHours: '32',
        courseCode: 'CS1',
        evaluated: loads > 1,
        submitted: loads > 1,
        totalScore: '',
        formPath: 'xspj/form',
      ),
    ];
  }
}

class _ExportPlatform extends DemoCithubPlatform {
  final export = Completer<String>();
  @override
  Future<String> exportRuntimeLog() => export.future;
}

class _UnknownAcademicPlatform extends DemoCithubPlatform {
  @override
  Future<WebVpnSessionDto> initializeAcademic(String webVpnUsername) async =>
      throw StateError('无法识别教务系统页面');
}

class _DenseAcademicPlatform extends _WeekPlatform {
  @override
  Future<List<CourseGradeDto>> loadGrades(
    String term, {
    bool bestOnly = false,
  }) async {
    final items = await super.loadGrades(term, bestOnly: bestOnly);
    return [for (var i = 0; i < 12; i++) ...items];
  }

  @override
  Future<List<SelectedCourseDto>> loadSelectionResults(String term) async {
    final items = await super.loadSelectionResults(term);
    return [for (var i = 0; i < 12; i++) ...items];
  }

  @override
  Future<TimetableDto> loadTimetable([String? term]) async {
    final data = await super.loadTimetable(term);
    final course = data.courses.firstWhere((course) => course.dayOfWeek == 2);
    data.courses = [for (var i = 0; i < 12; i++) course];
    return data;
  }
}

class _HistoricalTimetablePlatform extends _WeekPlatform {
  @override
  Future<TimetableDto> loadTimetable([String? term]) async {
    final data = await super.loadTimetable(term);
    data.referenceWeek = null;
    return data;
  }
}
