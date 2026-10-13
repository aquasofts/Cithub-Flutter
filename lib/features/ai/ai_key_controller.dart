import 'package:flutter/material.dart';

/// Masks only the Flutter rendering, keeping the platform input configuration
/// as ordinary text so phone keyboards do not switch to password mode.
class AiKeyController extends TextEditingController {
  AiKeyController({super.text});
  bool _revealed = false;
  bool get revealed => _revealed;
  void toggleVisibility() {
    _revealed = !_revealed;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (_revealed) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    return TextSpan(text: '•' * text.length, style: style);
  }
}
