import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../core/yards.dart';
import '../../models/models.dart';
import '../../widgets/error_view.dart';
import '../../widgets/empty_table_state.dart';
import 'taxes_tab.dart';
import '../../widgets/styled_dropdown.dart';
import '../../widgets/styled_form_dialog.dart';
import '../../widgets/package_details_dialog.dart';

class DisposalDashboardScreen extends ConsumerWidget {
  const DisposalDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final green = context.colors.successGreen;
    final profile = ref.watch(currentProfileProvider);
    return DefaultTabController(
      length: 8,
      child: Scaffold(
        backgroundColor: context.colors.scaffoldBg,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top bar ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    green.withOpacity(0.08),
                    context.colors.cardDark,
                  ],
                ),
                border: Border(
                    bottom: BorderSide(color: context.colors.borderColor)),
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: green.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: green.withOpacity(0.3)),
                  ),
                  child: SvgPicture.asset('Sri_Lanka_Customs_logo_tinted.svg',
                      width: 30,
                      height: 30,
                      theme: SvgTheme(currentColor: green)),
                ),
                const Gap(14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Central Disposal Directorate',
                        style: TextStyle(
                            color: context.colors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w800)),
                    Text('Sold & forfeited items across all yards · tender sales',
                        style: TextStyle(
                            color: context.colors.textMuted, fontSize: 12)),
                  ],
                ),
                const Spacer(),
                if (profile != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: green.withOpacity(0.35)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.verified_user_rounded, color: green, size: 16),
                      const Gap(8),
                      Text(profile.fullName,
                          style: TextStyle(
                              color: green,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                    ]),
                  ),
                const Gap(8),
                IconButton(
                  tooltip: 'Toggle theme',
                  icon: Icon(
                      ref.watch(themeModeProvider) == ThemeMode.dark
                          ? Icons.light_mode_rounded
                          : Icons.dark_mode_rounded,
                      color: context.colors.textPrimary),
                  onPressed: () {
                    final isDark =
                        ref.read(themeModeProvider) == ThemeMode.dark;
                    ref.read(themeModeProvider.notifier).state =
                        isDark ? ThemeMode.light : ThemeMode.dark;
                  },
                ),
                const Gap(4),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.colors.dangerRed,
                    side: BorderSide(
                        color: context.colors.dangerRed.withOpacity(0.5)),
                  ),
                  icon: const Icon(Icons.logout_rounded, size: 16),
                  label: const Text('Sign Out'),
                  onPressed: () async {
                    await ref.read(authServiceProvider).signOut();
                    ref.read(currentProfileProvider.notifier).state = null;
                    if (context.mounted) context.go('/');
                  },
                ),
              ]),
            ).animate().fadeIn(duration: 350.ms).slideY(begin: -0.15),
            // ── Tabs ─────────────────────────────────────────────
            Container(
              color: context.colors.cardDark,
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              child: Container(
                decoration: BoxDecoration(
                  color: context.colors.surfaceDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.colors.borderColor),
                ),
                child: TabBar(
                  splashFactory: NoSplash.splashFactory,
                  overlayColor:
                      WidgetStateProperty.all(Colors.transparent),
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicatorPadding: const EdgeInsets.all(4),
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    color: green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: green.withOpacity(0.5)),
                  ),
                  labelColor: green,
                  unselectedLabelColor: context.colors.textMuted,
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13),
                  tabs: const [
                    Tab(
                        height: 44,
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.sell_rounded, size: 18),
                          Gap(8),
                          Flexible(child: Text('Sold Packages', overflow: TextOverflow.ellipsis)),
                        ])),
                    Tab(
                        height: 44,
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.gavel_outlined, size: 18),
                          Gap(8),
                          Flexible(child: Text('Forfeited Packages', overflow: TextOverflow.ellipsis)),
                        ])),
                    Tab(
                        height: 44,
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.assignment_turned_in_rounded, size: 18),
                          Gap(8),
                          Flexible(child: Text('Disposal Requests', overflow: TextOverflow.ellipsis)),
                        ])),
                    Tab(
                        height: 44,
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.storefront_rounded, size: 18),
                          Gap(8),
                          Flexible(child: Text('Tender Sales', overflow: TextOverflow.ellipsis)),
                        ])),
                    Tab(
                        height: 44,
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.replay_rounded, size: 18),
                          Gap(8),
                          Flexible(child: Text('Unsold Tenders', overflow: TextOverflow.ellipsis)),
                        ])),
                    Tab(
                        height: 44,
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.gavel_rounded, size: 18),
                          Gap(8),
                          Flexible(child: Text('Destructions', overflow: TextOverflow.ellipsis)),
                        ])),
                    Tab(
                        height: 44,
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.auto_delete_rounded, size: 18),
                          Gap(8),
                          Flexible(child: Text('Undestroyed', overflow: TextOverflow.ellipsis)),
                        ])),
                    Tab(
                        height: 44,
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.receipt_long_rounded, size: 18),
                          Gap(8),
                          Flexible(child: Text('Taxes', overflow: TextOverflow.ellipsis)),
                        ])),
                  ],
                ),
              ),
            ).animate().fadeIn(duration: 350.ms, delay: 80.ms),
            const Expanded(
              child: TabBarView(children: [
                _SoldPackagesTab(),
                _ForfeitedPackagesTab(),
                _DisposalRequestsTab(),
                _TenderSalesTab(),
                _UnsoldReTenderTab(),
                _DestructionsTab(),
                _UndestroyedReDestructionTab(),
                TaxesTab(),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────

class _YardFilter extends ConsumerWidget {
  const _YardFilter();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedYard = ref.watch(disposalSelectedYardProvider);
    return SizedBox(
      width: 240,
      child: StyledDropdownFormField<String>(
        value: selectedYard,
        label: 'Yard',
        helperText: null,
        isDense: true,
        menuWidth: 240,
        prefixIcon:
            Icon(Icons.warehouse_outlined, color: context.colors.textMuted),
        options: [
          for (final y in kYards) StyledDropdownOption(y.code, y.name),
        ],
        onChanged: (v) => ref.read(disposalSelectedYardProvider.notifier).state =
            v ?? kYards.first.code,
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip(
      {required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(value,
            style: TextStyle(
                color: color, fontSize: 18, fontWeight: FontWeight.w800)),
        const Gap(8),
        Text(label,
            style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

Widget _listCard(BuildContext context, Widget child) {
  return Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: context.colors.cardDark,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: context.colors.borderColor),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: child,
    ),
  ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.06);
}

WidgetStateProperty<Color?> _headingColor(BuildContext context) =>
    WidgetStateProperty.all(context.colors.surfaceDark);

// ── Sold Packages (cross-yard, yard dropdown) ─────────────────────

bool _isSoldEntry(WarehouseEntryModel e) {
  final notes = (e.returnNotes ?? '').trim().toUpperCase();
  final m = RegExp(r'^\[([^\]]+)\]').firstMatch(notes);
  if (m == null) return false;
  final tag = m.group(1)!.trim();
  return tag == 'FINAL:SOLD' || tag == 'SOLD';
}

class _SoldRow {
  final PackageModel package;
  final WarehouseEntryModel entry;
  final String itemName;
  final String officer;
  const _SoldRow(this.package, this.entry, this.itemName, this.officer);
}

class _SoldPackagesTab extends ConsumerWidget {
  const _SoldPackagesTab();

  List<_SoldRow> _rows(List<PackageModel> packages) {
    final rows = <_SoldRow>[];
    for (final p in packages) {
      for (final e in p.warehouseEntries) {
        if (!_isSoldEntry(e)) continue;
        final item =
            p.items.where((i) => i.id == e.packageItemId).firstOrNull;
        rows.add(_SoldRow(
          p,
          e,
          item?.itemName ?? (p.items.isNotEmpty ? p.items.first.itemName : '—'),
          e.returnedByName ?? e.returnedByBadge ?? '—',
        ));
      }
    }
    rows.sort((a, b) => (b.entry.returnedAt ?? b.entry.admittedAt)
        .compareTo(a.entry.returnedAt ?? a.entry.admittedAt));
    return rows;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final green = context.colors.successGreen;
    final selectedYard = ref.watch(disposalSelectedYardProvider);
    final sold = ref.watch(disposalSoldPackagesProvider);
    final storageRate = ref.watch(storageRateProvider).valueOrNull ??
        {DateTime(2020, 1, 1): 50.0};

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Sold Packages',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            const _YardFilter(),
          ]).animate().fadeIn(duration: 300.ms),
          const Gap(14),
          sold.maybeWhen(
            data: (packages) {
              final count = _rows(packages).length;
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(children: [
                  _StatChip(
                      label: 'Sold in ${yardName(selectedYard)}',
                      value: '$count',
                      color: green),
                ]),
              ).animate().fadeIn(duration: 300.ms);
            },
            orElse: () => const SizedBox.shrink(),
          ),
          Expanded(
            child: sold.when(
              skipLoadingOnReload: true,
              loading: () =>
                  Center(child: CircularProgressIndicator(color: green)),
              error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.refresh(disposalSoldPackagesProvider)),
              data: (packages) {
                final rows = _rows(packages);
                return _listCard(
                  context,
                  DataTable2(
                    columnSpacing: 12,
                    horizontalMargin: 16,
                    fixedTopRows: 1,
                    empty: EmptyTableState(
                        message:
                            'No sold packages in ${yardName(selectedYard)}'),
                    headingRowColor: _headingColor(context),
                    columns: const [
                      DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
                      DataColumn2(label: Text('Item'), size: ColumnSize.M),
                      DataColumn2(
                          label: Text('Qty'),
                          size: ColumnSize.S,
                          fixedWidth: 60),
                      DataColumn2(label: Text('Sold Date'), size: ColumnSize.M),
                      DataColumn2(label: Text('Sold By'), size: ColumnSize.M),
                      DataColumn2(label: Text('Financials'), size: ColumnSize.M),
                      DataColumn2(label: Text('Delivery'), fixedWidth: 120),
                      DataColumn2(
                          label: Center(child: Text('Details')),
                          size: ColumnSize.S,
                          fixedWidth: 70),
                    ],
                    rows: rows
                        .map((r) => DataRow(cells: [
                              DataCell(Text(r.package.srNumber,
                                  style: TextStyle(
                                      color: context.colors.accentLightBlue,
                                      fontWeight: FontWeight.w600))),
                              DataCell(Text(r.itemName,
                                  overflow: TextOverflow.ellipsis)),
                              DataCell(Text('${r.entry.itemCount}')),
                              DataCell(Text(r.entry.returnedAt != null
                                  ? DateFormat('yyyy-MM-dd')
                                      .format(r.entry.returnedAt!)
                                  : '—')),
                              DataCell(Text(r.officer,
                                  overflow: TextOverflow.ellipsis)),
                              DataCell(_SaleFinancialsCell(package: r.package)),
                              DataCell(_DeliveryStatusCell(package: r.package)),
                              DataCell(Center(
                                child: IconButton(
                                  icon: Icon(Icons.info_outline_rounded,
                                      color: context.colors.accentLightBlue,
                                      size: 18),
                                  onPressed: () => showDialog(
                                    context: context,
                                    builder: (_) => PackageDetailsDialog(
                                      package: r.package,
                                      storageRate: storageRate,
                                      highlightEntry: r.entry,
                                      useLegacySummary: true,
                                    ),
                                  ),
                                ),
                              )),
                            ]))
                        .toList(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Read-only sold price + tax total (watches the shared per-package provider).
class _SaleFinancialsCell extends ConsumerWidget {
  final PackageModel package;
  const _SaleFinancialsCell({required this.package});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(saleItemForPackageProvider(package.id));
    return async.when(
      loading: () => const SizedBox(
          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) => const Text('—'),
      data: (item) {
        if (item == null) return const Text('—');
        double taxSum = 0;
        for (final t in item.appliedTaxes) {
          taxSum += (t['amount'] as num?)?.toDouble() ?? 0;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Rs ${item.soldPrice.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Tax: Rs ${taxSum.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 11, color: context.colors.textMuted)),
          ],
        );
      },
    );
  }
}

// Read-only delivery STATUS chip (the action button lives in the details
// dialog, enabled for yards only). Watches the shared per-package provider.
class _DeliveryStatusCell extends ConsumerWidget {
  final PackageModel package;
  const _DeliveryStatusCell({required this.package});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(saleItemForPackageProvider(package.id));
    return async.when(
      loading: () => const SizedBox(
          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) => const Text('—'),
      data: (item) => item == null
          ? const Text('—')
          : DeliveryStatusChip(delivered: item.isDelivered),
    );
  }
}

/// Small read-only Delivered/Pending chip shared by the Sold tables.
class DeliveryStatusChip extends StatelessWidget {
  final bool delivered;
  const DeliveryStatusChip({super.key, required this.delivered});
  @override
  Widget build(BuildContext context) {
    final color =
        delivered ? context.colors.successGreen : context.colors.warningAmber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(delivered ? Icons.check_circle_rounded : Icons.schedule_rounded,
            size: 13, color: color),
        const Gap(5),
        Text(delivered ? 'Delivered' : 'Pending',
            style:
                TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}


// ── Forfeited Packages (cross-yard, yard dropdown) ────────────────

class _ForfeitedPackagesTab extends ConsumerWidget {
  const _ForfeitedPackagesTab();

  String _itemName(ForfeitedPackageModel f) {
    final items = f.packageDetails?.items ?? const [];
    if (items.isEmpty) return 'Multiple/Unspecified';
    if (items.length == 1) return items.first.itemName;
    return '${items.first.itemName} +${items.length - 1}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final green = context.colors.successGreen;
    final selectedYard = ref.watch(disposalSelectedYardProvider);
    final forfeited = ref.watch(disposalForfeitedPackagesProvider);
    final storageRate = ref.watch(storageRateProvider).valueOrNull ??
        {DateTime(2020, 1, 1): 50.0};

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Forfeited Packages',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            const _YardFilter(),
          ]).animate().fadeIn(duration: 300.ms),
          const Gap(14),
          forfeited.maybeWhen(
            data: (list) {
              final expired = list.where((f) => f.isAppealExpired).length;
              final inAppeal = list.length - expired;
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(children: [
                  _StatChip(
                      label: 'Total',
                      value: '${list.length}',
                      color: context.colors.accentLightBlue),
                  const Gap(12),
                  _StatChip(
                      label: 'In Appeal',
                      value: '$inAppeal',
                      color: green),
                  const Gap(12),
                  _StatChip(
                      label: 'Appeal Expired',
                      value: '$expired',
                      color: context.colors.dangerRed),
                ]),
              ).animate().fadeIn(duration: 300.ms);
            },
            orElse: () => const SizedBox.shrink(),
          ),
          Expanded(
            child: forfeited.when(
              skipLoadingOnReload: true,
              loading: () =>
                  Center(child: CircularProgressIndicator(color: green)),
              error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () =>
                      ref.refresh(disposalForfeitedPackagesProvider)),
              data: (list) {
                return _listCard(
                  context,
                  DataTable2(
                    columnSpacing: 12,
                    horizontalMargin: 16,
                    fixedTopRows: 1,
                    empty: EmptyTableState(
                        message:
                            'No forfeited packages in ${yardName(selectedYard)}'),
                    headingRowColor: _headingColor(context),
                    columns: const [
                      DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
                      DataColumn2(label: Text('Item'), size: ColumnSize.M),
                      DataColumn2(label: Text('Consignee'), size: ColumnSize.M),
                      DataColumn2(
                          label: Text('Forfeited'), size: ColumnSize.S),
                      DataColumn2(
                          label: Text('Appeal Deadline'), size: ColumnSize.S),
                      DataColumn2(
                          label: Text('Status'),
                          size: ColumnSize.S,
                          fixedWidth: 130),
                      DataColumn2(
                          label: Center(child: Text('Details')),
                          size: ColumnSize.S,
                          fixedWidth: 70),
                    ],
                    rows: list
                        .map((f) => DataRow(cells: [
                              DataCell(Text(f.srNumber,
                                  style: TextStyle(
                                      color: context.colors.accentLightBlue,
                                      fontWeight: FontWeight.w600))),
                              DataCell(Text(_itemName(f),
                                  overflow: TextOverflow.ellipsis)),
                              DataCell(Text(f.consigneeName,
                                  overflow: TextOverflow.ellipsis)),
                              DataCell(Text(DateFormat('yyyy-MM-dd')
                                  .format(f.forfeitedAt))),
                              DataCell(Text(
                                  DateFormat('yyyy-MM-dd')
                                      .format(f.appealDeadline),
                                  style: TextStyle(
                                      color: f.isAppealExpired
                                          ? context.colors.dangerRed
                                          : context.colors.textSecondary,
                                      fontWeight: FontWeight.w600))),
                              DataCell(_AppealStatusChip(f: f)),
                              DataCell(Center(
                                child: IconButton(
                                  icon: Icon(Icons.info_outline_rounded,
                                      color: context.colors.accentLightBlue,
                                      size: 18),
                                  onPressed: f.packageDetails == null
                                      ? null
                                      : () => showDialog(
                                            context: context,
                                            builder: (_) =>
                                                PackageDetailsDialog(
                                              package: f.packageDetails!,
                                              storageRate: storageRate,
                                              useLegacySummary: true,
                                            ),
                                          ),
                                ),
                              )),
                            ]))
                        .toList(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AppealStatusChip extends StatelessWidget {
  final ForfeitedPackageModel f;
  const _AppealStatusChip({required this.f});
  @override
  Widget build(BuildContext context) {
    final expired = f.isAppealExpired;
    final color =
        expired ? context.colors.dangerRed : context.colors.successGreen;
    final label = expired
        ? 'Appeal Expired'
        : 'In Appeal · ${f.daysUntilDeadline}d';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

// ── Disposal Requests (per yard, per submission) ──────────────────
// null = all yards.
final _requestYardFilterProvider = StateProvider<String?>((ref) => null);

class _DisposalRequestsTab extends ConsumerWidget {
  const _DisposalRequestsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final green = context.colors.successGreen;
    final requests = ref.watch(disposalRequestsProvider);
    final yardFilter = ref.watch(_requestYardFilterProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Disposal Requests',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            SizedBox(
              width: 240,
              child: StyledDropdownFormField<String>(
                value: yardFilter ?? '_all',
                label: 'Yard',
                helperText: null,
                isDense: true,
                menuWidth: 240,
                prefixIcon: Icon(Icons.warehouse_outlined,
                    color: context.colors.textMuted),
                options: [
                  const StyledDropdownOption('_all', 'All Yards'),
                  for (final y in kYards) StyledDropdownOption(y.code, y.name),
                ],
                onChanged: (v) =>
                    ref.read(_requestYardFilterProvider.notifier).state =
                        (v == null || v == '_all') ? null : v,
              ),
            ),
          ]).animate().fadeIn(duration: 300.ms),
          const Gap(16),
          Expanded(
            child: requests.when(
              skipLoadingOnReload: true,
              loading: () =>
                  Center(child: CircularProgressIndicator(color: green)),
              error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.refresh(disposalRequestsProvider)),
              data: (list) {
                final filtered = yardFilter == null
                    ? list
                    : list.where((r) => r.yard == yardFilter).toList();
                if (filtered.isEmpty) {
                  return _listCard(
                    context,
                    const EmptyTableState(
                        message: 'No disposal requests submitted yet'),
                  );
                }
                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Gap(16),
                  itemBuilder: (context, i) =>
                      _RequestCard(request: filtered[i]),
                ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.05);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends ConsumerWidget {
  final DisposalRequestModel request;
  const _RequestCard({required this.request});

  String _itemName(DisposalRequestItemModel it) {
    final items = it.forfeited?.packageDetails?.items ?? const [];
    if (items.isEmpty) return 'Multiple/Unspecified';
    if (items.length == 1) return items.first.itemName;
    return '${items.first.itemName} +${items.length - 1}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final green = context.colors.successGreen;
    final red = context.colors.dangerRed;
    final storageRate = ref.watch(storageRateProvider).valueOrNull ??
        {DateTime(2020, 1, 1): 50.0};
    final items = request.items;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: green.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: green.withOpacity(0.35)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.warehouse_rounded, size: 16, color: green),
                  const Gap(8),
                  Text(yardName(request.yard),
                      style: TextStyle(
                          color: green,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                ]),
              ),
              const Gap(14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.calendar_today_rounded,
                          size: 12, color: context.colors.textMuted),
                      const Gap(4),
                      Text(
                          DateFormat('yyyy-MM-dd').format(request.requestDate),
                          style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      if (request.createdByName != null) ...[
                        const Gap(12),
                        Icon(Icons.person_rounded,
                            size: 12, color: context.colors.textMuted),
                        const Gap(4),
                        Text(request.createdByName!,
                            style: TextStyle(
                                color: context.colors.textMuted, fontSize: 12)),
                      ],
                    ]),
                    const Gap(2),
                    Text('${items.length} package${items.length == 1 ? '' : 's'} requested',
                        style: TextStyle(
                            color: context.colors.textMuted, fontSize: 11)),
                  ],
                ),
              ),
              _CountPill(
                  icon: Icons.delete_forever_rounded,
                  label: 'Destruction',
                  count: request.destructionCount,
                  color: red),
              const Gap(8),
              _CountPill(
                  icon: Icons.sell_rounded,
                  label: 'Sale',
                  count: request.saleCount,
                  color: green),
            ]),
          ),
          Divider(height: 1, color: context.colors.borderColor),
          // Items table
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              height: (items.length * 48.0 + 52).clamp(100, 320),
              decoration: BoxDecoration(
                border: Border.all(color: context.colors.borderColor),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: DataTable2(
                  columnSpacing: 12,
                  horizontalMargin: 14,
                  fixedTopRows: 1,
                  headingRowColor: _headingColor(context),
                  empty: const EmptyTableState(
                      message: 'No packages in this request'),
                  columns: const [
                    DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
                    DataColumn2(label: Text('Item'), size: ColumnSize.M),
                    DataColumn2(label: Text('Consignee'), size: ColumnSize.M),
                    DataColumn2(
                        label: Text('Disposition'),
                        size: ColumnSize.S,
                        fixedWidth: 130),
                    DataColumn2(
                        label: Center(child: Text('Details')),
                        size: ColumnSize.S,
                        fixedWidth: 70),
                  ],
                  rows: items.map((it) {
                    final f = it.forfeited;
                    return DataRow(cells: [
                      DataCell(Text(f?.srNumber ?? '—',
                          style: TextStyle(
                              color: context.colors.accentLightBlue,
                              fontWeight: FontWeight.w600))),
                      DataCell(Text(_itemName(it),
                          overflow: TextOverflow.ellipsis)),
                      DataCell(Text(f?.consigneeName ?? '—',
                          overflow: TextOverflow.ellipsis)),
                      DataCell(_DispositionChip(disposition: it.disposition)),
                      DataCell(Center(
                        child: IconButton(
                          icon: Icon(Icons.info_outline_rounded,
                              color: context.colors.accentLightBlue, size: 18),
                          onPressed: f?.packageDetails == null
                              ? null
                              : () => showDialog(
                                    context: context,
                                    builder: (_) => PackageDetailsDialog(
                                      package: f!.packageDetails!,
                                      storageRate: storageRate,
                                      useLegacySummary: true,
                                    ),
                                  ),
                        ),
                      )),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DispositionChip extends StatelessWidget {
  final String disposition;
  const _DispositionChip({required this.disposition});
  @override
  Widget build(BuildContext context) {
    final isSale = disposition == 'sale';
    final color =
        isSale ? context.colors.successGreen : context.colors.dangerRed;
    final icon =
        isSale ? Icons.sell_rounded : Icons.delete_forever_rounded;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const Gap(5),
        Text(dispositionLabel(disposition),
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _CountPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;
  const _CountPill(
      {required this.icon,
      required this.label,
      required this.count,
      required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: color),
        const Gap(6),
        Text('$count',
            style: TextStyle(
                color: color, fontSize: 16, fontWeight: FontWeight.w800)),
        const Gap(6),
        Text(label,
            style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ── Unsold packages → Re-tender (separate page/tab) ───────────────

class _UnsoldReTenderTab extends ConsumerWidget {
  const _UnsoldReTenderTab();

  String _itemName(ForfeitedPackageModel f) {
    final items = f.packageDetails?.items ?? const [];
    if (items.isEmpty) return 'Multiple/Unspecified';
    if (items.length == 1) return items.first.itemName;
    return '${items.first.itemName} +${items.length - 1}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final green = context.colors.successGreen;
    final amber = context.colors.warningAmber;
    final async = ref.watch(unsoldTenderSalesProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Unsold Packages — Re-tender',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            async.maybeWhen(
                  data: (list) => ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: green, foregroundColor: Colors.white),
                    icon: const Icon(Icons.gavel_rounded, size: 18),
                    label: const Text('Re-tender',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    onPressed: list.isEmpty
                        ? null
                        : () => showDialog(
                              context: context,
                              builder: (_) =>
                                  const _TenderSaleFormDialog(reTender: true),
                            ).then((_) {
                              ref.invalidate(unsoldTenderSalesProvider);
                              ref.invalidate(tenderSalesProvider);
                            }),
                  ),
              orElse: () => const SizedBox(),
            ),
          ]).animate().fadeIn(duration: 300.ms),
          const Gap(14),
          async.maybeWhen(
            data: (list) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _StatChip(
                  label: 'Unsold — re-tenderable',
                  value: '${list.length}',
                  color: amber),
            ).animate().fadeIn(duration: 300.ms),
            orElse: () => const SizedBox.shrink(),
          ),
          Expanded(
            child: async.when(
              skipLoadingOnReload: true,
              loading: () =>
                  Center(child: CircularProgressIndicator(color: green)),
              error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.refresh(unsoldTenderSalesProvider)),
              data: (list) {
                if (list.isEmpty) {
                  return _listCard(
                    context,
                    const EmptyTableState(
                        message:
                            'No unsold packages — everything tendered is sold or still in an active sale window'),
                  );
                }
                return _listCard(
                  context,
                  DataTable2(
                    columnSpacing: 12,
                    horizontalMargin: 16,
                    fixedTopRows: 1,
                    minWidth: 760,
                    headingRowColor: _headingColor(context),
                    columns: const [
                      DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
                      DataColumn2(label: Text('Item'), size: ColumnSize.L),
                      DataColumn2(label: Text('Consignee'), size: ColumnSize.M),
                      DataColumn2(
                          label: Center(child: Text('Times Tendered')),
                          size: ColumnSize.S,
                          fixedWidth: 130),
                      DataColumn2(
                          label: Center(child: Text('Tenders')),
                          size: ColumnSize.S,
                          fixedWidth: 90),
                    ],
                    rows: list.map((info) {
                      final f = info.forfeited;
                      return DataRow(cells: [
                        DataCell(Text(f.srNumber,
                            style: TextStyle(
                                color: context.colors.accentLightBlue,
                                fontWeight: FontWeight.w600))),
                        DataCell(Text(_itemName(f),
                            overflow: TextOverflow.ellipsis)),
                        DataCell(Text(f.consigneeName,
                            overflow: TextOverflow.ellipsis)),
                        DataCell(Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: amber.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: amber.withOpacity(0.4)),
                            ),
                            child: Text('${info.tenderCount}×',
                                style: TextStyle(
                                    color: amber, fontWeight: FontWeight.w800)),
                          ),
                        )),
                        DataCell(Center(
                          child: IconButton(
                            icon: const Icon(Icons.history_rounded, size: 18),
                            color: context.colors.accentLightBlue,
                            onPressed: () => showDialog(
                              context: context,
                              builder: (_) => _TenderSaleHistoryDialog(info: info),
                            ),
                          ),
                        )),
                      ]);
                    }).toList(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tender Sales ──────────────────────────────────────────────────

class _TenderSalesTab extends ConsumerWidget {
  const _TenderSalesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final green = context.colors.successGreen;
    final sales = ref.watch(tenderSalesProvider);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Tender Sales',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: green, foregroundColor: Colors.white),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New Tender Sale',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const _TenderSaleFormDialog()),
            ),
          ]).animate().fadeIn(duration: 300.ms),
          const Gap(16),
          Expanded(
            child: sales.when(
              skipLoadingOnReload: true,
              loading: () =>
                  Center(child: CircularProgressIndicator(color: green)),
              error: (e, _) => ErrorView(
                  error: e, onRetry: () => ref.refresh(tenderSalesProvider)),
              data: (list) {
                // Hide sales whose packages are all sold (fully consumed).
                final visible =
                    list.where((s) => s.items.any((i) => !i.sold)).toList();
                if (visible.isEmpty) {
                  return _listCard(
                    context,
                    const EmptyTableState(
                        message: 'No tender sales with unsold packages'),
                  );
                }
                return ListView.separated(
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const Gap(16),
                  itemBuilder: (context, i) => _TenderSaleCard(sale: visible[i]),
                ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.05);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tender Sale card (header + per-item detail table + Mark Sold) ─────────

class _TsRow {
  final TenderSaleItemModel saleItem;
  final PackageItem? item;
  final String warehouse;
  const _TsRow(this.saleItem, this.item, this.warehouse);
}

class _TenderSaleCard extends ConsumerWidget {
  final TenderSaleModel sale;
  const _TenderSaleCard({required this.sale});

  String _warehouseFor(PackageModel? pkg, String itemId) {
    if (pkg == null) return '—';
    final entries =
        pkg.warehouseEntries.where((e) => e.packageItemId == itemId).toList()
          ..sort((a, b) => b.admittedAt.compareTo(a.admittedAt));
    if (entries.isEmpty) return '—';
    final w = entries.first;
    return w.zone != null && w.zone!.isNotEmpty
        ? '${w.warehouseName} · ${w.zone}'
        : w.warehouseName;
  }

  List<_TsRow> _rows() {
    final rows = <_TsRow>[];
    // Sold items leave the Tender Sales page (they move to Sold Packages).
    for (final si in sale.items.where((s) => !s.sold)) {
      final pkg = si.forfeited?.packageDetails;
      final items = pkg?.items ?? const [];
      if (items.isEmpty) {
        rows.add(_TsRow(si, null, '—'));
      } else {
        for (final it in items) {
          rows.add(_TsRow(si, it, _warehouseFor(pkg, it.id)));
        }
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final green = context.colors.successGreen;
    final rows = _rows();
    final total = sale.items.length;
    final sold = sale.soldCount;
    final allSold = total > 0 && sold == total;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: allSold
                ? green.withOpacity(0.4)
                : context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: green.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.receipt_long_rounded, color: green, size: 20),
              ),
              const Gap(14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        sale.saleNumber?.isNotEmpty == true
                            ? sale.saleNumber!
                            : 'Tender Sale',
                        style: TextStyle(
                            color: context.colors.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 16)),
                    const Gap(2),
                    Row(children: [
                      Icon(Icons.calendar_today_rounded,
                          size: 12, color: context.colors.textMuted),
                      const Gap(4),
                      Text(
                          sale.saleDate != null
                              ? DateFormat('yyyy-MM-dd').format(sale.saleDate!)
                              : '—',
                          style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 12)),
                      const Gap(12),
                      Flexible(
                        child: Text(sale.typeLabel,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: context.colors.textMuted,
                                fontSize: 12)),
                      ),
                    ]),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: (allSold ? green : context.colors.warningAmber)
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: (allSold ? green : context.colors.warningAmber)
                          .withOpacity(0.4)),
                ),
                child: Text(
                  total == 0 ? 'No packages' : '$sold / $total sold',
                  style: TextStyle(
                      color: allSold ? green : context.colors.warningAmber,
                      fontWeight: FontWeight.w700,
                      fontSize: 12),
                ),
              ),
            ]),
          ),
          Divider(height: 1, color: context.colors.borderColor),
          // Items table
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              height: (rows.length * 46.0 + 56).clamp(110, 360),
              decoration: BoxDecoration(
                border: Border.all(color: context.colors.borderColor),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: DataTable2(
                  columnSpacing: 10,
                  horizontalMargin: 12,
                  fixedTopRows: 1,
                  minWidth: 1080,
                  headingRowColor: _headingColor(context),
                  empty:
                      const EmptyTableState(message: 'No packages in this sale'),
                  columns: const [
                    DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
                    DataColumn2(label: Text('Case No'), size: ColumnSize.S),
                    DataColumn2(label: Text('Item'), size: ColumnSize.M),
                    DataColumn2(
                        label: Text('Qty'), size: ColumnSize.S, fixedWidth: 56),
                    DataColumn2(label: Text('Forfeit Reason'), size: ColumnSize.M),
                    DataColumn2(label: Text('Location'), size: ColumnSize.M),
                    DataColumn2(
                        label: Text('Goods Description'), size: ColumnSize.L),
                    DataColumn2(
                        label: Center(child: Text('Status')),
                        size: ColumnSize.M,
                        fixedWidth: 140),
                  ],
                  rows: rows.map((r) {
                    final f = r.saleItem.forfeited;
                    final pkg = f?.packageDetails;
                    return DataRow(cells: [
                      DataCell(Text(f?.srNumber ?? '—',
                          style: TextStyle(
                              color: context.colors.accentLightBlue,
                              fontWeight: FontWeight.w600))),
                      DataCell(Text(pkg?.caseNumber ?? '—',
                          overflow: TextOverflow.ellipsis)),
                      DataCell(Text(r.item?.itemName ?? 'Multiple/Unspecified',
                          overflow: TextOverflow.ellipsis)),
                      DataCell(Text('${r.item?.quantity ?? '—'}')),
                      DataCell(Tooltip(
                        message: f?.reason ?? '',
                        child: Text(
                            f?.reason.isNotEmpty == true ? f!.reason : '—',
                            overflow: TextOverflow.ellipsis),
                      )),
                      DataCell(Text(
                          '${yardName(r.saleItem.yard)} / ${r.warehouse}',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 12))),
                      DataCell(Tooltip(
                        message: r.item?.goodsDescription ?? '',
                        child: Text(
                            r.item?.goodsDescription?.isNotEmpty == true
                                ? r.item!.goodsDescription!
                                : '—',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 12)),
                      )),
                      DataCell(Center(
                        child: r.saleItem.sold
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: green.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border:
                                      Border.all(color: green.withOpacity(0.4)),
                                ),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.check_circle_rounded,
                                          size: 13, color: green),
                                      const Gap(5),
                                      Text('Sold',
                                          style: TextStyle(
                                              color: green,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700)),
                                    ]),
                              )
                            : OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: green,
                                  side: BorderSide(
                                      color: green.withOpacity(0.5)),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  minimumSize: const Size(0, 32),
                                ),
                                icon: const Icon(Icons.sell_rounded, size: 14),
                                label: const Text('Mark Sold',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700)),
                                onPressed: () => _markSold(
                                    context, ref, r.saleItem),
                              ),
                      )),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _markSold(
      BuildContext context, WidgetRef ref, TenderSaleItemModel item) {
    showDialog(
      context: context,
      builder: (ctx) => _MarkSoldDialog(item: item, ref: ref),
    );
  }
}

class _MarkSoldDialog extends StatefulWidget {
  final TenderSaleItemModel item;
  final WidgetRef ref;
  const _MarkSoldDialog({required this.item, required this.ref});
  @override
  State<_MarkSoldDialog> createState() => _MarkSoldDialogState();
}

class _MarkSoldDialogState extends State<_MarkSoldDialog> {
  final _receiptC = TextEditingController();
  final _soldPriceC = TextEditingController();
  bool _loading = false;
  List<DisposalTaxModel>? _activeTaxes;

  @override
  void initState() {
    super.initState();
    widget.ref.read(disposalServiceProvider).getTaxes().then((taxes) {
      if (mounted) {
        setState(() {
          _activeTaxes = taxes.where((t) => t.isActive).toList();
        });
      }
    });
    _soldPriceC.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _receiptC.dispose();
    _soldPriceC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final price = double.tryParse(_soldPriceC.text) ?? 0.0;
    double totalTax = 0.0;
    final List<Map<String, dynamic>> appliedTaxesList = [];
    if (_activeTaxes != null) {
      for (var t in _activeTaxes!) {
        final taxAmount = price * (t.percentage / 100);
        totalTax += taxAmount;
        appliedTaxesList.add({
          'id': t.id,
          'name': t.name,
          'percentage': t.percentage,
          'amount': taxAmount,
        });
      }
    }
    final double grandTotal = price + totalTax;

    return StyledFormDialog(
      label: 'Tender Sale',
      title: 'Mark Package Sold',
      icon: Icons.sell_rounded,
      width: 460,
      child: StyledFormSection(
        title: 'Sale Confirmation',
        icon: Icons.receipt_rounded,
        children: [
          Text(
            '${widget.item.forfeited?.srNumber ?? 'Package'} — ${yardName(widget.item.yard)}. '
            'This records the package as SOLD.',
            style: TextStyle(
              color: context.colors.textSecondary, fontSize: 13)
          ),
          TextField(
            controller: _receiptC,
            decoration: const InputDecoration(labelText: 'Receipt Number (optional)'),
          ),
          const Gap(16),
          TextField(
            controller: _soldPriceC,
            decoration: const InputDecoration(labelText: 'Sold Price', prefixText: 'Rs '),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          if (_activeTaxes != null && _activeTaxes!.isNotEmpty) ...[
            const Gap(16),
            const Text('Taxes:', style: TextStyle(fontWeight: FontWeight.bold)),
            for (var t in _activeTaxes!)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${t.name} (${t.percentage}%)'),
                  Text('Rs ${(price * (t.percentage / 100)).toStringAsFixed(2)}'),
                ],
              ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Grand Total:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('Rs ${grandTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel')
        ),
        StyledDialogPrimaryButton(
          labelText: 'Confirm Sold',
          icon: Icons.check_circle_rounded,
          loading: _loading,
          onPressed: () async {
            setState(() => _loading = true);
            try {
              await widget.ref.read(disposalServiceProvider).markTenderSaleItemSold(
                tenderSaleItemId: widget.item.id,
                receipt: _receiptC.text,
                soldPrice: price,
                appliedTaxes: appliedTaxesList,
              );
              widget.ref.read(tenderSalesRefreshProvider.notifier).trigger();
              widget.ref.read(packagesRefreshTriggerProvider.notifier).trigger();
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: const Text('Package marked sold'),
                  backgroundColor: context.colors.successGreen,
                ));
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Error: $e'),
                  backgroundColor: context.colors.dangerRed,
                ));
              }
            } finally {
              if (mounted) setState(() => _loading = false);
            }
          },
        ),
      ],
    );
  }
}

// ── New Tender Sale form (details + Sale-only package picker) ─────────────

class _TenderSaleFormDialog extends ConsumerStatefulWidget {
  /// In [reTender] mode the package pool is the unsold tender-sale packages
  /// (not fresh "Sale" requests) — used by the Unsold Tenders page.
  final bool reTender;
  const _TenderSaleFormDialog({this.reTender = false});
  @override
  ConsumerState<_TenderSaleFormDialog> createState() =>
      _TenderSaleFormDialogState();
}

class _TenderSaleFormDialogState extends ConsumerState<_TenderSaleFormDialog> {
  final _numberC = TextEditingController();
  final _serialC = TextEditingController();
  final _yearC = TextEditingController(text: DateTime.now().year.toString());
  DateTime? _saleDate;
  TimeOfDay? _saleTime;
  String? _tenderType;
  bool _loading = false;
  // forfeited_package_id → yard
  final Map<String, String> _selected = {};

  @override
  void initState() {
    super.initState();
    _yearC.addListener(_onYearChanged);
    _serialC.addListener(_updateSaleNumber);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSerialForYear();
    });
  }

  @override
  void dispose() {
    _yearC.removeListener(_onYearChanged);
    _serialC.removeListener(_updateSaleNumber);
    _numberC.dispose();
    _serialC.dispose();
    _yearC.dispose();
    super.dispose();
  }

  void _onYearChanged() {
    if (_yearC.text.length == 4) {
      _loadSerialForYear();
    }
  }

  Future<void> _loadSerialForYear() async {
    final year = int.tryParse(_yearC.text);
    if (year == null) return;
    try {
      final nextSerial = await ref.read(disposalServiceProvider).getNextTenderSaleSerial(year);
      if (mounted) {
        _serialC.text = nextSerial.toString();
        _updateSaleNumber();
      }
    } catch (e) {
      // ignore
    }
  }

  void _updateSaleNumber() {
    final year = _yearC.text;
    final serial = _serialC.text;
    if (year.isEmpty || serial.isEmpty) return;
    
    String saleNum = 'CDU/TS/$year/$serial';
    if (_tenderType == 'special') {
      saleNum += '(Special)';
    }
    _numberC.text = saleNum;
  }

  String _summary(DisposalRequestItemModel it) {
    final items = it.forfeited?.packageDetails?.items ?? const [];
    if (items.isEmpty) return 'Multiple/Unspecified';
    if (items.length == 1) return items.first.itemName;
    return '${items.first.itemName} +${items.length - 1}';
  }

  @override
  Widget build(BuildContext context) {
    final green = context.colors.successGreen;
    // Fresh sale → "Sale"-tagged requests. Re-tender → only the unsold packages
    // shown on the Unsold Tenders page.
    final AsyncValue<List<DisposalRequestItemModel>> pool = widget.reTender
        ? ref.watch(unsoldTenderSalesProvider).whenData((list) => list
            .map((info) => DisposalRequestItemModel(
                  id: info.forfeited.id,
                  requestId: '',
                  forfeitedPackageId: info.forfeited.id,
                  disposition: 'sale',
                  forfeited: info.forfeited,
                ))
            .toList())
        : ref.watch(saleRequestItemsProvider);
    return StyledFormDialog(
      label: 'Tender Sale',
      title: widget.reTender ? 'Re-tender Sale' : 'New Tender Sale',
      icon: Icons.gavel_rounded,
      width: 720,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StyledFormSection(
            title: 'Sale Details',
            icon: Icons.receipt_long_rounded,
            children: [
              TextField(
                controller: _numberC,
                readOnly: true,
                decoration:
                    const InputDecoration(labelText: 'Tender Sale Number'),
              ),
              Row(children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _saleDate ?? DateTime.now(),
                        firstDate: DateTime(2015),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setState(() => _saleDate = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Tender Sale Date',
                        suffixIcon: Icon(Icons.calendar_month_rounded),
                      ),
                      child: Text(_saleDate != null
                          ? DateFormat('yyyy-MM-dd').format(_saleDate!)
                          : 'Select sale date', style: _saleDate == null ? TextStyle(color: context.colors.textMuted) : null),
                    ),
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _saleTime ?? TimeOfDay.now(),
                      );
                      if (picked != null) setState(() => _saleTime = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Sale Start Time',
                        suffixIcon: Icon(Icons.access_time_rounded),
                      ),
                      child: Text(_saleTime != null
                          ? _saleTime!.format(context)
                          : 'Select time', style: _saleTime == null ? TextStyle(color: context.colors.textMuted) : null),
                    ),
                  ),
                ),
              ]),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _serialC,
                    readOnly: true,
                    decoration: const InputDecoration(labelText: 'Serial'),
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: TextField(
                    controller: _yearC,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Year'),
                  ),
                ),
              ]),
              DropdownButtonFormField<String>(
                value: _tenderType,
                isExpanded: true,
                decoration:
                    const InputDecoration(labelText: 'Tender Sale Type'),
                items: [
                  for (final e in kTenderSaleTypes.entries)
                    DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) {
                  setState(() => _tenderType = v);
                  _updateSaleNumber();
                },
              ),
            ],
          ),
          const Gap(16),
          StyledFormSection(
            title: 'Select Packages — for Sale (${_selected.length} selected)',
            icon: Icons.inventory_2_rounded,
            children: [
              pool.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => ErrorView(
                    error: e,
                    onRetry: () => ref.refresh(widget.reTender
                        ? unsoldTenderSalesProvider
                        : saleRequestItemsProvider)),
                data: (items) {
                  if (items.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: Text(
                          'No "Sale" packages awaiting a tender sale.\n'
                          'Yards mark packages for Sale in a Disposal Request.',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: context.colors.textSecondary),
                        ),
                      ),
                    );
                  }
                  return ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: context.colors.borderColor.withOpacity(0.5)),
                      itemBuilder: (context, i) {
                        final it = items[i];
                        final id = it.forfeitedPackageId;
                        final yard = it.forfeited?.yard ?? '';
                        final selected = _selected.containsKey(id);
                        return InkWell(
                          onTap: () => setState(() {
                            if (selected) {
                              _selected.remove(id);
                            } else {
                              _selected[id] = yard;
                            }
                          }),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 6),
                            child: Row(children: [
                              Checkbox(
                                activeColor: green,
                                value: selected,
                                onChanged: (_) => setState(() {
                                  if (selected) {
                                    _selected.remove(id);
                                  } else {
                                    _selected[id] = yard;
                                  }
                                }),
                              ),
                              Expanded(
                                flex: 5,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(it.forfeited?.srNumber ?? '—',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: context
                                                .colors.accentLightBlue)),
                                    Text(_summary(it),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: context
                                                .colors.textSecondary)),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 4,
                                child: Text(
                                    it.forfeited?.consigneeName ?? '—',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: context.colors.textPrimary)),
                              ),
                              const Gap(8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border:
                                      Border.all(color: green.withOpacity(0.3)),
                                ),
                                child: Text(yardName(yard),
                                    style: TextStyle(
                                        color: green,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        StyledDialogPrimaryButton(
          labelText: 'Save Tender Sale',
          icon: Icons.save_rounded,
          loading: _loading,
          onPressed: () async {
            setState(() => _loading = true);
            try {
              await ref.read(disposalServiceProvider).createTenderSale(
                    saleNumber: _numberC.text.trim().isEmpty ? null : _numberC.text.trim(),
                    saleDate: _saleDate,
                    saleTime: _saleTime?.format(context),
                    serial:
                        _serialC.text.trim().isEmpty ? null : _serialC.text.trim(),
                    year: int.tryParse(_yearC.text.trim()),
                    tenderType: _tenderType,
                    yard: ref.read(disposalSelectedYardProvider),
                    packageYards: Map<String, String>.from(_selected),
                  );
              ref.read(tenderSalesRefreshProvider.notifier).trigger();
              if (mounted) Navigator.pop(context);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: const Text('Tender sale recorded'),
                  backgroundColor: green,
                ));
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Error: $e'),
                  backgroundColor: context.colors.dangerRed,
                ));
              }
            } finally {
              if (mounted) setState(() => _loading = false);
            }
          },
        ),
      ],
    );
  }
}

