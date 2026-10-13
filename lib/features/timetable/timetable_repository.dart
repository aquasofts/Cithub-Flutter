import 'dart:convert';

export '../../core/storage/local_database.dart' show localRevisionProvider;

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/native/cithub_api.g.dart';
import '../../core/storage/local_database.dart';

Map<String, dynamic> courseJson(TimetableCourseDto c) => {
  'id': c.id,
  'dayOfWeek': c.dayOfWeek,
  'periodIndex': c.periodIndex,
  'startSection': c.startSection,
  'endSection': c.endSection,
  'name': c.name,
  'teacher': c.teacher,
  'weeks': c.weeks,
  'weekNumbers': c.weekNumbers,
  'location': c.location,
};
TimetableCourseDto courseFromJson(Map<String, dynamic> c) => TimetableCourseDto(
  id: c['id'] as String? ?? localId(),
  dayOfWeek: (c['dayOfWeek'] as num).toInt(),
  periodIndex:
      (c['periodIndex'] as num?)?.toInt() ??
      ((c['startSection'] as num).toInt() + 1) ~/ 2,
  startSection: (c['startSection'] as num).toInt(),
  endSection: (c['endSection'] as num).toInt(),
  name: c['name'] as String,
  teacher: c['teacher'] as String? ?? '',
  weeks: c['weeks'] as String? ?? '',
  weekNumbers: (c['weekNumbers'] as List? ?? [])
      .map((v) => (v as num).toInt())
      .toList(),
  location: c['location'] as String? ?? '',
);
Map<String, dynamic> timetableJson(TimetableDto t) => {
  'terms': t.terms
      .map((v) => {'value': v.value, 'label': v.label, 'selected': v.selected})
      .toList(),
  'selectedTerm': t.selectedTerm,
  'periods': t.periods
      .map(
        (p) => {
          'index': p.index,
          'label': p.label,
          'startTime': p.startTime,
          'endTime': p.endTime,
        },
      )
      .toList(),
  'courses': t.courses.map(courseJson).toList(),
  'note': t.note,
  'referenceDateIso': t.referenceDateIso,
  'referenceWeek': t.referenceWeek,
  'totalWeeks': t.totalWeeks,
};
TimetableDto timetableFromJson(Map<String, dynamic> t) => TimetableDto(
  terms: (t['terms'] as List? ?? [])
      .map(
        (v) => AcademicTermDto(
          value: v['value'] as String,
          label: v['label'] as String,
          selected: v['selected'] == true,
        ),
      )
      .toList(),
  selectedTerm: t['selectedTerm'] as String? ?? '',
  periods: (t['periods'] as List? ?? [])
      .map(
        (p) => TimetablePeriodDto(
          index: (p['index'] as num).toInt(),
          label: p['label'] as String,
          startTime: p['startTime'] as String,
          endTime: p['endTime'] as String,
        ),
      )
      .toList(),
  courses: (t['courses'] as List? ?? [])
      .map((v) => courseFromJson(Map<String, dynamic>.from(v as Map)))
      .toList(),
  note: t['note'] as String? ?? '',
  referenceDateIso: t['referenceDateIso'] as String?,
  referenceWeek: (t['referenceWeek'] as num?)?.toInt(),
  totalWeeks: (t['totalWeeks'] as num?)?.toInt(),
);

class LocalCourse {
  LocalCourse({required this.id, required this.source, required this.course});
  final String id;
  final String source;
  final TimetableCourseDto course;
  Map<String, dynamic> toJson() => {
    'localId': id,
    'source': source,
    'course': courseJson(course),
  };
  factory LocalCourse.fromJson(Map<String, dynamic> v) => LocalCourse(
    id: v['localId'] as String,
    source: v['source'] as String,
    course: courseFromJson(Map<String, dynamic>.from(v['course'] as Map)),
  );
}

