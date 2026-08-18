import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'news_repository.dart';

const _dangerousTags = {
  'script',
  'form',
  'iframe',
  'object',
  'embed',
  'applet',
  'input',
  'button',
  'textarea',
  'select',
  'option',
  'link',
  'meta',
  'base',
};

const _globalAttributes = {'title', 'colspan', 'rowspan'};
const _safeStyleProperties = {
  'align-items',
  'align-self',
  'background-color',
  'border',
  'border-bottom',
  'border-color',
  'border-left',
  'border-radius',
  'border-right',
  'border-style',
  'border-top',
  'border-width',
  'color',
  'display',
  'flex',
  'flex-basis',
  'flex-direction',
  'flex-grow',
  'flex-shrink',
  'flex-wrap',
  'font-size',
  'font-style',
  'font-weight',
  'gap',
  'height',
  'justify-content',
  'letter-spacing',
  'line-height',
  'margin',
  'margin-bottom',
  'margin-left',
  'margin-right',
  'margin-top',
  'max-height',
  'max-width',
  'min-height',
  'min-width',
  'opacity',
  'overflow',
  'overflow-wrap',
  'padding',
  'padding-bottom',
  'padding-left',
  'padding-right',
  'padding-top',
  'position',
  'text-align',
  'text-decoration',
  'text-indent',
  'vertical-align',
  'white-space',
  'width',
  'word-break',
};
const _spacerBlockTags = {
  'article',
  'aside',
  'div',
  'figure',
  'footer',
  'header',
  'p',
  'section',
};

String buildSafeNewsHtml(
  NewsArticle article, {
  String backgroundColor = '#fffbff',
  String textColor = '#1d1b20',
  String secondaryTextColor = '#625f66',
  String linkColor = '#00639b',
}) {
  final document = html_parser.parse('<body>${article.html}</body>');
  final fragment = document.body!;
  final base = Uri.tryParse(article.link);
  for (final legacyImage in fragment.querySelectorAll('vsbimg').toList()) {
    final image = Element.tag('img')..attributes.addAll(legacyImage.attributes);
    legacyImage.replaceWith(image);
  }
  final elements = fragment.querySelectorAll('*').toList(growable: false);
  for (final element in elements) {
    if (_dangerousTags.contains(element.localName)) {
      element.remove();
      continue;
    }
    _sanitizeAttributes(element, base);
    if (element.localName == 'img') {
      final source = safeNewsUrl(
        element.attributes['src'] ?? '',
        baseUrl: base,
      );
      if (source.isEmpty) {
        element.remove();
      } else {
        final style = element.attributes['style'];
        final title = element.attributes['title'];
        element.attributes
          ..clear()
          ..['src'] = source
          ..['loading'] = 'lazy'
          ..['data-news-image'] = source;
        if (style != null) element.attributes['style'] = style;
        if (title != null) element.attributes['title'] = title;
      }
    }
    if (element.localName == 'a') {
      final href = safeNewsUrl(element.attributes['href'] ?? '', baseUrl: base);
      if (href.isEmpty) {
        element.attributes.remove('href');
      } else {
        element.attributes['href'] = href;
      }
    }
  }
  for (final element in elements.reversed) {
    if (element.parentNode == null ||
        !_spacerBlockTags.contains(element.localName)) {
      continue;
    }
    final visibleText = element.text.replaceAll('\u00a0', '').trim();
    final hasVisualContent =
        element.querySelector('img,video,svg,canvas,table,hr,pre') != null;
    if (visibleText.isEmpty && !hasVisualContent) element.remove();
  }

  final bodyMarkup = fragment.innerHtml.trim().isEmpty
      ? '<p>${const HtmlEscape().convert(article.summary)}</p>'
      : fragment.innerHtml;
  final published = article.publishedAt?.toLocal();
  final date = published == null
      ? ''
      : '${published.year}年${published.month}月${published.day}日';
  final metadata = [article.source, date]
      .where((value) => value.isNotEmpty)
      .map(const HtmlEscape().convert)
      .join(' · ');

  return '''<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=5,user-scalable=yes">
  <style>
    :root { color-scheme: light dark; }
    * { box-sizing: border-box; overflow-wrap: anywhere; }
    html, body { margin: 0; padding: 0; background: $backgroundColor; color: $textColor; }
    body { padding: 18px 18px 52px; font-family: sans-serif; font-size: 17px; line-height: 1.72; }
    h1.article-title { margin: 4px 0 8px; font-size: 28px; line-height: 1.3; }
    .article-meta { margin-bottom: 22px; color: $secondaryTextColor; font-size: 14px; }
    p { margin: 0 0 1em; }
    article, section, div, figure, p { max-width: 100%; }
    article { width: 100%; overflow: hidden; }
    article > :first-child { margin-top: 0 !important; }
    article > :last-child { margin-bottom: 0 !important; }
    h1, h2, h3, h4, h5, h6 { line-height: 1.35; }
    img, video, svg, canvas { display: block; width: auto !important; max-width: 100% !important; height: auto !important; margin: 14px auto; border-radius: 10px; }
    figure { max-width: 100%; margin: 16px 0; }
    table { display: table; width: 100% !important; max-width: 100% !important; min-width: 0 !important; table-layout: fixed; border-collapse: collapse; }
    th, td { width: auto !important; min-width: 0 !important; padding: 6px 8px; border: 1px solid $secondaryTextColor; white-space: normal !important; overflow-wrap: anywhere; word-break: break-word; }
    th > *, td > * { max-width: 100% !important; min-width: 0 !important; }
    pre { max-width: 100%; overflow-x: auto; white-space: pre-wrap; }
    a { color: $linkColor; }
    blockquote { margin: 1em 0; padding-left: 14px; border-left: 3px solid $linkColor; color: $secondaryTextColor; }
  </style>
</head>
<body>
  <h1 class="article-title">${const HtmlEscape().convert(article.title)}</h1>
  <div class="article-meta">$metadata</div>
  <article>$bodyMarkup</article>
  <script>
    document.addEventListener('click', function(event) {
      var node = event.target;
      if (node && node.tagName === 'IMG') {
        event.preventDefault();
        NewsImage.postMessage(node.getAttribute('data-news-image') || node.src);
      }
    });
  </script>
</body>
</html>''';
}