class _TenderSaleHistoryDialog extends StatelessWidget {
  final ReTenderSaleInfo info;
  const _TenderSaleHistoryDialog({required this.info});

  @override
  Widget build(BuildContext context) {
    final sales = info.sales;
    return Dialog(
      backgroundColor: context.colors.scaffoldBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        width: 540,
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.history_rounded, color: context.colors.primaryGold),
              const Gap(10),
              Expanded(
                child: Text('Tender Sale History — ${info.forfeited.srNumber}',
                    style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
              ),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded)),
            ]),
            const Gap(4),
            Text('Tendered ${info.tenderCount} time(s)',
                style: TextStyle(color: context.colors.textSecondary)),
            const Gap(12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: sales.length,
                separatorBuilder: (_, __) => const Gap(10),
                itemBuilder: (context, i) {
                  final t = sales[i];
                  final isLatest = i == 0;
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.colors.cardDark,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: isLatest
                              ? context.colors.primaryGold.withOpacity(0.5)
                              : context.colors.borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.gavel_rounded,
                              size: 16, color: context.colors.primaryGold),
                          const Gap(8),
                          Text(t.saleNumber ?? 'No Number',
                              style: TextStyle(
                                  color: context.colors.textPrimary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15)),
                          if (isLatest) ...[
                            const Gap(8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: context.colors.primaryGold
                                    .withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('Latest',
                                  style: TextStyle(
                                      color: context.colors.primaryGold,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ]),
                        const Gap(8),
                        _kv(
                            context,
                            'Sale Date',
                            t.saleDate != null
                                ? DateFormat('yyyy-MM-dd').format(t.saleDate!)
                                : '—'),
                        _kv(context, 'Sale Start Time', t.saleTime ?? '—'),
                        if (t.createdByName != null)
                          _kv(context, 'Created By', t.createdByName!),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(
          width: 130,
          child: Text(k,
              style: TextStyle(
                  color: context.colors.textMuted, fontSize: 12)),
        ),
        Expanded(
          child: Text(v,
              style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}


// ── Destructions ──────────────────────────────────────────────

class _DestructionsTab extends ConsumerWidget {
  const _DestructionsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final green = context.colors.successGreen;
    final sales = ref.watch(destructionsProvider);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Destruction Sales',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: green, foregroundColor: Colors.white),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New Destruction Sale',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const _DestructionFormDialog()),
            ),
          ]).animate().fadeIn(duration: 300.ms),
          const Gap(16),
          Expanded(
            child: sales.when(
              skipLoadingOnReload: true,
              loading: () =>
                  Center(child: CircularProgressIndicator(color: green)),
              error: (e, _) => ErrorView(
                  error: e, onRetry: () => ref.refresh(destructionsProvider)),
              data: (list) {
                // Hide sales whose packages are all destroyed (fully consumed).
                final visible =
                    list.where((s) => s.items.any((i) => !i.destroyed)).toList();
                if (visible.isEmpty) {
                  return _listCard(
                    context,
                    const EmptyTableState(
                        message: 'No destruction sales with undestroyed packages'),
                  );
                }
                return ListView.separated(
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const Gap(16),
                  itemBuilder: (context, i) => _DestructionCard(sale: visible[i]),
                ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.05);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Destruction Sale card (header + per-item detail table + Mark Destroyed) ─────────

class _DestRow {
  final DestructionItemModel saleItem;
  final PackageItem? item;
  final String warehouse;
  const _DestRow(this.saleItem, this.item, this.warehouse);
}

class _DestructionCard extends ConsumerWidget {
  final DestructionModel sale;
  const _DestructionCard({required this.sale});

  String _warehouseFor(PackageModel? pkg, String itemId) {
    if (pkg == null) return '—';
    final entries =
        pkg.warehouseEntries.where((e) => e.packageItemId == itemId).toList()
          ..sort((a, b) => b.admittedAt.compareTo(a.admittedAt));
    if (entries.isEmpty) return '—';
    final w = entries.first;
    return w.zone != null && w.zone!.isNotEmpty
        ? '${w.warehouseName} · ${w.zone}'
        : w.warehouseName;
  }

  List<_DestRow> _rows() {
    final rows = <_DestRow>[];
    // Destroyed items leave the Destruction Sales page (they move to Destroyed Packages).
    for (final si in sale.items.where((s) => !s.destroyed)) {
      final pkg = si.forfeited?.packageDetails;
      final items = pkg?.items ?? const [];
      if (items.isEmpty) {
        rows.add(_DestRow(si, null, '—'));
      } else {
        for (final it in items) {
          rows.add(_DestRow(si, it, _warehouseFor(pkg, it.id)));
        }
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final green = context.colors.successGreen;
    final rows = _rows();
    final total = sale.items.length;
    final destroyed = sale.destroyedCount;
    final allDestroyed = total > 0 && destroyed == total;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: allDestroyed
                ? green.withOpacity(0.4)
                : context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: green.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.receipt_long_rounded, color: green, size: 20),
              ),
              const Gap(14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        sale.saleNumber?.isNotEmpty == true
                            ? sale.saleNumber!
                            : 'Destruction Sale',
                        style: TextStyle(
                            color: context.colors.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 16)),
                    const Gap(2),
                    Row(children: [
                      Icon(Icons.calendar_today_rounded,
                          size: 12, color: context.colors.textMuted),
                      const Gap(4),
                      Text(
                          sale.saleDate != null
                              ? DateFormat('yyyy-MM-dd').format(sale.saleDate!)
                              : '—',
                          style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 12)),
                      const Gap(12),
                      Flexible(
                        child: Text(sale.typeLabel,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: context.colors.textMuted,
                                fontSize: 12)),
                      ),
                    ]),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: (allDestroyed ? green : context.colors.warningAmber)
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: (allDestroyed ? green : context.colors.warningAmber)
                          .withOpacity(0.4)),
                ),
                child: Text(
                  total == 0 ? 'No packages' : '$destroyed / $total destroyed',
                  style: TextStyle(
                      color: allDestroyed ? green : context.colors.warningAmber,
                      fontWeight: FontWeight.w700,
                      fontSize: 12),
                ),
              ),
            ]),
          ),
          Divider(height: 1, color: context.colors.borderColor),
          // Items table
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              height: (rows.length * 46.0 + 56).clamp(110, 360),
              decoration: BoxDecoration(
                border: Border.all(color: context.colors.borderColor),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: DataTable2(
                  columnSpacing: 10,
                  horizontalMargin: 12,
                  fixedTopRows: 1,
                  minWidth: 1080,
                  headingRowColor: _headingColor(context),
                  empty:
                      const EmptyTableState(message: 'No packages in this sale'),
                  columns: const [
                    DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
                    DataColumn2(label: Text('Case No'), size: ColumnSize.S),
                    DataColumn2(label: Text('Item'), size: ColumnSize.M),
                    DataColumn2(
                        label: Text('Qty'), size: ColumnSize.S, fixedWidth: 56),
                    DataColumn2(label: Text('Forfeit Reason'), size: ColumnSize.M),
                    DataColumn2(label: Text('Location'), size: ColumnSize.M),
                    DataColumn2(
                        label: Text('Goods Description'), size: ColumnSize.L),
                    DataColumn2(
                        label: Center(child: Text('Status')),
                        size: ColumnSize.M,
                        fixedWidth: 140),
                  ],
                  rows: rows.map((r) {
                    final f = r.saleItem.forfeited;
                    final pkg = f?.packageDetails;
                    return DataRow(cells: [
                      DataCell(Text(f?.srNumber ?? '—',
                          style: TextStyle(
                              color: context.colors.accentLightBlue,
                              fontWeight: FontWeight.w600))),
                      DataCell(Text(pkg?.caseNumber ?? '—',
                          overflow: TextOverflow.ellipsis)),
                      DataCell(Text(r.item?.itemName ?? 'Multiple/Unspecified',
                          overflow: TextOverflow.ellipsis)),
                      DataCell(Text('${r.item?.quantity ?? '—'}')),
                      DataCell(Tooltip(
                        message: f?.reason ?? '',
                        child: Text(
                            f?.reason.isNotEmpty == true ? f!.reason : '—',
                            overflow: TextOverflow.ellipsis),
                      )),
                      DataCell(Text(
                          '${yardName(r.saleItem.yard)} / ${r.warehouse}',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 12))),
                      DataCell(Tooltip(
                        message: r.item?.goodsDescription ?? '',
                        child: Text(
                            r.item?.goodsDescription?.isNotEmpty == true
                                ? r.item!.goodsDescription!
                                : '—',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 12)),
                      )),
                      DataCell(Center(
                        child: r.saleItem.destroyed
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: green.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border:
                                      Border.all(color: green.withOpacity(0.4)),
                                ),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.check_circle_rounded,
                                          size: 13, color: green),
                                      const Gap(5),
                                      Text('Destroyed',
                                          style: TextStyle(
                                              color: green,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700)),
                                    ]),
                              )
                            : OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: green,
                                  side: BorderSide(
                                      color: green.withOpacity(0.5)),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  minimumSize: const Size(0, 32),
                                ),
                                icon: const Icon(Icons.sell_rounded, size: 14),
                                label: const Text('Mark Destroyed',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700)),
                                onPressed: () => _markDestroyed(
                                    context, ref, r.saleItem),
                              ),
                      )),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _markDestroyed(
      BuildContext context, WidgetRef ref, DestructionItemModel item) {
    showDialog(
      context: context,
      builder: (ctx) => _MarkDestroyedDialog(item: item, ref: ref),
    );
  }
}

