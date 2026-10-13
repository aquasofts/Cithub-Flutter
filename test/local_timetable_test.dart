import 'package:cithub_flutter/core/storage/local_database.dart';
import 'package:cithub_flutter/features/timetable/timetable_repository.dart';
import 'package:cithub_flutter/core/native/cithub_api.g.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

TimetableDto timetable({
  String name = '数学',
  String location = 'A101',
  int week = 1,
}) => timetableFromJson({
  'selectedTerm': '2026-1',
  'totalWeeks': 20,
  'referenceDateIso': '2026-10-12',
  'referenceWeek': week,
  'courses': [
    {
      'id': 'monday-$location',
      'name': name,
      'teacher': '教师',
      'location': location,
      'dayOfWeek': 1,
      'startSection': 1,
      'endSection': 2,
      'weekNumbers': [1, 2, 3],
    },
  ],
});
void main() {
  late Database db;
  late TimetableRepository repo;
  setUp(() async {
    sqfliteFfiInit();
    final store = LocalDatabase.at(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    db = await store.database;
    repo = TimetableRepository(store);
  });
  tearDown(() => db.close());
  test('AI import survives academic refresh; official deletes may be retained explicitly', () async {
    final ai = LocalCourse(
      id: 'ai-course',
      source: 'ai',
      course: timetable(name: '自习').courses.first,
    );
    await repo.save(
      ScheduleSnapshot(
        id: 'local',
        revision: 0,
        data: timetable(),
        courses: [ai],
      ),
      '导入',
      'import',
    );
    var s = await repo.importAcademic('student', timetable());
    final officialId = s.official.single.id;
    s = await repo.save(
      s.copyWith(
        courses: [ai],
        edits: {
          officialId: {
            'op': 'delete',
            'course': courseJson(s.official.single.course),
          },
        },
      ),
      '删除数学',
      'delete',
    );
    s = await repo.importAcademic(
      'student',
      timetable(location: 'B201'),
      preserve: [officialId],
      expectedRevision: s.revision,
    );
    expect(s.courses.map((c) => c.id), ['ai-course']);
    expect(s.official.single.course.location, 'B201');
    s = await repo.importAcademic('student', timetable(location: 'C301'));
    expect(s.courses.length, 2);
    expect(s.edits, isEmpty);
    expect(s.official.single.id, officialId);
  });
  test('manual courses and actual time edits survive refresh and history restoration', () async {
    var s = await repo.importAcademic('student', timetable());
    final original = s.courses.single;
    s = await repo.putCourse(
      s,
      LocalCourse(
        id: original.id,
        source: original.source,
        course: courseFromJson({
          ...courseJson(original.course),
          'name': '修改后的数学',
        }),
        startTime: '08:15',
        endTime: '09:50',
      ),
    );
    final manual = LocalCourse(
      id: 'manual',
      source: 'manual',
      course: timetable(name: '语文').courses.first,
      startTime: '10:00',
      endTime: '10:45',
    );
    s = await repo.putCourse(s, manual);
    final version = s;
    s = await repo.importAcademic(
      'student',
      timetable(location: 'B201'),
      preserve: [original.id],
      expectedRevision: s.revision,
    );
    expect(s.courses.firstWhere((c) => c.id == original.id).startTime, '08:15');
    expect(s.courses.firstWhere((c) => c.id == manual.id).source, 'manual');
    s = await repo.removeCourse(
      s,
      s.courses.firstWhere((c) => c.id == manual.id),
    );
    expect(s.courses.any((c) => c.id == manual.id), false);
    s = await repo.restore(version);
    expect(s.courses.firstWhere((c) => c.id == manual.id).endTime, '10:45');
    expect((await repo.history(s.id)).length, greaterThanOrEqualTo(6));
  });

  test('transaction rejects stale revisions and invalid courses; operation IDs are idempotent', () async {
    final s = await repo.importAcademic('student', timetable());
    final changed = await repo.save(s.copyWith(courses: []), '清空', 'change');
    final duplicate = await repo.save(s.copyWith(courses: []), '清空', 'change');
    expect(duplicate.revision, changed.revision);
    await expectLater(repo.save(s, 'stale', 'stale'), throwsStateError);
    final invalid = LocalCourse(
      id: 'bad',
      source: 'ai',
      course: courseFromJson({
        'name': '',
        'dayOfWeek': 8,
        'startSection': 1,
        'endSection': 2,
      }),
    );
    await expectLater(
      repo.save(changed.copyWith(courses: [invalid]), 'bad', 'bad'),
      throwsFormatException,
    );
    expect((await repo.active())!.courses, isEmpty);
  });
  test(
    'restoring versions preserves newer history and account separation',
    () async {
      final first = await repo.importAcademic('one', timetable());
      await repo.importAcademic('one', timetable(location: 'B201'));
      final restored = await repo.restore(first);
      expect(restored.official.single.course.location, 'A101');
      expect((await repo.history(first.id)).length, 3);
      final other = await repo.importAcademic('two', timetable());
      expect(other.id, isNot(first.id));
      expect((await repo.all()).length, 2);
    },
  );
  test(
    'fingerprint ignores reference week/order but detects actual changes',
    () {
      expect(
        academicFingerprint(timetable(week: 1)),
        academicFingerprint(timetable(week: 2)),
      );
      expect(
        academicFingerprint(timetable()),
        isNot(academicFingerprint(timetable(location: 'B201'))),
      );
    },
  );
  test('first use is consumed once', () async {
    expect(await repo.consumeOnboarding(), isTrue);
    expect(await repo.consumeOnboarding(), isFalse);
  });
}
