import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../core/directorates.dart';
import '../core/providers.dart';
import '../core/yards.dart';

/// The yard a group of rows belongs to, as a chip.
///
/// ⚠️ ONE definition, used by all three directorate portals. Central Disposal,
/// Valuation and Top Management each had their own copy of the same twelve
/// lines, and they had already drifted: the same yard read "Grey Line 1" on
/// one page and carried a different icon size on another. Only the ACCENT
/// differs between portals, so that is the only thing the caller passes.
///
/// ⚠️ It names the DIRECTORATE as well as the yard — "CED/GL1 · Grey Line 1".
/// A yard code alone is ambiguous: ICT groups yards under directorates, one
/// yard can sit under two of them (NNR is CED and PSD), and every SR number
/// these pages list is written `CED/GL1/SR/…`. A page showing rows from one
/// directorate that labels them with the bare yard makes the reader map the
/// name back to the code they were just reading.
class YardChip extends ConsumerWidget {
  const YardChip({
    super.key,
    required this.yard,
    required this.accent,
    this.srNumber,
    this.compact = false,
  });

  /// The yard code, e.g. `GL1`.
  final String? yard;

  /// The portal's colour.
  final Color accent;

  /// An SR number from this group, for the directorate prefix.
  ///
  /// ⚠️ The SR NUMBER is the authority, not the yard-directorate table. A yard
  /// under two directorates has no single answer, but the SR number written
  /// on the goods says which one raised them — `CED/GL1/SR/24/2026` is a CED
  /// entry whatever else GL1 also belongs to. The link table is the fallback,
  /// and only when it is unambiguous.
  final String? srNumber;

  /// Smaller type, for headers that already carry a lot.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = (yard ?? '').trim();
    final prefix = _prefix(ref, code);
    final label = code.isEmpty
        ? yardName(yard)
        : '${prefix == null ? '' : '$prefix/'}$code · ${yardName(yard)}';

    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12, vertical: compact ? 6 : 8),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withOpacity(0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.warehouse_rounded, size: compact ? 14 : 16, color: accent),
        Gap(compact ? 6 : 8),
        Text(label,
            style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w800,
                fontSize: compact ? 12.5 : 14)),
      ]),
    );
  }

  /// The directorate's SR prefix for this group, or null when unknown.
  String? _prefix(WidgetRef ref, String code) {
    // 1. The SR number itself, which is unambiguous.
    final sr = (srNumber ?? '').trim();
    if (sr.isNotEmpty) {
      final slash = sr.indexOf('/');
      if (slash > 0) {
        final head = sr.substring(0, slash).toUpperCase();
        // Only accept it if it IS a directorate prefix — an SR number that
        // starts with the yard code instead must not print "GL1/GL1".
        final known = ref.watch(directorateSrPrefixMapProvider).valueOrNull ??
            {for (final d in kDirectorates) d.srPrefix: d.code};
        if (known.containsKey(head)) return head;
      }
    }
    // 2. The ICT link table, when the yard sits under exactly one.
    if (code.isEmpty) return null;
    final links = ref.watch(yardDirectoratesProvider).valueOrNull;
    final forYard = links?[code] ?? const <String>[];
    if (forYard.length != 1) return null;
    final directorates = ref.watch(directoratesProvider).valueOrNull;
    for (final d in directorates ?? const []) {
      if (d.code == forYard.first) return d.srPrefix;
    }
    return forYard.first;
  }
}
