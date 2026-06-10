import 'dart:io';

import 'package:flutter/foundation.dart';

class AppLogger {
  static final String _level = kDebugMode
      ? 'debug'
      : Platform.environment['DEBUG_LOG']?.toLowerCase() ?? 'none';

  static const _levels = ['debug', 'info', 'error', 'none'];

  // ── public API ──────────────────────────────────────────

  static void d(String message) => _log('debug', message);
  static void i(String message) => _log('info', message);
  static void e(String message, {Object? error, StackTrace? stack}) =>
      _log('error', message, error: error, stack: stack ?? StackTrace.current);

  // ── internal ─────────────────────────────────────────────

  static bool _canLog(String level) {
    final current = _levels.indexOf(_level);
    final target = _levels.indexOf(level);
    return current != -1 && current != 3 && target >= current;
  }

  static String _caller() {
    final frames = StackTrace.current.toString().split('\n');
    // frame 0 = _caller, frame 1 = _log, frame 2 = d/i/e, frame 3 = actual caller
    final callerFrame = frames.length > 3 ? frames[3] : frames.last;
    // Parses:  #3  ClassName.methodName (package:app/file.dart:42:15)
    final match = RegExp(
      r'#\d+\s+(.+?)\s+\((.+?\.dart):(\d+)',
    ).firstMatch(callerFrame);

    if (match != null) {
      final function =
          match.group(1) ?? '?'; // e.g. _MyHomePageState._incrementCounter
      final file = match.group(2)?.split('/').last ?? '?'; // e.g. main.dart
      final line = match.group(3) ?? '?'; // e.g. 42
      return '$file:$line | $function';
    }

    return 'unknown';
  }

  static void _log(
    String levelName,
    String message, {
    Object? error,
    StackTrace? stack,
  }) {
    if (!_canLog(levelName)) return;

    final caller = _caller();
    final time = DateTime.now();
    final timeStr = time.toString().split('.').first;

    final formatted =
        '\n'
        '[$timeStr][${levelName.toUpperCase()}] $message\n'
        '  └─ $caller'
        '${error != null ? '\n  └─ error: $error' : ''}'
        '${stack != null ? '\n  └─ stack: $stack' : ''}';

    debugPrint(formatted);
  }
}