class _MarkDestroyedDialog extends StatefulWidget {
  final DestructionItemModel item;
  final WidgetRef ref;
  const _MarkDestroyedDialog({required this.item, required this.ref});
  @override
  State<_MarkDestroyedDialog> createState() => _MarkDestroyedDialogState();
}

class _MarkDestroyedDialogState extends State<_MarkDestroyedDialog> {
  final _receiptC = TextEditingController();
  final _destroyedPriceC = TextEditingController();
  bool _loading = false;
  List<DisposalTaxModel>? _activeTaxes;

  @override
  void initState() {
    super.initState();
    widget.ref.read(disposalServiceProvider).getTaxes().then((taxes) {
      if (mounted) {
        setState(() {
          _activeTaxes = taxes.where((t) => t.isActive).toList();
        });
      }
    });
    _destroyedPriceC.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _receiptC.dispose();
    _destroyedPriceC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final price = double.tryParse(_destroyedPriceC.text) ?? 0.0;
    double totalTax = 0.0;
    final List<Map<String, dynamic>> appliedTaxesList = [];
    if (_activeTaxes != null) {
      for (var t in _activeTaxes!) {
        final taxAmount = price * (t.percentage / 100);
        totalTax += taxAmount;
        appliedTaxesList.add({
          'id': t.id,
          'name': t.name,
          'percentage': t.percentage,
          'amount': taxAmount,
        });
      }
    }
    final double grandTotal = price + totalTax;

    return StyledFormDialog(
      label: 'Destruction Sale',
      title: 'Mark Package Destroyed',
      icon: Icons.sell_rounded,
      width: 460,
      child: StyledFormSection(
        title: 'Sale Confirmation',
        icon: Icons.receipt_rounded,
        children: [
          Text(
            '${widget.item.forfeited?.srNumber ?? 'Package'} — ${yardName(widget.item.yard)}. '
            'This records the package as SOLD.',
            style: TextStyle(
              color: context.colors.textSecondary, fontSize: 13)
          ),
          TextField(
            controller: _receiptC,
            decoration: const InputDecoration(labelText: 'Receipt Number (optional)'),
          ),
          const Gap(16),
          TextField(
            controller: _destroyedPriceC,
            decoration: const InputDecoration(labelText: 'Destroyed Price', prefixText: 'Rs '),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          if (_activeTaxes != null && _activeTaxes!.isNotEmpty) ...[
            const Gap(16),
            const Text('Taxes:', style: TextStyle(fontWeight: FontWeight.bold)),
            for (var t in _activeTaxes!)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${t.name} (${t.percentage}%)'),
                  Text('Rs ${(price * (t.percentage / 100)).toStringAsFixed(2)}'),
                ],
              ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Grand Total:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('Rs ${grandTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel')
        ),
        StyledDialogPrimaryButton(
          labelText: 'Confirm Destroyed',
          icon: Icons.check_circle_rounded,
          loading: _loading,
          onPressed: () async {
            setState(() => _loading = true);
            try {
              await widget.ref.read(disposalServiceProvider).markDestructionItemDestroyed(
                destructionItemId: widget.item.id,
                receipt: _receiptC.text,
              );
              widget.ref.read(destructionsRefreshProvider.notifier).trigger();
              widget.ref.read(packagesRefreshTriggerProvider.notifier).trigger();
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: const Text('Package marked destroyed'),
                  backgroundColor: context.colors.successGreen,
                ));
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Error: $e'),
                  backgroundColor: context.colors.dangerRed,
                ));
              }
            } finally {
              if (mounted) setState(() => _loading = false);
            }
          },
        ),
      ],
    );
  }
}

