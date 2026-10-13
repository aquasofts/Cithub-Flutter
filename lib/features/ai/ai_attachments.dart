import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import '../../core/utils/text_chunks.dart';

import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:xml/xml.dart';

import '../../core/storage/local_database.dart';
import 'ai_client.dart';

class AiAttachment {
  AiAttachment({
    required this.id,
    required this.name,
    required this.path,
    required this.blocks,
    this.image = false,
  });
  final String id, name, path;
  final bool image;
  final List<Map<String, dynamic>> blocks;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'blocks': blocks,
    'image': image,
  };
  factory AiAttachment.fromJson(Map<String, dynamic> v) => AiAttachment(
    id: v['id'] as String,
    name: v['name'] as String,
    path: v['path'] as String,
    blocks: (v['blocks'] as List)
        .map((b) => Map<String, dynamic>.from(b as Map))
        .toList(),
    image: v['image'] == true,
  );
  Map<String, dynamic> get manifest => {
    'id': id,
    'filename': name,
    'blocks': blocks.length,
    'image': image,
    'sections': blocks.map((b) => b['label']).toList(),
  };
  Future<Map<String, dynamic>> read(
    int index,
    bool supportsImages,
    AiCancellation cancellation,
  ) async {
    cancellation.check();
    if (image) {
      if (!supportsImages) throw StateError('请选择支持图片的模型');
      final bytes = await File(path).readAsBytes();
      return {
        'filename': name,
        'image':
            'data:image/${path.toLowerCase().endsWith('.png')
                ? 'png'
                : path.toLowerCase().endsWith('.webp')
                ? 'webp'
                : 'jpeg'};base64,${base64Encode(bytes)}',
      };
    }
    if (index < 0 || index >= blocks.length) throw RangeError('附件分块编号无效');
    final block = blocks[index];
    if (block['scanPage'] == null) {
      return {'filename': name, 'block': index, ...block};
    }
    if (!supportsImages) throw StateError('这是扫描 PDF，请选择支持图片的模型');
    final document = await PdfDocument.openFile(path);
    try {
      cancellation.check();
      final page = document.pages[(block['scanPage'] as int) - 1];
      final factor =
          1600 / (page.width > page.height ? page.width : page.height);
      final rendered = await page.render(
        fullWidth: page.width * factor,
        fullHeight: page.height * factor,
      );
      if (rendered == null) throw StateError('PDF 页面无法读取');
      try {
        final image = await rendered.createImage();
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          cancellation.check();
          return {
            'filename': name,
            'block': index,
            'label': block['label'],
            'image':
                'data:image/png;base64,${base64Encode(bytes!.buffer.asUint8List())}',
          };
        } finally {
          image.dispose();
        }
      } finally {
        rendered.dispose();
      }
    } finally {
      await document.dispose();
    }
  }
}

List<Map<String, dynamic>> textBlocks(String text, String label) {
  final chunks = chunkText(text);
  return [
    for (var i = 0; i < chunks.length; i++)
      {'label': '$label · 分块 ${i + 1}', 'text': chunks[i]},
  ];
}

String _zipText(Archive archive, String name) {
  final file = archive.findFile(name);
  if (file == null) return '';
  return utf8.decode(file.content as List<int>);
}

