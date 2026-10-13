import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/native/cithub_api.g.dart';
import '../../core/platform/cithub_platform.dart';
import '../ai/ai_screen.dart';
import 'timetable_repository.dart';

final academicSessionProvider = StateProvider<WebVpnSessionDto?>((ref) => null);
final pendingAcademicProvider = StateProvider<TimetableDto?>((ref) => null);
final academicSyncErrorProvider = StateProvider<String?>((ref) => null);
final _syncing = <String>{};

Future<void> syncAcademicSchedule(
  BuildContext context,
  WidgetRef ref, {
  bool manual = false,
}) async {
  final session = ref.read(academicSessionProvider);
  if (session?.status != AuthStatus.signedIn) {
    if (manual && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先在“教务”页面登录教务系统')));
    }
    return;
  }
  final account = session!.user?.username;
  if (account == null || account.isEmpty || !_syncing.add(account)) return;
  try {
    ref.read(academicSyncErrorProvider.notifier).state = null;
    final data = await ref.read(cithubPlatformProvider).loadTimetable();
    if (!context.mounted) return;
    final repo = ref.read(timetableRepositoryProvider);
    final old = await repo.forAcademic(account, data.selectedTerm);
    if (!context.mounted) return;
    if (old == null || old.account == null) {
      await repo.importAcademic(account, data);
      ref.read(localRevisionProvider.notifier).state++;
      if (manual && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('课表已缓存到本机')));
      }
      return;
    }
    final original = timetableFromJson(
      timetableJson(old.data)
        ..['courses'] = old.official.map((c) => courseJson(c.course)).toList(),
    );
    if (academicFingerprint(original) == academicFingerprint(data)) {
      if (manual && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('课表已是最新')));
      }
      return;
    }
    if (!context.mounted) return;
    ref.read(pendingAcademicProvider.notifier).state = data;
    final answer = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('教务课表有更新'),
        content: const Text('更新将替换旧的教务课程及其修改记录，保留独立导入的课程。需要保留部分修改时，可以让 AI 合并。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'later'),
            child: const Text('暂不更新'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'ai'),
            child: const Text('让 AI 合并'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'update'),
            child: const Text('更新'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (answer == 'update') {
      await repo.importAcademic(account, data, expectedRevision: old.revision);
      ref.read(localRevisionProvider.notifier).state++;
      ref.read(pendingAcademicProvider.notifier).state = null;
    }
    if (answer == 'ai' && context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const AiScreen(initialText: '请更新教务课表。需要保留的修改是：'),
        ),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ref.read(academicSyncErrorProvider.notifier).state = '同步失败，已保留本地课表';
    }
    if (manual && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('同步失败，已保留本地课表，可稍后重试')));
    }
  } finally {
    _syncing.remove(account);
  }
}
