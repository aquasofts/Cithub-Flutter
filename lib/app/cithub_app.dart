import '../core/logging/runtime_audit.dart';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings/app_settings.dart';
import '../core/theme/cithub_theme.dart';
import '../features/shell/main_shell.dart';

class CithubApp extends ConsumerWidget {
  const CithubApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    return MaterialApp(
      title: 'Cithub Flutter',
      navigatorObservers: [RuntimeNavigatorObserver()],
      builder: (context, child) =>
          RuntimeAudit(child: child ?? const SizedBox.shrink()),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      debugShowCheckedModeBanner: false,
      theme: buildCithubTheme(settings, Brightness.light),
      darkTheme: buildCithubTheme(settings, Brightness.dark),
      themeMode: settings.themeMode,
      themeAnimationDuration: settings.reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 250),
      home: const MainShell(),
    );
  }
}
