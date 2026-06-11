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
      length: 2,
      child: Scaffold(
        backgroundColor: context.colors.scaffoldBg,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top bar ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
              decoration: BoxDecoration(
                color: context.colors.cardDark,
                border: Border(
                    bottom: BorderSide(color: context.colors.borderColor)),
              ),
              child: Row(children: [
                SvgPicture.asset('Sri_Lanka_Customs_logo_tinted.svg',
                    width: 38, height: 38, theme: SvgTheme(currentColor: green)),
                const Gap(12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Central Disposal Directorate',
                        style: TextStyle(
                            color: context.colors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800)),
                    Text('Sold items across all yards & tender sales',
                        style: TextStyle(
                            color: context.colors.textMuted, fontSize: 12)),
                  ],
                ),
                const Spacer(),
                if (profile != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(profile.fullName,
                        style: TextStyle(
                            color: context.colors.textSecondary,
                            fontWeight: FontWeight.w600)),
                  ),
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
                const Gap(8),
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
            ),
            // ── Tabs ─────────────────────────────────────────────
            Container(
              color: context.colors.cardDark,
              child: TabBar(
                isScrollable: true,
                labelColor: green,
                unselectedLabelColor: context.colors.textMuted,
                indicatorColor: green,
                tabs: const [
                  Tab(icon: Icon(Icons.sell_rounded), text: 'Sold Packages'),
                  Tab(icon: Icon(Icons.gavel_rounded), text: 'Tender Sales'),
                ],
              ),
            ),
            const Expanded(
              child: TabBarView(children: [
                _SoldPackagesTab(),
                _TenderSalesTab(),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

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
            SizedBox(
              width: 240,
              child: StyledDropdownFormField<String>(
                value: selectedYard,
                label: 'Yard',
                helperText: null,
                isDense: true,
                menuWidth: 240,
                prefixIcon: Icon(Icons.warehouse_outlined,
                    color: context.colors.textMuted),
                options: [
                  for (final y in kYards) StyledDropdownOption(y.code, y.name),
                ],
                onChanged: (v) => ref
                    .read(disposalSelectedYardProvider.notifier)
                    .state = v ?? kYards.first.code,
              ),
            ),
          ]),
          const Gap(16),
          Expanded(
            child: sold.when(
              skipLoadingOnReload: true,
              loading: () => Center(
                  child: CircularProgressIndicator(color: context.colors.successGreen)),
              error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.refresh(disposalSoldPackagesProvider)),
              data: (packages) {
                final rows = _rows(packages);
                return Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: context.colors.cardDark,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.colors.borderColor),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: DataTable2(
                      columnSpacing: 12,
                      horizontalMargin: 16,
                      fixedTopRows: 1,
                      empty: EmptyTableState(
                          message:
                              'No sold packages in ${yardName(selectedYard)}'),
                      headingRowColor: WidgetStateProperty.all(
                          context.colors.surfaceDark),
                      columns: const [
                        DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
                        DataColumn2(label: Text('Item'), size: ColumnSize.M),
                        DataColumn2(
                            label: Text('Qty'),
                            size: ColumnSize.S,
                            fixedWidth: 60),
                        DataColumn2(label: Text('Sold Date'), size: ColumnSize.M),
                        DataColumn2(label: Text('Sold By'), size: ColumnSize.M),
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
                  ),
                ).animate().fadeIn(duration: 300.ms);
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
              onPressed: () => _showTenderSaleForm(context, ref),
            ),
          ]),
          const Gap(16),
          Expanded(
            child: sales.when(
              loading: () => Center(
                  child: CircularProgressIndicator(color: green)),
              error: (e, _) => ErrorView(
                  error: e, onRetry: () => ref.refresh(tenderSalesProvider)),
              data: (list) => Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: context.colors.cardDark,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.colors.borderColor),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: DataTable2(
                    columnSpacing: 12,
                    horizontalMargin: 16,
                    fixedTopRows: 1,
                    empty: const EmptyTableState(
                        message: 'No tender sales recorded yet'),
                    headingRowColor:
                        WidgetStateProperty.all(context.colors.surfaceDark),
                    columns: const [
                      DataColumn2(label: Text('Sale No'), size: ColumnSize.M),
                      DataColumn2(label: Text('Date'), size: ColumnSize.S),
                      DataColumn2(
                          label: Text('Serial'),
                          size: ColumnSize.S,
                          fixedWidth: 90),
                      DataColumn2(
                          label: Text('Year'),
                          size: ColumnSize.S,
                          fixedWidth: 70),
                      DataColumn2(label: Text('Type'), size: ColumnSize.L),
                    ],
                    rows: list
                        .map((s) => DataRow(cells: [
                              DataCell(Text(s.saleNumber ?? '—',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600))),
                              DataCell(Text(s.saleDate != null
                                  ? DateFormat('yyyy-MM-dd').format(s.saleDate!)
                                  : '—')),
                              DataCell(Text(s.serial ?? '—')),
                              DataCell(Text(s.year?.toString() ?? '—')),
                              DataCell(Text(s.typeLabel,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: context.colors.textSecondary,
                                      fontSize: 12))),
                            ]))
                        .toList(),
                  ),
                ),
              ).animate().fadeIn(duration: 300.ms),
            ),
          ),
        ],
      ),
    );
  }

  void _showTenderSaleForm(BuildContext context, WidgetRef ref) {
    final numberC = TextEditingController();
    final serialC = TextEditingController();
    final yearC =
        TextEditingController(text: DateTime.now().year.toString());
    DateTime? saleDate = DateTime.now();
    String? tenderType;
    bool loading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => StyledFormDialog(
          label: 'Tender Sale',
          title: 'New Tender Sale',
          icon: Icons.gavel_rounded,
          width: 480,
          child: StyledFormSection(
            title: 'Sale Details',
            icon: Icons.receipt_long_rounded,
            children: [
              TextField(
                controller: numberC,
                decoration:
                    const InputDecoration(labelText: 'Tender Sale Number'),
              ),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: saleDate ?? DateTime.now(),
                    firstDate: DateTime(2015),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => saleDate = picked);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date',
                    suffixIcon: Icon(Icons.calendar_month_rounded),
                  ),
                  child: Text(
                    saleDate != null
                        ? DateFormat('yyyy-MM-dd').format(saleDate!)
                        : 'Select date',
                  ),
                ),
              ),
              TextField(
                controller: serialC,
                decoration: const InputDecoration(labelText: 'Serial'),
              ),
              TextField(
                controller: yearC,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Year'),
              ),
              DropdownButtonFormField<String>(
                value: tenderType,
                isExpanded: true,
                decoration:
                    const InputDecoration(labelText: 'Tender Sale Type'),
                items: [
                  for (final e in kTenderSaleTypes.entries)
                    DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value,
                            overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => tenderType = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            StyledDialogPrimaryButton(
              labelText: 'Save Tender Sale',
              icon: Icons.save_rounded,
              loading: loading,
              onPressed: () async {
                setState(() => loading = true);
                try {
                  await ref.read(disposalServiceProvider).createTenderSale(
                        saleNumber: numberC.text.trim().isEmpty
                            ? null
                            : numberC.text.trim(),
                        saleDate: saleDate,
                        serial: serialC.text.trim().isEmpty
                            ? null
                            : serialC.text.trim(),
                        year: int.tryParse(yearC.text.trim()),
                        tenderType: tenderType,
                        yard: ref.read(disposalSelectedYardProvider),
                      );
                  ref.read(tenderSalesRefreshProvider.notifier).trigger();
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: const Text('Tender sale recorded'),
                      backgroundColor: context.colors.successGreen,
                    ));
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: context.colors.dangerRed,
                    ));
                  }
                } finally {
                  setState(() => loading = false);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
