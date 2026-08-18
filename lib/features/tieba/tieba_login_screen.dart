import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/platform/cithub_platform.dart';

const tiebaMobileLoginUrl =
    'https://wappass.baidu.com/passport?login&u=https%3A%2F%2Ftieba.baidu.com%2Findex%2Ftbwise%2Fmine';
const tiebaMobileUserAgent =
    'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36';

bool isTiebaLoginCompletionUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null) return false;
  final supportedHost =
      uri.host == 'tieba.baidu.com' || uri.host == 'tiebac.baidu.com';
  return uri.scheme == 'https' &&
      supportedHost &&
      uri.path.startsWith('/index/tbwise/');
}

class TiebaLoginScreen extends ConsumerStatefulWidget {
  const TiebaLoginScreen({super.key});

  @override
  ConsumerState<TiebaLoginScreen> createState() => _TiebaLoginScreenState();
}

class _TiebaLoginScreenState extends ConsumerState<TiebaLoginScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _finishing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(tiebaMobileUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (url) {
            if (mounted) setState(() => _loading = false);
            _maybeComplete(url);
          },
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) {
              setState(() => _error = error.description);
            }
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            return uri != null && uri.scheme == 'https'
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(tiebaMobileLoginUrl));
  }

  void _maybeComplete(String url) {
    if (_finishing) return;
    if (isTiebaLoginCompletionUrl(url)) _complete();
  }

  Future<void> _complete() async {
    setState(() {
      _finishing = true;
      _error = null;
    });
    try {
      final account = await ref
          .read(cithubPlatformProvider)
          .completeTiebaWebLogin();
      if (!mounted) return;
      Navigator.pop(context, account);
    } catch (error) {
      if (mounted) {
        setState(() {
          _finishing = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('登录百度贴吧'),
      bottom: _loading
          ? const PreferredSize(
              preferredSize: Size.fromHeight(2),
              child: LinearProgressIndicator(minHeight: 2),
            )
          : null,
    ),
    body: Column(
      children: [
        if (_error != null)
          MaterialBanner(
            content: Text(_error!),
            actions: [
              TextButton(
                onPressed: _finishing ? null : _complete,
                child: const Text('重试'),
              ),
              TextButton(
                onPressed: () => setState(() => _error = null),
                child: const Text('关闭'),
              ),
            ],
          ),
        if (_finishing)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text('正在保存贴吧登录状态…'),
              ],
            ),
          ),
        Expanded(child: WebViewWidget(controller: _controller)),
      ],
    ),
  );
}
