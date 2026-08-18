import 'package:cithub_flutter/core/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('normalizes forum names with or without trailing 吧', () {
    expect(normalizeTiebaForumName(' 长春工程学院吧 '), '长春工程学院');
    expect(normalizeTiebaForumName('南湖吧吧'), '南湖');
    expect(displayTiebaForumName('南湖'), '南湖吧');
    expect(displayTiebaForumName(''), '长春工程学院吧');
  });

  test('persists and restores the home forum name', () async {
    final controller = AppSettingsController();
    await Future<void>.delayed(Duration.zero);
    await controller.setTiebaHomeForumName('南湖吧');
    expect(controller.state.tiebaHomeForumName, '南湖');
    expect(
      (await SharedPreferences.getInstance()).getString('tieba.homeForumName'),
      '南湖',
    );
    controller.dispose();

    final restored = AppSettingsController();
    await Future<void>.delayed(Duration.zero);
    expect(restored.state.tiebaHomeForumName, '南湖');
    restored.dispose();
  });
}
