import 'dart:convert';

import 'package:flutter/material.dart';

import '../timetable/academic_sync.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/native/cithub_api.g.dart';
import '../../core/logging/runtime_log.dart';
import '../../core/platform/cithub_platform.dart';
import '../../core/utils/user_facing_error.dart';

class AcademicFeature {
  const AcademicFeature(
    this.id,
    this.title,
    this.subtitle,
    this.icon, {
    this.webPath,
  });
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final String? webPath;
}

const academicFeatures = [
  AcademicFeature('grades', '成绩查询', '学期成绩与绩点明细', Icons.query_stats),
  AcademicFeature('timetable', '我的课表', '周次、节次与上课地点', Icons.calendar_month),
  AcademicFeature('selection_results', '选课结果', '查看已选课程', Icons.fact_check),
  AcademicFeature('evaluation', '学生评价', '课程评价与提交状态', Icons.rate_review),
  AcademicFeature(
    'course_selection',
    '学生选课中心',
    '进入选课与选课轮次',
    Icons.playlist_add_check,
    webPath: 'xsxk/xklc_list',
  ),
  AcademicFeature(
    'classroom_request',
    '教室借用申请',
    '查询并申请可用教室',
    Icons.meeting_room,
    webPath: 'kbxx/jsjy_query',
  ),
  AcademicFeature(
    'textbook_account',
    '教材账目信息',
    '查看教材费用与账目',
    Icons.receipt_long,
    webPath: 'nxsjc/jczmxx',
  ),
  AcademicFeature(
    'textbook_confirmation',
    '学生教材确认',
    '核对并确认课程教材',
    Icons.menu_book,
    webPath: 'nxsjc/jccx',
  ),
  AcademicFeature(
    'minor_registration',
    '辅修报名',
    '查看辅修项目与报名信息',
    Icons.school,
    webPath: 'fxgl/fxbmxx_query',
  ),
];

class AcademicScreen extends ConsumerStatefulWidget {
  const AcademicScreen({super.key});

  @override
  ConsumerState<AcademicScreen> createState() => _AcademicScreenState();
}