List<Map<String, dynamic>> extractOffice(List<int> bytes, String extension) {
  final archive = ZipDecoder().decodeBytes(bytes, verify: true);
  if (archive.files.fold<int>(0, (sum, file) => sum + file.size) >
      100 * 1024 * 1024) {
    throw const FormatException('文件解压后过大，请拆分后上传');
  }
  if (extension == 'docx') {
    final xml = _zipText(archive, 'word/document.xml');
    if (xml.isEmpty) throw const FormatException('DOCX 内容缺失或已加密');
    final document = XmlDocument.parse(xml);
    final lines = document.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'p')
        .map(
          (p) => p.descendants
              .whereType<XmlElement>()
              .where((e) => e.name.local == 't')
              .map((e) => e.innerText)
              .join(),
        )
        .join('\n');
    return textBlocks(lines, '正文（含表格段落）');
  }
  final sharedXml = _zipText(archive, 'xl/sharedStrings.xml');
  final shared = sharedXml.isEmpty
      ? <String>[]
      : XmlDocument.parse(sharedXml).descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == 'si')
            .map(
              (e) => e.descendants
                  .whereType<XmlElement>()
                  .where((t) => t.name.local == 't')
                  .map((t) => t.innerText)
                  .join(),
            )
            .toList();
  final workbook = XmlDocument.parse(_zipText(archive, 'xl/workbook.xml'));
  final relationships = XmlDocument.parse(
    _zipText(archive, 'xl/_rels/workbook.xml.rels'),
  );
  final rels = {
    for (final r in relationships.descendants.whereType<XmlElement>().where(
      (e) => e.name.local == 'Relationship',
    ))
      r.getAttribute('Id'): r.getAttribute('Target'),
  };
  final output = <Map<String, dynamic>>[];
  for (final sheet in workbook.descendants.whereType<XmlElement>().where(
    (e) => e.name.local == 'sheet',
  )) {
    final relation = sheet.attributes
        .where((a) => a.name.local == 'id')
        .firstOrNull
        ?.value;
    final target = rels[relation];
    if (target == null) continue;
    final path = target.startsWith('/')
        ? target.substring(1)
        : Uri.parse('xl/workbook.xml').resolve(target).path;
    final xml = _zipText(archive, path);
    if (xml.isEmpty) throw const FormatException('工作表内容缺失');
    final rows = XmlDocument.parse(xml).descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'row')
        .map(
          (row) => row.childElements
              .where((e) => e.name.local == 'c')
              .map((cell) {
                final raw =
                    cell.childElements
                        .where((e) => e.name.local == 'v')
                        .firstOrNull
                        ?.innerText ??
                    '';
                final value = cell.getAttribute('t') == 's'
                    ? shared[int.parse(raw)]
                    : cell.getAttribute('t') == 'inlineStr'
                    ? cell.descendants
                          .whereType<XmlElement>()
                          .where((e) => e.name.local == 't')
                          .map((e) => e.innerText)
                          .join()
                    : raw;
                return '${cell.getAttribute('r') ?? ''}=$value';
              })
              .join('\t'),
        )
        .join('\n');
    output.addAll(textBlocks(rows, '工作表 ${sheet.getAttribute('name') ?? ''}'));
  }
  if (output.isEmpty) throw const FormatException('XLSX 未包含可读工作表');
  return output;
}

Future<AiAttachment> importAttachment(
  PlatformFile file,
  AiCancellation cancellation,
) async {
  cancellation.check();
  if ((await file.length()) > 20 * 1024 * 1024) {
    throw const FormatException('单文件不能超过 20 MB');
  }
  final extension = file.name.split('.').last.toLowerCase();
  if (![
    'jpg',
    'jpeg',
    'png',
    'webp',
    'txt',
    'md',
    'csv',
    'pdf',
    'docx',
    'xlsx',
  ].contains(extension)) {
    throw const FormatException('不支持该文件格式，请使用图片、文字、PDF、DOCX 或 XLSX');
  }
  final bytes = await file.readAsBytes();
  if (bytes.length > 20 * 1024 * 1024) {
    throw const FormatException('单文件不能超过 20 MB');
  }
  final id = localId();
  final directory = Directory(
    '${(await getApplicationSupportDirectory()).path}/ai_attachments/$id',
  );
  await directory.create(recursive: true);
  final path = '${directory.path}/file.$extension';
  await File(path).writeAsBytes(bytes);
  try {
    final isImage = ['jpg', 'jpeg', 'png', 'webp'].contains(extension);
    final blocks = <Map<String, dynamic>>[];
    if (isImage) {
      final codec = await ui.instantiateImageCodecWithSize(
        await ui.ImmutableBuffer.fromUint8List(bytes),
        getTargetSize: (width, height) {
          final factor = math.min(1.0, 1600 / math.max(width, height));
          return ui.TargetImageSize(
            width: math.max(1, (width * factor).round()),
            height: math.max(1, (height * factor).round()),
          );
        },
      );
      try {
        final frame = await codec.getNextFrame();
        try {
          final png = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final imagePath = '${directory.path}/image.png';
          await File(imagePath).writeAsBytes(png!.buffer.asUint8List());
          return AiAttachment(
            id: id,
            name: file.name,
            path: imagePath,
            blocks: [],
            image: true,
          );
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } else if (extension == 'pdf') {
      final document = await PdfDocument.openFile(path);
      try {
        for (final page in document.pages) {
          cancellation.check();
          final text = (await page.loadText())?.fullText ?? '';
          if (text.trim().isEmpty) {
            blocks.add({
              'label': '第${page.pageNumber}页',
              'scanPage': page.pageNumber,
            });
          } else {
            blocks.addAll(textBlocks(text, '第${page.pageNumber}页'));
          }
        }
      } finally {
        await document.dispose();
      }
    } else if (extension == 'docx' || extension == 'xlsx') {
      blocks.addAll(await Isolate.run(() => extractOffice(bytes, extension)));
    } else {
      blocks.addAll(textBlocks(utf8.decode(bytes), '正文'));
    }
    cancellation.check();
    return AiAttachment(id: id, name: file.name, path: path, blocks: blocks);
  } catch (_) {
    await directory.delete(recursive: true);
    rethrow;
  }
}

Future<void> deleteAttachment(AiAttachment attachment) async {
  final directory = File(attachment.path).parent;
  if (await directory.exists()) await directory.delete(recursive: true);
}
