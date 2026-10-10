import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Records any frame that holds the UI thread long enough to swallow a click.
///
/// ⚠️ Why this exists. Flutter delivers a pointer tap only BETWEEN frames. A
/// frame that takes 1.5s therefore does not make a button slow — it makes the
/// button do NOTHING, because the tap is never received until the frame ends.
/// The officer presses again, and when the thread frees up both taps are
/// honoured at once: two popups stacked. That is exactly what was reported on
/// the Destroyed Goods page, and nothing in the popup's own path showed it —
/// tap-to-painted was 15-20ms every time. Only a per-frame timing exposed a
/// 1,546ms frame with 1ms of build in it.
///
/// So this stays in the release build. It writes to `frame_watch.log` beside
/// the executable, one line per slow frame, so the next such report can be
/// answered by reading a file instead of rebuilding with probes.
///
/// A frame costs nothing here unless it is already slow: the callback runs
/// once per frame with a handful of integer compares, and the file is touched
/// only above the threshold.
class FrameWatch {
  FrameWatch._();

  /// Frames longer than this are logged. 250ms is well past "noticeable" and
  /// well short of the 1.5s stall being hunted, so it catches regressions
  /// early without filling the log during ordinary load spikes.
  static const Duration threshold = Duration(milliseconds: 250);

  static bool _armed = false;

  static void arm() {
    if (_armed) return;
    _armed = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      if (t.totalSpan < threshold) continue;
      final line = '${DateTime.now().toIso8601String()} '
          'SLOW FRAME ${t.totalSpan.inMilliseconds}ms '
          '(build ${t.buildDuration.inMilliseconds}ms, '
          'raster ${t.rasterDuration.inMilliseconds}ms)';
      try {
        File('frame_watch.log')
            .writeAsStringSync('$line\n', mode: FileMode.append);
      } catch (_) {
        // A read-only install directory must not turn a diagnostic into a
        // crash. The line is simply lost.
      }
    }
  }
}