class _AcademicScreenState extends ConsumerState<AcademicScreen>
    with AutomaticKeepAliveClientMixin {
  WebVpnSessionDto? _latestSession;
  Object? _sessionError;
  List<AcademicFeature> _features = [...academicFeatures];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _restoreFeatureOrder();
  }

  Future<void> _restoreFeatureOrder() async {
    final ids = (await SharedPreferences.getInstance()).getStringList(
      'academic.featureOrder',
    );
    if (ids == null || !mounted) return;
    final ordered = ids
        .toSet()
        .map(
          (id) =>
              academicFeatures.where((feature) => feature.id == id).firstOrNull,
        )
        .whereType<AcademicFeature>()
        .toList();
    ordered.addAll(
      academicFeatures.where((feature) => !ordered.contains(feature)),
    );
    setState(() => _features = ordered);
  }

  Future<WebVpnSessionDto> _trackSession(
    Future<WebVpnSessionDto> value, {
    bool preserveOnError = false,
    Future<WebVpnSessionDto> Function()? recoverOnError,
  }) async {
    try {
      final session = await value;
      _latestSession = session;
      if (session.status != AuthStatus.signedIn) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ref.read(academicSessionProvider.notifier).state = null;
        });
      }
      if (mounted && _sessionError != null) {
        setState(() => _sessionError = null);
      }
      return session;
    } catch (error) {
      var fallback = preserveOnError ? _latestSession : null;
      if (recoverOnError != null) {
        try {
          fallback = await recoverOnError();
        } catch (_) {
          // Keep the last usable form if refreshing the captcha also fails.
        }
      }
      if (fallback == null) rethrow;
      _latestSession = fallback;
      if (mounted) setState(() => _sessionError = error);
      return fallback;
    }
  }

  void _setSession(
    Future<WebVpnSessionDto> value, {
    Future<WebVpnSessionDto> Function()? recoverOnError,
  }) {
    if (!mounted) return;
    setState(() {
      _sessionError = null;
      ref.read(webVpnSessionProvider.notifier).state = _trackSession(
        value,
        preserveOnError: true,
        recoverOnError: recoverOnError,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final session = ref.watch(webVpnSessionProvider);
    return CustomScrollView(
      key: const PageStorageKey('academic-scroll'),
      slivers: [
        SliverAppBar(
          pinned: true,
          toolbarHeight: 68,
          titleSpacing: 20,
          title: const Text('教务系统'),
          actions: [
            IconButton(
              tooltip: '功能排序',
              onPressed: () async {
                final ordered = await Navigator.of(context)
                    .push<List<AcademicFeature>>(
                      MaterialPageRoute(
                        builder: (_) =>
                            AcademicFeatureOrderScreen(initial: _features),
                      ),
                    );
                if (ordered != null && mounted) {
                  setState(() => _features = ordered);
                }
              },
              icon: const Icon(Icons.reorder),
            ),
          ],
        ),
        FutureBuilder<WebVpnSessionDto>(
          future: session,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return SliverFillRemaining(
                child: _AcademicError(
                  error: snapshot.error,
                  onRetry: () => _setSession(
                    ref.read(cithubPlatformProvider).initializeWebVpn(),
                  ),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final session = snapshot.requireData;
            _latestSession = session;
            if (session.status != AuthStatus.signedIn) {
              return SliverPadding(
                padding: const EdgeInsets.only(bottom: 32),
                sliver: SliverToBoxAdapter(
                  child: WebVpnLoginPanel(
                    session: session,
                    error: _sessionError,
                    loading:
                        snapshot.connectionState == ConnectionState.waiting,
                    onLogin: (request) {
                      final platform = ref.read(cithubPlatformProvider);
                      _setSession(
                        platform.loginWebVpn(request),
                        recoverOnError: platform.refreshWebVpnCaptcha,
                      );
                    },
                    onRefreshCaptcha: () => _setSession(
                      ref.read(cithubPlatformProvider).refreshWebVpnCaptcha(),
                    ),
                    onSelectSavedAccount: (username) => _setSession(
                      ref
                          .read(cithubPlatformProvider)
                          .selectSavedWebVpnAccount(username),
                    ),
                    onForgetSavedAccount: (username) => _setSession(
                      ref
                          .read(cithubPlatformProvider)
                          .forgetSavedWebVpnAccount(username),
                    ),
                  ),
                ),
              );
            }
            return _AcademicSessionSliver(
              key: ValueKey(session.user?.username),
              webVpnSession: session,
              features: _features,
              onWebVpnRefresh: () => _setSession(
                ref.read(cithubPlatformProvider).initializeWebVpn(),
              ),
              onWebVpnLogout: () =>
                  _setSession(ref.read(cithubPlatformProvider).logoutWebVpn()),
            );
          },
        ),
      ],
    );
  }
}

class _AcademicSessionSliver extends ConsumerStatefulWidget {
  const _AcademicSessionSliver({
    super.key,
    required this.webVpnSession,
    required this.features,
    required this.onWebVpnLogout,
    required this.onWebVpnRefresh,
  });

  final WebVpnSessionDto webVpnSession;
  final List<AcademicFeature> features;
  final VoidCallback onWebVpnLogout;
  final VoidCallback onWebVpnRefresh;

  @override
  ConsumerState<_AcademicSessionSliver> createState() =>
      _AcademicSessionSliverState();
}

class _AcademicSessionSliverState
    extends ConsumerState<_AcademicSessionSliver> {
  late Future<WebVpnSessionDto> _session;
  WebVpnSessionDto? _latestSession;
  Object? _sessionError;
  String? _syncedAccount;

  @override
  void initState() {
    super.initState();
    _session = _trackSession(
      ref
          .read(cithubPlatformProvider)
          .initializeAcademic(widget.webVpnSession.user?.username ?? ''),
    );
  }

  Future<WebVpnSessionDto> _trackSession(
    Future<WebVpnSessionDto> value, {
    bool preserveOnError = false,
    Future<WebVpnSessionDto> Function()? recoverOnError,
  }) async {
    try {
      final session = await value;
      _latestSession = session;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(academicSessionProvider.notifier).state = session;
        final account = session.user?.username;
        if (session.status == AuthStatus.signedIn &&
            account != null &&
            account != _syncedAccount) {
          _syncedAccount = account;
          syncAcademicSchedule(context, ref);
        } else if (session.status != AuthStatus.signedIn) {
          _syncedAccount = null;
        }
      });
      if (mounted && _sessionError != null) {
        setState(() => _sessionError = null);
      }
      return session;
    } catch (error) {
      var fallback = preserveOnError ? _latestSession : null;
      if (recoverOnError != null) {
        try {
          fallback = await recoverOnError();
        } catch (_) {
          // Keep the last usable form if refreshing the captcha also fails.
        }
      }
      if (fallback == null) rethrow;
      _latestSession = fallback;
      if (mounted) setState(() => _sessionError = error);
      return fallback;
    }
  }

  void _set(
    Future<WebVpnSessionDto> value, {
    Future<WebVpnSessionDto> Function()? recoverOnError,
  }) {
    if (!mounted) return;
    setState(() {
      _sessionError = null;
      _session = _trackSession(
        value,
        preserveOnError: true,
        recoverOnError: recoverOnError,
      );
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<WebVpnSessionDto>(
    future: _session,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return SliverFillRemaining(
          child: _AcademicError(
            error: snapshot.error,
            onReconnect: widget.onWebVpnRefresh,
            webPath: 'framework/xsMain.jsp',
            onRetry: () => _set(
              ref
                  .read(cithubPlatformProvider)
                  .initializeAcademic(
                    widget.webVpnSession.user?.username ?? '',
                  ),
            ),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const SliverFillRemaining(
          child: Center(child: CircularProgressIndicator()),
        );
      }
      final academic = snapshot.requireData;
      if (academic.status != AuthStatus.signedIn) {
        return SliverPadding(
          padding: const EdgeInsets.only(bottom: 32),
          sliver: SliverToBoxAdapter(
            child: WebVpnLoginPanel(
              session: academic,
              error: _sessionError,
              loading: snapshot.connectionState == ConnectionState.waiting,
              onSelectSavedAccount: (username) => _set(
                ref
                    .read(cithubPlatformProvider)
                    .selectSavedAcademicAccount(username),
              ),
              onForgetSavedAccount: (username) => _set(
                ref
                    .read(cithubPlatformProvider)
                    .forgetSavedAcademicAccount(username),
              ),
              title: '登录教务系统',
              description: '教务账号独立登录，密码只在本机加密保存。',
              usernameLabel: '教务系统账号',
              passwordLabel: '教务系统密码',
              icon: Icons.school_outlined,
              onLogin: (request) {
                final platform = ref.read(cithubPlatformProvider);
                _set(
                  platform.loginAcademic(request),
                  recoverOnError: platform.refreshAcademicCaptcha,
                );
              },
              onRefreshCaptcha: () => _set(
                ref.read(cithubPlatformProvider).refreshAcademicCaptcha(),
              ),
            ),
          ),
        );
      }
      return SliverMainAxisGroup(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 10),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.features.length} 项学生服务',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          academic.user?.fullName ??
                              academic.user?.username ??
                              '教务已登录',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '账户操作',
                    onSelected: (value) async {
                      if (value == 'academic') {
                        await ref.read(cithubPlatformProvider).logoutAcademic();
                        _set(
                          ref
                              .read(cithubPlatformProvider)
                              .initializeAcademic(
                                widget.webVpnSession.user?.username ?? '',
                              ),
                        );
                      } else {
                        widget.onWebVpnLogout();
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'academic', child: Text('退出教务系统')),
                      PopupMenuItem(value: 'webvpn', child: Text('退出 WebVPN')),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            sliver: SliverList.separated(
              itemCount: widget.features.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, index) => _AcademicFeatureCard(
                feature: widget.features[index],
                onReturn: () => _set(
                  ref
                      .read(cithubPlatformProvider)
                      .initializeAcademic(
                        widget.webVpnSession.user?.username ?? '',
                      ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class WebVpnLoginPanel extends StatefulWidget {
  const WebVpnLoginPanel({
    super.key,
    required this.session,
    required this.onLogin,
    required this.onRefreshCaptcha,
    this.loading = false,
    this.title = '登录 WebVPN',
    this.description = '登录后可访问教务系统；新应用不会读取旧版账号。',
    this.usernameLabel = '统一身份认证账号',
    this.passwordLabel = '密码',
    this.icon = Icons.shield_outlined,
    this.onSelectSavedAccount,
    this.onForgetSavedAccount,
    this.error,
  });
  final WebVpnSessionDto session;
  final bool loading;
  final ValueChanged<LoginRequestDto> onLogin;
  final VoidCallback onRefreshCaptcha;
  final String title;
  final String description;
  final String usernameLabel;
  final String passwordLabel;
  final IconData icon;
  final ValueChanged<String>? onSelectSavedAccount;
  final ValueChanged<String>? onForgetSavedAccount;
  final Object? error;

  @override
  State<WebVpnLoginPanel> createState() => _WebVpnLoginPanelState();
}

class _WebVpnLoginPanelState extends State<WebVpnLoginPanel> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  late final _captcha = TextEditingController(
    text: widget.session.captcha?.recognizedCode ?? '',
  );
  bool _remember = true;
  bool _obscure = true;
  bool _useSavedPassword = false;

  @override
  void didUpdateWidget(covariant WebVpnLoginPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final recognized = widget.session.captcha?.recognizedCode ?? '';
    final captchaChanged =
        widget.session.captcha?.id != oldWidget.session.captcha?.id;
    if (captchaChanged ||
        (recognized.isNotEmpty && recognized != _captcha.text)) {
      _captcha.text = recognized;
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _captcha.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: Padding(
      padding: EdgeInsets.all(
        MediaQuery.sizeOf(context).width <= 360 ? 12 : 20,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        widget.icon,
                        size: 25,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.description,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (widget.error case final error?) ...[
                  const SizedBox(height: 14),
                  Container(
                    key: const Key('academic-login-error'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 20,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            userFacingError(error),
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                if (widget.session.savedAccounts.isNotEmpty) ...[
                  Text('已保存账号', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.session.savedAccounts
                        .map(
                          (account) => InputChip(
                            label: Text(account.username),
                            selected:
                                _useSavedPassword &&
                                _username.text == account.username,
                            onSelected: (_) {
                              setState(() {
                                _username.text = account.username;
                                _password.clear();
                                _useSavedPassword = true;
                              });
                              widget.onSelectSavedAccount?.call(
                                account.username,
                              );
                            },
                            onDeleted: widget.onForgetSavedAccount == null
                                ? null
                                : () {
                                    if (_username.text == account.username) {
                                      setState(() => _useSavedPassword = false);
                                    }
                                    widget.onForgetSavedAccount!(
                                      account.username,
                                    );
                                  },
                            deleteButtonTooltipMessage: '删除保存的账号',
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: _username,
                  autofillHints: const [AutofillHints.username],
                  onChanged: (value) {
                    if (_useSavedPassword &&
                        !widget.session.savedAccounts.any(
                          (account) => account.username == value.trim(),
                        )) {
                      setState(() => _useSavedPassword = false);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: widget.usernameLabel,
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  enabled: !_useSavedPassword,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: _useSavedPassword
                        ? '使用本机已保存密码'
                        : widget.passwordLabel,
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off,
                      ),
                    ),
                  ),
                ),
                if (widget.session.requiresCaptcha) ...[
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final image =
                          (widget.session.captcha?.base64Image ?? '').isEmpty
                          ? null
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.memory(
                                base64Decode(
                                  widget.session.captcha!.base64Image.contains(
                                        ',',
                                      )
                                      ? widget.session.captcha!.base64Image
                                            .split(',')
                                            .last
                                      : widget.session.captcha!.base64Image,
                                ),
                                width: 104,
                                height: 52,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) =>
                                    const SizedBox.shrink(),
                              ),
                            );
                      final field = TextField(
                        controller: _captcha,
                        decoration: InputDecoration(
                          labelText: '验证码',
                          suffixIcon: IconButton(
                            key: const Key('webvpn-captcha-refresh'),
                            onPressed: widget.loading
                                ? null
                                : widget.onRefreshCaptcha,
                            tooltip: '刷新验证码',
                            icon: widget.loading
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh),
                          ),
                        ),
                      );
                      if (image == null) return field;
                      if (constraints.maxWidth < 270) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [image, const SizedBox(height: 8), field],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          image,
                          const SizedBox(width: 10),
                          Expanded(child: field),
                        ],
                      );
                    },
                  ),
                  if ((widget.session.captcha?.recognizedCode ?? '').isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('自动版已识别验证码，请核对后提交。'),
                    ),
                ],
                CheckboxListTile(
                  value: _remember,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('在本机安全存储中加密保存密码'),
                  onChanged: (value) =>
                      setState(() => _remember = value ?? false),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  key: const Key('webvpn-login'),
                  onPressed: widget.loading
                      ? null
                      : () => widget.onLogin(
                          LoginRequestDto(
                            username: _username.text.trim(),
                            password: _password.text,
                            captchaId: widget.session.captcha?.id ?? '',
                            captchaCode: _captcha.text.trim(),
                            rememberPassword: _remember,
                            useSavedPassword: _useSavedPassword,
                          ),
                        ),
                  child: widget.loading
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('登录'),
                ),
                if (widget.session.message case final message?)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(message, textAlign: TextAlign.center),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _AcademicFeatureCard extends StatelessWidget {
  const _AcademicFeatureCard({required this.feature, this.onReturn});
  final AcademicFeature feature;
  final VoidCallback? onReturn;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () async {
        final page = switch (feature.id) {
          'grades' => const GradesScreen(),
          'timetable' => const TimetableScreen(),
          'selection_results' => const SelectionResultsScreen(),
          'evaluation' => const EvaluationScreen(),
          _ => AcademicWebScreen(feature: feature),
        };
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => page));
        onReturn?.call();
      },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                feature.icon,
                size: 24,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    feature.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    feature.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class GradesScreen extends ConsumerStatefulWidget {
  const GradesScreen({super.key});

  @override
  ConsumerState<GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends ConsumerState<GradesScreen> {
  late Future<List<AcademicTermDto>> _terms;
  String? _selected;
  bool _bestOnly = false;
  Future<List<CourseGradeDto>>? _items;

  @override
  void initState() {
    super.initState();
    _terms = ref.read(cithubPlatformProvider).loadAcademicTerms();
  }

  void _load() {
    if (_selected == null) return;
    setState(() {
      _items = ref
          .read(cithubPlatformProvider)
          .loadGrades(_selected!, bestOnly: _bestOnly);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('成绩查询'),
      actions: const [
        _OriginalAcademicButton(title: '成绩查询', path: 'kscj/cjcx_query'),
      ],
    ),
    body: FutureBuilder<List<AcademicTermDto>>(
      future: _terms,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _AcademicError(
            error: snapshot.error,
            webPath: 'kscj/cjcx_query',
            onRetry: () => setState(() {
              _terms = ref.read(cithubPlatformProvider).loadAcademicTerms();
            }),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final terms = snapshot.requireData;
        if (terms.isEmpty) {
          return _AcademicError(
            error: StateError('教务系统未返回学期，可使用原始页面查询'),
            webPath: 'kscj/cjcx_query',
            onRetry: () => setState(() {
              _terms = ref.read(cithubPlatformProvider).loadAcademicTerms();
            }),
          );
        }
        _selected ??=
            terms.where((term) => term.selected).firstOrNull?.value ??
            terms.first.value;
        _items ??= ref
            .read(cithubPlatformProvider)
            .loadGrades(_selected!, bestOnly: _bestOnly);
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.school_outlined,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '成绩查询',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                  Text(
                                    '按学期筛选课程成绩',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        LayoutBuilder(
                          builder: (context, constraints) =>
                              DropdownMenu<String>(
                                width: constraints.maxWidth,
                                initialSelection: _selected,
                                label: const Text('学年学期'),
                                dropdownMenuEntries: terms
                                    .map(
                                      (term) => DropdownMenuEntry(
                                        value: term.value,
                                        label: term.label,
                                      ),
                                    )
                                    .toList(),
                                onSelected: (value) {
                                  if (value != null) {
                                    setState(() => _selected = value);
                                  }
                                },
                              ),
                        ),
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          value: _bestOnly,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text('同一课程只显示最好成绩'),
                          onChanged: (value) =>
                              setState(() => _bestOnly = value ?? false),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.search),
                          label: const Text('查询成绩'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _AcademicResultsSliver<CourseGradeDto>(
              future: _items!,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              errorBuilder: (error) => _AcademicError(
                error: error,
                webPath: 'kscj/cjcx_query',
                onRetry: _load,
              ),
              itemBuilder: (item) => _GradeCard(item: item),
            ),
          ],
        );
      },
    ),
  );
}

class _AcademicResultsSliver<T> extends StatelessWidget {
  const _AcademicResultsSliver({
    required this.future,
    required this.padding,
    required this.errorBuilder,
    required this.itemBuilder,
  });

  final Future<List<T>> future;
  final EdgeInsets padding;
  final Widget Function(Object?) errorBuilder;
  final Widget Function(T) itemBuilder;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<T>>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return SliverFillRemaining(
          hasScrollBody: false,
          child: errorBuilder(snapshot.error),
        );
      }
      if (!snapshot.hasData) {
        return const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      final items = snapshot.requireData;
      if (items.isEmpty) {
        return const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: Text('该学期暂无记录')),
        );
      }
      return SliverPadding(
        padding: padding,
        sliver: SliverList.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, index) => itemBuilder(items[index]),
        ),
      );
    },
  );
}

class _GradeCard extends StatelessWidget {
  const _GradeCard({required this.item});

  final CourseGradeDto item;

  @override
  Widget build(BuildContext context) {
    final details = [
      if (item.credit.isNotEmpty) '学分 ${item.credit}',
      if (item.gradePoint.isNotEmpty) '绩点 ${item.gradePoint}',
      if (item.assessmentMethod.isNotEmpty) item.assessmentMethod,
      if (item.courseAttribute.isNotEmpty) item.courseAttribute,
      if (item.courseNature.isNotEmpty) item.courseNature,
    ].join(' · ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.courseName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${item.semester} · ${item.courseCode}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  item.score,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(details, style: Theme.of(context).textTheme.bodyMedium),
            ],
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('完整成绩明细'),
              children: [
                for (final entry in <String, String>{
                  '序号': item.sequence,
                  '学期': item.semester,
                  '课程代码': item.courseCode,
                  '课程名称': item.courseName,
                  '分组名': item.groupName,
                  '成绩': item.score,
                  '成绩标识': item.scoreMark,
                  '学分': item.credit,
                  '总学时': item.totalHours,
                  '绩点': item.gradePoint,
                  '通选课': item.generalElective,
                  '原始成绩': item.originalScore,
                  '说明': item.scoreDescription,
                  '备注': item.note,
                  '重修学期': item.retakeSemester,
                  '考核方式': item.assessmentMethod,
                  '考试性质': item.examType,
                  '课程属性': item.courseAttribute,
                  '课程性质': item.courseNature,
                  '课程类别': item.courseCategory,
                }.entries)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(entry.key),
                    subtitle: SelectableText(
                      entry.value.isEmpty ? '—' : entry.value,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SelectionResultsScreen extends ConsumerWidget {
  const SelectionResultsScreen({super.key});
  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) => _TermAcademicListPage<SelectedCourseDto>(
    title: '选课结果',
    load: (term) => ref.read(cithubPlatformProvider).loadSelectionResults(term),
    builder: (item) => ListTile(
      title: Text(item.courseName),
      subtitle: Text(
        '${item.courseCode} · ${item.teacher}\n学分 ${item.credit} · 学时 ${item.totalHours}\n${item.courseAttribute} · ${item.courseNature}',
      ),
    ),
  );
}

class _TermAcademicListPage<T> extends ConsumerStatefulWidget {
  const _TermAcademicListPage({
    required this.title,
    required this.load,
    required this.builder,
  });
  final String title;
  final Future<List<T>> Function(String term) load;
  final Widget Function(T) builder;

  @override
  ConsumerState<_TermAcademicListPage<T>> createState() =>
      _TermAcademicListPageState<T>();
}

class _TermAcademicListPageState<T>
    extends ConsumerState<_TermAcademicListPage<T>> {
  late Future<List<AcademicTermDto>> _terms;
  String? _selected;
  Future<List<T>>? _items;

  @override
  void initState() {
    super.initState();
    _terms = ref.read(cithubPlatformProvider).loadSelectionTerms();
  }

  void _select(String value) {
    setState(() {
      _selected = value;
      _items = widget.load(value);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [
        const _OriginalAcademicButton(title: '选课结果', path: 'xkgl/xsxkjgcx'),
        IconButton(
          tooltip: '刷新',
          onPressed: _selected == null ? null : () => _select(_selected!),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<List<AcademicTermDto>>(
      future: _terms,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _AcademicError(
            error: snapshot.error,
            onRetry: () => setState(() {
              _terms = ref.read(cithubPlatformProvider).loadSelectionTerms();
            }),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final terms = snapshot.requireData;
        if (terms.isEmpty) return const Center(child: Text('教务系统未返回学期'));
        _selected ??=
            terms.where((term) => term.selected).firstOrNull?.value ??
            terms.first.value;
        _items ??= widget.load(_selected!);
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: LayoutBuilder(
                      builder: (context, constraints) => DropdownMenu<String>(
                        width: constraints.maxWidth,
                        initialSelection: _selected,
                        label: const Text('学期'),
                        dropdownMenuEntries: terms
                            .map(
                              (term) => DropdownMenuEntry(
                                value: term.value,
                                label: term.label,
                              ),
                            )
                            .toList(),
                        onSelected: (value) {
                          if (value != null) _select(value);
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _AcademicResultsSliver<T>(
              future: _items!,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              errorBuilder: (error) => _AcademicError(
                error: error,
                onRetry: () => _select(_selected!),
              ),
              itemBuilder: (item) => Card(child: widget.builder(item)),
            ),
          ],
        );
      },
    ),
  );
}

class EvaluationScreen extends ConsumerWidget {
  const EvaluationScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _AcademicListPage<EvaluationBatchDto>(
        title: '学生评价',
        webPath: 'xspj/xspj_find.do',
        load: () => ref.read(cithubPlatformProvider).loadEvaluationBatches(),
        builder: (item, reload) => ListTile(
          title: Text(item.name),
          subtitle: Text(
            '${item.semester} · ${item.startDate} 至 ${item.endDate}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EvaluationCoursesScreen(batch: item),
              ),
            );
            if (context.mounted) reload();
          },
        ),
      );
}

class EvaluationCoursesScreen extends ConsumerWidget {
  const EvaluationCoursesScreen({super.key, required this.batch});
  final EvaluationBatchDto batch;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _AcademicListPage<EvaluationCourseDto>(
        title: batch.name,
        webPath: batch.courseListPath,
        load: () => ref
            .read(cithubPlatformProvider)
            .loadEvaluationCourses(batch.courseListPath),
        builder: (item, reload) => ListTile(
          title: Text(item.courseName),
          subtitle: Text(
            '${item.teacher} · ${item.category} · ${item.teachingHours} 学时',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.submitted
                    ? '已提交'
                    : item.evaluated
                    ? '已保存'
                    : '待评价',
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right),
            ],
          ),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EvaluationFormScreen(course: item),
              ),
            );
            if (context.mounted) reload();
          },
        ),
      );
}

class EvaluationFormScreen extends ConsumerStatefulWidget {
  const EvaluationFormScreen({super.key, required this.course});
  final EvaluationCourseDto course;

  @override
  ConsumerState<EvaluationFormScreen> createState() =>
      _EvaluationFormScreenState();
}

class _EvaluationFormScreenState extends ConsumerState<EvaluationFormScreen> {
  late Future<EvaluationFormDto> _future;
  final _answers = <String, String>{};
  final _suggestion = TextEditingController();
  bool _initialized = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _future = ref
        .read(cithubPlatformProvider)
        .loadEvaluationForm(widget.course.formPath);
  }

  @override
  void dispose() {
    _suggestion.dispose();
    super.dispose();
  }

  void _initialize(EvaluationFormDto form) {
    if (_initialized) return;
    _initialized = true;
    _suggestion.text = form.suggestion;
    for (final question in form.questions) {
      final selected = question.options.where((option) => option.selected);
      if (selected.isNotEmpty) _answers[question.id] = selected.first.id;
    }
  }

  Future<void> _save(EvaluationFormDto form, {required bool submit}) async {
    if (form.questions.any((question) => !_answers.containsKey(question.id))) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请完成每一项评价指标')));
      return;
    }
    if (submit) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认提交评价？'),
          content: const Text('提交后教务系统可能不允许再次修改。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认提交'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(cithubPlatformProvider)
          .saveEvaluation(
            form,
            _answers.entries
                .map(
                  (entry) => EvaluationAnswerDto(
                    questionId: entry.key,
                    optionId: entry.value,
                  ),
                )
                .toList(),
            _suggestion.text,
            submit: submit,
          );
      if (!saved) throw StateError('教务系统未确认保存成功');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(submit ? '评价已提交' : '评价草稿已保存')));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(userFacingError(error))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.course.courseName)),
    body: FutureBuilder<EvaluationFormDto>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _AcademicError(
            error: snapshot.error,
            onRetry: () => setState(() {
              _future = ref
                  .read(cithubPlatformProvider)
                  .loadEvaluationForm(widget.course.formPath);
            }),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final form = snapshot.requireData;
        _initialize(form);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(form.courseName),
              subtitle: Text(form.category),
              trailing: form.readOnly
                  ? const Chip(label: Text('已提交，只读'))
                  : null,
            ),
            for (var index = 0; index < form.questions.length; index++)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${index + 1}. ${form.questions[index].title}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: form.questions[index].options
                            .map(
                              (option) => ChoiceChip(
                                label: Text(
                                  option.score.isEmpty
                                      ? option.label
                                      : '${option.label}（${option.score}）',
                                ),
                                selected:
                                    _answers[form.questions[index].id] ==
                                    option.id,
                                onSelected: form.readOnly
                                    ? null
                                    : (_) => setState(
                                        () =>
                                            _answers[form.questions[index].id] =
                                                option.id,
                                      ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ),
            if (form.suggestionField != null) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _suggestion,
                enabled: !form.readOnly,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: '意见与建议',
                  alignLabelWithHint: true,
                ),
              ),
            ],
            if (!form.readOnly) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => _save(form, submit: false),
                      child: const Text('保存草稿'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving
                          ? null
                          : () => _save(form, submit: true),
                      child: Text(_saving ? '正在保存…' : '提交评价'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    ),
  );
}

class TimetableScreen extends ConsumerStatefulWidget {
  const TimetableScreen({super.key});

  @override
  ConsumerState<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends ConsumerState<TimetableScreen> {
  late Future<TimetableDto> _timetable;
  String? _term;
  int? _week;
  int? _day;
  bool _weekInitialized = false;

  @override
  void initState() {
    super.initState();
    _timetable = ref.read(cithubPlatformProvider).loadTimetable();
  }

  void _reload() => setState(() {
    _timetable = ref.read(cithubPlatformProvider).loadTimetable(_term);
  });

  DateTime? _dateForDay(TimetableDto data, int day) {
    final reference = DateTime.tryParse(data.referenceDateIso ?? '');
    final referenceWeek = data.referenceWeek;
    if (reference == null || referenceWeek == null || _week == null) {
      return null;
    }
    // Use calendar dates so week changes remain correct across DST boundaries.
    return DateTime(
      reference.year,
      reference.month,
      reference.day + (_week! - referenceWeek) * 7 + day - reference.weekday,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('学期理论课表'),
      actions: const [
        _OriginalAcademicButton(title: '我的课表', path: 'xskb/xskb_list.do'),
      ],
    ),
    body: FutureBuilder<TimetableDto>(
      future: _timetable,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _AcademicError(
            error: snapshot.error,
            webPath: 'xskb/xskb_list.do',
            onRetry: _reload,
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.requireData;
        final reference = DateTime.tryParse(data.referenceDateIso ?? '');
        _day ??= reference?.weekday ?? DateTime.now().weekday;
        if (!_weekInitialized) {
          _week = data.referenceWeek;
          _weekInitialized = true;
        }
        final maxWeek = [
          data.totalWeeks ?? 0,
          ...data.courses.expand((c) => c.weekNumbers),
        ].fold<int>(20, (a, b) => a > b ? a : b);
        final courses =
            data.courses
                .where(
                  (course) =>
                      (_day == 0 || course.dayOfWeek == _day) &&
                      (_week == null ||
                          course.weekNumbers.isEmpty ||
                          course.weekNumbers.contains(_week)),
                )
                .toList()
              ..sort((a, b) {
                final day = a.dayOfWeek.compareTo(b.dayOfWeek);
                return day == 0
                    ? a.startSection.compareTo(b.startSection)
                    : day;
              });
        final days = _day == 0
            ? [for (var day = 1; day <= 7; day++) day]
            : [_day!];
        final selectedDate = _day == 0 ? null : _dateForDay(data, _day!);
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        return CustomScrollView(
          key: const PageStorageKey('timetable-scroll'),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        if (data.terms.isNotEmpty)
                          Expanded(
                            child: _TimetableDropdown<String>(
                              label: '学年学期',
                              value: data.selectedTerm,
                              entries: data.terms
                                  .map(
                                    (term) => DropdownMenuEntry(
                                      value: term.value,
                                      label: term.label,
                                    ),
                                  )
                                  .toList(),
                              onSelected: (value) {
                                if (value == null) return;
                                _term = value;
                                _weekInitialized = false;
                                _reload();
                              },
                            ),
                          )
                        else
                          const Expanded(child: Text('教务系统未返回学期')),
                        const SizedBox(width: 12),
                        IconButton(
                          tooltip: '刷新课表',
                          onPressed: _reload,
                          icon: const Icon(Icons.refresh),
                          iconSize: 28,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _TimetableDropdown<int>(
                            label: '周次',
                            value: _week ?? 0,
                            entries: [
                              const DropdownMenuEntry(value: 0, label: '全部周次'),
                              for (var week = 1; week <= maxWeek; week++)
                                DropdownMenuEntry(
                                  value: week,
                                  label: '第 $week 周',
                                ),
                            ],
                            onSelected: (value) {
                              if (value != null) {
                                setState(
                                  () => _week = value == 0 ? null : value,
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _TimetableDropdown<int>(
                            label: '星期',
                            value: _day,
                            entries: [
                              const DropdownMenuEntry(value: 0, label: '整周课表'),
                              for (var day = 1; day <= 7; day++)
                                DropdownMenuEntry(
                                  value: day,
                                  label: '周${'一二三四五六日'[day - 1]}',
                                ),
                            ],
                            onSelected: (value) {
                              if (value != null) setState(() => _day = value);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedDate == null
                                ? (_day == 0
                                      ? '整周课表'
                                      : _timetableDayLabel(_day!))
                                : '${selectedDate.month}月${selectedDate.day}日',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_week == null ? '全部周次' : '第 $_week 周'} · ${_day == 0 ? '星期一至星期日' : _timetableDayLabel(_day!)}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (data.note.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          data.note,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            for (final day in days) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                sliver: SliverToBoxAdapter(
                  child: _TimetableDayHeader(
                    day: day,
                    date: _dateForDay(data, day),
                    count: courses
                        .where((course) => course.dayOfWeek == day)
                        .length,
                  ),
                ),
              ),
              if (!courses.any((course) => course.dayOfWeek == day))
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('当天暂无课程', style: theme.textTheme.bodyLarge),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList.separated(
                    itemCount: courses
                        .where((course) => course.dayOfWeek == day)
                        .length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, index) {
                      final course = courses
                          .where((course) => course.dayOfWeek == day)
                          .elementAt(index);
                      return _TimetableCourseCard(
                        course: course,
                        period: data.periods
                            .where(
                              (period) => period.index == course.periodIndex,
                            )
                            .firstOrNull,
                        showWeeks: _week == null,
                      );
                    },
                  ),
                ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
          ],
        );
      },
    ),
  );
}

String _timetableDayLabel(int day) => '星期${'一二三四五六日'[day - 1]}';

class _TimetableDropdown<T> extends StatelessWidget {
  const _TimetableDropdown({
    required this.label,
    required this.value,
    required this.entries,
    required this.onSelected,
  });

  final String label;
  final T? value;
  final List<DropdownMenuEntry<T>> entries;
  final ValueChanged<T?> onSelected;

  @override
  Widget build(BuildContext context) => DropdownMenu<T>(
    key: ValueKey('$label:$value'),
    expandedInsets: EdgeInsets.zero,
    initialSelection: value,
    label: Text(label),
    requestFocusOnTap: false,
    menuHeight: 320,
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
      ),
    ),
    dropdownMenuEntries: entries,
    onSelected: onSelected,
  );
}

class _TimetableDayHeader extends StatelessWidget {
  const _TimetableDayHeader({
    required this.day,
    required this.date,
    required this.count,
  });
  final int day;
  final DateTime? date;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _timetableDayLabel(day),
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            if (date != null)
              Text(
                '${date!.month}月${date!.day}日',
                style: theme.textTheme.bodyLarge,
              ),
            const Spacer(),
            Text('$count 门课程', style: theme.textTheme.bodyLarge),
          ],
        ),
      ],
    );
  }
}

