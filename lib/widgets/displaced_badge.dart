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
///
/// Shows a clear "from → to" flow so the reader can see at a glance where
/// these goods were meant to go and where they actually ended up.
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

    // --- Intended (source) location ---
    final intendedName = e.intendedWarehouseName ??
        warehouses
            ?.where((w) => w.id == e.intendedWarehouseId)
            .firstOrNull
            ?.name;
    final fromWarehouse = (intendedName ?? '').trim();
    final fromZone = (e.intendedZone ?? '').trim();
    final fromLabel = [
      if (fromWarehouse.isNotEmpty) fromWarehouse,
      if (fromZone.isNotEmpty) 'Zone $fromZone',
    ].join(' · ');

    // --- Actual (current) location ---
    final toWarehouse = (e.warehouseName).trim();
    final toZone = (e.zone ?? '').trim();
    final toLabel = [
      if (toWarehouse.isNotEmpty) toWarehouse,
      if (toZone.isNotEmpty) 'Zone $toZone',
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title row
          Row(children: [
            Icon(Icons.swap_horiz_rounded, size: 16, color: accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Relocated — No Space',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: accent)),
            ),
          ]),
          const SizedBox(height: 10),

          // From → To flow
          if (fromLabel.isNotEmpty || toLabel.isNotEmpty)
            Row(
              children: [
                // FROM column
                Expanded(
                  child: _LocationCard(
                    label: 'Intended Location',
                    location: fromLabel.isEmpty ? 'Unknown' : fromLabel,
                    icon: Icons.location_on_outlined,
                    color: Colors.orange.shade700,
                    bgColor: Colors.orange.withOpacity(0.08),
                    borderColor: Colors.orange.withOpacity(0.25),
                  ),
                ),
                // Arrow
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward_rounded,
                      size: 18, color: accent),
                ),
                // TO column
                Expanded(
                  child: _LocationCard(
                    label: 'Current Location',
                    location: toLabel.isEmpty ? 'Unknown' : toLabel,
                    icon: Icons.warehouse_rounded,
                    color: accent,
                    bgColor: accent.withOpacity(0.08),
                    borderColor: accent.withOpacity(0.25),
                  ),
                ),
              ],
            ),

          if (fromLabel.isEmpty && toLabel.isEmpty)
            Text(
                'These goods were admitted here because the location '
                'their category points at was full.',
                style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: context.colors.textSecondary)),

          if ((e.movedReason ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(e.movedReason!.trim(),
                style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: context.colors.textMuted)),
          ],
        ],
      ),
    );
  }
}

/// A small location card for the from/to flow.
class _LocationCard extends StatelessWidget {
  final String label;
  final String location;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final Color borderColor;

  const _LocationCard({
    required this.label,
    required this.location,
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: color.withOpacity(0.7))),
          ]),
          const SizedBox(height: 3),
          Text(location,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: color)),
        ],
      ),
    );
  }
}
