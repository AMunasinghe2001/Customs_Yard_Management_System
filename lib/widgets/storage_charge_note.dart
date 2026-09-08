import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../core/providers.dart';
import '../core/theme.dart';
import '../models/models.dart';

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

    // ⚠️ Only entries that are STILL HELD. A package with a returned entry
    // and a live one would otherwise be charged for both, and the returned
    // one stopped accruing the day it closed.
    final entries = pkg.warehouseEntries.where((e) {
      if (e.isReturned) return false;
      if (packageItemId == null) return true;
      return e.packageItemId == packageItemId;
    }).toList();
    if (entries.isEmpty) return const SizedBox.shrink();

    // Charged from the SR's ENTRY DATE, the same rule the Released Goods
    // table uses, so this figure and that column cannot disagree.
    double total = 0;
    DateTime? since;
    for (final e in entries) {
      final start = pkg.entryDate ?? e.admittedAt;
      if (since == null || start.isBefore(since)) since = start;
      total += WarehouseEntryModel(
        id: e.id,
        packageId: e.packageId,
        packageItemId: e.packageItemId,
        warehouseId: e.warehouseId,
        warehouseName: e.warehouseName,
        warehouseCode: e.warehouseCode,
        holdReason: e.holdReason,
        itemCount: e.itemCount,
        admittedAt: start,
        dailyRate: e.dailyRate,
        // Null: to TODAY. These goods are still here, and the figure is what
        // they have cost so far.
        returnedAt: null,
      ).calculatePackageCharge(pkg.items, rates);
    }
    if (total <= 0) return const SizedBox.shrink();

    final money = NumberFormat('#,##0.00');
    final days = since == null
        ? null
        : DateTime.now().difference(since).inDays;
    final caption = days == null
        ? 'Accrued so far'
        : 'Accrued over $days day${days == 1 ? '' : 's'} in storage';

    if (compact) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.warehouse_rounded,
            size: 13, color: context.colors.textMuted),
        const Gap(5),
        Text('Storage so far: LKR ${money.format(total)}',
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
              Text('Warehouse charge to date',
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
