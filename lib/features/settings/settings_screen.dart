import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/platform/cithub_platform.dart';
import '../../core/native/cithub_api.g.dart';
import '../../core/settings/app_settings.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('设置')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _SettingsCard(
          children: [
            _SettingsLink(
              icon: Icons.palette_outlined,
              title: '外观',
              subtitle: '主题、自定义颜色、深色模式和动效',
              page: const AppearanceSettingsScreen(),
            ),
            _SettingsLink(
              icon: Icons.rss_feed,
              title: 'RSS 订阅',
              subtitle: '管理公众号与校内新闻源',
              page: const RssSettingsScreen(),
            ),
            _SettingsLink(
              icon: Icons.forum_outlined,
              title: '贴吧设置',
              subtitle: '浏览、图片、签到与关注偏好',
              page: const TiebaSettingsScreen(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SettingsCard(
          children: [
            _SettingsLink(
              icon: Icons.system_update_outlined,
              title: '应用更新',
              subtitle: '检查 Cithub-Flutter Releases',
              page: const UpdateSettingsScreen(),
            ),
            _SettingsLink(
              icon: Icons.description_outlined,
              title: '运行日志',
              subtitle: '仅本机保存，主动导出',
              page: const RuntimeLogScreen(),
            ),
          ],
        ),
      ],
    ),
  );
}

class AppearanceSettingsScreen extends ConsumerWidget {
  const AppearanceSettingsScreen({super.key});
  static const colors = [
    Color(0xff00639b),
    Color(0xff006b55),
    Color(0xff795900),
    Color(0xff904b40),
    Color(0xff735085),
    Color(0xff8e495e),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('外观')),
      body: ListView(
        children: [
          const _SectionTitle('主题模式'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('跟随系统'),
                  icon: Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('浅色'),
                  icon: Icon(Icons.light_mode),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('深色'),
                  icon: Icon(Icons.dark_mode),
                ),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (value) =>
                  controller.setThemeMode(value.first),
            ),
          ),
          SwitchListTile(
            title: const Text('AMOLED 纯黑'),
            subtitle: const Text('仅在深色模式下生效'),
            value: settings.amoled,
            onChanged: controller.setAmoled,
          ),
          const _SectionTitle('主题色'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 14,
              runSpacing: 14,
              children: colors
                  .map(
                    (color) => InkWell(
                      borderRadius: BorderRadius.circular(28),
                      onTap: () => controller.setSeedColor(color),
                      child: CircleAvatar(
                        radius: 24,
                        backgroundColor: color,
                        child: settings.seedColor.toARGB32() == color.toARGB32()
                            ? const Icon(Icons.check, color: Colors.white)
                            : null,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const _SectionTitle('界面'),
          SwitchListTile(
            title: const Text('紧凑底部导航'),
            subtitle: const Text('缩小导航栏高度'),
            value: settings.compactNavigation,
            onChanged: controller.setCompactNavigation,
          ),
          SwitchListTile(
            title: const Text('减少动效'),
            subtitle: const Text('缩短或关闭页面与主题动画'),
            value: settings.reduceMotion,
            onChanged: controller.setReduceMotion,
          ),
          SwitchListTile(
            title: const Text('跟随主题的应用图标'),
            subtitle: const Text('Android 13 及更高版本可用'),
            value: settings.themedIcon,
            onChanged: (value) async {
              final ok = await ref
                  .read(cithubPlatformProvider)
                  .setThemedIcon(value);
              if (ok) controller.setThemedIcon(value);
            },
          ),
        ],
      ),
    );
  }
}

class RssSettingsScreen extends StatefulWidget {
  const RssSettingsScreen({super.key});
  @override
  State<RssSettingsScreen> createState() => _RssSettingsScreenState();
}

class _RssSettingsScreenState extends State<RssSettingsScreen> {
  List<String> _wechat = [
    'https://cloudflare-rss-hub-pages.pages.dev/api/rss.xml',
  ];
  List<String> _campus = ['https://cit-news.pages.dev/rss.xml'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _wechat = prefs.getStringList('rss.wechat') ?? _wechat;
      _campus = prefs.getStringList('rss.campus') ?? _campus;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('rss.wechat', _wechat);
    await prefs.setStringList('rss.campus', _campus);
  }