// ── New Destruction Sale form (details + Sale-only package picker) ─────────────

class _DestructionFormDialog extends ConsumerStatefulWidget {
  /// In [reDestruction] mode the package pool is the undestroyed destruction-sale packages
  /// (not fresh "Sale" requests) — used by the Undestroyed Destructions page.
  final bool reDestruction;
  const _DestructionFormDialog({this.reDestruction = false});
  @override
  ConsumerState<_DestructionFormDialog> createState() =>
      _DestructionFormDialogState();
}

class _DestructionFormDialogState extends ConsumerState<_DestructionFormDialog> {
  final _numberC = TextEditingController();
  final _serialC = TextEditingController();
  final _yearC = TextEditingController(text: DateTime.now().year.toString());
  DateTime? _saleDate;
  TimeOfDay? _saleTime;
  String? _destructionType;
  bool _loading = false;
  // forfeited_package_id → yard
  final Map<String, String> _selected = {};

  @override
  void initState() {
    super.initState();
    _yearC.addListener(_onYearChanged);
    _serialC.addListener(_updateSaleNumber);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSerialForYear();
    });
  }

  @override
  void dispose() {
    _yearC.removeListener(_onYearChanged);
    _serialC.removeListener(_updateSaleNumber);
    _numberC.dispose();
    _serialC.dispose();
    _yearC.dispose();
    super.dispose();
  }

  void _onYearChanged() {
    if (_yearC.text.length == 4) {
      _loadSerialForYear();
    }
  }

  Future<void> _loadSerialForYear() async {
    final year = int.tryParse(_yearC.text);
    if (year == null) return;
    try {
      final nextSerial = await ref.read(disposalServiceProvider).getNextDestructionSerial(year);
      if (mounted) {
        _serialC.text = nextSerial.toString();
        _updateSaleNumber();
      }
    } catch (e) {
      // ignore
    }
  }

  void _updateSaleNumber() {
    final year = _yearC.text;
    final serial = _serialC.text;
    if (year.isEmpty || serial.isEmpty) return;
    
    String saleNum = 'CDU/TS/$year/$serial';
    if (_destructionType == 'special') {
      saleNum += '(Special)';
    }
    _numberC.text = saleNum;
  }

  String _summary(DisposalRequestItemModel it) {
    final items = it.forfeited?.packageDetails?.items ?? const [];
    if (items.isEmpty) return 'Multiple/Unspecified';
    if (items.length == 1) return items.first.itemName;
    return '${items.first.itemName} +${items.length - 1}';
  }

  @override
  Widget build(BuildContext context) {
    final green = context.colors.successGreen;
    // Fresh sale → "Destruction"-tagged requests. Re-destruction → only the undestroyed packages
    // shown on the Undestroyed Destructions page.
    final AsyncValue<List<DisposalRequestItemModel>> pool = widget.reDestruction
        ? ref.watch(undestroyedDestructionsProvider).whenData((list) => list
            .map((info) => DisposalRequestItemModel(
                  id: info.forfeited.id,
                  requestId: '',
                  forfeitedPackageId: info.forfeited.id,
                  disposition: 'destruction',
                  forfeited: info.forfeited,
                ))
            .toList())
        : ref.watch(saleRequestItemsProvider);
    return StyledFormDialog(
      label: 'Destruction Sale',
      title: widget.reDestruction ? 'Re-destruction Sale' : 'New Destruction Sale',
      icon: Icons.gavel_rounded,
      width: 720,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StyledFormSection(
            title: 'Sale Details',
            icon: Icons.receipt_long_rounded,
            children: [
              TextField(
                controller: _numberC,
                readOnly: true,
                decoration:
                    const InputDecoration(labelText: 'Destruction Sale Number'),
              ),
              Row(children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _saleDate ?? DateTime.now(),
                        firstDate: DateTime(2015),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setState(() => _saleDate = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Destruction Sale Date',
                        suffixIcon: Icon(Icons.calendar_month_rounded),
                      ),
                      child: Text(_saleDate != null
                          ? DateFormat('yyyy-MM-dd').format(_saleDate!)
                          : 'Select sale date', style: _saleDate == null ? TextStyle(color: context.colors.textMuted) : null),
                    ),
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _saleTime ?? TimeOfDay.now(),
                      );
                      if (picked != null) setState(() => _saleTime = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Sale Start Time',
                        suffixIcon: Icon(Icons.access_time_rounded),
                      ),
                      child: Text(_saleTime != null
                          ? _saleTime!.format(context)
                          : 'Select time', style: _saleTime == null ? TextStyle(color: context.colors.textMuted) : null),
                    ),
                  ),
                ),
              ]),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _serialC,
                    readOnly: true,
                    decoration: const InputDecoration(labelText: 'Serial'),
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: TextField(
                    controller: _yearC,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Year'),
                  ),
                ),
              ]),
              DropdownButtonFormField<String>(
                value: _destructionType,
                isExpanded: true,
                decoration:
                    const InputDecoration(labelText: 'Destruction Sale Type'),
                items: [
                  for (final e in kDestructionTypes.entries)
                    DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) {
                  setState(() => _destructionType = v);
                  _updateSaleNumber();
                },
              ),
            ],
          ),
          const Gap(16),
          StyledFormSection(
            title: 'Select Packages — for Sale (${_selected.length} selected)',
            icon: Icons.inventory_2_rounded,
            children: [
              pool.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => ErrorView(
                    error: e,
                    onRetry: () => ref.refresh(widget.reDestruction
                        ? undestroyedDestructionsProvider
                        : saleRequestItemsProvider)),
                data: (items) {
                  if (items.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: Text(
                          'No "Destruction" packages awaiting a destruction sale.\n'
                          'Yards mark packages for Destruction in a Disposal Request.',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: context.colors.textSecondary),
                        ),
                      ),
                    );
                  }
                  return ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: context.colors.borderColor.withOpacity(0.5)),
                      itemBuilder: (context, i) {
                        final it = items[i];
                        final id = it.forfeitedPackageId;
                        final yard = it.forfeited?.yard ?? '';
                        final selected = _selected.containsKey(id);
                        return InkWell(
                          onTap: () => setState(() {
                            if (selected) {
                              _selected.remove(id);
                            } else {
                              _selected[id] = yard;
                            }
                          }),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 6),
                            child: Row(children: [
                              Checkbox(
                                activeColor: green,
                                value: selected,
                                onChanged: (_) => setState(() {
                                  if (selected) {
                                    _selected.remove(id);
                                  } else {
                                    _selected[id] = yard;
                                  }
                                }),
                              ),
                              Expanded(
                                flex: 5,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(it.forfeited?.srNumber ?? '—',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: context
                                                .colors.accentLightBlue)),
                                    Text(_summary(it),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: context
                                                .colors.textSecondary)),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 4,
                                child: Text(
                                    it.forfeited?.consigneeName ?? '—',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: context.colors.textPrimary)),
                              ),
                              const Gap(8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border:
                                      Border.all(color: green.withOpacity(0.3)),
                                ),
                                child: Text(yardName(yard),
                                    style: TextStyle(
                                        color: green,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        StyledDialogPrimaryButton(
          labelText: 'Save Destruction Sale',
          icon: Icons.save_rounded,
          loading: _loading,
          onPressed: () async {
            setState(() => _loading = true);
            try {
              await ref.read(disposalServiceProvider).createDestruction(
                    saleNumber: _numberC.text.trim().isEmpty ? null : _numberC.text.trim(),
                    saleDate: _saleDate,
                    saleTime: _saleTime?.format(context),
                    serial:
                        _serialC.text.trim().isEmpty ? null : _serialC.text.trim(),
                    year: int.tryParse(_yearC.text.trim()),
                    tenderType: _destructionType,
                    yard: ref.read(disposalSelectedYardProvider),
                    packageYards: Map<String, String>.from(_selected),
                  );
              ref.read(destructionsRefreshProvider.notifier).trigger();
              if (mounted) Navigator.pop(context);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: const Text('Destruction sale recorded'),
                  backgroundColor: green,
                ));
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Error: $e'),
                  backgroundColor: context.colors.dangerRed,
                ));
              }
            } finally {
              if (mounted) setState(() => _loading = false);
            }
          },
        ),
      ],
    );
  }
}

