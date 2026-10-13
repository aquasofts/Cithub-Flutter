/// Splits UTF-16 strings without cutting a surrogate pair in half.
List<String> chunkText(String text, {int length = 12000}) {
  if (text.isEmpty) return [''];
  final chunks = <String>[];
  var start = 0;
  while (start < text.length) {
    var end = (start + length).clamp(0, text.length);
    if (end < text.length &&
        text.codeUnitAt(end - 1) >= 0xd800 &&
        text.codeUnitAt(end - 1) <= 0xdbff) {
      end--;
    }
    chunks.add(text.substring(start, end));
    start = end;
  }
  return chunks;
}
