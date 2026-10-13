import '../../core/logging/runtime_audit.dart';
import '../../core/logging/runtime_log.dart';

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/native/cithub_api.g.dart';
import '../../core/storage/local_database.dart';
import '../../core/settings/navigation_state.dart';
import '../settings/settings_screen.dart';
import '../ai/ai_screen.dart';
import '../timetable/academic_sync.dart';
import '../timetable/timetable_repository.dart';
import '../timetable/timetable_time.dart';
import '../timetable/timetable_editor_screen.dart';

class MineScreen extends ConsumerStatefulWidget {
  const MineScreen({super.key});
  @override
  ConsumerState<MineScreen> createState() => _MineScreenState();
}

class _MineScreenState extends ConsumerState<MineScreen> {
  int? _week;
  String? _scheduleId;
  bool _today = false;
  bool _firstUse = false;
  @override
  void initState() {
    super.initState();
    ref.listenManual<int>(mainTabProvider, (_, tab) {
      if (tab == 3) _onboard();
    }, fireImmediately: true);
  }

  bool _onboarded = false;
  Future<void> _onboard() async {
    if (_onboarded) return;
    _onboarded = true;
    try {
      final first = await ref
          .read(timetableRepositoryProvider)
          .consumeOnboarding();
      if (mounted) setState(() => _firstUse = first);
    } catch (_) {
      _onboarded = false;
    }
  }

  void _ai() => Navigator.of(context).push(
    LoggedMaterialPageRoute<void>(
      builder: (_) => const AiScreen(initialText: '请根据我提供的文字、图片或文件修改课表：'),
    ),
  );
  int currentWeek(TimetableDto data) {
    final date = DateTime.tryParse(data.referenceDateIso ?? '');
    if (date == null || data.referenceWeek == null) return 1;
    final now = ref.read(timetableNowProvider)();
    final monday = DateTime(date.year, date.month, date.day - date.weekday + 1);
    return (data.referenceWeek! +
            DateTime(now.year, now.month, now.day).difference(monday).inDays ~/
                7)
        .clamp(1, data.totalWeeks ?? 60);
  }

