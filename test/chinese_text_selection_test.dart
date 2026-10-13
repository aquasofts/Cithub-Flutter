import 'package:cithub_flutter/core/widgets/chinese_text_selection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'selected text uses Chinese menu labels even with English app locale',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SelectionArea(
                contextMenuBuilder: chineseSelectionMenu,
                child: Text('hello world'),
              ),
            ),
          ),
        ),
      );
      await tester.longPress(find.text('hello world'));
      await tester.pumpAndSettle();
      expect(find.text('复制'), findsOneWidget);
      expect(find.text('全选'), findsOneWidget);
      expect(find.text('Copy'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('editable text uses Chinese cut, copy and select-all actions', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'hello world');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: controller,
            contextMenuBuilder: chineseEditableTextMenu,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    await tester.pump();
    tester.state<EditableTextState>(find.byType(EditableText)).showToolbar();
    await tester.pumpAndSettle();
    expect(find.text('剪切'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
    expect(find.text('Cut'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
