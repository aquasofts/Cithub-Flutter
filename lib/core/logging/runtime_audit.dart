import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'runtime_log.dart';

/// Audit every provider, including state changes initiated by background work.
class RuntimeProviderObserver extends ProviderObserver {
  @override
  void didAddProvider(
    ProviderBase<Object?> provider,
    Object? value,
    ProviderContainer container,
  ) {
    RuntimeLog.event('state', 'initialized', {
      'provider': provider.name ?? provider.toString(),
      'value': value,
    });
  }

  @override
  void didDisposeProvider(
    ProviderBase<Object?> provider,
    ProviderContainer container,
  ) {
    RuntimeLog.event('state', 'disposed', {
      'provider': provider.name ?? provider.toString(),
    });
  }

  @override
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    RuntimeLog.event('state', 'changed', {
      'provider': provider.name ?? provider.toString(),
      'before': previousValue,
      'after': newValue,
    });
  }

  @override
  void providerDidFail(
    ProviderBase<Object?> provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    RuntimeLog.event('state', 'failure', {
      'provider': provider.name ?? provider.toString(),
      'error': '$error',
      'stack': '$stackTrace',
    });
  }
}

class RuntimeNavigatorObserver extends NavigatorObserver {
  final String scope;
  RuntimeNavigatorObserver([this.scope = 'app']);
  void _record(String action, Route<dynamic>? route, Route<dynamic>? previous) {
    RuntimeLog.event('navigation', action, {
      'scope': scope,
      'route': route?.settings.name ?? '${route?.runtimeType}',
      'arguments': route?.settings.arguments,
      'previous': previous?.settings.name ?? '${previous?.runtimeType}',
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record('push', route, previousRoute);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record('pop', route, previousRoute);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record('remove', route, previousRoute);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _record('replace', newRoute, oldRoute);
}

/// Resolves runtime-selected page names without calling builders twice.
class LoggedMaterialPageRoute<T> extends MaterialPageRoute<T> {
  LoggedMaterialPageRoute({
    required WidgetBuilder builder,
    super.settings,
    super.fullscreenDialog,
    super.maintainState,
  }) : super(builder: (context) => _LoggedPage(child: builder(context)));
}

class _LoggedPage extends StatefulWidget {
  const _LoggedPage({required this.child});
  final Widget child;
  @override
  State<_LoggedPage> createState() => _LoggedPageState();
}

class _LoggedPageState extends State<_LoggedPage> {
  @override
  void initState() {
    super.initState();
    RuntimeLog.event('page', 'opened', {
      'page': '${widget.child.runtimeType}',
      'key': '${widget.child.key}',
    });
  }

  @override
  void dispose() {
    RuntimeLog.event('page', 'closed', {'page': '${widget.child.runtimeType}'});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Global input recording works for existing and future Flutter pages in release
/// builds. It never depends on debugCreator or assertions.
class RuntimeAudit extends StatefulWidget {
  const RuntimeAudit({super.key, required this.child});
  final Widget child;
  @override
  State<RuntimeAudit> createState() => _RuntimeAuditState();
}

class _RuntimeAuditState extends State<RuntimeAudit>
    with WidgetsBindingObserver {
  final _inputs = <TextEditingController, VoidCallback>{};
  Timer? _retention;
  final _controls = <Element, String>{};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_pointer);
    _retention = Timer.periodic(
      const Duration(minutes: 1),
      (_) => RuntimeLog.event('runtime', 'retention-tick'),
    );
    WidgetsBinding.instance.addPostFrameCallback(_scan);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    RuntimeLog.event('lifecycle', state.name);
    unawaited(RuntimeLog.flush());
  }

  void _walk(Element element, void Function(Element) visitor) {
    visitor(element);
    element.visitChildren((child) => _walk(child, visitor));
  }

  void _scan(Duration _) {
    if (!mounted) return;
    final current = <TextEditingController>{};
    final controls = <Element>{};
    _walk(context as Element, (element) {
      final widget = element.widget;
      Object? value;
      if (widget is Switch) value = widget.value;
      if (widget is Checkbox) value = widget.value;
      if (widget is Slider) value = widget.value;
      if (widget is RangeSlider) {
        value = [widget.values.start, widget.values.end];
      }
      if (widget is DropdownButton) value = widget.value;
      if (widget is SegmentedButton) value = widget.selected.toList();
      if (widget is NavigationBar) value = widget.selectedIndex;
      if (widget is ChoiceChip) value = widget.selected;
      if (widget is FilterChip) value = widget.selected;
      if (value != null) {
        controls.add(element);
        final encoded = RuntimeLog.describe(value);
        final before = _controls[element];
        if (before != encoded) {
          RuntimeLog.event('control', before == null ? 'mounted' : 'changed', {
            'widget': '${widget.runtimeType}',
            'key': '${widget.key}',
            'before': before,
            'after': value,
          });
          _controls[element] = encoded;
        }
      }
      if (widget is! EditableText) return;
      final controller = widget.controller;
      current.add(controller);
      if (_inputs.containsKey(controller)) return;
      var previous = controller.value;
      void changed() {
        final value = controller.value;
        if (value == previous) return;
        RuntimeLog.event('input', 'edit', {
          'key': '${widget.key}',
          'before': previous.text,
          'after': value.text,
          'selection': [
            value.selection.baseOffset,
            value.selection.extentOffset,
          ],
        });
        previous = value;
      }

      _inputs[controller] = changed;
      controller.addListener(changed);
    });
    for (final controller in _inputs.keys.toList()) {
      if (!current.contains(controller)) {
        controller.removeListener(_inputs.remove(controller)!);
      }
    }
    _controls.removeWhere((element, _) => !controls.contains(element));
    // Post-frame registration does not schedule a frame or cause rebuilds.
    WidgetsBinding.instance.addPostFrameCallback(_scan);
  }

  void _pointer(PointerEvent event) {
    if (event is PointerMoveEvent || event is PointerHoverEvent) return;
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(hit, event.position, event.viewId);
    final targets = hit.path.map((entry) => entry.target).toSet();
    final labels = <String>{};
    _walk(context as Element, (element) {
      if (element is! RenderObjectElement ||
          !targets.contains(element.renderObject)) {
        return;
      }
      element.visitAncestorElements((ancestor) {
        final widget = ancestor.widget;
        if (widget.key != null) {
          labels.add('${widget.runtimeType}:${widget.key}');
        }
        if (widget is Text && widget.data != null) labels.add(widget.data!);
        if (widget is Tooltip) {
          labels.add(widget.message ?? widget.richMessage?.toPlainText() ?? '');
        }
        if (widget is InkWell ||
            widget is ButtonStyleButton ||
            widget is ListTile) {
          _walk(ancestor, (child) {
            if (child.widget is Text) {
              labels.add((child.widget as Text).data ?? '');
            }
          });
          return false;
        }
        return true;
      });
    });
    RuntimeLog.event('interaction', '${event.runtimeType}', {
      'pointer': event.pointer,
      'x': event.position.dx,
      'y': event.position.dy,
      'buttons': event.buttons,
      'targets': labels.toList(),
      if (event is PointerScrollEvent)
        'scroll': [event.scrollDelta.dx, event.scrollDelta.dy],
    });
  }

  @override
  void dispose() {
    _retention?.cancel();
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_pointer);
    WidgetsBinding.instance.removeObserver(this);
    for (final entry in _inputs.entries) {
      entry.key.removeListener(entry.value);
    }
    _inputs.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollStartNotification ||
              notification is ScrollEndNotification) {
            RuntimeLog.event('interaction', '${notification.runtimeType}', {
              'pixels': notification.metrics.pixels,
              'axis': notification.metrics.axis.name,
            });
          }
          return false;
        },
        child: widget.child,
      );
}
