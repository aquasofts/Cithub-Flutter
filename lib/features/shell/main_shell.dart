import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/app_settings.dart';
import '../academic/academic_screen.dart';
import '../mine/mine_screen.dart';
import '../news/news_screen.dart';
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
    NewsScreen(key: PageStorageKey('news')),
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
      icon: Icon(Icons.newspaper_outlined),
      selectedIcon: Icon(Icons.newspaper),
      label: '新闻',
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
              (index) => Navigator(
                key: _navigators[index],
                observers: [_navigatorObservers[index]],
                onGenerateRoute: (_) =>
                    MaterialPageRoute<void>(builder: (_) => _roots[index]),
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
            if (value == _index) {
              _navigators[value].currentState?.popUntil(
                (route) => route.isFirst,
              );
            } else {
              setState(() => _index = value);
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