class _DestructionSaleHistoryDialog extends StatelessWidget {
  final ReDestructionInfo info;
  const _DestructionSaleHistoryDialog({required this.info});

  @override
  Widget build(BuildContext context) {
    final sales = info.destructions;
    return Dialog(
      backgroundColor: context.colors.scaffoldBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        width: 540,
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.history_rounded, color: context.colors.primaryGold),
              const Gap(10),
              Expanded(
                child: Text('Destruction Sale History — ${info.forfeited.srNumber}',
                    style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
              ),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded)),
            ]),
            const Gap(4),
            Text('Destructioned ${info.timesAttempted} time(s)',
                style: TextStyle(color: context.colors.textSecondary)),
            const Gap(12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: sales.length,
                separatorBuilder: (_, __) => const Gap(10),
                itemBuilder: (context, i) {
                  final t = sales[i];
                  final isLatest = i == 0;
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.colors.cardDark,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: isLatest
                              ? context.colors.primaryGold.withOpacity(0.5)
                              : context.colors.borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.gavel_rounded,
                              size: 16, color: context.colors.primaryGold),
                          const Gap(8),
                          Text(t.saleNumber ?? 'No Number',
                              style: TextStyle(
                                  color: context.colors.textPrimary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15)),
                          if (isLatest) ...[
                            const Gap(8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: context.colors.primaryGold
                                    .withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('Latest',
                                  style: TextStyle(
                                      color: context.colors.primaryGold,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ]),
                        const Gap(8),
                        _kv(
                            context,
                            'Sale Date',
                            t.saleDate != null
                                ? DateFormat('yyyy-MM-dd').format(t.saleDate!)
                                : '—'),
                        _kv(context, 'Sale Start Time', t.saleTime ?? '—'),
                        if (t.createdByName != null)
                          _kv(context, 'Created By', t.createdByName!),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(
          width: 130,
          child: Text(k,
              style: TextStyle(
                  color: context.colors.textMuted, fontSize: 12)),
        ),
        Expanded(
          child: Text(v,
              style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

class _UndestroyedReDestructionTab extends ConsumerWidget {
  const _UndestroyedReDestructionTab();

  String _itemName(ForfeitedPackageModel f) {
    final items = f.packageDetails?.items ?? const [];
    if (items.isEmpty) return 'Multiple/Unspecified';
    if (items.length == 1) return items.first.itemName;
    return '${items.first.itemName} +${items.length - 1}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final green = context.colors.successGreen;
    final amber = context.colors.warningAmber;
    final async = ref.watch(undestroyedDestructionsProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Undestroyed Packages — Re-destruction',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            async.maybeWhen(
                  data: (list) => ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: green, foregroundColor: Colors.white),
                    icon: const Icon(Icons.auto_delete_rounded, size: 18),
                    label: const Text('Re-destruction',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    onPressed: list.isEmpty
                        ? null
                        : () => showDialog(
                              context: context,
                              builder: (_) =>
                                  const _DestructionFormDialog(reDestruction: true),
                            ).then((_) {
                              ref.invalidate(undestroyedDestructionsProvider);
                              ref.invalidate(destructionsProvider);
                            }),
                  ),
              orElse: () => const SizedBox(),
            ),
          ]).animate().fadeIn(duration: 300.ms),
          const Gap(14),
          async.maybeWhen(
            data: (list) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _StatChip(
                  label: 'Undestroyed — re-destructionable',
                  value: '${list.length}',
                  color: amber),
            ).animate().fadeIn(duration: 300.ms),
            orElse: () => const SizedBox.shrink(),
          ),
          Expanded(
            child: async.when(
              skipLoadingOnReload: true,
              loading: () =>
                  Center(child: CircularProgressIndicator(color: green)),
              error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.refresh(undestroyedDestructionsProvider)),
              data: (list) {
                if (list.isEmpty) {
                  return _listCard(
                    context,
                    const EmptyTableState(
                        message:
                            'No undestroyed packages — everything destructioned is destroyed or still in an active destruction window'),
                  );
                }
                return _listCard(
                  context,
                  DataTable2(
                    columnSpacing: 12,
                    horizontalMargin: 16,
                    fixedTopRows: 1,
                    minWidth: 760,
                    headingRowColor: _headingColor(context),
                    columns: const [
                      DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
                      DataColumn2(label: Text('Item'), size: ColumnSize.L),
                      DataColumn2(label: Text('Consignee'), size: ColumnSize.M),
                      DataColumn2(
                          label: Center(child: Text('Times Attempted')),
                          size: ColumnSize.S,
                          fixedWidth: 130),
                      DataColumn2(
                          label: Center(child: Text('Destructions')),
                          size: ColumnSize.S,
                          fixedWidth: 100),
                    ],
                    rows: list.map((info) {
                      final f = info.forfeited;
                      return DataRow(cells: [
                        DataCell(Text(f.srNumber,
                            style: TextStyle(
                                color: context.colors.accentLightBlue,
                                fontWeight: FontWeight.w600))),
                        DataCell(Text(_itemName(f),
                            overflow: TextOverflow.ellipsis)),
                        DataCell(Text(f.consigneeName,
                            overflow: TextOverflow.ellipsis)),
                        DataCell(Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: amber.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: amber.withOpacity(0.4)),
                            ),
                            child: Text('${info.timesAttempted}×',
                                style: TextStyle(
                                    color: amber, fontWeight: FontWeight.w800)),
                          ),
                        )),
                        DataCell(Center(
                          child: IconButton(
                            icon: const Icon(Icons.history_rounded, size: 18),
                            color: context.colors.accentLightBlue,
                            onPressed: () => showDialog(
                              context: context,
                              builder: (_) => _DestructionSaleHistoryDialog(info: info),
                            ),
                          ),
                        )),
                      ]);
                    }).toList(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
