import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../core/providers.dart';
import '../core/theme.dart';
import '../models/models.dart';

/// What one entry's space has cost, from [from] to today.
///
/// ⚠️ The same day-by-day walk `calculatePackageCharge` does -- rates
/// change mid-stay, and a single multiplication by today's rate would
/// misprice every entry that spans a rate change. What it does NOT do is
/// zero the figure for forfeited goods: that rule belongs to billing, and
/// this is about space.
/// Public alias — the per-item Storage & Movement block in the package popup
/// needs the same figure, and a second copy of this walk would drift from
/// this one the first time a rate rule changed.
double spaceCostFor({
  required DateTime from,
  required int units,
  required Map<DateTime, double> rates,
  DateTime? until,
}) =>
    _spaceCost(from: from, units: units, rates: rates, until: until);

double _spaceCost({
  required DateTime from,
  required int units,
  required Map<DateTime, double> rates,

  /// The day the goods LEFT, when they have. Null runs to today.
  ///
  /// ⚠️ Without this the figure was live-entries-only, and 146 of the
  /// rows on the disposition pages have a closed entry -- every sold,
  /// released, re-exported and "other" package in this yard. Their popups
  /// showed nothing at all, which is the opposite of the point: what the
  /// space cost is most worth knowing about goods that are gone.
  DateTime? until,
}) {
  final start = DateTime(from.year, from.month, from.day);
  final last = until ?? DateTime.now();
  final end = DateTime(last.year, last.month, last.day);
  if (end.isBefore(start)) return 0;
  var total = 0.0;
  for (var i = 0; i <= end.difference(start).inDays; i++) {
    final day = start.add(Duration(days: i));
    var rate = 50.0; // the same fallback the model uses
    rates.forEach((effectiveFrom, r) {
      final at = DateTime(
          effectiveFrom.year, effectiveFrom.month, effectiveFrom.day);
      if (!day.isBefore(at)) rate = r;
    });
    total += units * rate;
  }
  return total;
}

/// What the goods have cost the yard in storage, as of today.
///
/// ⚠️ Shown wherever somebody puts a PRICE on goods — the valuation forms, the
/// re-valuation after a failed tender, the committee's figure, and the sale
/// itself. A valuation set without it is a number chosen in ignorance of what
/// the goods have already cost to keep: goods valued at Rs 40,000 that have
/// run up Rs 90,000 in storage are worth tendering at a different figure than
/// the same goods admitted last week, and the officer could not see that from
/// the form.
///
/// ⚠️ It is a NOTE, never an input. Nothing here changes what is charged; the
/// charge is the rate history times the days, and it goes on accruing whatever
/// anybody types into the form beside it.
/// Whether [StorageChargeNote] would draw anything for this package.
///
/// ⚠️ A caller that wraps the note in a titled section needs to ask
/// BEFORE building the frame. A widget returning `SizedBox.shrink()` still
/// leaves its parent's heading, border and padding on screen -- so "show
/// nothing" rendered as an empty box with the word STORAGE over it.
///
/// Returns null while the package or the rates are still loading, so a
/// caller can hold the section back rather than flashing it away.
final storageChargeVisibleProvider =
    Provider.family<bool?, String?>((ref, packageId) {
  if (packageId == null || packageId.isEmpty) return false;
  final pkg = ref.watch(packageByIdProvider(packageId)).valueOrNull;
  final rates = ref.watch(storageRateProvider).valueOrNull;
  if (pkg == null || rates == null) return null;
  final isPerishable = pkg.items.any((i) => i.nature == kNaturePerishable);
  return pkg.warehouseEntries.isNotEmpty || isPerishable;
});

/// Whether these goods reached a Top Management ruling or are awaiting
/// a Top Management decision after failing tender — the Unsold route.
///
/// Keyed through the forfeited record and tender sale item record.
bool _isUnsoldDisposal(WidgetRef ref, PackageModel pkg,
    [String? packageItemId]) {
  final proposals = ref.watch(unsoldProposalsProvider).valueOrNull;
  final byItem = ref.watch(forfeitedByItemProvider(pkg.id)).valueOrNull;
  if (proposals != null && proposals.isNotEmpty && byItem != null) {
    if (packageItemId != null) {
      final fp = byItem[packageItemId];
      if (fp != null && proposals.containsKey(fp.id)) return true;
    } else {
      if (byItem.values.any((f) => proposals.containsKey(f.id))) return true;
    }
  }

  // Check if marked unsold in tender sale items (Awaiting Top Management or Unsold)
  final saleItem = packageItemId != null
      ? ref
          .watch(saleItemForPackageItemProvider('${pkg.id}|$packageItemId'))
          .valueOrNull
      : ref.watch(saleItemForPackageProvider(pkg.id)).valueOrNull;
  if (saleItem?.unsold == true) return true;

  if (packageItemId == null && byItem != null) {
    for (final itemId in byItem.keys) {
      final si = ref
          .watch(saleItemForPackageItemProvider('${pkg.id}|$itemId'))
          .valueOrNull;
      if (si?.unsold == true) return true;
    }
  }

  return false;
}

