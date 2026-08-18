import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const defaultTiebaHomeForum = '长春工程学院';

String normalizeTiebaForumName(String value) {
  var normalized = value.trim();
  while (normalized.endsWith('吧')) {
    normalized = normalized.substring(0, normalized.length - 1).trimRight();
  }
  return normalized;
}

String displayTiebaForumName(String value) {
  final normalized = normalizeTiebaForumName(value);
  return '${normalized.isEmpty ? defaultTiebaHomeForum : normalized}吧';
}

@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.seedColor = const Color(0xff00639b),
    this.amoled = false,
    this.reduceMotion = false,
    this.themedIcon = false,
    this.compactNavigation = false,
    this.tiebaHomeForumName = defaultTiebaHomeForum,
  });

  final ThemeMode themeMode;
  final Color seedColor;
  final bool amoled;
  final bool reduceMotion;
  final bool themedIcon;
  final bool compactNavigation;
  final String tiebaHomeForumName;

  AppSettings copyWith({
    ThemeMode? themeMode,
    Color? seedColor,
    bool? amoled,
    bool? reduceMotion,
    bool? themedIcon,
    bool? compactNavigation,
    String? tiebaHomeForumName,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    seedColor: seedColor ?? this.seedColor,
    amoled: amoled ?? this.amoled,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    themedIcon: themedIcon ?? this.themedIcon,
    compactNavigation: compactNavigation ?? this.compactNavigation,
    tiebaHomeForumName: tiebaHomeForumName ?? this.tiebaHomeForumName,
  );
}

class AppSettingsController extends StateNotifier<AppSettings> {
  AppSettingsController() : super(const AppSettings()) {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final themeName = prefs.getString('appearance.themeMode');
    ThemeMode? themeMode;
    for (final item in ThemeMode.values) {
      if (item.name == themeName) themeMode = item;
    }
    state = state.copyWith(
      themeMode: themeMode,
      seedColor: Color(
        prefs.getInt('appearance.seedColor') ?? state.seedColor.toARGB32(),
      ),
      amoled: prefs.getBool('appearance.amoled') ?? false,
      reduceMotion: prefs.getBool('appearance.reduceMotion') ?? false,
      themedIcon: prefs.getBool('appearance.themedIcon') ?? false,
      compactNavigation: prefs.getBool('appearance.compactNavigation') ?? false,
      tiebaHomeForumName: normalizeTiebaForumName(
        prefs.getString('tieba.homeForumName') ?? defaultTiebaHomeForum,
      ),
    );
  }

  Future<void> setThemeMode(ThemeMode value) async {
    state = state.copyWith(themeMode: value);
    await (await SharedPreferences.getInstance()).setString(
      'appearance.themeMode',
      value.name,
    );
  }

  Future<void> setSeedColor(Color value) async {
    state = state.copyWith(seedColor: value);
    await (await SharedPreferences.getInstance()).setInt(
      'appearance.seedColor',
      value.toARGB32(),
    );
  }

  Future<void> setAmoled(bool value) async {
    state = state.copyWith(amoled: value);
    await (await SharedPreferences.getInstance()).setBool(
      'appearance.amoled',
      value,
    );
  }

  Future<void> setReduceMotion(bool value) async {
    state = state.copyWith(reduceMotion: value);
    await (await SharedPreferences.getInstance()).setBool(
      'appearance.reduceMotion',
      value,
    );
  }

  Future<void> setThemedIcon(bool value) async {
    state = state.copyWith(themedIcon: value);
    await (await SharedPreferences.getInstance()).setBool(
      'appearance.themedIcon',
      value,
    );
  }

  Future<void> setCompactNavigation(bool value) async {
    state = state.copyWith(compactNavigation: value);
    await (await SharedPreferences.getInstance()).setBool(
      'appearance.compactNavigation',
      value,
    );
  }

  Future<void> setTiebaHomeForumName(String value) async {
    final normalized = normalizeTiebaForumName(value);
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'value', '吧名不能为空');
    }
    state = state.copyWith(tiebaHomeForumName: normalized);
    await (await SharedPreferences.getInstance()).setString(
      'tieba.homeForumName',
      normalized,
    );
  }
}

final appSettingsProvider =
    StateNotifierProvider<AppSettingsController, AppSettings>(
      (ref) => AppSettingsController(),
    );
