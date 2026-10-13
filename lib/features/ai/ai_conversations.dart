import 'dart:convert';

import '../../core/storage/local_database.dart';
import 'ai_attachments.dart';

class AiConversation {
  AiConversation({
    required this.id,
    this.title = '新会话',
    this.model = '',
    List<Map<String, dynamic>>? messages,
    List<Map<String, dynamic>>? display,
    List<AiAttachment>? attachments,
  }) : messages = messages ?? [],
       display = display ?? [],
       attachments = attachments ?? [];
  final String id;
  String title, model;
  final List<Map<String, dynamic>> messages;
  final List<Map<String, dynamic>> display;
  final List<AiAttachment> attachments;
  Map<String, dynamic> toJson() => {
    'messages': messages,
    'display': display,
    'attachments': attachments.map((a) => a.toJson()).toList(),
  };
  factory AiConversation.fromRow(Map<String, Object?> row) {
    final body = jsonDecode(row['messages'] as String) as Map<String, dynamic>;
    return AiConversation(
      id: row['id'] as String,
      title: row['title'] as String,
      model: row['model'] as String,
      messages: (body['messages'] as List)
          .map((m) => Map<String, dynamic>.from(m as Map))
          .toList(),
      display: (body['display'] as List)
          .map((m) => Map<String, dynamic>.from(m as Map))
          .toList(),
      attachments: (body['attachments'] as List? ?? [])
          .map(
            (a) => AiAttachment.fromJson(Map<String, dynamic>.from(a as Map)),
          )
          .toList(),
    );
  }
}

class AiConversationRepository {
  AiConversationRepository(this.store);
  final LocalDatabase store;
  Future<List<AiConversation>> all() async =>
      (await (await store.database).query(
        'conversations',
        orderBy: 'updated_at DESC',
      )).map(AiConversation.fromRow).toList();
  Future<void> save(AiConversation c) async => (await store.database).rawInsert(
    'INSERT OR REPLACE INTO conversations(id,title,model,updated_at,messages) VALUES(?,?,?,?,?)',
    [
      c.id,
      c.title,
      c.model,
      DateTime.now().toIso8601String(),
      jsonEncode(c.toJson()),
    ],
  );
  Future<void> delete(AiConversation c) async {
    await (await store.database).delete(
      'conversations',
      where: 'id = ?',
      whereArgs: [c.id],
    );
    for (final a in c.attachments) {
      await deleteAttachment(a);
    }
  }
}
