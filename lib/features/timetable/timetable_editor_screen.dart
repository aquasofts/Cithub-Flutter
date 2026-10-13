import '../../core/logging/runtime_audit.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/chinese_text_selection.dart';
import '../../core/storage/local_database.dart' show localId;
import 'timetable_repository.dart';
import 'timetable_time.dart';

Future<void> editTimetableCourse(
  BuildContext context,
  ScheduleSnapshot? schedule, [
  LocalCourse? course,
]) => Navigator.of(context).push<void>(
  LoggedMaterialPageRoute(
    builder: (_) => CourseEditorScreen(schedule: schedule, course: course),
  ),
);

class TimetableEditorScreen extends ConsumerWidget {
  const TimetableEditorScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeScheduleProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('修改课表'),
        actions: [
          IconButton(
            tooltip: '新增课程',
            icon: const Icon(Icons.add),
            onPressed: () => editTimetableCourse(context, active.valueOrNull),
          ),
        ],
      ),
      body: active.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('课表读取失败，请返回重试')),
        data: (schedule) {
          if (schedule == null) {
            return Center(
              child: FilledButton.icon(
                onPressed: () => editTimetableCourse(context, null),
                icon: const Icon(Icons.add),
                label: const Text('新建课表并添加课程'),
              ),
            );
          }
          final clock = TimetableTime(schedule);
          final available =
              ref.watch(schedulesProvider).valueOrNull ?? [schedule];
          final schedules = available.any((s) => s.id == schedule.id)
              ? available
              : [schedule, ...available];
          final list = [...schedule.courses]
            ..sort((a, b) {
              final day = a.course.dayOfWeek.compareTo(b.course.dayOfWeek);
              return day != 0
                  ? day
                  : a.course.startSection.compareTo(b.course.startSection);
            });
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButton<String>(
                isExpanded: true,
                value: schedule.id,
                items: schedules
                    .map(
                      (s) => DropdownMenuItem(
                        value: s.id,
                        child: Text(
                          s.data.selectedTerm.isEmpty
                              ? '导入课表'
                              : s.data.selectedTerm,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (id) async {
                  if (id == null) return;
                  await ref.read(timetableRepositoryProvider).select(id);
                  ref.read(localRevisionProvider.notifier).state++;
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule),
                title: const Text('节次时间'),
                subtitle: const Text('设置每一节的上下课时间'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  LoggedMaterialPageRoute<void>(
                    builder: (_) => SectionTimesScreen(schedule: schedule),
                  ),
                ),
              ),
              const Text('修改仅保存在本机，可从课表历史恢复。'),
              const SizedBox(height: 12),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('暂无课程，点击右上角添加。'),
                ),
              for (final course in list)
                Card(
                  child: ListTile(
                    title: Text(course.course.name),
                    subtitle: Text(
                      '周${'一二三四五六日'[course.course.dayOfWeek - 1]} · 第${course.course.startSection}–${course.course.endSection}节\n${clock.course(course)?.label ?? '时间未设置'} · ${course.course.location}\n第${course.course.weekNumbers.join('、')}周',
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => editTimetableCourse(context, schedule, course),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class CourseEditorScreen extends ConsumerStatefulWidget {
  const CourseEditorScreen({super.key, required this.schedule, this.course});
  final ScheduleSnapshot? schedule;
  final LocalCourse? course;
  @override
  ConsumerState<CourseEditorScreen> createState() => _CourseEditorScreenState();
}

class _CourseEditorScreenState extends ConsumerState<CourseEditorScreen> {
  late final TextEditingController _term,
      _name,
      _room,
      _teacher,
      _first,
      _last,
      _weeks,
      _start,
      _end;
  int _day = 1, _weekMode = 0;
  bool _customTime = false, _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final course = widget.course;
    final time = widget.schedule == null || course == null
        ? null
        : TimetableTime(widget.schedule!).course(course);
    _term = TextEditingController(text: widget.schedule?.data.selectedTerm);
    _name = TextEditingController(text: course?.course.name);
    _room = TextEditingController(text: course?.course.location);
    _teacher = TextEditingController(text: course?.course.teacher);
    _first = TextEditingController(text: '${course?.course.startSection ?? 1}');
    _last = TextEditingController(text: '${course?.course.endSection ?? 2}');
    _weeks = TextEditingController(
      text: course == null
          ? '1-16'
          : course.course.weekNumbers.isEmpty
          ? '1-${widget.schedule?.data.totalWeeks ?? 20}'
          : course.course.weekNumbers.join(','),
    );
    _day = course?.course.dayOfWeek ?? 1;
    _customTime = course?.startTime != null;
    _start = TextEditingController(
      text: course?.startTime ?? (time == null ? '' : clockLabel(time.start)),
    );
    _end = TextEditingController(
      text: course?.endTime ?? (time == null ? '' : clockLabel(time.end)),
    );
  }

  @override
  void dispose() {
    for (final c in [
      _term,
      _name,
      _room,
      _teacher,
      _first,
      _last,
      _weeks,
      _start,
      _end,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? helper,
    bool number = false,
    bool readOnly = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: TextField(
      controller: controller,
      readOnly: readOnly,
      contextMenuBuilder: chineseEditableTextMenu,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 3,
      ),
    ),
  );

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_term.text.trim().isEmpty) throw const FormatException('请填写学期');
      var weeks = parseWeekNumbers(_weeks.text);
      if (_weekMode != 0) {
        weeks = weeks
            .where((w) => _weekMode == 1 ? w.isOdd : w.isEven)
            .toList();
      }
      if (weeks.isEmpty) throw const FormatException('筛选后没有上课周次');
      final first = int.tryParse(_first.text), last = int.tryParse(_last.text);
      if (first == null || last == null) throw const FormatException('请填写有效节次');
      if (_customTime && LessonTime.parse(_start.text, _end.text) == null) {
        throw const FormatException('请填写有效的开始、结束时间，例如 08:00、09:35');
      }
      final old = widget.course;
      final id = old?.id ?? localId();
      final course = LocalCourse(
        id: id,
        source: old?.source ?? 'manual',
        course: courseFromJson({
          'id': old?.course.id ?? id,
          'name': _name.text.trim(),
          'location': _room.text.trim(),
          'teacher': _teacher.text.trim(),
          'dayOfWeek': _day,
          'startSection': first,
          'endSection': last,
          'weekNumbers': weeks,
        }),
        startTime: _customTime ? clockLabel(clockMinutes(_start.text)!) : null,
        endTime: _customTime ? clockLabel(clockMinutes(_end.text)!) : null,
      );
      final snapshot =
          widget.schedule ??
          ScheduleSnapshot(
            id: localId(),
            revision: 0,
            data: timetableFromJson({
              'selectedTerm': _term.text.trim(),
              'courses': [],
            }),
          );
      await ref
          .read(timetableRepositoryProvider)
          .putCourse(
            snapshot.copyWith(
              data: timetableFromJson(
                timetableJson(snapshot.data)
                  ..['selectedTerm'] = _term.text.trim(),
              ),
            ),
            course,
          );
      ref.read(localRevisionProvider.notifier).state++;
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is FormatException
              ? e.message
              : e is StateError
              ? e.message.toString()
              : '保存失败，请重试',
        );
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_error!)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这门课程？'),
        content: Text(widget.course!.course.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(timetableRepositoryProvider)
          .removeCourse(widget.schedule!, widget.course!);
      ref.read(localRevisionProvider.notifier).state++;
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is StateError ? e.message.toString() : '删除失败，请重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.course == null ? '新增课程' : '编辑课程'),
      actions: [
        if (widget.course != null)
          IconButton(
            tooltip: '删除课程',
            icon: const Icon(Icons.delete_outline),
            onPressed: _busy ? null : _delete,
          ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        _field(
          '学期',
          _term,
          readOnly: widget.schedule?.data.selectedTerm.isNotEmpty == true,
        ),
        _field('课程名称', _name),
        _field('教室', _room),
        _field('教师', _teacher),
        DropdownButtonFormField<int>(
          initialValue: _day,
          decoration: const InputDecoration(labelText: '星期'),
          items: List.generate(
            7,
            (i) => DropdownMenuItem(
              value: i + 1,
              child: Text('星期${'一二三四五六日'[i]}'),
            ),
          ),
          onChanged: _busy ? null : (v) => _day = v!,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: _field('开始节次', _first, number: true)),
            const SizedBox(width: 12),
            Expanded(child: _field('结束节次', _last, number: true)),
          ],
        ),
        _field('周次', _weeks, helper: '支持 1-16,18；单周或双周可在下方筛选'),
        DropdownButtonFormField<int>(
          initialValue: _weekMode,
          decoration: const InputDecoration(labelText: '单双周'),
          items: const [
            DropdownMenuItem(value: 0, child: Text('全部所选周次')),
            DropdownMenuItem(value: 1, child: Text('单周')),
            DropdownMenuItem(value: 2, child: Text('双周')),
          ],
          onChanged: _busy ? null : (v) => _weekMode = v!,
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('单独设置上课时间'),
          subtitle: const Text('用于错峰、提前或延后上课；关闭则跟随节次时间'),
          value: _customTime,
          onChanged: _busy
              ? null
              : (value) => setState(() {
                  if (value && !_customTime && widget.schedule != null) {
                    final clock = TimetableTime(widget.schedule!);
                    final first = clock.section(int.tryParse(_first.text) ?? 1);
                    final last = clock.section(int.tryParse(_last.text) ?? 2);
                    if (first != null) _start.text = clockLabel(first.start);
                    if (last != null) _end.text = clockLabel(last.end);
                  }
                  _customTime = value;
                }),
        ),
        if (_customTime)
          Row(
            children: [
              Expanded(child: _field('开始时间', _start, helper: '例如 08:00')),
              const SizedBox(width: 12),
              Expanded(child: _field('结束时间', _end, helper: '例如 09:35')),
            ],
          ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('保存课程'),
        ),
      ],
    ),
  );
}

class SectionTimesScreen extends ConsumerStatefulWidget {
  const SectionTimesScreen({super.key, required this.schedule});
  final ScheduleSnapshot schedule;
  @override
  ConsumerState<SectionTimesScreen> createState() => _SectionTimesScreenState();
}

class _SectionTimesScreenState extends ConsumerState<SectionTimesScreen> {
  late final List<(TextEditingController, TextEditingController)> _times;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final clock = TimetableTime(widget.schedule);
    _times = List.generate(clock.sectionCount, (i) {
      final time = clock.section(i + 1);
      return (
        TextEditingController(text: time == null ? '' : clockLabel(time.start)),
        TextEditingController(text: time == null ? '' : clockLabel(time.end)),
      );
    });
  }

  @override
  void dispose() {
    for (final pair in _times) {
      pair.$1.dispose();
      pair.$2.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final times = <String, dynamic>{};
      var last = -1;
      for (var i = 0; i < _times.length; i++) {
        final a = _times[i].$1.text.trim(), b = _times[i].$2.text.trim();
        if (a.isEmpty && b.isEmpty) continue;
        final time = LessonTime.parse(a, b);
        if (time == null || time.start < last) {
          throw FormatException('第${i + 1}节时间无效或与上一节重叠');
        }
        last = time.end;
        times['${i + 1}'] =
            '${clockLabel(time.start)}\n${clockLabel(time.end)}';
      }
      await ref
          .read(timetableRepositoryProvider)
          .save(
            widget.schedule.copyWith(sectionTimes: times),
            '修改节次时间',
            localId(),
          );
      ref.read(localRevisionProvider.notifier).state++;
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is FormatException ? e.message : '保存失败，课表可能已变化';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('节次时间')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('教务大节时间会拆成两节作为初始值，请按学校实际作息校正。未填写的节次沿用教务时间。'),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        for (var i = 0; i < _times.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                SizedBox(width: 48, child: Text('第${i + 1}节')),
                Expanded(
                  child: TextField(
                    controller: _times[i].$1,
                    contextMenuBuilder: chineseEditableTextMenu,
                    decoration: const InputDecoration(
                      labelText: '开始',
                      hintText: '08:00',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _times[i].$2,
                    contextMenuBuilder: chineseEditableTextMenu,
                    decoration: const InputDecoration(
                      labelText: '结束',
                      hintText: '08:45',
                    ),
                  ),
                ),
              ],
            ),
          ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('保存节次时间'),
        ),
      ],
    ),
  );
}
