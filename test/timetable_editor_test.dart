import 'package:cithub_flutter/core/storage/local_database.dart';
import 'package:cithub_flutter/features/settings/settings_screen.dart';
import 'package:cithub_flutter/features/timetable/timetable_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
void main() {
  testWidgets('Settings supports manual add, time edit and delete without AI', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    sqfliteFfiInit();
    final store = LocalDatabase.at(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfiNoIsolate,
    );
    await tester.runAsync(() async {
      await store.database;
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localDatabaseProvider.overrideWithValue(store)],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
      await tester.pumpAndSettle();
    }

    Future<void> fill(String label, String value) async {
      await tester.scrollUntilVisible(
        field(label),
        120,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.enterText(field(label), value);
      await settle();
    }

    await tester.tap(find.text('修改课表'));
    await settle();
    await tester.tap(find.text('新建课表并添加课程'));
    await settle();
    await fill('学期', '2026-1');
    await fill('课程名称', '数学');
    await fill('教室', 'XJ7-403');
    await fill('周次', '1-3,5');
    await tester.scrollUntilVisible(
      find.byType(SwitchListTile),
      120,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await settle();
    await fill('开始时间', '08:15');
    await fill('结束时间', '09:50');
    await tester.ensureVisible(find.text('保存课程'));
    await tester.tap(find.text('保存课程'));
    await settle();
    late ScheduleSnapshot saved;
    await tester.runAsync(() async {
      saved = (await TimetableRepository(store).active())!;
    });
    expect(saved.courses.single.source, 'manual');
    expect(saved.courses.single.startTime, '08:15');
    expect(saved.courses.single.course.weekNumbers, [1, 2, 3, 5]);
    expect(find.text('修改课表'), findsOneWidget);
    await tester.tap(find.text('数学'));
    await settle();
    await fill('课程名称', '微积分');
    await fill('结束时间', '09:40');
    await tester.ensureVisible(find.text('保存课程'));
    await tester.tap(find.text('保存课程'));
    await settle();
    await tester.runAsync(() async {
      final changed = (await TimetableRepository(store).active())!;
      expect(changed.courses.single.id, saved.courses.single.id);
      expect(changed.courses.single.course.name, '微积分');
      expect(changed.courses.single.endTime, '09:40');
    });
    await tester.tap(find.text('微积分'));
    await settle();
    expect(find.text('编辑课程'), findsOneWidget);
    await tester.tap(find.byTooltip('删除课程'));
    await settle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await settle();
    await tester.runAsync(() async {
      final deleted = (await TimetableRepository(store).active())!;
      expect(deleted.courses, isEmpty);
      expect((await TimetableRepository(store).history(deleted.id)).length, 3);
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await (await store.database).close();
    });
  });
}
