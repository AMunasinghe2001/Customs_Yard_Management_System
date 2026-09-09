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
  return pkg.warehouseEntries.isNotEmpty;
});

class StorageChargeNote extends ConsumerWidget {
  const StorageChargeNote({
    super.key,
    required this.packageId,
    this.packageItemId,
    this.compact = false,
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = packageId;
    if (id == null || id.isEmpty) return const SizedBox.shrink();

    final pkgAsync = ref.watch(packageByIdProvider(id));
    final rates = ref.watch(storageRateProvider).valueOrNull;
    final pkg = pkgAsync.valueOrNull;
    if (pkg == null || rates == null) return const SizedBox.shrink();

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
    // Whether any of them is still accruing, which changes the wording
    // below from "to date" to a closed figure.
    final anyLive = entries.any((e) => !e.isReturned);
    if (entries.isEmpty) return const SizedBox.shrink();

    // Charged from the SR's ENTRY DATE, the same rule the Released Goods
    // table uses, so this figure and that column cannot disagree.
    //
    // ⚠️ `calculatePackageCharge` returns ZERO for goods whose status is
    // confiscated / forfeit / abandoned / destroyed -- the state has taken
    // them, so there is no owner left to bill. That is the right rule for
    // an INVOICE and the wrong answer for a VALUATION: 48 of the 168 goods
    // that reach a valuation form carry exactly those statuses, so the note
    // would simply never appear on the forms it was built for.
    //
    // So the days and the rate are computed here, and the figure is labelled
    // for what it is: what the SPACE has cost, whether or not anybody will
    // be billed for it. An officer pricing goods that have occupied a zone
    // for 703 days needs that number either way.
    double total = 0;
    DateTime? since;
    DateTime? lastDay;
    var billable = true;
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
