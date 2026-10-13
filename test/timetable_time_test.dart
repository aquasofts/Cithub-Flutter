import 'package:cithub_flutter/features/timetable/timetable_repository.dart';
import 'package:cithub_flutter/features/timetable/timetable_time.dart';
import 'package:flutter_test/flutter_test.dart';

ScheduleSnapshot timeFixture() => ScheduleSnapshot(
  id: 's',
  revision: 0,
  data: timetableFromJson({
    'selectedTerm': '2026-1',
    'periods': [
      {'index': 1, 'label': '第一大节', 'startTime': '08:00', 'endTime': '09:35'},
    ],
  }),
  sectionTimes: {
    '1': '08:00\n08:45',
    '2': '08:50\n09:35',
    '3': '10:05\n10:50',
    '4': '10:55\n11:40',
  },
);
LocalCourse timed(String? start, String? end) => LocalCourse(
  id: 'c',
  source: 'manual',
  startTime: start,
  endTime: end,
  course: courseFromJson({
    'name': '课程',
    'dayOfWeek': 1,
    'startSection': 1,
    'endSection': 2,
    'weekNumbers': [1, 3],
  }),
);
void main() {
  test(
    'early, late and short classes alter minute-based course boundaries',
    () {
      final clock = TimetableTime(timeFixture());
      final normal = clock.bounds(timed(null, null));
      final early = clock.bounds(timed('07:55', '09:30'));
      final late = clock.bounds(timed('08:15', '09:50'));
      final short = clock.bounds(timed('08:10', '09:10'));
      expect(early.$1, lessThan(normal.$1));
      expect(early.$2, lessThan(normal.$2));
      expect(late.$1, greaterThan(normal.$1));
      expect(late.$2, greaterThan(normal.$2));
      expect(short.$2 - short.$1, lessThan(normal.$2 - normal.$1));
      expect(clock.course(timed('08:15', '09:50'))!.label, '08:15–09:50');
      expect(clock.position(9 * 60 + 50), greaterThan(1.96));
      expect(clock.position(9 * 60 + 50), lessThan(2.04));
    },
  );
  test(
    'period times split into sections and old courses have a time range',
    () {
      final s = timeFixture().copyWith(sectionTimes: {});
      final clock = TimetableTime(s);
      expect(clock.section(1)!.label, '08:00–08:45');
      expect(clock.section(2)!.label, '08:50–09:35');
      expect(clock.course(timed(null, null))!.label, '08:00–09:35');
    },
  );
  test(
    'actual time overrides round-trip without changing section identity',
    () {
      final original = timed('08:15', '09:50');
      final restored = LocalCourse.fromJson(original.toJson());
      expect(restored.startTime, '08:15');
      expect(restored.endTime, '09:50');
      expect(restored.id, original.id);
      expect(restored.course.startSection, 1);
    },
  );
  test(
    'week parsing and real-time conflicts are independent of nominal sections',
    () {
      expect(parseWeekNumbers('1-3，5,7-8'), [1, 2, 3, 5, 7, 8]);
      expect(() => parseWeekNumbers('3-1'), throwsFormatException);
      expect(() => parseWeekNumbers('1-61'), throwsFormatException);
      final clock = TimetableTime(timeFixture());
      expect(
        clock.overlaps(timed('08:00', '08:40'), timed('08:50', '09:30')),
        false,
      );
      expect(
        clock.overlaps(timed('08:00', '09:00'), timed('08:50', '09:30')),
        true,
      );
    },
  );
}