class ScheduleSnapshot {
  ScheduleSnapshot({
    required this.id,
    required this.revision,
    required this.data,
    this.account,
    this.courses = const [],
    this.official = const [],
    this.edits = const {},
    this.sectionTimes = const {},
  });
  final String id;
  final int revision;
  final String? account;
  final TimetableDto data;
  final List<LocalCourse> courses;
  final List<LocalCourse> official;
  final Map<String, dynamic> edits;
  final Map<String, dynamic> sectionTimes;
  Map<String, dynamic> toJson() => {
    'id': id,
    'revision': revision,
    'account': account,
    'data': timetableJson(data),
    'courses': courses.map((v) => v.toJson()).toList(),
    'official': official.map((v) => v.toJson()).toList(),
    'edits': edits,
    'sectionTimes': sectionTimes,
  };
  factory ScheduleSnapshot.fromJson(Map<String, dynamic> v) => ScheduleSnapshot(
    id: v['id'] as String,
    revision: v['revision'] as int? ?? 0,
    account: v['account'] as String?,
    data: timetableFromJson(Map<String, dynamic>.from(v['data'] as Map)),
    courses: (v['courses'] as List)
        .map((c) => LocalCourse.fromJson(Map<String, dynamic>.from(c as Map)))
        .toList(),
    official: (v['official'] as List? ?? [])
        .map((c) => LocalCourse.fromJson(Map<String, dynamic>.from(c as Map)))
        .toList(),
    edits: Map<String, dynamic>.from(v['edits'] as Map? ?? {}),
    sectionTimes: Map<String, dynamic>.from(v['sectionTimes'] as Map? ?? {}),
  );
  ScheduleSnapshot copyWith({
    int? revision,
    String? account,
    TimetableDto? data,
    List<LocalCourse>? courses,
    List<LocalCourse>? official,
    Map<String, dynamic>? edits,
    Map<String, dynamic>? sectionTimes,
  }) => ScheduleSnapshot(
    id: id,
    revision: revision ?? this.revision,
    account: account ?? this.account,
    data: data ?? this.data,
    courses: courses ?? this.courses,
    official: official ?? this.official,
    edits: edits ?? this.edits,
    sectionTimes: sectionTimes ?? this.sectionTimes,
  );
  TimetableDto get visibleData {
    final json = timetableJson(data);
    json['courses'] = courses.map((v) => courseJson(v.course)).toList();
    return timetableFromJson(json);
  }
}

String academicFingerprint(TimetableDto t) {
  final rows = t.courses.map((c) {
    final v = courseJson(c)..remove('id');
    v['weekNumbers'] = [...c.weekNumbers]..sort();
    return jsonEncode(v);
  }).toList()..sort();
  final periods =
      t.periods.map((p) => '${p.index}|${p.startTime}|${p.endTime}').toList()
        ..sort();
  return sha256
      .convert(
        utf8.encode(jsonEncode([t.selectedTerm, periods, rows, t.totalWeeks])),
      )
      .toString();
}

final timetableNowProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

final timetableRepositoryProvider = Provider<TimetableRepository>(
  (ref) => TimetableRepository(ref.watch(localDatabaseProvider)),
);
final schedulesProvider = FutureProvider<List<ScheduleSnapshot>>((ref) {
  ref.watch(localRevisionProvider);
  return ref.read(timetableRepositoryProvider).all();
});
final activeScheduleProvider = FutureProvider<ScheduleSnapshot?>((ref) {
  ref.watch(localRevisionProvider);
  return ref.read(timetableRepositoryProvider).active();
});

class TimetableRepository {
  TimetableRepository(this.store);
  final LocalDatabase store;
  Future<List<ScheduleSnapshot>> all() async =>
      (await (await store.database).query(
            'schedules',
            orderBy: 'revision DESC',
          ))
          .map(
            (r) => ScheduleSnapshot.fromJson(
              jsonDecode(r['body'] as String) as Map<String, dynamic>,
            ),
          )
          .toList();
  Future<ScheduleSnapshot?> active() async {
    final id = await store.getMeta('schedule.active');
    final list = await all();
    return list.where((s) => s.id == id).firstOrNull ?? list.firstOrNull;
  }

  Future<void> select(String id) => store.setMeta('schedule.active', id);
  Future<bool> consumeOnboarding() async {
    final first = await store.getMeta('schedule.onboarded') == null;
    if (first) await store.setMeta('schedule.onboarded', 'true');
    return first;
  }

  Future<ScheduleSnapshot?> forAcademic(String account, String term) async {
    final rows = await all();
    return rows
            .where((s) => s.account == account && s.data.selectedTerm == term)
            .firstOrNull ??
        rows
            .where(
              (s) =>
                  s.account == null &&
                  (s.data.selectedTerm == term || s.data.selectedTerm.isEmpty),
            )
            .firstOrNull;
  }

