import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:cithub_flutter/features/ai/ai_attachments.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> office(Map<String, String> entries) {
  final archive = Archive();
  for (final e in entries.entries) {
    archive.addFile(ArchiveFile.string(e.key, e.value));
  }
  return ZipEncoder().encode(archive);
}

void main() {
  test('DOCX includes table paragraphs and Chinese text', () {
    final bytes = office({
      'word/document.xml': '<w:document xmlns:w="word"><w:body><w:p><w:r><w:t>课程表</w:t></w:r></w:p><w:tbl><w:tr><w:tc><w:p><w:r><w:t>数学 周一1-2节</w:t></w:r></w:p></w:tc></w:tr></w:tbl></w:body></w:document>',
    });
    final blocks = extractOffice(bytes, 'docx');
    expect(blocks.single['text'], '课程表\n数学 周一1-2节');
  });
  test('XLSX preserves sheet names, shared strings, inline values and cell coordinates', () {
    final bytes = office({
      'xl/workbook.xml': '<workbook xmlns:r="rel"><sheets><sheet name="课表" r:id="r1"/></sheets></workbook>',
      'xl/_rels/workbook.xml.rels': '<Relationships><Relationship Id="r1" Target="worksheets/sheet1.xml"/></Relationships>',
      'xl/sharedStrings.xml': '<sst><si><t>数学</t></si></sst>',
      'xl/worksheets/sheet1.xml': '<worksheet><sheetData><row><c r="A1" t="s"><v>0</v></c><c r="B1" t="inlineStr"><is><t>周一</t></is></c><c r="C1"><v>2</v></c></row></sheetData></worksheet>',
    });
    final block = extractOffice(bytes, 'xlsx').single;
    expect(block['label'], contains('课表'));
    expect(block['text'], 'A1=数学\tB1=周一\tC1=2');
  });
  test('text chunks preserve emoji on the boundary and malformed office files fail', () {
    final text = 'a' * 11999 + '😀数学';
    final blocks = textBlocks(text, '正文');
    expect(blocks.map((b) => b['text']).join(), text);
    for (final b in blocks) {
      expect(utf8.decode(utf8.encode(b['text'] as String)), b['text']);
    }
    expect(
      () => extractOffice(office({'wrong.xml': '<xml/>'}), 'docx'),
      throwsFormatException,
    );
  });
}
