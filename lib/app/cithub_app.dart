import 'package:flutter/material.dart';
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