/// Stands in for the figure on goods nobody is billed for.
///
/// ⚠️ A sentence, not a blank. Removing the panel entirely would read as
/// "storage was never recorded", and the next person would go looking for
/// the number somewhere else.
class _NotChargedNote extends StatelessWidget {
  const _NotChargedNote({required this.compact, required this.priceOnly});

  final bool compact;
  final bool priceOnly;

  static const _line = 'No warehouse charge — unsold goods are not billed';

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.textMuted;
    if (priceOnly) {
      return Text('Not charged',
          style: TextStyle(color: muted, fontSize: 12));
    }
    if (compact) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.block_rounded, size: 13, color: muted),
        const Gap(5),
        Flexible(
          child: Text(_line,
              style: TextStyle(
                  color: muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ),
      ]);
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: muted.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: muted.withOpacity(0.25)),
      ),
      child: Row(children: [
        Icon(Icons.block_rounded, size: 16, color: muted),
        const Gap(10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('No warehouse charge',
                  style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const Gap(2),
              Text(
                  'Storage is not billed on unsold goods — every sale route '
                  'was exhausted and Top Management has ruled on them.',
                  style: TextStyle(color: muted, fontSize: 11)),
            ],
          ),
        ),
      ]),
    );
  }
}

class StorageChargeNote extends ConsumerWidget {
  const StorageChargeNote({
    super.key,
    required this.packageId,
    this.packageItemId,
    this.compact = false,
    this.priceOnly = false,
  });

  /// The package the goods belong to.
  final String? packageId;

  /// The specific item, when the form is about one.
  ///
  /// ⚠️ A package holds several items with separate entries, and charging the
  /// whole package on a form about one of them would overstate it — sometimes
  /// several times over.
  final String? packageItemId;

  /// One line rather than a panel, for forms that are already dense.
  final bool compact;

  /// Show only the formatted amount — no icon, no label. For table cells
  /// where the column header already identifies the figure.
  final bool priceOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = packageId;
    if (id == null || id.isEmpty) return const SizedBox.shrink();

    final pkgAsync = ref.watch(packageByIdProvider(id));
    final rates = ref.watch(storageRateProvider).valueOrNull;
    final pkg = pkgAsync.valueOrNull;
    if (pkg == null || rates == null) return const SizedBox.shrink();

    // ⚠️ Goods that exhausted every sale route are NOT charged for storage,
    // and no figure belongs on them at all — not even as "cost of space".
    //
    // These are the packages Top Management ruled on after four failed
    // tenders: taken into Government Use, sent to auction, converted, or
    // removed from the premises. Nobody will ever be invoiced, and nobody
    // is weighing a reserve price against the days any more, so a number
    // here reads as a bill that is owed. The same goods appear again under
    // each Final Outcome page, so the rule has to live with the figure
    // rather than with any one page.
    if (_isUnsoldDisposal(ref, pkg, packageItemId)) {
      return _NotChargedNote(compact: compact, priceOnly: priceOnly);
    }

    // ⚠️ A closed entry still COUNTS -- it just stops at the day it
    // closed. Skipping them entirely meant every sold, released and
    // re-exported package showed nothing, and those are exactly the goods
    // whose storage cost somebody wants to know.
    //
    // The item filter still applies: a package holds several items with
    // separate entries, and charging the whole package on a form about one
    // of them would overstate it, sometimes several times over.
    final entries = pkg.warehouseEntries.where((e) {
      if (packageItemId == null) return true;
      return e.packageItemId == packageItemId;
    }).toList();

    final isPerishable = packageItemId != null
        ? (pkg.items.where((i) => i.id == packageItemId).firstOrNull?.nature ==
            kNaturePerishable)
        : pkg.items.any((i) => i.nature == kNaturePerishable);

    if (entries.isEmpty && !isPerishable) return const SizedBox.shrink();

    double total = 0;
    DateTime? since;
    DateTime? lastDay;
    var billable = true;
    bool anyLive = false;

