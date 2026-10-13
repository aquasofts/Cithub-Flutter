import 'package:flutter/material.dart';

List<ContextMenuButtonItem> _chineseButtons(
  List<ContextMenuButtonItem> items,
) => items
    .map(
      (item) => item.copyWith(
        label: switch (item.type) {
          ContextMenuButtonType.cut => '剪切',
          ContextMenuButtonType.copy => '复制',
          ContextMenuButtonType.paste => '粘贴',
          ContextMenuButtonType.selectAll => '全选',
          ContextMenuButtonType.delete => '删除',
          ContextMenuButtonType.lookUp => '查询',
          ContextMenuButtonType.searchWeb => '搜索',
          ContextMenuButtonType.share => '分享',
          ContextMenuButtonType.liveTextInput => '扫描文本',
          ContextMenuButtonType.custom => item.label,
        },
      ),
    )
    .toList();

/// Keep Flutter's enabled actions and platform layout, with Chinese labels even
/// when the phone's native text menu is configured for a different language.
Widget chineseEditableTextMenu(BuildContext context, EditableTextState state) =>
    AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: _chineseButtons(state.contextMenuButtonItems),
    );

Widget chineseSelectionMenu(
  BuildContext context,
  SelectableRegionState state,
) => AdaptiveTextSelectionToolbar.buttonItems(
  anchors: state.contextMenuAnchors,
  buttonItems: _chineseButtons(state.contextMenuButtonItems),
);