  Future<ScheduleSnapshot> save(
    ScheduleSnapshot snapshot,
    String summary,
    String operationId,
  ) async {
    final db = await store.database;
    return db.transaction((txn) async {
      final duplicate = await txn.query(
        'schedule_versions',
        where: 'operation_id = ?',
        whereArgs: [operationId],
      );
      if (duplicate.isNotEmpty) {
        return ScheduleSnapshot.fromJson(
          jsonDecode(duplicate.first['body'] as String) as Map<String, dynamic>,
        );
      }
      final existing = await txn.query(
        'schedules',
        where: 'id = ?',
        whereArgs: [snapshot.id],
      );
      final currentRevision = existing.isEmpty
          ? 0
          : existing.first['revision'] as int;
      if (currentRevision != snapshot.revision) {
        throw StateError('课表已发生变化，请重新读取后再修改');
      }
      validate(snapshot);
      final revision = await txn.insert('schedule_versions', {
        'schedule_id': snapshot.id,
        'body': jsonEncode(snapshot.toJson()),
        'summary': summary,
        'created_at': DateTime.now().toIso8601String(),
        'operation_id': operationId,
      });
      final saved = snapshot.copyWith(revision: revision);
      await txn.update(
        'schedule_versions',
        {'body': jsonEncode(saved.toJson())},
        where: 'revision = ?',
        whereArgs: [revision],
      );
      await txn.insert('schedules', {
        'id': saved.id,
        'revision': revision,
        'body': jsonEncode(saved.toJson()),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('meta', {
        'key': 'schedule.active',
        'value': saved.id,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return saved;
    });
  }

  void validate(ScheduleSnapshot s) {
    for (final item in s.courses) {
      final c = item.course;
      if (c.name.trim().isEmpty ||
          c.dayOfWeek < 1 ||
          c.dayOfWeek > 7 ||
          c.startSection < 1 ||
          c.endSection < c.startSection ||
          c.endSection > 30 ||
          c.weekNumbers.any((w) => w < 1 || w > 60)) {
        throw const FormatException('课程名称、星期、节次或周次无效');
      }
    }
    if (s.courses.map((c) => c.id).toSet().length != s.courses.length) {
      throw const FormatException('课程编号重复');
    }
  }

  Future<ScheduleSnapshot> importAcademic(
    String account,
    TimetableDto data, {
    List<String> preserve = const [],
    int? expectedRevision,
    String? operationId,
  }) async {
    final old = await forAcademic(account, data.selectedTerm);
    if (expectedRevision != null && (old?.revision ?? 0) != expectedRevision) {
      throw StateError('课表已发生变化，请重新读取');
    }
    final base =
        old ??
        ScheduleSnapshot(
          id: localId(),
          revision: 0,
          data: data,
          account: account,
        );
    final official = <LocalCourse>[];
    final used = <String>{};
    for (final c in data.courses) {
      var matches = base.official
          .where((v) => v.course.id == c.id && !used.contains(v.id))
          .toList();
      if (matches.isEmpty) {
        matches = base.official
            .where(
              (v) =>
                  v.course.name == c.name &&
                  v.course.teacher == c.teacher &&
                  v.course.dayOfWeek == c.dayOfWeek &&
                  v.course.startSection == c.startSection &&
                  !used.contains(v.id),
            )
            .toList();
      }
      if (matches.isEmpty) {
        matches = base.official
            .where(
              (v) =>
                  v.course.name == c.name &&
                  v.course.teacher == c.teacher &&
                  !used.contains(v.id),
            )
            .toList();
      }
      if (matches.length > 1 && matches.any((m) => preserve.contains(m.id))) {
        throw StateError('课程“${c.name}”对应多条记录，请明确保留哪一条操作');
      }
      final id = matches.length == 1 ? matches.first.id : localId();
      used.add(id);
      official.add(LocalCourse(id: id, source: 'academic', course: c));
    }
    final edits = <String, dynamic>{};
    for (final id in preserve) {
      if (!base.edits.containsKey(id)) throw StateError('找不到要保留的修改：$id');
      if (!official.any((c) => c.id == id) &&
          base.edits[id]['op'] != 'delete') {
        throw StateError('修改的课程已不在新课表中，请明确处理方式');
      }
      edits[id] = base.edits[id];
    }
    final courses = [
      ...official
          .where((c) => edits[c.id]?['op'] != 'delete')
          .map(
            (c) => edits[c.id]?['op'] == 'update'
                ? LocalCourse(
                    id: c.id,
                    source: 'academic',
                    course: courseFromJson(
                      Map<String, dynamic>.from(edits[c.id]['course'] as Map),
                    ),
                  )
                : c,
          ),
      ...base.courses.where((c) => c.source == 'ai'),
    ];
    return save(
      base.copyWith(
        account: account,
        data: data,
        courses: courses,
        official: official,
        edits: edits,
      ),
      preserve.isEmpty ? '更新教务课表' : '更新教务课表并保留指定修改',
      operationId ?? localId(),
    );
  }

  Future<List<Map<String, Object?>>> history(String id) async =>
      (await store.database).query(
        'schedule_versions',
        where: 'schedule_id = ?',
        whereArgs: [id],
        orderBy: 'revision DESC',
      );
  Future<ScheduleSnapshot> restore(ScheduleSnapshot version) async {
    final current = (await all()).firstWhere((s) => s.id == version.id);
    return save(
      version.copyWith(revision: current.revision),
      '恢复到版本 ${version.revision}',
      localId(),
    );
  }

  Future<void> clearHistory(String id) async {
    final current = (await all()).firstWhere((s) => s.id == id);
    await (await store.database).delete(
      'schedule_versions',
      where: 'schedule_id = ? AND revision != ?',
      whereArgs: [id, current.revision],
    );
  }
}
