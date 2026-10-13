import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/cithub_app.dart';
import 'core/logging/runtime_log.dart';
import 'core/logging/runtime_audit.dart';

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      RuntimeLog.installErrorHandlers();
      CachedNetworkImageProvider.defaultCacheManager = CacheManager(
        Config(
          'libCachedImageData',
          fileService: HttpFileService(
            httpClient: LoggingHttpClient(http.Client(), streaming: true),
          ),
        ),
      );
      runApp(
        ProviderScope(
          observers: [RuntimeProviderObserver()],
          child: const CithubApp(),
        ),
      );
    },
    (error, stack) {
      RuntimeLog.write('uncaught', '$error\n$stack');
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        RuntimeLog.write('dart-console', line);
        parent.print(zone, line);
      },
    ),
  );
}
