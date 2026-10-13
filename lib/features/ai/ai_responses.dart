import 'dart:convert';

/// Translate local Chat Completions history to stateless Responses input.
Map<String, dynamic> responsesBody(
  String model,
  List<Map<String, dynamic>> messages,
  List<Map<String, dynamic>> tools, {
  bool webSearch = false,
  String reasoningEffort = 'default',
  bool reasoning = false,
}) => {
  'model': model,
  'stream': true,
  'store': false,
  'include': [
    'reasoning.encrypted_content',
    if (webSearch) 'web_search_call.action.sources',
  ],
  if (reasoning)
    'reasoning': {
      if (reasoningEffort != 'default') 'effort': reasoningEffort,
      'summary': 'auto',
    },
  'input': [for (final message in messages) ..._input(message)],
  if (tools.isNotEmpty || webSearch)
    'tools': [
      if (webSearch) {'type': 'web_search'},
      for (final tool in tools)
        {
          'type': 'function',
          ...Map<String, dynamic>.from(tool['function'] as Map),
          'strict': false,
        },
    ],
  if (tools.isNotEmpty || webSearch) 'tool_choice': 'auto',
};

List<Map<String, dynamic>> _input(Map<String, dynamic> message) {
  if (message['_responsesOutput'] is List) {
    return (message['_responsesOutput'] as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }
  if (message['role'] == 'tool') {
    return [
      {
        'type': 'function_call_output',
        'call_id': message['tool_call_id'],
        'output': message['content'],
      },
    ];
  }
  final content = message['content'];
  return [
    if (content != null && (content is! String || content.isNotEmpty))
      {
        'role': message['role'],
        'content': content is List
            ? [
                for (final part in content)
                  if (part['type'] == 'image_url')
                    {
                      'type': 'input_image',
                      'image_url': part['image_url']['url'],
                      if (part['image_url']['detail'] != null)
                        'detail': part['image_url']['detail'],
                    }
                  else if (part['type'] == 'text')
                    {
                      'type': message['role'] == 'assistant'
                          ? 'output_text'
                          : 'input_text',
                      'text': part['text'],
                    },
              ]
            : content,
      },
    for (final call in message['tool_calls'] as List? ?? [])
      {
        'type': 'function_call',
        'call_id': call['id'],
        'name': call['function']['name'],
        'arguments': call['function']['arguments'],
      },
  ];
}

List<Map<String, dynamic>> responseOutput(Map<String, dynamic> response) {
  if (response['error'] != null ||
      response['status'] == 'failed' ||
      response['status'] == 'incomplete') {
    throw StateError('Responses API 未完成回复，请检查模型、额度或输出限制后重试');
  }
  return (response['output'] as List? ?? [])
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();
}

List<Map<String, dynamic>> responseCalls(List<Map<String, dynamic>> output) => [
  for (final item in output)
    if (item['type'] == 'function_call')
      {
        'id': item['call_id'],
        'type': 'function',
        'function': {
          'name': item['name'],
          'arguments': item['arguments'] ?? '{}',
        },
      },
];

String responseText(
  List<Map<String, dynamic>> output, {
  bool reasoning = false,
}) => [
  for (final item in output)
    if (item['type'] == (reasoning ? 'reasoning' : 'message'))
      for (final part in item[reasoning ? 'summary' : 'content'] as List? ?? [])
        if (part['text'] is String) part['text'] as String,
].join();

/// Emit the final SSE frame at EOF too, as some compatible servers omit its
/// terminating empty line. UTF-8 decoding remains incremental.
Stream<String> ssePayloads(Stream<List<int>> stream) async* {
  final data = <String>[];
  await for (final line
      in stream.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.startsWith('data:')) {
      data.add(line.substring(5).trimLeft());
    } else if (line.isEmpty && data.isNotEmpty) {
      yield data.join('\n');
      data.clear();
    }
  }
  if (data.isNotEmpty) yield data.join('\n');
}

List<Map<String, dynamic>> responseCitations(
  List<Map<String, dynamic>> output,
) => [
  for (final item in output)
    if (item['type'] == 'message')
      for (final part in item['content'] as List? ?? [])
        ...normalizeCitations(part['annotations'] as List? ?? []),
];

List<Map<String, dynamic>> normalizeCitations(List<dynamic> annotations) => [
  for (final entry in annotations)
    if (entry is Map && entry['type'] == 'url_citation')
      Map<String, dynamic>.from(
        entry['url_citation'] is Map ? entry['url_citation'] as Map : entry,
      ),
];

String textWithCitations(String text, List<Map<String, dynamic>> citations) {
  final valid = citations
      .where((c) => Uri.tryParse(c['url'] as String? ?? '')?.scheme == 'https')
      .toList();
  var result = text;
  final insertions = <({int offset, String link})>[];
  final footnotes = <String>[];
  for (var i = 0; i < valid.length; i++) {
    final c = valid[i];
    final url = (c['url'] as String)
        .replaceAll('(', '%28')
        .replaceAll(')', '%29');
    final link = '[来源 ${i + 1}]($url)';
    final end = (c['end_index'] as num?)?.toInt();
    if (end != null && end >= 0 && end <= text.runes.length) {
      final offset = String.fromCharCodes(text.runes.take(end)).length;
      insertions.add((offset: offset, link: link));
    } else {
      footnotes.add(link);
    }
  }
  insertions.sort((a, b) => b.offset.compareTo(a.offset));
  for (final item in insertions) {
    result =
        '${result.substring(0, item.offset)} ${item.link}${result.substring(item.offset)}';
  }
  if (footnotes.isNotEmpty) result += '\n\n${footnotes.join(' · ')}';
  return result;
}
