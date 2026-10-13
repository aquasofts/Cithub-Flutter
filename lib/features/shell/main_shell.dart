import '../../core/logging/runtime_log.dart';
import '../../core/logging/runtime_audit.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/native/cithub_api.g.dart';
import '../../core/platform/cithub_platform.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/navigation_state.dart';
import '../academic/academic_screen.dart';
import '../mine/mine_screen.dart';
import '../ai/ai_screen.dart';
import '../tieba/tieba_screen.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _index = 0;
  final _navigators = List.generate(4, (_) => GlobalKey<NavigatorState>());
  late final List<NavigatorObserver> _navigatorObservers;

  static const _roots = <Widget>[
    TiebaScreen(key: PageStorageKey('tieba')),
    AiScreen(key: PageStorageKey('ai')),
    AcademicScreen(key: PageStorageKey('academic')),
    MineScreen(key: PageStorageKey('mine')),
  ];

  @override
  void initState() {
    super.initState();
    _navigatorObservers = List.generate(
      _roots.length,
      (_) => _TabNavigatorObserver(() {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      }),
    );
  }

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.forum_outlined),
      selectedIcon: Icon(Icons.forum),
      label: '贴吧',
    ),
    NavigationDestination(
      icon: Icon(Icons.auto_awesome_outlined),
      selectedIcon: Icon(Icons.auto_awesome),
      label: 'AI',
    ),
    NavigationDestination(
      icon: Icon(Icons.school_outlined),
      selectedIcon: Icon(Icons.school),
      label: '教务',
    ),
    NavigationDestination(
      icon: Icon(Icons.person_outline),
      selectedIcon: Icon(Icons.person),
      label: '我的',
    ),
  ];

  Future<void> _recheckWebVpnSession() async {
    final current = ref.read(webVpnSessionProvider);
    try {
      final session = await current;
      if (!mounted ||
          !identical(ref.read(webVpnSessionProvider), current) ||
          session.status != AuthStatus.signedIn) {
        return;
      }
      ref.read(webVpnSessionProvider.notifier).state = ref
          .read(cithubPlatformProvider)
          .initializeWebVpn();
    } catch (_) {
      // The Academic tab already displays the initialization error and retry.
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = ref.watch(
      appSettingsProvider.select((value) => value.reduceMotion),
    );
    final activeNavigator = _navigators[_index].currentState;
    return PopScope(
      canPop: !(activeNavigator?.canPop() ?? false),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _navigators[_index].currentState?.maybePop();
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _index,
            children: List.generate(
              _roots.length,
              (index) => TickerMode(
                enabled: index == _index,
                child: Navigator(
                  key: _navigators[index],
                  observers: [
                    _navigatorObservers[index],
                    RuntimeNavigatorObserver('tab:$index'),
                  ],
                  onGenerateRoute: (_) => LoggedMaterialPageRoute<void>(
                    builder: (_) => _roots[index],
                  ),
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          animationDuration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 350),
          destinations: _destinations,
          onDestinationSelected: (value) {
            RuntimeLog.event('navigation', 'tab-selected', {
              'from': _index,
              'to': value,
              'page': '${_roots[value].runtimeType}',
            });
            if (value == _index) {
              _navigators[value].currentState?.popUntil(
                (route) => route.isFirst,
              );
            } else {
              setState(() => _index = value);
              ref.read(mainTabProvider.notifier).state = value;
              if (value == 2) _recheckWebVpnSession();
            }
          },
        ),
      ),
    );
  }
}

class _TabNavigatorObserver extends NavigatorObserver {
  _TabNavigatorObserver(this.onChanged);
  final VoidCallback onChanged;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onChanged();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onChanged();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onChanged();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    onChanged();
  }
}
