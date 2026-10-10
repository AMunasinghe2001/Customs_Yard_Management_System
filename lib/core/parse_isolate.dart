import 'package:flutter/foundation.dart';

import '../models/models.dart';

/// Parsing that runs OFF the UI thread.
///
/// ── Why this exists ────────────────────────────────────────────────────────
/// Dart is single-threaded: the UI, animations and every `fromJson` share one
/// isolate. A frame has 16ms to be built at 60fps, so any parse that takes
/// longer is a dropped frame, and a parse that takes 300ms is a visibly frozen
/// window — the title bar stops responding and Windows may grey it out.
///
/// [PackageModel.fromJson] is the heaviest parse in the app because it is
/// NESTED: every package also parses its items and its warehouse entries, and
/// each warehouse entry parses its warehouse and returning officer. The
/// Reports screen calls `getAllPackages()` twenty-one times across its tabs,
/// each pulling every package in the yard with all of that attached.
///
/// ── Why `compute` and not a long-lived isolate ─────────────────────────────
/// `compute` spawns an isolate, runs one function, returns the result and
/// tears it down. That costs a few ms of start-up, which is why it is worth it
/// for a list of hundreds and NOT worth it for a list of five — see the
/// threshold in [parsePackages]. A pooled long-lived isolate would avoid the
/// start-up, but it has to be kept alive, drained and disposed, and the
/// screens that need this run a handful of times per session rather than per
/// frame.
///
/// ⚠️ The entry points MUST be top-level or static functions. An isolate gets
/// a copy of its argument and cannot close over `this`, so a closure or an
/// instance method is rejected at run time, not compile time.
///
/// ⚠️ What crosses the boundary is COPIED. That is why these take the raw
/// decoded rows (maps and lists of primitives, which copy cheaply) and return
/// models, rather than taking a database handle — a `Connection` or a
/// `PgQuery` cannot be sent to an isolate at all.

/// Below this many rows, parsing inline is faster than spawning an isolate.
///
/// Measured against the shape of this app's data: a package with its items and
/// warehouse entries parses in roughly 10-20µs, while `compute` costs a few
/// milliseconds to spawn, transfer and tear down. So a hundred rows parse in
/// about a millisecond or two inline — well inside one frame — and handing
/// that to an isolate would make it SLOWER while adding a context switch.
///
/// The Reports and cross-yard screens are the ones that exceed this; the small
/// per-dialog reads stay on the main thread, correctly.
const int kIsolateParseThreshold = 150;

/// Parses package rows, moving off the UI thread once there are enough to
/// matter.
///
/// The caller passes what the driver returned — a `List` of row maps. Anything
/// that is not a map is skipped rather than throwing: one malformed row should
/// not lose the user the other four hundred.
Future<List<PackageModel>> parsePackages(List<dynamic> rows) async {
  if (rows.isEmpty) return const [];

  // Small lists: inline, because the isolate would cost more than the parse.
  if (rows.length < kIsolateParseThreshold) {
    return _parsePackagesSync(rows);
  }

  // ⚠️ `rows` is already plain maps and lists from the driver, so it copies to
  // the isolate cheaply. Passing models the other way is the expensive half,
  // and it is unavoidable — but it happens once per screen load, not per frame.
  return compute(_parsePackagesSync, rows);
}

/// The actual work. Top-level and static-shaped so `compute` can take it.
List<PackageModel> _parsePackagesSync(List<dynamic> rows) {
  final out = <PackageModel>[];
  for (final row in rows) {
    if (row is! Map<String, dynamic>) continue;
    out.add(PackageModel.fromJson(row));
  }
  return out;
}

/// The same treatment for forfeited packages, the other list the cross-yard
/// Disposal, Appeal and Executive screens load in full.
Future<List<ForfeitedPackageModel>> parseForfeitedPackages(
    List<dynamic> rows) async {
  if (rows.isEmpty) return const [];
  if (rows.length < kIsolateParseThreshold) {
    return _parseForfeitedSync(rows);
  }
  return compute(_parseForfeitedSync, rows);
}

List<ForfeitedPackageModel> _parseForfeitedSync(List<dynamic> rows) {
  final out = <ForfeitedPackageModel>[];
  for (final row in rows) {
    if (row is! Map<String, dynamic>) continue;
    out.add(ForfeitedPackageModel.fromJson(row));
  }
  return out;
}
