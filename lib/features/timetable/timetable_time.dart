import 'dart:math' as math;

import 'timetable_repository.dart';

int? clockMinutes(String text) {
  final m = RegExp(r'^(\d{1,2}):([0-5]\d)$').firstMatch(text.trim());
  if (m == null || int.parse(m[1]!) > 23) return null;
  return int.parse(m[1]!) * 60 + int.parse(m[2]!);
}

String clockLabel(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

class LessonTime {
  const LessonTime(this.start, this.end);
  final int start, end;
  String get label => '${clockLabel(start)}–${clockLabel(end)}';
  static LessonTime? parse(String? start, String? end) {
    final a = clockMinutes(start ?? ''), b = clockMinutes(end ?? '');
    return a != null && b != null && a < b ? LessonTime(a, b) : null;
  }
}

/// WakeUp uses a separate per-node time table and maps courses by start node
/// and span. Here the same section coordinate system also interpolates actual
/// minutes; recess/lunch gaps are compressed so the whole week stays on screen.
class TimetableTime {
  TimetableTime(this.snapshot);
  final ScheduleSnapshot snapshot;
  int get sectionCount => math.max(
    10,
    [
      ...snapshot.data.periods.map((p) => p.index * 2),
      ...snapshot.courses.map((c) => c.course.endSection),
      ...snapshot.sectionTimes.keys.map((k) => int.tryParse(k) ?? 0),
    ].fold<int>(0, math.max),
  );

  LessonTime? section(int index) {
    final raw = snapshot.sectionTimes['$index'];
    if (raw is String) {
      final parts = raw.trim().split(RegExp(r'[\n–-]+'));
      if (parts.length == 2) return LessonTime.parse(parts[0], parts[1]);
    }
    final period = snapshot.data.periods
        .where((p) => p.index == (index + 1) ~/ 2)
        .firstOrNull;
    final full = LessonTime.parse(period?.startTime, period?.endTime);
    if (full == null) return null;
    // Imported periods cover two lessons. A 95-minute period is 45 + 5 + 45;
    // inferred times can be corrected in the per-section editor.
    final total = full.end - full.start;
    final recess = (total - 90).clamp(0, 10);
    final duration = (total - recess) ~/ 2;
    if (duration < 1) return null;
    return index.isOdd
        ? LessonTime(full.start, full.start + duration)
        : LessonTime(full.end - duration, full.end);
  }

  LessonTime? course(LocalCourse course) {
    final explicit = LessonTime.parse(course.startTime, course.endTime);
    if (explicit != null) return explicit;
    final first = section(course.course.startSection),
        last = section(course.course.endSection);
    return first == null || last == null
        ? null
        : LessonTime(first.start, last.end);
  }

  double position(int minute, {bool isStart = true}) {
    final knots = <(int, double)>[];
    for (var i = 1; i <= sectionCount; i++) {
      final time = section(i);
      if (time != null) {
        knots.add((time.start, i - 1 + .04));
        knots.add((time.end, i - .04));
      }
    }
    if (knots.isEmpty) return 0;
    final exact = knots.where((k) => k.$1 == minute).map((k) => k.$2).toList();
    if (exact.isNotEmpty) {
      return isStart ? exact.reduce(math.max) : exact.reduce(math.min);
    }
    for (var i = 1; i < knots.length; i++) {
      final a = knots[i - 1], b = knots[i];
      if (minute <= b.$1) {
        if (b.$1 <= a.$1) continue;
        return (a.$2 + (minute - a.$1) / (b.$1 - a.$1) * (b.$2 - a.$2)).clamp(
          0.0,
          sectionCount.toDouble(),
        );
      }
    }
    final last = knots.last, previous = knots[knots.length - 2];
    return (last.$2 +
            (minute - last.$1) /
                (last.$1 - previous.$1) *
                (last.$2 - previous.$2))
        .clamp(0.0, sectionCount.toDouble());
  }

  (double, double) bounds(LocalCourse course) {
    final baseStart = course.course.startSection - 1 + .04;
    final baseEnd = course.course.endSection - .04;
    if (course.startTime == null ||
        section(course.course.startSection) == null ||
        section(course.course.endSection) == null) {
      return (baseStart, baseEnd);
    }
    final time = this.course(course)!;
    final top = position(time.start),
        bottom = position(time.end, isStart: false);
    if (bottom > top) return (top, bottom);
    final anchor = top.clamp(0.0, sectionCount - .16);
    return (anchor, anchor + .16);
  }

  bool overlaps(LocalCourse a, LocalCourse b) {
    final x = course(a), y = course(b);
    if (x != null && y != null) return x.start < y.end && y.start < x.end;
    return a.course.startSection <= b.course.endSection &&
        b.course.startSection <= a.course.endSection;
  }
}

List<int> parseWeekNumbers(String text) {
  final result = <int>{};
  for (final part
      in text
          .replaceAll('，', ',')
          .split(RegExp(r'[,\s]+'))
          .where((s) => s.isNotEmpty)) {
    final m = RegExp(r'^(\d+)(?:[-–](\d+))?$').firstMatch(part);
    if (m == null) throw const FormatException('周次示例：1-16,18');
    final start = int.parse(m[1]!), end = int.parse(m[2] ?? m[1]!);
    if (start < 1 || end > 60 || end < start) {
      throw const FormatException('周次需为 1–60，起始周不能晚于结束周');
    }
    result.addAll(List.generate(end - start + 1, (i) => start + i));
  }
  if (result.isEmpty) throw const FormatException('请填写上课周次');
  return result.toList()..sort();
}