void _sanitizeAttributes(Element element, Uri? base) {
  final original = Map<String, String>.from(element.attributes);
  element.attributes.clear();
  for (final entry in original.entries) {
    final name = entry.key.toLowerCase();
    if (name.startsWith('on') ||
        name == 'srcset' ||
        name == 'action' ||
        name == 'formaction') {
      continue;
    }
    if (name == 'style') {
      final style = _sanitizeInlineStyle(entry.value);
      if (style.isNotEmpty) element.attributes['style'] = style;
      continue;
    }
    if (_globalAttributes.contains(name)) {
      element.attributes[name] = entry.value;
    }
  }
  if (element.localName == 'img') {
    final raw =
        original['src'] ?? original['data-src'] ?? original['orisrc'] ?? '';
    final source = safeNewsUrl(raw, baseUrl: base);
    if (source.isNotEmpty) element.attributes['src'] = source;
  } else if (element.localName == 'a') {
    final href = safeNewsUrl(original['href'] ?? '', baseUrl: base);
    if (href.isNotEmpty) element.attributes['href'] = href;
  }
}

String _sanitizeInlineStyle(String raw) {
  final declarations = <String>[];
  for (final declaration in raw.split(';')) {
    final separator = declaration.indexOf(':');
    if (separator <= 0) continue;
    final property = declaration.substring(0, separator).trim().toLowerCase();
    final value = declaration.substring(separator + 1).trim();
    final lowerValue = value.toLowerCase();
    if (!_safeStyleProperties.contains(property) ||
        value.isEmpty ||
        lowerValue.contains('url(') ||
        lowerValue.contains('expression') ||
        lowerValue.contains('javascript:') ||
        lowerValue.contains('@import') ||
        (property == 'position' &&
            (lowerValue == 'fixed' || lowerValue == 'sticky'))) {
      continue;
    }
    if (!RegExp(r'^[\w\s#(),.%+\-/:]+$').hasMatch(value)) continue;
    declarations.add('$property: $value');
  }
  return declarations.join('; ');
}