  DateTime? mondayFor(TimetableDto data, int week) {
    final date = DateTime.tryParse(data.referenceDateIso ?? '');
    return date == null || data.referenceWeek == null
        ? null
        : DateTime(
            date.year,
            date.month,
            date.day - date.weekday + 1 + (week - data.referenceWeek!) * 7,
          );
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(activeScheduleProvider);
    final syncError = ref.watch(academicSyncErrorProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的课表'),
        actions: [
          IconButton(
            tooltip: 'AI 导入',
            onPressed: _ai,
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
          IconButton(
            tooltip: '设置',
            onPressed: () => Navigator.of(context).push(
              LoggedMaterialPageRoute<void>(
                builder: (_) => const SettingsScreen(),
              ),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              final s = value.valueOrNull;
              if (v == 'sync') {
                await syncAcademicSchedule(context, ref, manual: true);
              }
              if (v == 'history' && s != null && context.mounted) {
                await Navigator.of(context).push(
                  LoggedMaterialPageRoute<void>(
                    builder: (_) => ScheduleHistoryScreen(scheduleId: s.id),
                  ),
                );
              }
              if (v == 'dates' && s != null) await _dates(s);
              if (v == 'times' && s != null) await _times(s);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'sync', child: Text('同步教务课表')),
              const PopupMenuItem(value: 'history', child: Text('历史版本')),
              const PopupMenuItem(value: 'dates', child: Text('设置学期起始日期')),
              const PopupMenuItem(value: 'times', child: Text('设置节次时间')),
            ],
          ),
        ],
      ),
      body: value.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('本地课表读取失败'),
              TextButton(
                onPressed: () => ref.invalidate(activeScheduleProvider),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        data: (s) {
          if (s == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_month_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _firstUse ? '第一次使用，请登录教务系统缓存课表' : '暂无本地课表',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    if (syncError != null) Text(syncError),
                    const Text(
                      '在“教务”页面登录，或使用 AI 导入文字、图片与文件。',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _ai,
                      icon: const Icon(Icons.add),
                      label: const Text('AI 导入课表'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (_scheduleId != s.id) {
            _scheduleId = s.id;
            _week = currentWeek(s.data);
          }
          final maxWeek = math.max(
            s.data.totalWeeks ?? 20,
            s.courses
                .expand((c) => c.course.weekNumbers)
                .fold<int>(1, math.max),
          );
          final week = (_week ?? 1).clamp(1, maxWeek);
          final monday = mondayFor(s.data, week);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      Expanded(
                        child: Consumer(
                          builder: (_, ref, _) {
                            final list =
                                ref.watch(schedulesProvider).valueOrNull ?? [s];
                            return DropdownButton<String>(
                              isExpanded: true,
                              isDense: true,
                              underline: const SizedBox(),
                              iconSize: 18,
                              value: list.any((v) => v.id == s.id)
                                  ? s.id
                                  : null,
                              selectedItemBuilder: (_) => list
                                  .map(
                                    (v) => Align(
                                      alignment: Alignment.centerLeft,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          v.data.selectedTerm.isEmpty
                                              ? '导入课表'
                                              : v.data.selectedTerm,
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              items: list
                                  .map(
                                    (v) => DropdownMenuItem(
                                      value: v.id,
                                      child: Text(
                                        '${v.data.selectedTerm.isEmpty ? '导入课表' : v.data.selectedTerm}${v.account != null ? ' · ${v.account}' : ''}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (id) async {
                                if (id == null) return;
                                await ref
                                    .read(timetableRepositoryProvider)
                                    .select(id);
                                ref
                                    .read(localRevisionProvider.notifier)
                                    .state++;
                              },
                            );
                          },
                        ),
                      ),
                      SizedBox(
                        width: 32,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: 22,
                          tooltip: '上一周',
                          onPressed: week > 1
                              ? () => setState(() => _week = week - 1)
                              : null,
                          icon: const Icon(Icons.chevron_left),
                        ),
                      ),
                      SizedBox(
                        width: 70,
                        child: DropdownButton<int>(
                          value: week,
                          isExpanded: true,
                          isDense: true,
                          underline: const SizedBox(),
                          iconSize: 18,
                          items: List.generate(
                            maxWeek,
                            (i) => DropdownMenuItem(
                              value: i + 1,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '第${i + 1}周',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                          ),
                          onChanged: (v) => setState(() => _week = v),
                        ),
                      ),
                      SizedBox(
                        width: 32,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: 22,
                          tooltip: '下一周',
                          onPressed: week < maxWeek
                              ? () => setState(() => _week = week + 1)
                              : null,
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                          ),
                          onPressed: () =>
                              setState(() => _week = currentWeek(s.data)),
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('本周', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 36,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: 22,
                          tooltip: _today ? '整周课表' : '今日列表',
                          onPressed: () => setState(() => _today = !_today),
                          icon: Icon(
                            _today
                                ? Icons.calendar_view_week
                                : Icons.view_agenda_outlined,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (syncError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    syncError,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (monday != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${monday.year}/${monday.month}/${monday.day} — ${monday.add(const Duration(days: 6)).month}/${monday.add(const Duration(days: 6)).day}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              if (monday == null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('尚未设置学期日期', style: TextStyle(fontSize: 12)),
                      ),
                      TextButton(
                        onPressed: () => _dates(s),
                        child: const Text('设置日期'),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: _today
                    ? _todayList(s, week)
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          const axisWidth = 42.0;
                          const headerHeight = 48.0;
                          final rowHeight = math.max(
                            64.0,
                            (constraints.maxHeight - headerHeight - 1) /
                                math.min(9, sections(s)),
                          );
                          return Column(
                            children: [
                              SizedBox(
                                height: headerHeight,
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: axisWidth,
                                      child: Text(
                                        monday == null
                                            ? '节次'
                                            : '${monday.month}月',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ),
                                    for (var i = 0; i < 7; i++)
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              '一二三四五六日'[i],
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                            Builder(
                                              builder: (context) {
                                                final date = monday?.add(
                                                  Duration(days: i),
                                                );
                                                final today =
                                                    date != null &&
                                                    DateUtils.isSameDay(
                                                      date,
                                                      ref.read(
                                                        timetableNowProvider,
                                                      )(),
                                                    );
                                                final scheme = Theme.of(context)
                                                    .colorScheme;
                                                return Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 4,
                                                        vertical: 2,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: today
                                                        ? scheme
                                                              .primaryContainer
                                                        : null,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    date == null
                                                        ? '—'
                                                        : '${date.day}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: today
                                                          ? scheme
                                                                .onPrimaryContainer
                                                          : null,
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                              Expanded(
                                child:
                                    NotificationListener<
                                      UserScrollNotification
                                    >(
                                      onNotification: (notification) {
                                        RuntimeLog.event(
                                          'schedule',
                                          'grid-scroll',
                                          {
                                            'direction':
                                                notification.direction.name,
                                            'offset':
                                                notification.metrics.pixels,
                                            'week': week,
                                            'scheduleId': s.id,
                                          },
                                        );
                                        return false;
                                      },
                                      child: SingleChildScrollView(
                                        key: const Key('schedule-grid-scroll'),
                                        child: SizedBox(
                                          height: sections(s) * rowHeight,
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              SizedBox(
                                                width: axisWidth,
                                                child: _timeAxis(s, rowHeight),
                                              ),
                                              Expanded(
                                                child: _grid(
                                                  s,
                                                  week,
                                                  rowHeight,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  int sections(ScheduleSnapshot s) => TimetableTime(s).sectionCount;
  Widget _timeAxis(ScheduleSnapshot s, double rowHeight) => Column(
    children: List.generate(sections(s), (i) {
      final section = i + 1;
      final interval = TimetableTime(s).section(section);
      final time = interval == null
          ? ''
          : '${clockLabel(interval.start)}\n${clockLabel(interval.end)}';
      return SizedBox(
        height: rowHeight,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              children: [
                Text('$section', style: Theme.of(context).textTheme.titleSmall),
                if (time.trim().isNotEmpty)
                  Text(
                    time,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall,
                    maxLines: 2,
                    softWrap: false,
                  ),
              ],
            ),
          ),
        ),
      );
    }),
  );
  Widget _grid(ScheduleSnapshot s, int week, double height) {
    final clock = TimetableTime(s);
    return SizedBox(
      height: sections(s) * height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(
          7,
          (i) => Expanded(
            child: LayoutBuilder(
              builder: (context, size) {
                final all =
                    s.courses.where((c) => c.course.dayOfWeek == i + 1).toList()
                      ..sort(
                        (a, b) => a.course.startSection.compareTo(
                          b.course.startSection,
                        ),
                      );
                bool active(LocalCourse c) =>
                    c.course.weekNumbers.isEmpty ||
                    c.course.weekNumbers.contains(week);
                bool overlaps(LocalCourse a, LocalCourse b) =>
                    clock.overlaps(a, b);
                final shown = all.where(active).toList();
                final lanes = <String, int>{};
                final occupied = <List<LocalCourse>>[];
                for (final c in shown) {
                  var lane = occupied.indexWhere(
                    (list) => !list.any((v) => overlaps(c, v)),
                  );
                  if (lane < 0) {
                    lane = occupied.length;
                    occupied.add([]);
                  }
                  occupied[lane].add(c);
                  lanes[c.id] = lane;
                }
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    for (var section = 0; section < sections(s); section++)
                      Positioned(
                        top: section * height,
                        left: 0,
                        right: 0,
                        child: Divider(
                          height: 1,
                          color: Theme.of(context).colorScheme.outlineVariant
                              .withValues(alpha: .25),
                        ),
                      ),
                    for (final c in shown) ...[
                      Builder(
                        builder: (_) {
                          final group = shown
                              .where((v) => overlaps(c, v))
                              .toList();
                          final count = group.fold<int>(
                            1,
                            (n, v) => math.max(n, lanes[v.id]! + 1),
                          );
                          final laneWidth = size.maxWidth / count;
                          final inactive = !active(c);
                          final scheme = Theme.of(context).colorScheme;
                          final hash = c.course.name.codeUnits.fold<int>(
                            0,
                            (a, b) => (a * 31 + b) & 0x7fffffff,
                          );
                          final hue =
                              (HSLColor.fromColor(scheme.primary).hue +
                                  (hash % 6) * 43) %
                              360;
                          final color = HSLColor.fromAHSL(
                            1,
                            hue,
                            .35,
                            Theme.of(context).brightness == Brightness.dark
                                ? .27
                                : .87,
                          ).toColor();
                          final bounds = clock.bounds(c);
                          return Positioned(
                            key: ValueKey('course-${c.id}'),
                            top: bounds.$1 * height,
                            left: lanes[c.id]! * laneWidth + 2,
                            width: laneWidth - 4,
                            height: math.max(
                              12.0,
                              (bounds.$2 - bounds.$1) * height - 4,
                            ),
                            child: Semantics(
                              button: true,
                              label:
                                  '${c.course.name} ${c.course.location}${inactive ? ' 非本周' : ''}',
                              child: Material(
                                color: inactive
                                    ? Color.alphaBlend(
                                        scheme.surface.withValues(alpha: .55),
                                        color,
                                      )
                                    : color,
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () => _details(
                                    [
                                      c,
                                      ...shown.where(
                                        (v) => v.id != c.id && overlaps(c, v),
                                      ),
                                    ],
                                    week,
                                    s,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: LayoutBuilder(
                                            builder: (context, bounds) {
                                              final fontSize =
                                                  bounds.maxWidth < 30
                                                  ? 9.5
                                                  : 11.5;
                                              final title = Text(
                                                c.course.name,
                                                maxLines: math.max(
                                                  1,
                                                  (bounds.maxHeight /
                                                          (fontSize * 1.25))
                                                      .floor(),
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: fontSize,
                                                  height: 1.25,
                                                  fontWeight: FontWeight.w600,
                                                  color: scheme.onSurface,
                                                ),
                                              );
                                              if (bounds.maxHeight < 48 ||
                                                  c.course.location.isEmpty) {
                                                return title;
                                              }
                                              return Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Expanded(child: title),
                                                  Text(
                                                    c.course.location,
                                                    maxLines:
                                                        bounds.maxHeight < 80
                                                        ? 1
                                                        : 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: math.max(
                                                        9,
                                                        fontSize - 1,
                                                      ),
                                                      height: 1.2,
                                                      color: scheme.onSurface
                                                          .withValues(
                                                            alpha: .75,
                                                          ),
                                                    ),
                                                  ),
                                                ],
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _todayList(ScheduleSnapshot s, int week) {
    final items =
        s.courses
            .where(
              (c) =>
                  c.course.dayOfWeek ==
                      ref.read(timetableNowProvider)().weekday &&
                  (c.course.weekNumbers.isEmpty ||
                      c.course.weekNumbers.contains(week)),
            )
            .toList()
          ..sort(
            (a, b) => a.course.startSection.compareTo(b.course.startSection),
          );
    if (items.isEmpty) return const Center(child: Text('当天暂无课程'));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final c = items[i].course;
        return Card(
          child: ListTile(
            title: Text(c.name),
            subtitle: Text(
              '${c.startSection}–${c.endSection}节 · ${TimetableTime(s).course(items[i])?.label ?? '时间未设置'} · ${c.location}',
            ),
            onTap: () => _details([items[i]], week, s),
          ),
        );
      },
    );
  }

  Future<void> _details(
    List<LocalCourse> courses,
    int week,
    ScheduleSnapshot schedule,
  ) => RuntimeLog.trace(
    'schedule',
    'course-details',
    {
      'scheduleId': schedule.id,
      'week': week,
      'courses': courses.map((c) => c.toJson()).toList(),
    },
    () => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in courses) ...[
                Text(
                  item.course.name,
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  '星期${'一二三四五六日'[item.course.dayOfWeek - 1]} · ${item.course.startSection}–${item.course.endSection}节',
                ),
                Text(
                  '上课时间：${TimetableTime(schedule).course(item)?.label ?? '未设置'}',
                ),
                Text(
                  '教室：${item.course.location.isEmpty ? '待定' : item.course.location}',
                ),
                Text(
                  '教师：${item.course.teacher.isEmpty ? '待定' : item.course.teacher}',
                ),
                Text(
                  '周次：${item.course.weekNumbers.isEmpty
                      ? item.course.weeks.isEmpty
                            ? '每周'
                            : item.course.weeks
                      : item.course.weekNumbers.join('、')}',
                ),
                if (item.course.weekNumbers.isNotEmpty &&
                    !item.course.weekNumbers.contains(week))
                  const Text('非本周'),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    editTimetableCourse(context, schedule, item);
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('手动编辑这门课'),
                ),
                const Divider(height: 32),
              ],
              FilledButton.tonal(
                onPressed: () {
                  Navigator.pop(ctx);
                  _ai();
                },
                child: const Text('用 AI 修改课表'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Future<void> _dates(ScheduleSnapshot s) async {
    final date = await showDatePicker(
      context: context,
      initialDate: mondayFor(s.data, 1) ?? ref.read(timetableNowProvider)(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
      helpText: '选择第1周周一',
    );
    if (date == null || !mounted) return;
    if (date.weekday != DateTime.monday) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请选择第1周的周一')));
      return;
    }
    try {
      await ref
          .read(timetableRepositoryProvider)
          .save(
            s.copyWith(
              data: timetableFromJson(
                timetableJson(s.data)
                  ..['referenceDateIso'] = date.toIso8601String()
                  ..['referenceWeek'] = 1,
              ),
            ),
            '设置学期起始日期',
            localId(),
          );
      ref.read(localRevisionProvider.notifier).state++;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('保存失败，请重新打开课表后重试')));
      }
    }
  }

  Future<void> _times(ScheduleSnapshot s) => Navigator.of(context).push<void>(
    LoggedMaterialPageRoute(builder: (_) => SectionTimesScreen(schedule: s)),
  );
}

class ScheduleHistoryScreen extends ConsumerWidget {
  const ScheduleHistoryScreen({super.key, required this.scheduleId});
  final String scheduleId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(localRevisionProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('课表历史'),
        actions: [
          IconButton(
            tooltip: '清理历史',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final yes = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('清理历史版本？'),
                  content: const Text('保留当前版本，其他版本将无法恢复。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('清理'),
                    ),
                  ],
                ),
              );
              if (yes == true) {
                await ref
                    .read(timetableRepositoryProvider)
                    .clearHistory(scheduleId);
                ref.read(localRevisionProvider.notifier).state++;
              }
            },
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: ref.read(timetableRepositoryProvider).history(scheduleId),
        builder: (ctx, value) {
          if (value.hasError) return const Center(child: Text('历史读取失败'));
          if (!value.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView.builder(
            itemCount: value.data!.length,
            itemBuilder: (_, i) {
              final v = value.data![i];
              return ListTile(
                title: Text('版本 ${v['revision']} · ${v['summary']}'),
                subtitle: Text(
                  DateTime.parse(v['created_at'] as String)
                      .toLocal()
                      .toString()
                      .split('.')
                      .first,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final version = ScheduleSnapshot.fromJson(
                    jsonDecode(v['body'] as String) as Map<String, dynamic>,
                  );
                  final current =
                      (await ref.read(timetableRepositoryProvider).all())
                          .firstWhere((s) => s.id == scheduleId);
                  final previous = {for (final c in current.courses) c.id: c};
                  final chosen = {for (final c in version.courses) c.id: c};
                  final diff = <String>[
                    for (final c in version.courses)
                      if (!previous.containsKey(c.id))
                        '新增：${c.course.name}'
                      else if (jsonEncode(courseJson(previous[c.id]!.course)) !=
                          jsonEncode(courseJson(c.course)))
                        '修改：${c.course.name}',
                    for (final c in current.courses)
                      if (!chosen.containsKey(c.id)) '删除：${c.course.name}',
                  ];
                  if (!ctx.mounted) return;
                  final yes = await showDialog<bool>(
                    context: ctx,
                    builder: (dialog) => AlertDialog(
                      title: Text('版本 ${version.revision}'),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: SingleChildScrollView(
                          child: Text(
                            '${diff.isEmpty ? '课程内容相同' : diff.join('\n')}\n\n${version.courses.map((c) => '${c.course.name} · 星期${c.course.dayOfWeek} · ${c.course.startSection}-${c.course.endSection}节').join('\n')}',
                          ),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialog, false),
                          child: const Text('关闭'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialog, true),
                          child: const Text('恢复此版本'),
                        ),
                      ],
                    ),
                  );
                  if (yes == true) {
                    await ref
                        .read(timetableRepositoryProvider)
                        .restore(version);
                    ref.read(localRevisionProvider.notifier).state++;
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}