class _TimetableCourseCard extends StatelessWidget {
  const _TimetableCourseCard({
    required this.course,
    required this.period,
    required this.showWeeks,
  });
  final TimetableCourseDto course;
  final TimetablePeriodDto? period;
  final bool showWeeks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const colors = [
      Color(0xff4b5fba),
      Color(0xff628a92),
      Color(0xff7d6a7f),
      Color(0xff4b5fba),
    ];
    final colorIndex =
        course.name.codeUnits.fold<int>(0, (sum, unit) => sum + unit) %
        colors.length;
    final dark = theme.brightness == Brightness.dark;
    final color = Color.alphaBlend(
      colors[colorIndex].withValues(alpha: dark ? 0.65 : 0.2),
      scheme.surfaceContainerLow,
    );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Column(
                children: [
                  Text(
                    '${course.startSection}-${course.endSection}节',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (period != null) ...[
                    const SizedBox(height: 8),
                    if (period!.startTime.isNotEmpty)
                      Text(
                        period!.startTime,
                        style: theme.textTheme.bodyMedium,
                      ),
                    if (period!.endTime.isNotEmpty)
                      Text(period!.endTime, style: theme.textTheme.bodyMedium),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    course.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '教室 · ${course.location.isEmpty ? '待定' : course.location}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '教师 · ${course.teacher.isEmpty ? '待定' : course.teacher}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (showWeeks && course.weeks.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(course.weeks, style: theme.textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AcademicListPage<T> extends StatefulWidget {
  const _AcademicListPage({
    required this.title,
    required this.load,
    required this.builder,
    this.webPath,
  });
  final String title;
  final Future<List<T>> Function() load;
  final String? webPath;
  final Widget Function(T, VoidCallback) builder;
  @override
  State<_AcademicListPage<T>> createState() => _AcademicListPageState<T>();
}

class _AcademicListPageState<T> extends State<_AcademicListPage<T>> {
  late Future<List<T>> _future = widget.load();
  void _reload() {
    if (mounted) {
      setState(() {
        _future = widget.load();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [
        if (widget.webPath != null)
          _OriginalAcademicButton(title: widget.title, path: widget.webPath!),
        IconButton(
          tooltip: '刷新',
          onPressed: _reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<List<T>>(
      future: _future,
      builder: (_, snapshot) {
        if (snapshot.hasError) {
          return _AcademicError(
            error: snapshot.error,
            webPath: widget.webPath,
            onRetry: _reload,
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.requireData.isEmpty) {
          return const Center(child: Text('当前暂无记录'));
        }
        return RefreshIndicator(
          onRefresh: () async {
            _reload();
            await _future;
          },
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            itemCount: snapshot.requireData.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, index) => Card(
              child: widget.builder(snapshot.requireData[index], _reload),
            ),
          ),
        );
      },
    ),
  );
}

class AcademicWebScreen extends ConsumerStatefulWidget {
  const AcademicWebScreen({super.key, required this.feature});
  final AcademicFeature feature;
  @override
  ConsumerState<AcademicWebScreen> createState() => _AcademicWebScreenState();
}

class _AcademicWebScreenState extends ConsumerState<AcademicWebScreen> {
  WebViewController? _controller;
  Object? _error;
  int _progress = 0;
  bool _canGoBack = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    if (mounted) {
      setState(() {
        _error = null;
        _progress = 0;
      });
    }
    try {
      final url = await ref
          .read(cithubPlatformProvider)
          .prepareAcademicWebPage(widget.feature.webPath!);
      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setOnConsoleMessage(
        (message) => RuntimeLog.write(
          'academic-web-console',
          '${message.level}: ${message.message}',
        ),
      );
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            RuntimeLog.write(
              'academic-web',
              'NAVIGATION ${request.url} mainFrame=${request.isMainFrame}',
            );
            final uri = Uri.tryParse(request.url);
            return uri != null &&
                    (uri.scheme == 'https' || request.url == 'about:blank')
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onPageStarted: (url) {
            RuntimeLog.write('academic-web', 'START $url');
            if (mounted) {
              setState(() {
                _error = null;
                _progress = 0;
              });
            }
          },
          onPageFinished: (url) async {
            RuntimeLog.write('academic-web', 'FINISH $url');
            final back = await controller.canGoBack();
            if (mounted) {
              setState(() {
                _canGoBack = back;
                _progress = 100;
              });
            }
            // Preserve the returned HTML and browser cookies for diagnosis.
            try {
              final page = await controller.runJavaScriptReturningResult(
                'JSON.stringify({url:location.href,cookie:document.cookie,html:document.documentElement.outerHTML})',
              );
              RuntimeLog.write('academic-web-page', '$page');
            } catch (error, stack) {
              RuntimeLog.write('academic-web', '$error\n$stack');
            }
          },
          onWebResourceError: (error) {
            RuntimeLog.write(
              'academic-web-error',
              '${error.errorCode} ${error.description} url=${error.url}',
            );
            if (mounted && error.isForMainFrame != false) {
              setState(() => _error = StateError(error.description));
            }
          },
          onHttpError: (error) => RuntimeLog.write(
            'academic-web-http',
            '${error.response?.statusCode} ${error.request?.uri}',
          ),
        ),
      );
      if (!mounted) return;
      setState(() => _controller = controller);
      await controller.loadRequest(Uri.parse(url));
    } catch (error, stack) {
      RuntimeLog.write('academic-web', '$error\n$stack');
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _back() async {
    if (_controller != null && await _controller!.canGoBack()) {
      await _controller!.goBack();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_canGoBack,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.feature.title),
        leading: IconButton(
          tooltip: '返回',
          onPressed: _back,
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          IconButton(
            tooltip: '关闭网页',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
          IconButton(
            tooltip: '刷新网页',
            onPressed: _prepare,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _error != null
          ? _AcademicError(error: _error, onRetry: _prepare)
          : _controller == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_progress < 100)
                  LinearProgressIndicator(value: _progress / 100),
                Expanded(child: WebViewWidget(controller: _controller!)),
              ],
            ),
    ),
  );
}

Future<void> _openOriginalAcademicPage(
  BuildContext context,
  String title,
  String path,
) async {
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => AcademicWebScreen(
        feature: AcademicFeature(
          'original',
          title,
          '教务系统原始页面',
          Icons.language,
          webPath: path,
        ),
      ),
    ),
  );
}

class _OriginalAcademicButton extends StatelessWidget {
  const _OriginalAcademicButton({required this.title, required this.path});
  final String title;
  final String path;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: '使用教务原始页面',
    onPressed: () => _openOriginalAcademicPage(context, title, path),
    icon: const Icon(Icons.language),
  );
}

class AcademicFeatureOrderScreen extends StatefulWidget {
  const AcademicFeatureOrderScreen({super.key, required this.initial});
  final List<AcademicFeature> initial;
  @override
  State<AcademicFeatureOrderScreen> createState() =>
      _AcademicFeatureOrderScreenState();
}

class _AcademicFeatureOrderScreenState
    extends State<AcademicFeatureOrderScreen> {
  late final _items = [...widget.initial];

  Future<void> _save() async {
    await (await SharedPreferences.getInstance()).setStringList(
      'academic.featureOrder',
      _items.map((item) => item.id).toList(),
    );
    if (mounted) Navigator.pop(context, [..._items]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('功能排序'),
      actions: [TextButton(onPressed: _save, child: const Text('完成'))],
    ),
    body: ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _items.length,
      onReorderItem: (oldIndex, newIndex) => setState(() {
        _items.insert(newIndex, _items.removeAt(oldIndex));
      }),
      itemBuilder: (_, index) => ListTile(
        key: ValueKey(_items[index].id),
        leading: Icon(_items[index].icon),
        title: Text(_items[index].title),
        trailing: const Icon(Icons.drag_handle),
      ),
    ),
  );
}

class _AcademicError extends StatelessWidget {
  const _AcademicError({
    required this.error,
    required this.onRetry,
    this.onReconnect,
    this.webPath,
  });
  final Object? error;
  final VoidCallback onRetry;
  final VoidCallback? onReconnect;
  final String? webPath;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 36,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              userFacingError(error, fallback: '暂时无法连接服务'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
            if (webPath != null)
              TextButton(
                onPressed: () async {
                  await _openOriginalAcademicPage(context, '教务原始页面', webPath!);
                  if (context.mounted) onRetry();
                },
                child: const Text('使用教务原始页面'),
              ),
            if (onReconnect != null)
              TextButton(
                onPressed: onReconnect,
                child: const Text('重新连接 WebVPN'),
              ),
            if (Navigator.of(context).canPop())
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('返回教务首页 / 重新登录'),
              ),
          ],
        ),
      ),
    ),
  );
}
