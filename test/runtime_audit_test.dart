import 'dart:convert';

import 'package:cithub_flutter/core/logging/runtime_audit.dart';
import 'package:cithub_flutter/core/logging/runtime_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('records page visits, manual edits, control changes and taps', (
    tester,
  ) async {
    final entries = <Map<String, dynamic>>[];
    const channel = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.cithub_flutter.RuntimeLogHostApi.append',
      StandardMessageCodec(),
    );
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
      channel,
      (value) async {
        final args = value! as List;
        entries.add({
          'source': args[0],
          ...jsonDecode(args[1] as String) as Map<String, dynamic>,
        });
        return [true];
      },
    );
    final controller = TextEditingController();
    var selected = false;
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [RuntimeNavigatorObserver()],
        builder: (_, child) => RuntimeAudit(child: child!),
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: Column(
              children: [
                TextField(controller: controller),
                Checkbox(
                  value: selected,
                  onChanged: (value) => setState(() => selected = value!),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    LoggedMaterialPageRoute<void>(
                      builder: (_) => const Scaffold(body: Text('详情页')),
                    ),
                  ),
                  child: const Text('打开详情'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '手动修改内容');
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();
    await tester.runAsync(RuntimeLog.flush);
    expect(
      entries.any(
        (e) => e['source'] == 'input' && e['data']['after'] == '手动修改内容',
      ),
      isTrue,
    );
    expect(
      entries.any(
        (e) =>
            e['source'] == 'control' &&
            e['action'] == 'changed' &&
            e['data']['after'] == true,
      ),
      isTrue,
    );
    expect(
      entries.any(
        (e) =>
            e['source'] == 'interaction' &&
            (e['data']['targets'] as List).contains('打开详情'),
      ),
      isTrue,
    );
    expect(
      entries.any((e) => e['source'] == 'page' && e['action'] == 'opened'),
      isTrue,
    );
    expect(
      entries.any((e) => e['source'] == 'navigation' && e['action'] == 'push'),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(RuntimeLog.flush);
    controller.dispose();
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
      channel,
      null,
    );
  });
}
