import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/native/cithub_api.g.dart';
import '../../core/platform/cithub_platform.dart';
import '../settings/settings_screen.dart';
import '../tieba/tieba_login_screen.dart';

class MineScreen extends ConsumerStatefulWidget {
  const MineScreen({super.key});

  @override
  ConsumerState<MineScreen> createState() => _MineScreenState();
}

class _MineScreenState extends ConsumerState<MineScreen>
    with AutomaticKeepAliveClientMixin {
  late Future<WebVpnSessionDto> _webVpn;
  late Future<TiebaAccountDto?> _tieba;
  late Future<NativeCapabilities> _capabilities;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final platform = ref.read(cithubPlatformProvider);
    _webVpn = platform.initializeWebVpn();
    _tieba = platform.currentTiebaAccount();
    _capabilities = platform.capabilities();
  }

  Future<void> _openTiebaLogin() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const TiebaLoginScreen()));
    if (mounted) {
      setState(() {
        _tieba = ref.read(cithubPlatformProvider).currentTiebaAccount();
      });
    }
  }

  void _refreshTieba() => setState(
    () => _tieba = ref.read(cithubPlatformProvider).refreshTiebaAccount(),
  );

  void _logoutTieba() => setState(() {
    _tieba = () async {
      await ref.read(cithubPlatformProvider).logoutTieba();
      return null;
    }();
  });

  void _logoutWebVpn() =>
      setState(() => _webVpn = ref.read(cithubPlatformProvider).logoutWebVpn());

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return CustomScrollView(
      key: const PageStorageKey('mine-scroll'),
      slivers: [
        SliverAppBar(
          pinned: true,
          toolbarHeight: 72,
          titleSpacing: 20,
          title: const Text('我的'),
          actions: [
            IconButton(
              tooltip: '设置',
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
              icon: const Icon(Icons.settings_outlined),
            ),
            const SizedBox(width: 4),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          sliver: SliverList.list(
            children: [
              Text('个人信息', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              FutureBuilder<TiebaAccountDto?>(
                future: _tieba,
                builder: (_, snapshot) => Column(
                  children: [
                    _TiebaProfileCard(
                      account: snapshot.data,
                      loading:
                          snapshot.connectionState == ConnectionState.waiting,
                      error: snapshot.hasError,
                      onLogin: _openTiebaLogin,
                      onRefresh: _refreshTieba,
                    ),
                    if (snapshot.data != null) ...[
                      const SizedBox(height: 12),
                      _LogoutButton(
                        key: const Key('mine-tieba-logout'),
                        label: '退出贴吧账号',
                        onPressed: _logoutTieba,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FutureBuilder<WebVpnSessionDto>(
                future: _webVpn,
                builder: (_, snapshot) => Column(
                  children: [
                    _WebVpnInfoCard(
                      session: snapshot.data,
                      loading:
                          snapshot.connectionState == ConnectionState.waiting,
                      error: snapshot.hasError,
                    ),
                    if (snapshot.data?.status == AuthStatus.signedIn) ...[
                      const SizedBox(height: 12),
                      _LogoutButton(
                        key: const Key('mine-webvpn-logout'),
                        label: '退出 WebVPN',
                        onPressed: _logoutWebVpn,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('关于 Cithub Flutter'),
                  subtitle: FutureBuilder<NativeCapabilities>(
                    future: _capabilities,
                    builder: (_, value) => Text(
                      value.hasData
                          ? 'v${value.data!.versionName} · ${value.data!.flavor == CaptchaFlavor.autoCaptcha ? '自动验证码版' : '手动验证码版'}'
                          : '正在读取版本…',
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showAboutDialog(
                    context: context,
                    applicationName: 'Cithub Flutter',
                    applicationVersion: '1.0.0',
                    applicationLegalese: 'Copyright © 2026 aquasofts\nGNU General Public License v3.0',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TiebaProfileCard extends StatelessWidget {
  const _TiebaProfileCard({
    required this.account,
    required this.loading,
    required this.error,
    required this.onLogin,
    required this.onRefresh,
  });

  final TiebaAccountDto? account;
  final bool loading;
  final bool error;
  final VoidCallback onLogin;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_circle_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text('百度贴吧', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (account != null)
                IconButton(
                  tooltip: '刷新贴吧资料',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (loading)
            const Center(child: CircularProgressIndicator())
          else if (account case final value?)
            Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundImage: value.avatarUrl.isEmpty
                      ? null
                      : NetworkImage(value.avatarUrl),
                  child: value.avatarUrl.isEmpty
                      ? Text(_initial(value.nickname))
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value.nickname.isEmpty
                            ? value.username
                            : value.nickname,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 2),
                      Text('用户名：${value.username}'),
                      Text('${value.fans} 粉丝 · ${value.posts} 帖子'),
                    ],
                  ),
                ),
                Icon(Icons.check, color: Theme.of(context).colorScheme.primary),
              ],
            )
          else
            Row(
              children: [
                const Expanded(child: Text('尚未登录贴吧账号')),
                FilledButton.tonal(
                  onPressed: onLogin,
                  child: Text(error ? '重试' : '登录'),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}

class _WebVpnInfoCard extends StatelessWidget {
  const _WebVpnInfoCard({
    required this.session,
    required this.loading,
    required this.error,
  });

  final WebVpnSessionDto? session;
  final bool loading;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final user = session?.user;
    final signedIn = session?.status == AuthStatus.signedIn;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.shield_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('WebVPN', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text(
                  loading
                      ? '检查中'
                      : error
                      ? '检查失败'
                      : signedIn
                      ? '已连接'
                      : '未登录',
                  style: TextStyle(
                    color: signedIn
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (signedIn && user != null) ...[
              const SizedBox(height: 16),
              _InfoRow(label: '用户名', value: user.username),
              _InfoRow(
                label: '昵称',
                value: user.fullName.isEmpty ? user.nickname : user.fullName,
              ),
              _InfoRow(label: '用户组', value: user.groups.join('、')),
              _InfoRow(label: '微信绑定', value: user.bindWechat ? '已绑定' : '未绑定'),
              _InfoRow(
                label: '动态口令',
                value: user.bindOtp ? '已绑定' : '未绑定',
                bottomPadding: 0,
              ),
            ] else if (!loading) ...[
              const SizedBox(height: 12),
              const Text('请切换到“教务”页面登录 WebVPN。'),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.bottomPadding = 10,
  });

  final String label;
  final String value;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: bottomPadding),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 84,
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ],
    ),
  );
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.logout),
      label: Text(label),
    ),
  );
}

String _initial(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? '?' : trimmed.characters.first;
}
