import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/native/cithub_api.g.dart';
import '../../core/platform/cithub_platform.dart';

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
  late Future<WebVpnSessionDto> _session;
  List<AcademicFeature> _features = [...academicFeatures];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _session = ref.read(cithubPlatformProvider).initializeWebVpn();
    _restoreFeatureOrder();
  }

  Future<void> _restoreFeatureOrder() async {
    final ids = (await SharedPreferences.getInstance()).getStringList(
      'academic.featureOrder',
    );
    if (ids == null || !mounted) return;
    final ordered = ids
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

  void _setSession(Future<WebVpnSessionDto> value) =>
      setState(() => _session = value);

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
          future: _session,
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
            if (session.status != AuthStatus.signedIn) {
              return SliverPadding(
                padding: const EdgeInsets.only(bottom: 32),
                sliver: SliverToBoxAdapter(
                  child: WebVpnLoginPanel(
                    session: session,
                    onLogin: (request) => _setSession(
                      ref.read(cithubPlatformProvider).loginWebVpn(request),
                    ),
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
              webVpnSession: session,
              features: _features,
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
    required this.webVpnSession,
    required this.features,
    required this.onWebVpnLogout,
  });

  final WebVpnSessionDto webVpnSession;
  final List<AcademicFeature> features;
  final VoidCallback onWebVpnLogout;

  @override
  ConsumerState<_AcademicSessionSliver> createState() =>
      _AcademicSessionSliverState();
}

class _AcademicSessionSliverState
    extends ConsumerState<_AcademicSessionSliver> {
  late Future<WebVpnSessionDto> _session;

  @override
  void initState() {
    super.initState();
    _session = ref
        .read(cithubPlatformProvider)
        .initializeAcademic(widget.webVpnSession.user?.username ?? '');
  }

  void _set(Future<WebVpnSessionDto> value) => setState(() => _session = value);

  @override
  Widget build(BuildContext context) => FutureBuilder<WebVpnSessionDto>(
    future: _session,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return SliverFillRemaining(
          child: _AcademicError(
            error: snapshot.error,
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
              title: '登录教务系统',
              description: '教务账号独立登录，密码只在本机加密保存。',
              usernameLabel: '教务系统账号',
              passwordLabel: '教务系统密码',
              icon: Icons.school_outlined,
              onLogin: (request) =>
                  _set(ref.read(cithubPlatformProvider).loginAcademic(request)),
              onRefreshCaptcha: () => _set(
                ref
                    .read(cithubPlatformProvider)
                    .initializeAcademic(
                      widget.webVpnSession.user?.username ?? '',
                    ),
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
              itemBuilder: (_, index) =>
                  _AcademicFeatureCard(feature: widget.features[index]),
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
    this.title = '登录 WebVPN',
    this.description = '登录后可访问教务系统；新应用不会读取旧版账号。',
    this.usernameLabel = '统一身份认证账号',
    this.passwordLabel = '密码',
    this.icon = Icons.shield_outlined,
    this.onSelectSavedAccount,
    this.onForgetSavedAccount,
  });
  final WebVpnSessionDto session;
  final ValueChanged<LoginRequestDto> onLogin;
  final VoidCallback onRefreshCaptcha;
  final String title;
  final String description;
  final String usernameLabel;
  final String passwordLabel;
  final IconData icon;
  final ValueChanged<String>? onSelectSavedAccount;
  final ValueChanged<String>? onForgetSavedAccount;

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
    if (recognized.isNotEmpty && recognized != _captcha.text) {
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
                            onPressed: widget.onRefreshCaptcha,
                            tooltip: '刷新验证码',
                            icon: const Icon(Icons.refresh),
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
                  title: const Text('使用 Android Keystore 在本机加密保存密码'),
                  onChanged: (value) =>
                      setState(() => _remember = value ?? false),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => widget.onLogin(
                    LoginRequestDto(
                      username: _username.text.trim(),
                      password: _password.text,
                      captchaId: widget.session.captcha?.id ?? '',
                      captchaCode: _captcha.text.trim(),
                      rememberPassword: _remember,
                      useSavedPassword: _useSavedPassword,
                    ),
                  ),
                  child: const Text('登录'),
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
  const _AcademicFeatureCard({required this.feature});
  final AcademicFeature feature;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        final page = switch (feature.id) {
          'grades' => const GradesScreen(),
          'timetable' => const TimetableScreen(),
          'selection_results' => const SelectionResultsScreen(),
          'evaluation' => const EvaluationScreen(),
          _ => AcademicWebScreen(feature: feature),
        };
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
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
  late final Future<List<AcademicTermDto>> _terms;
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
    appBar: AppBar(title: const Text('成绩查询')),
    body: FutureBuilder<List<AcademicTermDto>>(
      future: _terms,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('学期加载失败：${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final terms = snapshot.requireData;
        if (terms.isEmpty) return const Center(child: Text('教务系统未返回学期'));
        _selected ??=
            terms.where((term) => term.selected).firstOrNull?.value ??
            terms.first.value;
        _items ??= ref
            .read(cithubPlatformProvider)
            .loadGrades(_selected!, bestOnly: _bestOnly);
        return Column(
          children: [
            Padding(
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
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                Text(
                                  '按学期筛选课程成绩',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      LayoutBuilder(
                        builder: (context, constraints) => DropdownMenu<String>(
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
            Expanded(
              child: FutureBuilder<List<CourseGradeDto>>(
                future: _items,
                builder: (context, items) {
                  if (items.hasError) {
                    return Center(child: Text('加载失败：${items.error}'));
                  }
                  if (!items.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (items.requireData.isEmpty) {
                    return const Center(child: Text('该学期暂无记录'));
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                    itemCount: items.requireData.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, index) =>
                        _GradeCard(item: items.requireData[index]),
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
          ],
        ),
      ),
    );
  }
}

class SelectionResultsScreen extends ConsumerWidget {
  const SelectionResultsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _TermAcademicListPage<SelectedCourseDto>(
        title: '选课结果',
        load: (term) =>
            ref.read(cithubPlatformProvider).loadSelectionResults(term),
        builder: (item) => ListTile(
          title: Text(item.courseName),
          subtitle: Text(
            '${item.teacher} · ${item.credit} 学分 · ${item.courseNature}',
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
  late final Future<List<AcademicTermDto>> _terms;
  String? _selected;
  Future<List<T>>? _items;

  @override
  void initState() {
    super.initState();
    _terms = ref.read(cithubPlatformProvider).loadAcademicTerms();
  }

  void _select(String value) {
    setState(() {
      _selected = value;
      _items = widget.load(value);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: FutureBuilder<List<AcademicTermDto>>(
      future: _terms,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('学期加载失败：${snapshot.error}'));
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
        return Column(
          children: [
            Padding(
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
            Expanded(
              child: FutureBuilder<List<T>>(
                future: _items,
                builder: (context, items) {
                  if (items.hasError) {
                    return Center(child: Text('加载失败：${items.error}'));
                  }
                  if (!items.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (items.requireData.isEmpty) {
                    return const Center(child: Text('该学期暂无记录'));
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    itemCount: items.requireData.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, index) =>
                        Card(child: widget.builder(items.requireData[index])),
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

class EvaluationScreen extends ConsumerWidget {
  const EvaluationScreen({super.key});
  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) => _AcademicListPage<EvaluationBatchDto>(
    title: '学生评价',
    future: ref.read(cithubPlatformProvider).loadEvaluationBatches(),
    builder: (item) => ListTile(
      title: Text(item.name),
      subtitle: Text('${item.semester} · ${item.startDate} 至 ${item.endDate}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => EvaluationCoursesScreen(batch: item)),
      ),
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
        future: ref
            .read(cithubPlatformProvider)
            .loadEvaluationCourses(batch.courseListPath),
        builder: (item) => ListTile(
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
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EvaluationFormScreen(course: item),
            ),
          ),
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
  late final Future<EvaluationFormDto> _future;
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
      await ref
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
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(submit ? '评价已提交' : '评价草稿已保存')));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$error')));
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
          return Center(child: Text('评价表加载失败：${snapshot.error}'));
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

class TimetableScreen extends ConsumerWidget {
  const TimetableScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('我的课表')),
    body: FutureBuilder<TimetableDto>(
      future: ref.read(cithubPlatformProvider).loadTimetable(),
      builder: (_, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.requireData;
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          itemCount: data.courses.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, index) {
            final item = data.courses[index];
            return Card(
              child: ListTile(
                leading: CircleAvatar(child: Text('周${item.dayOfWeek}')),
                title: Text(item.name),
                subtitle: Text(
                  '${item.weeks}\n${item.teacher} · ${item.location}',
                ),
                isThreeLine: true,
              ),
            );
          },
        );
      },
    ),
  );
}

class _AcademicListPage<T> extends StatelessWidget {
  const _AcademicListPage({
    required this.title,
    required this.future,
    required this.builder,
  });
  final String title;
  final Future<List<T>> future;
  final Widget Function(T) builder;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: FutureBuilder<List<T>>(
      future: future,
      builder: (_, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('加载失败：${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          itemCount: snapshot.requireData.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, index) =>
              Card(child: builder(snapshot.requireData[index])),
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
  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final url = await ref
          .read(cithubPlatformProvider)
          .prepareAcademicWebPage(widget.feature.webPath!);
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) {
              final uri = Uri.tryParse(request.url);
              return uri != null && uri.scheme == 'https'
                  ? NavigationDecision.navigate
                  : NavigationDecision.prevent;
            },
          ),
        )
        ..loadRequest(Uri.parse(url));
      if (mounted) setState(() => _controller = controller);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.feature.title)),
    body: _error != null
        ? Center(child: Text('加载失败：$_error'))
        : _controller == null
        ? const Center(child: CircularProgressIndicator())
        : WebViewWidget(controller: _controller!),
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
  const _AcademicError({required this.error, required this.onRetry});
  final Object? error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('连接失败：$error'),
        const SizedBox(height: 12),
        FilledButton(onPressed: onRetry, child: const Text('重试')),
      ],
    ),
  );
}
