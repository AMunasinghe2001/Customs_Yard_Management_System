import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// App-wide crash handling.
///
/// This is a **desktop** app used by customs officers who have no console to
/// read, no DevTools, and no way to send a stack trace to a developer. Before
/// this, an unhandled exception did one of three unhelpful things:
///
///   * a build-time error painted Flutter's grey "red screen" (or, in release,
///     a bare grey rectangle) with no way out and no record of what happened;
///   * an async error vanished silently — the button simply did nothing;
///   * an error before `runApp` left a blank window (see the DB start-up case
///     in main.dart).
///
/// Now every one of them is caught, written to a log file the officer can find
/// and send on, and — for build errors — shown as a screen with the error, the
/// log location, and a way to carry on.
class AppErrorHandler {
  AppErrorHandler._();

  /// Where crashes are appended. Null until [install] has run, or if the log
  /// directory could not be created.
  static File? _logFile;

  /// The most recent errors, newest first — surfaced in the error screen so the
  /// user can read what happened without hunting for the file.
  static final List<AppErrorRecord> recent = <AppErrorRecord>[];
  static const int _maxRecent = 50;

  /// Keeps one runaway widget from writing thousands of identical lines: a
  /// failing build is retried every frame, which would fill the disk.
  static final Map<String, int> _seen = <String, int>{};
  static const int _maxPerSignature = 5;

  static String? get logPath => _logFile?.path;

  /// Installs the handlers. Call once, first thing in `main()`, INSIDE the same
  /// zone as `runApp` (see [guard]).
  static Future<void> install() async {
    await _openLogFile();

    // 1. Errors the Flutter framework catches — the great majority: anything
    //    thrown in build(), layout, paint, or a gesture callback.
    final priorOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      _record(details.exception, details.stack,
          context: details.context?.toDescription(),
          library: details.library);
      // Keep the default console dump in debug — it is what a developer reads.
      if (kDebugMode) priorOnError?.call(details);
    };

    // 2. Errors that reach the engine with no Flutter frame to blame: platform
    //    channel failures and un-awaited futures that escape the zone.
    PlatformDispatcher.instance.onError = (error, stack) {
      _record(error, stack, context: 'PlatformDispatcher');
      return true; // handled — do not kill the isolate
    };

    // 3. What the user SEES when a widget fails to build.
    //    The default is a grey box in release with no information at all.
    ErrorWidget.builder = (FlutterErrorDetails details) {
      // In debug keep Flutter's red screen: it is more informative to a
      // developer than anything worth rewriting here.
      if (kDebugMode) return ErrorWidget(details.exception);
      return _BrokenScreen(details: details);
    };
  }

  /// Runs [body] in a zone whose uncaught async errors are captured too.
  ///
  /// `runApp` must be called INSIDE this, otherwise the zone the widgets run in
  /// is not the guarded one and async errors escape anyway.
  static Future<void> guard(Future<void> Function() body) {
    return runZonedGuarded(body, (error, stack) {
      _record(error, stack, context: 'Uncaught async error');
    })!;
  }

  static Future<void> _openLogFile() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final logs = Directory('${dir.path}${Platform.pathSeparator}logs');
      if (!await logs.exists()) await logs.create(recursive: true);
      final f = File('${logs.path}${Platform.pathSeparator}crash.log');

      // Roll the file so it cannot grow without bound on a machine that is
      // never restarted; one previous generation is kept.
      if (await f.exists() && await f.length() > 2 * 1024 * 1024) {
        try {
          await f.rename('${f.path}.1');
        } catch (_) {
          await f.writeAsString('');
        }
      }
      _logFile = f;
    } catch (e) {
      // No log file is survivable — the in-memory list and console still work.
      debugPrint('Could not open the crash log: $e');
    }
  }

  static void _record(Object error, StackTrace? stack,
      {String? context, String? library}) {
    final signature = '${error.runtimeType}:${error.toString().split('\n').first}';
    final count = (_seen[signature] ?? 0) + 1;
    _seen[signature] = count;

    final record = AppErrorRecord(
      error: error,
      stack: stack,
      context: context,
      library: library,
      at: DateTime.now(),
    );

    recent.insert(0, record);
    if (recent.length > _maxRecent) recent.removeLast();

    debugPrint('── App error${context == null ? '' : ' ($context)'} ──\n$error');

    if (count > _maxPerSignature) {
      // Still counted and still visible in `recent`; just not written again.
      if (count == _maxPerSignature + 1) {
        _write('... further occurrences of [$signature] suppressed\n');
      }
      return;
    }
    _write(record.forLog);
  }

  /// Appends to the log. Deliberately fire-and-forget and never throws: this
  /// runs from inside an error handler, where a second failure would be a loop.
  static void _write(String text) {
    final f = _logFile;
    if (f == null) return;
    try {
      f.writeAsStringSync(text, mode: FileMode.append, flush: true);
    } catch (_) {
      // Disk full, file locked, permissions — nothing useful to do here.
    }
  }
}

/// One captured error, with everything needed to report it.
class AppErrorRecord {
  AppErrorRecord({
    required this.error,
    required this.stack,
    required this.at,
    this.context,
    this.library,
  });

  final Object error;
  final StackTrace? stack;
  final DateTime at;
  final String? context;
  final String? library;

  String get shortMessage => error.toString().split('\n').first;

  String get forLog {
    final b = StringBuffer()
      ..writeln('=' * 78)
      ..writeln('When    : ${at.toIso8601String()}')
      ..writeln('Version : ${Platform.operatingSystemVersion}');
    if (library != null) b.writeln('Library : $library');
    if (context != null) b.writeln('Context : $context');
    b
      ..writeln('Error   : $error')
      ..writeln('Stack   :')
      ..writeln(stack ?? '  <no stack trace>')
      ..writeln();
    return b.toString();
  }
}

/// Replaces the grey release-mode error box with something a customs officer
/// can act on: what broke, where the log is, and a way to keep working.
class _BrokenScreen extends StatelessWidget {
  const _BrokenScreen({required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    // No Scaffold/Theme assumed: this can be inserted anywhere in the tree,
    // including above MaterialApp, where those inherited widgets do not exist.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: const Color(0xFF15131F),
        padding: const EdgeInsets.all(24),
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Color(0xFFE0A23C), size: 26),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This part of the screen could not be shown',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  const Text(
                    'The rest of the app is still working — go back and try '
                    'again. If it keeps happening, send the log file below to '
                    'the ICT Directorate.',
                    style: TextStyle(
                        color: Color(0xFFB9B6C8), fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  _Mono(text: details.exception.toString()),
                  if (AppErrorHandler.logPath != null) ...[
                    const SizedBox(height: 12),
                    const Text('Log file',
                        style:
                            TextStyle(color: Color(0xFF807D91), fontSize: 11.5)),
                    const SizedBox(height: 4),
                    _Mono(text: AppErrorHandler.logPath!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Mono extends StatelessWidget {
  const _Mono({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: SelectableText(
        text,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 11.5,
          height: 1.45,
          color: Color(0xFF9C99AD),
        ),
      ),
    );
  }
}
