import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/models.dart';

/// Marks goods that are NOT where their category says they belong, because
/// that warehouse or zone was full when they arrived.
///
/// ⚠️ Reported directly: when space runs out the officer is offered another
/// zone and the goods go there, and afterwards nothing says so. A month later
/// nobody can tell a deliberate placement from an overflow, and nobody knows
/// which goods to move back when room frees up.
///
/// The flag is recorded at admission (migration 042) rather than worked out by
/// comparing the entry against the category's target, because targets are
/// editable: retargeting a category later would make every ordinary row look
/// displaced, and retargeting it TO the overflow warehouse would hide a real
/// displacement.
///
/// Two shapes, one wording, so the table and the popup cannot drift:
///   * [DisplacedBadge] — a small chip for a table row.
///   * [DisplacedNotice] — a full line for the details popup.

/// The colour this marking carries everywhere.
///
/// ⚠️ Deliberately NOT dangerRed. Nothing is wrong with these goods and
/// nobody has to act today; they are simply somewhere unexpected. Red down a
/// column of them would read as a fault the reader cannot fix.
Color displacedAccent(BuildContext context) => context.colors.accentBlue;

/// A compact "Moved" chip for a table row, with the full story in its tooltip.
class DisplacedBadge extends StatelessWidget {
  const DisplacedBadge({super.key, required this.entry, this.warehouses});

  final WarehouseEntryModel? entry;

  /// The warehouses already loaded by the page, so the INTENDED one can be
  /// named.
  ///
  /// ⚠️ Resolved here rather than embedded in the query: a second foreign key
  /// from `warehouse_entries` to `warehouses` would make every existing
  /// `warehouses(*)` embed ambiguous and break all 44 of them. The page has
  /// the list already, so naming it costs nothing.
  final List<WarehouseModel>? warehouses;

  String? get _intendedName =>
      entry?.intendedWarehouseName ??
      warehouses
          ?.where((w) => w.id == entry?.intendedWarehouseId)
          .firstOrNull
          ?.name;

  @override
  Widget build(BuildContext context) {
    final note = entry?.displacementNoteWith(_intendedName);
    if (note == null) return const SizedBox.shrink();
    final accent = displacedAccent(context);

    return Tooltip(
      message: note,
      child: Container(
        margin: const EdgeInsets.only(top: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: accent.withOpacity(0.12),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: accent.withOpacity(0.5)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.swap_horiz_rounded, size: 11, color: accent),
          const SizedBox(width: 3),
          Text('Moved — no space',
              style: TextStyle(
                  fontSize: 9.5, fontWeight: FontWeight.w700, color: accent)),
        ]),
      ),
    );
  }
}

/// The same fact as a full line, for the details popup where there is room to
/// say it properly.
class DisplacedNotice extends StatelessWidget {
  const DisplacedNotice({super.key, required this.entry, this.warehouses});

  final WarehouseEntryModel? entry;

  /// See [DisplacedBadge.warehouses].
  final List<WarehouseModel>? warehouses;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    if (e == null || !e.movedForSpace) return const SizedBox.shrink();
    final accent = displacedAccent(context);

    final named = e.intendedWarehouseName ??
        warehouses
            ?.where((w) => w.id == e.intendedWarehouseId)
            .firstOrNull
            ?.name;
    final home = [
      if ((named ?? '').trim().isNotEmpty) named!.trim(),
      if ((e.intendedZone ?? '').trim().isNotEmpty)
        'Zone ${e.intendedZone!.trim()}',
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withOpacity(0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.swap_horiz_rounded, size: 15, color: accent),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Moved here for space',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accent)),
            const SizedBox(height: 2),
            Text(
                home.isEmpty
                    ? 'These goods were admitted here because the location '
                        'their category points at was full.'
                    : 'These goods belong in $home. It was full when they '
                        'arrived, so they were admitted here instead.',
                style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: context.colors.textSecondary)),
            if ((e.movedReason ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(e.movedReason!.trim(),
                  style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: context.colors.textMuted)),
            ],
          ]),
        ),
      ]),
    );
  }
}