  Future<void> _add(bool wechat) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(wechat ? '添加公众号 RSS' : '添加校内新闻 RSS'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'HTTPS RSS 地址',
            hintText: 'https://example.com/rss.xml',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final uri = Uri.tryParse(controller.text.trim());
              if (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty) {
                Navigator.pop(context, uri.toString());
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    setState(() => (wechat ? _wechat : _campus).add(value));
    _save();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('RSS 订阅')),
    body: ListView(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('同一分类可添加多个 RSS。新闻页会并发加载并去重，再按发布时间整合。仅支持 HTTPS 地址。'),
        ),
        _RssGroup(
          title: '公众号',
          items: _wechat,
          onAdd: () => _add(true),
          onDelete: (index) {
            setState(() => _wechat.removeAt(index));
            _save();
          },
        ),
        _RssGroup(
          title: '校内新闻',
          items: _campus,
          onAdd: () => _add(false),
          onDelete: (index) {
            setState(() => _campus.removeAt(index));
            _save();
          },
        ),
      ],
    ),
  );
}

class TiebaSettingsScreen extends ConsumerStatefulWidget {
  const TiebaSettingsScreen({super.key});
  @override
  ConsumerState<TiebaSettingsScreen> createState() =>
      _TiebaSettingsScreenState();
}

class _TiebaSettingsScreenState extends ConsumerState<TiebaSettingsScreen> {
  bool _originalImages = false;
  bool _autoSign = true;
  bool _showAvatars = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _originalImages = preferences.getBool('tieba.originalImages') ?? false;
      _autoSign = preferences.getBool('tieba.autoSign') ?? true;
      _showAvatars = preferences.getBool('tieba.showAvatars') ?? true;
    });
  }

  Future<void> _set(String key, bool value) async {
    await (await SharedPreferences.getInstance()).setBool(key, value);
  }

  Future<void> _editHomeForum() async {
    final controller = TextEditingController(
      text: ref.read(appSettingsProvider).tiebaHomeForumName,
    );
    String? error;
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('更改主页贴吧'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 1,
            decoration: InputDecoration(
              labelText: '吧名',
              hintText: '长春工程学院吧',
              helperText: error == null ? '可输入带或不带“吧”的名称' : null,
              errorText: error,
            ),
            onSubmitted: (_) {
              final normalized = normalizeTiebaForumName(controller.text);
              if (normalized.isEmpty) {
                setDialogState(() => error = '吧名不能为空');
              } else {
                Navigator.pop(dialogContext, normalized);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final normalized = normalizeTiebaForumName(controller.text);
                if (normalized.isEmpty) {
                  setDialogState(() => error = '吧名不能为空');
                } else {
                  Navigator.pop(dialogContext, normalized);
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (value == null) return;
    await ref.read(appSettingsProvider.notifier).setTiebaHomeForumName(value);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('主页贴吧已改为${displayTiebaForumName(value)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final homeForum = ref.watch(
      appSettingsProvider.select((value) => value.tiebaHomeForumName),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('贴吧设置')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.school_outlined),
            title: const Text('主页贴吧'),
            subtitle: Text('当前加载：${displayTiebaForumName(homeForum)}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _editHomeForum,
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('优先加载原图'),
            subtitle: const Text('可能消耗更多流量'),
            value: _originalImages,
            onChanged: (value) {
              setState(() => _originalImages = value);
              _set('tieba.originalImages', value);
            },
          ),
          SwitchListTile(
            title: const Text('登录后自动签到'),
            value: _autoSign,
            onChanged: (value) {
              setState(() => _autoSign = value);
              _set('tieba.autoSign', value);
            },
          ),
          SwitchListTile(
            title: const Text('显示用户头像'),
            value: _showAvatars,
            onChanged: (value) {
              setState(() => _showAvatars = value);
              _set('tieba.showAvatars', value);
            },
          ),
          const ListTile(
            leading: Icon(Icons.reply),
            title: Text('回复行为'),
            subtitle: Text('长按楼层后跳转官方百度贴吧客户端'),
          ),
          const ListTile(
            leading: Icon(Icons.security),
            title: Text('账号安全'),
            subtitle: Text('Cookie 与 token 使用 Android Keystore 加密，不明文写入 Room'),
          ),
        ],
      ),
    );
  }
}