    if (entries.isNotEmpty) {
      anyLive = entries.any((e) => !e.isReturned);
      for (final e in entries) {
        final start = pkg.entryDate ?? e.admittedAt;
        if (since == null || start.isBefore(since)) since = start;
        // ⚠️ A closed entry ends on the day it CLOSED, not today. An
        // entry returned in 2024 has not been accruing since.
        final ends = e.isReturned ? (e.returnedAt ?? DateTime.now()) : null;
        final endOf = ends ?? DateTime.now();
        if (lastDay == null || endOf.isAfter(lastDay)) lastDay = endOf;
        final item =
            pkg.items.where((i) => i.id == e.packageItemId).firstOrNull;
        final status = (item?.status ?? '').trim().toLowerCase();
        if (WarehouseEntryModel.isNoChargeStatus(status)) billable = false;
        total += _spaceCost(
          from: start,
          units: e.itemCount,
          rates: rates,
          until: ends,
        );
      }
    } else {
      // Perishable goods stored in yard without warehouse admission entries.
      // Yard storage charges accrue from entry date until sold/completed.
      final saleItem = packageItemId != null
          ? ref
              .watch(saleItemForPackageItemProvider('$id|$packageItemId'))
              .valueOrNull
          : ref.watch(saleItemForPackageProvider(id)).valueOrNull;

      final start = pkg.entryDate ?? pkg.createdAt;
      since = start;
      final isDelivered = saleItem?.isDelivered == true;
      final ends = isDelivered
          ? (saleItem?.deliveredAt ?? saleItem?.soldAt ?? DateTime.now())
          : null;
      lastDay = ends ?? DateTime.now();
      anyLive = !isDelivered;
      billable = true;

      final units = packageItemId != null
          ? (pkg.items
                  .where((i) => i.id == packageItemId)
                  .firstOrNull
                  ?.quantity ??
              1)
          : (pkg.items.isNotEmpty
              ? pkg.items.fold<int>(
                  0, (sum, i) => sum + (i.quantity > 0 ? i.quantity : 1))
              : (pkg.totalItemCount > 0 ? pkg.totalItemCount : 1));

      total = _spaceCost(
        from: start,
        units: units,
        rates: rates,
        until: ends,
      );
    }

    if (total <= 0) return const SizedBox.shrink();

    final money = NumberFormat('#,##0.00');
    // ⚠️ Days to the LAST day counted, not to today. "703 days in
    // storage" about goods that left in 2024 is a figure and a lie in the
    // same line.
    final days = since == null
        ? null
        : (lastDay ?? DateTime.now()).difference(since).inDays;
    final held = days == null
        ? 'in storage'
        : 'over $days day${days == 1 ? '' : 's'} in storage';
    // ⚠️ Say WHICH figure this is. Billable goods will be invoiced for
    // it; forfeited and abandoned goods will not, and an officer told
    // "accrued" about goods nobody can be billed for would reasonably read
    // it as money the yard is owed.
    // ⚠️ Three sentences, because there are three cases: money still
    // owed, money that was owed and is settled, and days in a zone nobody
    // is billed for. Telling a reader goods are "payable on collection"
    // when they were collected two years ago is worse than saying nothing.
    final caption = !billable
        ? 'Cost of space $held \u00b7 not billable, the state holds these goods'
        : anyLive
            ? 'Accrued $held \u00b7 payable on collection'
            : 'Charged $held \u00b7 the goods have left the yard';

    if (priceOnly) {
      return Text(
        'Rs ${money.format(total)}',
        style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 12),
      );
    }

    if (compact) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.warehouse_rounded,
            size: 13, color: context.colors.textMuted),
        const Gap(5),
        // ⚠️ "so far" only where it is still running. The compact
        // line is the one that goes on a dense form, so it has to be
        // right in three words.
        Text(
            '${billable ? 'Storage charge' : 'Storage cost'}'
            '${anyLive ? ' so far' : ''}: '
            'LKR ${money.format(total)}',
            style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      ]);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.colors.warningAmber.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: context.colors.warningAmber.withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(Icons.warehouse_rounded,
            size: 16, color: context.colors.warningAmber),
        const Gap(10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  !billable
                      ? 'Storage cost'
                      : (anyLive
                          ? 'Warehouse charge to date'
                          : 'Warehouse charge'),
                  style: TextStyle(
                      color: context.colors.textMuted,
                      fontSize: 10,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w800)),
              const Gap(2),
              Text('LKR ${money.format(total)}',
                  style: TextStyle(
                      color: context.colors.warningAmber,
                      fontSize: 15,
                      fontWeight: FontWeight.w800)),
              Text(caption,
                  style: TextStyle(
                      color: context.colors.textSecondary, fontSize: 10.5)),
            ],
          ),
        ),
      ]),
    );
  }
}
