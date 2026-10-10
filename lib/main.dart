import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/cithub_app.dart';
import 'core/logging/runtime_log.dart';

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      RuntimeLog.installErrorHandlers();
      runApp(const ProviderScope(child: CithubApp()));
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