class UpdateSettingsScreen extends ConsumerStatefulWidget {
  const UpdateSettingsScreen({super.key});
  @override
  ConsumerState<UpdateSettingsScreen> createState() =>
      _UpdateSettingsScreenState();
}

class _UpdateSettingsScreenState extends ConsumerState<UpdateSettingsScreen> {
  bool _prerelease = false;
  bool _checking = false;
  String _status = '从 aquasofts/Cithub-Flutter Releases 获取对应 flavor 安装包。';
  UpdateReleaseDto? _release;
  double? _progress;
  late final Future<NativeCapabilities> _capabilities;
  StreamSubscription<NativeEventDto>? _subscription;

  @override
  void initState() {
    super.initState();
    _capabilities = ref.read(cithubPlatformProvider).capabilities();
    _subscription = ref
        .read(cithubPlatformProvider)
        .events
        .where((event) => event.source == 'update')
        .listen((event) {
          if (!mounted) return;
          setState(() {
            _progress = event.progress;
            if (event.message != null) _status = event.message!;
          });
        });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      final release = await ref
          .read(cithubPlatformProvider)
          .checkUpdate(includePrereleases: _prerelease);
      if (!mounted) return;
      setState(() {
        _release = release;
        _status = release == null
            ? '当前已是最新版本'
            : '发现 ${release.version}：${release.title}';
      });
    } catch (error) {
      if (mounted) setState(() => _status = '检查失败：$error');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('应用更新')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FutureBuilder<NativeCapabilities>(
                  future: _capabilities,
                  builder: (context, snapshot) => Text(
                    'Cithub Flutter ${snapshot.data?.versionName ?? ''}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 8),
                Text(_status),
                if (_progress != null) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: _progress),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _checking ? null : _check,
                      icon: _checking
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: const Text('检查更新'),
                    ),
                    if (_release != null)
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          await ref
                              .read(cithubPlatformProvider)
                              .startUpdate(_release!);
                          setState(() => _status = '已交给 Android 后台下载');
                        },
                        icon: const Icon(Icons.download),
                        label: const Text('下载'),
                      ),
                    OutlinedButton(
                      onPressed: () =>
                          ref.read(cithubPlatformProvider).installUpdate(),
                      child: const Text('安装已下载版本'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        SwitchListTile(
          title: const Text('接收预发布版本'),
          value: _prerelease,
          onChanged: (value) => setState(() => _prerelease = value),
        ),
        const ListTile(
          leading: Icon(Icons.verified_user_outlined),
          title: Text('安装包安全校验'),
          subtitle: Text('校验 flavor、SHA-256 与正式签名证书后才允许安装'),
        ),
      ],
    ),
  );
}

class RuntimeLogScreen extends ConsumerWidget {
  const RuntimeLogScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('运行日志')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              '完整诊断日志仅保存在本机滚动文件中，绝不自动上传。日志可能包含账号和会话信息，请只在主动排障时导出并妥善传递。',
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () async {
            final path = await ref
                .read(cithubPlatformProvider)
                .exportRuntimeLog();
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('日志已导出：$path')));
            }
          },
          icon: const Icon(Icons.ios_share),
          label: const Text('导出完整日志'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            await ref.read(cithubPlatformProvider).clearRuntimeLog();
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('运行日志已清除')));
            }
          },
          icon: const Icon(Icons.delete_outline),
          label: const Text('清除日志'),
        ),
      ],
    ),
  );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index != children.length - 1)
            const Divider(height: 1, indent: 56),
        ],
      ],
    ),
  );
}

class _SettingsLink extends StatelessWidget {
  const _SettingsLink({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.page,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget page;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    onTap: () =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

class _RssGroup extends StatelessWidget {
  const _RssGroup({
    required this.title,
    required this.items,
    required this.onAdd,
    required this.onDelete,
  });
  final String title;
  final List<String> items;
  final VoidCallback onAdd;
  final ValueChanged<int> onDelete;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SectionTitle(title),
      ...items.indexed.map(
        (entry) => ListTile(
          leading: const Icon(Icons.rss_feed),
          title: Text(entry.$2, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: IconButton(
            onPressed: () => onDelete(entry.$1),
            icon: const Icon(Icons.delete_outline),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: Text('添加$title RSS'),
        ),
      ),
    ],
  );
}
